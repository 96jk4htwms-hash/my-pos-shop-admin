-- DEVELOPMENT / TEST ONLY — DO NOT RUN AGAINST A PRODUCTION DATABASE.
-- ============================================================
-- Smart POS — FULL RESET + REBUILD (matches index.html exactly)
-- ============================================================
-- ใช้ไฟล์นี้แทน SMARTPOS_SINGLE_RUN.sql ทั้งหมด
--
-- ขั้นตอนที่ 1: ลบตาราง/ฟังก์ชัน/trigger/policy ทั้งหมดที่มาจาก
--               สคีมาแบบ multi-tenant (auth.uid()/owner_id/store_members) เดิม
--               ซึ่ง "ไม่ตรง" กับ index.html (index.html ไม่มีการ login เลย)
-- ขั้นตอนที่ 2: สร้างสคีมาใหม่แบบเรียบง่าย ตรงกับคอลัมน์ที่โค้ด JS
--               เรียกจริงทุกจุด (client.from('table').select/insert/upsert/delete)
--
-- Run ทั้งไฟล์นี้ครั้งเดียวใน Supabase SQL Editor
-- ⚠️ คำสั่งนี้จะลบข้อมูลเดิมทั้งหมดในตารางที่เกี่ยวข้อง — ถ้ามีข้อมูลจริงอยู่แล้ว
--    ให้ export/backup ก่อนรัน
-- ============================================================


-- ============================================================
-- STEP 1: DROP everything from the old incompatible schema
-- ============================================================

-- ---- Storage policies (old + new, drop before recreating) ----
drop policy if exists "product_images_anon_all" on storage.objects;
drop policy if exists "documents_anon_all" on storage.objects;
drop policy if exists "Public read product-images" on storage.objects;
drop policy if exists "Public read documents" on storage.objects;

-- ---- Triggers ----
drop trigger if exists on_auth_user_created on auth.users;
do $$
declare t text;
begin
  foreach t in array array[
    'app_accounts','profiles','categories','products',
    'product_variants','customers','suppliers','bills',
    'purchase_orders'
  ]
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    end if;
  end loop;
end $$;

-- ---- Functions (old multi-tenant / auth-based) ----
drop function if exists public.process_sale_atomic(jsonb) cascade;
drop function if exists public.set_business_store_id() cascade;
drop function if exists public.remove_store_member(uuid) cascade;
drop function if exists public.add_store_member(uuid, text) cascade;
drop function if exists public.get_my_store() cascade;
drop function if exists public.current_store_role() cascade;
drop function if exists public.current_store_id() cascade;
drop function if exists public.create_pos_account(text, text) cascade;
drop function if exists public.apply_latest_cost() cascade;
drop function if exists public.decrement_stock_atomic(text, numeric) cascade;
drop function if exists public.handle_new_user() cascade;
drop function if exists public.set_updated_at() cascade;

-- ---- Tables from the old multi-tenant install ----
-- (dropped in dependency-safe order via cascade; if a table doesn't
--  exist "if exists" makes this a no-op)
drop table if exists public.sale_transactions cascade;
drop table if exists public.terminals cascade;
drop table if exists public.cost_history cascade;
drop table if exists public.purchase_cost_history cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.error_logs cascade;
drop table if exists public.audit_log cascade;
drop table if exists public.documents cascade;
drop table if exists public.shifts cascade;
drop table if exists public.cash_ledger cascade;
drop table if exists public.supplier_payments cascade;
drop table if exists public.receiving_documents cascade;
drop table if exists public.purchase_order_items cascade;
drop table if exists public.purchase_orders cascade;
drop table if exists public.customer_payment_allocations cascade;
drop table if exists public.receipts cascade;
drop table if exists public.bill_items cascade;
drop table if exists public.bills cascade;
drop table if exists public.suppliers cascade;
drop table if exists public.customers cascade;
drop table if exists public.product_fractions cascade;
drop table if exists public.product_variants cascade;
drop table if exists public.product_categories cascade;
drop table if exists public.products cascade;
drop table if exists public.categories cascade;
drop table if exists public.pos_state cascade;
drop table if exists public.store_members cascade;
drop table if exists public.stores cascade;
drop table if exists public.profiles cascade;
drop table if exists public.app_accounts cascade;

-- ---- Storage buckets ----
-- หมายเหตุ: Supabase ไม่อนุญาตให้ DELETE ตาราง storage.objects / storage.buckets
-- ตรง ๆ ด้วย SQL (ต้องใช้ Storage API/Dashboard) จึงข้ามขั้นตอนนี้ไป
-- และใช้ "insert ... on conflict do update" ด้านล่างแทน ซึ่งจะสร้าง bucket
-- ใหม่ถ้ายังไม่มี หรืออัปเดตให้เป็น public ถ้ามีอยู่แล้วอย่างปลอดภัย
-- (ถ้าต้องการล้างไฟล์เก่าใน bucket จริง ๆ ให้ลบผ่าน Dashboard → Storage แทน)


-- ============================================================
-- STEP 2: CREATE the correct schema (matches index.html)
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1) pos_state : full-state sync (window.pushFullStateToSupabaseSafe)
-- ------------------------------------------------------------
create table public.pos_state (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2) categories (window.syncProductsToSupabase)
-- ------------------------------------------------------------
create table public.categories (
  id text primary key,
  name text not null,
  icon text,
  color text
);

-- ------------------------------------------------------------
-- 3) products
-- ------------------------------------------------------------
create table public.products (
  id text primary key,
  name text not null,
  category_id text references public.categories(id) on delete set null,
  icon text,
  image_url text,
  is_deleted boolean not null default false
);

-- ------------------------------------------------------------
-- 4) product_categories : ตารางเชื่อมสินค้า <-> หมวดหมู่ (many-to-many)
-- ------------------------------------------------------------
create table public.product_categories (
  id bigserial primary key,
  product_id text not null references public.products(id) on delete cascade,
  category_id text not null references public.categories(id) on delete cascade,
  unique (product_id, category_id)
);

create index idx_product_categories_product on public.product_categories(product_id);
create index idx_product_categories_category on public.product_categories(category_id);

-- ------------------------------------------------------------
-- 5) product_variants (ขนาด/หน่วยของสินค้า)
-- ------------------------------------------------------------
create table public.product_variants (
  id text primary key,
  product_id text not null references public.products(id) on delete cascade,
  size_name text,
  barcode text,
  cost numeric(14,4) not null default 0,
  price numeric(14,4) not null default 0,
  stock numeric(14,4) not null default 0,
  min_stock numeric(14,4) not null default 0
);

create index idx_product_variants_product on public.product_variants(product_id);
create index idx_product_variants_barcode on public.product_variants(barcode);

-- ------------------------------------------------------------
-- 6) product_fractions (หน่วยแบ่งขายย่อยของแต่ละ variant)
-- ------------------------------------------------------------
create table public.product_fractions (
  id text primary key,
  variant_id text not null references public.product_variants(id) on delete cascade,
  fraction_name text,
  multiplier numeric(14,4) not null default 1,
  fraction_price numeric(14,4) not null default 0
);

create index idx_product_fractions_variant on public.product_fractions(variant_id);

-- ------------------------------------------------------------
-- 7) bills (บิลขาย) — window.syncGranularTablesToSupabase('bills')
-- ------------------------------------------------------------
create table public.bills (
  id text primary key,
  time timestamptz not null default now(),
  total numeric(14,4) not null default 0,
  method text,
  customer_id text,
  payload_json jsonb not null default '{}'::jsonb
);

create index idx_bills_time on public.bills(time);

-- ------------------------------------------------------------
-- 8) cash_ledger (สมุดเงินสด) — syncGranularTablesToSupabase('cash_ledger')
-- ------------------------------------------------------------
create table public.cash_ledger (
  id text primary key,
  date date not null default current_date,
  description text,
  income numeric(14,4) not null default 0,
  expense numeric(14,4) not null default 0,
  type text,
  ref_id text
);

create index idx_cash_ledger_date on public.cash_ledger(date);

-- ------------------------------------------------------------
-- 9) shifts (กะการทำงาน) — syncGranularTablesToSupabase('shifts')
-- ------------------------------------------------------------
create table public.shifts (
  id text primary key,
  start_time timestamptz,
  end_time timestamptz,
  cash_on_hand numeric(14,4) default 0,
  payload_json jsonb not null default '{}'::jsonb
);

create index idx_shifts_start on public.shifts(start_time);

-- ------------------------------------------------------------
-- 10) audit_log (ประวัติการทำรายการ, append-only จากฝั่ง client)
-- ------------------------------------------------------------
create table public.audit_log (
  id text primary key,
  ts timestamptz not null default now(),
  action text,
  actor text,
  details jsonb,
  device_id text
);

create index idx_audit_log_ts on public.audit_log(ts);

-- ------------------------------------------------------------
-- 11) error_logs (telemetry ข้อผิดพลาดจากฝั่ง client)
-- ------------------------------------------------------------
create table public.error_logs (
  id text primary key,
  error_type text,
  message text,
  stack_trace text,
  device_id text,
  created_at timestamptz not null default now()
);

create index idx_error_logs_created on public.error_logs(created_at);

-- ============================================================
-- ROW LEVEL SECURITY
-- ------------------------------------------------------------
-- index.html เชื่อมด้วย anon key ตรง ๆ ไม่มี login จึงต้องเปิดสิทธิ์
-- ให้ role "anon" อ่าน/เขียนได้เต็มที่ มิฉะนั้นทุกฟังก์ชัน sync ในแอปจะพัง
-- ความปลอดภัยของร้านอยู่ที่การไม่เผยแพร่ Project URL + anon key ให้คนนอก
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'pos_state','categories','products','product_categories',
    'product_variants','product_fractions','bills','cash_ledger',
    'shifts','audit_log','error_logs'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_anon_all', t);
    execute format(
      'create policy %I on public.%I for all to anon, authenticated using (true) with check (true)',
      t || '_anon_all', t
    );
  end loop;
end $$;

-- ============================================================
-- STORAGE BUCKETS
-- ------------------------------------------------------------
-- product-images: window.uploadProductImageToSupabase
-- documents     : window.uploadGenericFileToSupabase
-- ============================================================

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do update set public = true;

create policy "product_images_anon_all"
on storage.objects for all
to anon, authenticated
using (bucket_id = 'product-images')
with check (bucket_id = 'product-images');

create policy "documents_anon_all"
on storage.objects for all
to anon, authenticated
using (bucket_id = 'documents')
with check (bucket_id = 'documents');

-- ============================================================
-- SANITY CHECK
-- ============================================================
do $$
begin
  if to_regclass('public.pos_state') is null then
    raise exception 'Setup incomplete: public.pos_state missing';
  end if;
  if to_regclass('public.products') is null then
    raise exception 'Setup incomplete: public.products missing';
  end if;
  if to_regclass('public.product_variants') is null then
    raise exception 'Setup incomplete: public.product_variants missing';
  end if;
  if to_regclass('public.bills') is null then
    raise exception 'Setup incomplete: public.bills missing';
  end if;
  raise notice 'Smart POS reset + setup completed successfully.';
end $$;

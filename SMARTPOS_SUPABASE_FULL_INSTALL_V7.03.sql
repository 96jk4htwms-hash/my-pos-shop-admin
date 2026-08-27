-- SMARTPOS SUPABASE FULL INSTALLER V7.03
-- Run in Supabase SQL Editor as project owner/postgres.
-- Additive: does not DROP POS tables or delete existing data.
-- Supabase Auth users are the owner identity; no owners table is required.

begin;
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text, role text not null default 'owner',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.categories (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null, parent_id uuid references public.categories(id) on delete restrict,
 icon text, color text, is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists categories_owner_name_uq on public.categories(owner_id, lower(name)) where is_active=true;
create index if not exists categories_owner_idx on public.categories(owner_id);

create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 sku text, barcode text, name text not null, description text,
 category_id uuid references public.categories(id) on delete set null, cat text,
 brand_id uuid, supplier_id uuid, cost numeric(14,2) not null default 0,
 price numeric(14,2) not null default 0, stock numeric(14,3) not null default 0,
 min_stock numeric(14,3) not null default 0, unit text default 'ชิ้น',
 image_url text, is_active boolean not null default true,
 is_deleted boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists products_owner_idx on public.products(owner_id);
create index if not exists products_barcode_idx on public.products(owner_id,barcode);
create index if not exists products_sku_idx on public.products(owner_id,sku);
create index if not exists products_category_idx on public.products(owner_id,category_id);

create table if not exists public.product_categories (
 product_id uuid not null references public.products(id) on delete cascade,
 category_id uuid not null references public.categories(id) on delete cascade,
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 is_primary boolean not null default false, created_at timestamptz not null default now(),
 primary key(product_id,category_id)
);

create table if not exists public.product_variants (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 sku text, barcode text, name text, size text, unit text,
 cost numeric(14,2) not null default 0, price numeric(14,2) not null default 0,
 stock numeric(14,3) not null default 0, image_url text,
 is_active boolean not null default true, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.product_fractions (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 name text not null, unit text not null, ratio numeric(14,6) not null,
 price numeric(14,2) not null default 0, barcode text,
 is_active boolean not null default true, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.product_images (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 image_url text, storage_path text, sort_order integer not null default 0,
 is_primary boolean not null default false, created_at timestamptz not null default now()
);

create table if not exists public.customers (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 code text, name text not null, phone text, email text, address text, note text,
 points numeric(14,2) not null default 0, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.bills (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 bill_no text, customer_id uuid references public.customers(id) on delete set null,
 status text not null default 'completed', subtotal numeric(14,2) not null default 0,
 discount numeric(14,2) not null default 0, total numeric(14,2) not null default 0,
 payment_method text, payload jsonb, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.cash_ledger (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 shift_id uuid, type text not null, amount numeric(14,2) not null default 0,
 note text, reference_id uuid, created_at timestamptz not null default now()
);

create table if not exists public.shifts (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 opened_by uuid references auth.users(id) on delete set null,
 closed_by uuid references auth.users(id) on delete set null,
 status text not null default 'open', opening_cash numeric(14,2) not null default 0,
 closing_cash numeric(14,2), opened_at timestamptz not null default now(), closed_at timestamptz
);

create table if not exists public.pos_state (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 payload jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now()
);

create table if not exists public.import_batches (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
 source_name text, source_type text,
 status text not null default 'PREVIEW' check(status in ('PREVIEW','READY','COMMITTED','ROLLED_BACK','CANCELLED','FAILED')),
 total_rows int not null default 0, ready_rows int not null default 0,
 review_rows int not null default 0, error_rows int not null default 0,
 skipped_rows int not null default 0, metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 committed_at timestamptz
);

create table if not exists public.import_items (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.import_batches(id) on delete cascade,
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 row_number int, action text not null default 'REVIEW',
 status text not null default 'PENDING',
 product_id uuid references public.products(id) on delete set null,
 sku text, barcode text, product_name text, image_url text,
 payload jsonb not null default '{}'::jsonb, diff jsonb not null default '{}'::jsonb,
 error_message text, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.import_changes (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.import_batches(id) on delete cascade,
 item_id uuid references public.import_items(id) on delete cascade,
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 product_id uuid references public.products(id) on delete set null,
 field_name text, old_value jsonb, new_value jsonb, created_at timestamptz not null default now()
);

create table if not exists public.import_snapshots (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.import_batches(id) on delete cascade,
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 snapshot_type text not null check(snapshot_type in ('PRE_IMPORT','POST_IMPORT','ROLLBACK')),
 snapshot_data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create table if not exists public.audit_log (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 user_id uuid default auth.uid() references auth.users(id) on delete set null,
 action text not null, entity_type text, entity_id uuid,
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create table if not exists public.error_logs (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid default auth.uid() references auth.users(id) on delete set null,
 user_id uuid default auth.uid() references auth.users(id) on delete set null,
 source text, message text, stack text, context jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,display_name)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',new.email))
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at=now(); return new; end $$;

do $$
declare t text;
begin
 foreach t in array array['profiles','categories','products','product_variants','product_fractions','customers','bills','import_batches','import_items','pos_state'] loop
  execute format('drop trigger if exists trg_%s_updated_at on public.%I',t,t);
  execute format('create trigger trg_%s_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end $$;

do $$
declare t text;
begin
 foreach t in array array['profiles','categories','products','product_categories','product_variants','product_fractions','product_images','customers','bills','cash_ledger','shifts','pos_state','import_batches','import_items','import_changes','import_snapshots','audit_log','error_logs'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;

-- Owner-isolation policies
do $$
declare t text;
begin
 foreach t in array array['categories','products','product_categories','product_variants','product_fractions','product_images','customers','bills','cash_ledger','shifts','pos_state','import_batches','import_items','import_changes','import_snapshots','audit_log','error_logs'] loop
  execute format('drop policy if exists owner_isolation on public.%I',t);
  execute format('create policy owner_isolation on public.%I for all to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid())',t);
 end loop;
end $$;

drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles for all to authenticated
using(id=auth.uid()) with check(id=auth.uid());

insert into storage.buckets(id,name,public) values('product-images','product-images',true)
on conflict(id) do update set public=true;
insert into storage.buckets(id,name,public) values('documents','documents',false)
on conflict(id) do update set public=false;

drop policy if exists product_images_select on storage.objects;
create policy product_images_select on storage.objects for select to authenticated
using(bucket_id='product-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists product_images_insert on storage.objects;
create policy product_images_insert on storage.objects for insert to authenticated
with check(bucket_id='product-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists product_images_update on storage.objects;
create policy product_images_update on storage.objects for update to authenticated
using(bucket_id='product-images' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='product-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists product_images_delete on storage.objects;
create policy product_images_delete on storage.objects for delete to authenticated
using(bucket_id='product-images' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists documents_select on storage.objects;
create policy documents_select on storage.objects for select to authenticated
using(bucket_id='documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists documents_insert on storage.objects;
create policy documents_insert on storage.objects for insert to authenticated
with check(bucket_id='documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists documents_update on storage.objects;
create policy documents_update on storage.objects for update to authenticated
using(bucket_id='documents' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists documents_delete on storage.objects;
create policy documents_delete on storage.objects for delete to authenticated
using(bucket_id='documents' and (storage.foldername(name))[1]=auth.uid()::text);

commit;

-- Verification
select table_name from information_schema.tables where table_schema='public'
and table_name in ('profiles','categories','products','product_categories','product_variants','product_fractions','product_images','customers','bills','cash_ledger','shifts','pos_state','import_batches','import_items','import_changes','import_snapshots','audit_log','error_logs')
order by table_name;
select id,name,public from storage.buckets where id in ('product-images','documents') order by id;

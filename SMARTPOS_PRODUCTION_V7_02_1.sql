-- SMART POS PRO V7.02.1
-- PRODUCTION MIGRATION / INSTALLER FOR SUPABASE
-- Safe/additive migration: does not DROP product tables or delete existing data.
-- Run with Supabase SQL Editor as project owner/postgres.
-- BACK UP THE DATABASE BEFORE RUNNING IN PRODUCTION.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.smartpos_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now(),
  description text NOT NULL
);

CREATE OR REPLACE FUNCTION public.smartpos_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================================================
-- AUDIT LOG / ERROR TELEMETRY
-- Existing application already writes audit_log and error_logs.
-- ============================================================
DO $$
BEGIN
  IF to_regclass('public.audit_log') IS NULL THEN
    CREATE TABLE public.audit_log (
      id text PRIMARY KEY,
      owner_id uuid,
      created_by uuid,
      ts timestamptz NOT NULL DEFAULT now(),
      action text NOT NULL,
      actor text,
      details jsonb NOT NULL DEFAULT '{}'::jsonb,
      device_id text,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  ELSE
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS owner_id uuid;
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS created_by uuid;
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS ts timestamptz DEFAULT now();
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS action text;
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS actor text;
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS device_id text;
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
    ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS details jsonb DEFAULT '{}'::jsonb;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.error_logs') IS NULL THEN
    CREATE TABLE public.error_logs (
      id text PRIMARY KEY,
      owner_id uuid,
      created_by uuid,
      error_type text NOT NULL,
      message text,
      stack_trace text,
      device_id text,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  ELSE
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS owner_id uuid;
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS created_by uuid;
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS error_type text;
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS message text;
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS stack_trace text;
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS device_id text;
    ALTER TABLE public.error_logs ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
  END IF;
END $$;

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS smartpos_audit_select_authenticated ON public.audit_log;
DROP POLICY IF EXISTS smartpos_audit_insert_authenticated ON public.audit_log;
DROP POLICY IF EXISTS smartpos_error_select_authenticated ON public.error_logs;
DROP POLICY IF EXISTS smartpos_error_insert_authenticated ON public.error_logs;

CREATE POLICY smartpos_audit_select_authenticated
ON public.audit_log FOR SELECT TO authenticated
USING (created_by = auth.uid() OR owner_id = auth.uid());

CREATE POLICY smartpos_audit_insert_authenticated
ON public.audit_log FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid() AND (owner_id IS NULL OR owner_id = auth.uid()));

CREATE POLICY smartpos_error_select_authenticated
ON public.error_logs FOR SELECT TO authenticated
USING (created_by = auth.uid() OR owner_id = auth.uid());

CREATE POLICY smartpos_error_insert_authenticated
ON public.error_logs FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid() AND (owner_id IS NULL OR owner_id = auth.uid()));

CREATE INDEX IF NOT EXISTS idx_audit_log_ts ON public.audit_log(ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON public.audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_by ON public.audit_log(created_by);
CREATE INDEX IF NOT EXISTS idx_error_logs_created_at ON public.error_logs(created_at DESC);

-- ============================================================
-- IMPORT CENTER
-- ============================================================
CREATE TABLE IF NOT EXISTS public.import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL DEFAULT auth.uid(),
  created_by uuid NOT NULL DEFAULT auth.uid(),
  file_name text,
  source_type text NOT NULL DEFAULT 'excel'
    CHECK (source_type IN ('excel','csv','json','manual','other')),
  schema_version text NOT NULL DEFAULT 'V7.02',
  status text NOT NULL DEFAULT 'PREVIEW'
    CHECK (status IN ('PREVIEW','READY','COMMITTED','ROLLED_BACK','CANCELLED','FAILED')),
  total_rows integer NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
  new_rows integer NOT NULL DEFAULT 0 CHECK (new_rows >= 0),
  update_rows integer NOT NULL DEFAULT 0 CHECK (update_rows >= 0),
  skip_rows integer NOT NULL DEFAULT 0 CHECK (skip_rows >= 0),
  error_rows integer NOT NULL DEFAULT 0 CHECK (error_rows >= 0),
  image_new_rows integer NOT NULL DEFAULT 0 CHECK (image_new_rows >= 0),
  image_bad_rows integer NOT NULL DEFAULT 0 CHECK (image_bad_rows >= 0),
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  rolled_back_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.import_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.import_batches(id) ON DELETE RESTRICT,
  owner_id uuid NOT NULL DEFAULT auth.uid(),
  row_number integer NOT NULL,
  row_type text NOT NULL DEFAULT 'MAIN'
    CHECK (row_type IN ('MAIN','FRACTION')),
  action text NOT NULL DEFAULT 'ADD'
    CHECK (action IN ('ADD','UPDATE','SKIP')),
  match_type text
    CHECK (match_type IS NULL OR match_type IN ('NEW','BARCODE','CODE','NAME_SIZE','FUZZY')),
  matched_product_id text,
  matched_variant_id text,
  product_id text,
  variant_id text,
  name text,
  code text,
  size_name text,
  category text,
  barcode text,
  cost numeric,
  price numeric,
  stock numeric,
  min_stock numeric,
  fraction_name text,
  fraction_multiplier numeric,
  image_url text,
  image_status text NOT NULL DEFAULT 'EMPTY'
    CHECK (image_status IN ('EMPTY','CHECKING','OK','BAD','BLOCKED','CHANGED')),
  image_http_status integer,
  image_checked_at timestamptz,
  errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  warnings jsonb NOT NULL DEFAULT '[]'::jsonb,
  diff jsonb NOT NULL DEFAULT '[]'::jsonb,
  field_actions jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.import_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.import_batches(id) ON DELETE RESTRICT,
  item_id uuid NOT NULL REFERENCES public.import_items(id) ON DELETE RESTRICT,
  owner_id uuid NOT NULL DEFAULT auth.uid(),
  product_id text,
  variant_id text,
  field_name text NOT NULL,
  old_value jsonb,
  new_value jsonb,
  decision text NOT NULL DEFAULT 'PENDING'
    CHECK (decision IN ('PENDING','APPLY','SKIP')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.import_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.import_batches(id) ON DELETE RESTRICT,
  owner_id uuid NOT NULL DEFAULT auth.uid(),
  snapshot_type text NOT NULL DEFAULT 'PRE_IMPORT'
    CHECK (snapshot_type IN ('PRE_IMPORT','POST_IMPORT','ROLLBACK')),
  schema_version text NOT NULL DEFAULT 'V7.02',
  state_json jsonb NOT NULL,
  checksum text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS for Import Center
ALTER TABLE public.import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS smartpos_import_batches_select ON public.import_batches;
DROP POLICY IF EXISTS smartpos_import_batches_insert ON public.import_batches;
DROP POLICY IF EXISTS smartpos_import_batches_update ON public.import_batches;
DROP POLICY IF EXISTS smartpos_import_items_select ON public.import_items;
DROP POLICY IF EXISTS smartpos_import_items_insert ON public.import_items;
DROP POLICY IF EXISTS smartpos_import_items_update ON public.import_items;
DROP POLICY IF EXISTS smartpos_import_changes_select ON public.import_changes;
DROP POLICY IF EXISTS smartpos_import_changes_insert ON public.import_changes;
DROP POLICY IF EXISTS smartpos_import_changes_update ON public.import_changes;
DROP POLICY IF EXISTS smartpos_import_snapshots_select ON public.import_snapshots;
DROP POLICY IF EXISTS smartpos_import_snapshots_insert ON public.import_snapshots;

CREATE POLICY smartpos_import_batches_select ON public.import_batches
FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY smartpos_import_batches_insert ON public.import_batches
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND created_by = auth.uid());
CREATE POLICY smartpos_import_batches_update ON public.import_batches
FOR UPDATE TO authenticated USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid() AND created_by = auth.uid());

CREATE POLICY smartpos_import_items_select ON public.import_items
FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY smartpos_import_items_insert ON public.import_items
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY smartpos_import_items_update ON public.import_items
FOR UPDATE TO authenticated USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());

CREATE POLICY smartpos_import_changes_select ON public.import_changes
FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY smartpos_import_changes_insert ON public.import_changes
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY smartpos_import_changes_update ON public.import_changes
FOR UPDATE TO authenticated USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());

CREATE POLICY smartpos_import_snapshots_select ON public.import_snapshots
FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY smartpos_import_snapshots_insert ON public.import_snapshots
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_import_batches_owner_created ON public.import_batches(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_import_batches_status ON public.import_batches(owner_id, status);
CREATE INDEX IF NOT EXISTS idx_import_items_batch ON public.import_items(batch_id, row_number);
CREATE INDEX IF NOT EXISTS idx_import_items_barcode ON public.import_items(owner_id, barcode) WHERE barcode IS NOT NULL AND barcode <> '';
CREATE INDEX IF NOT EXISTS idx_import_items_match ON public.import_items(owner_id, match_type, action);
CREATE INDEX IF NOT EXISTS idx_import_changes_batch ON public.import_changes(batch_id, created_at);
CREATE INDEX IF NOT EXISTS idx_import_snapshots_batch ON public.import_snapshots(batch_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_import_batches_updated_at ON public.import_batches;
CREATE TRIGGER trg_import_batches_updated_at
BEFORE UPDATE ON public.import_batches
FOR EACH ROW EXECUTE FUNCTION public.smartpos_touch_updated_at();

-- Finalize workflow without directly changing products.
CREATE OR REPLACE FUNCTION public.smartpos_finalize_import_batch(
  p_batch_id uuid,
  p_status text,
  p_summary jsonb DEFAULT '{}'::jsonb
)
RETURNS public.import_batches
LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE v_row public.import_batches;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_status NOT IN ('READY','COMMITTED','ROLLED_BACK','CANCELLED','FAILED')
    THEN RAISE EXCEPTION 'Invalid import status'; END IF;

  UPDATE public.import_batches
  SET status=p_status, summary=COALESCE(p_summary,'{}'::jsonb),
      updated_at=now(),
      committed_at=CASE WHEN p_status='COMMITTED' THEN now() ELSE committed_at END,
      rolled_back_at=CASE WHEN p_status='ROLLED_BACK' THEN now() ELSE rolled_back_at END
  WHERE id=p_batch_id AND owner_id=auth.uid()
  RETURNING * INTO v_row;

  IF NOT FOUND THEN RAISE EXCEPTION 'Import batch not found or not owned by current user'; END IF;
  RETURN v_row;
END;
$$;

-- ============================================================
-- Existing relational product tables: safe indexes only.
-- ============================================================
DO $$
BEGIN
  IF to_regclass('public.product_variants') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='product_variants' AND column_name='barcode') THEN
      CREATE INDEX IF NOT EXISTS idx_product_variants_barcode
      ON public.product_variants(barcode) WHERE barcode IS NOT NULL AND barcode <> '';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='product_variants' AND column_name='product_id') THEN
      CREATE INDEX IF NOT EXISTS idx_product_variants_product_id
      ON public.product_variants(product_id);
    END IF;
  END IF;

  IF to_regclass('public.products') IS NOT NULL
     AND EXISTS (SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='products' AND column_name='is_deleted') THEN
    CREATE INDEX IF NOT EXISTS idx_products_active
    ON public.products(id) WHERE is_deleted=false;
  END IF;
END $$;

-- Enable RLS on existing core tables without inventing destructive policies.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'products','product_variants','product_fractions',
    'categories','brands','suppliers','product_images'
  ] LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    END IF;
  END LOOP;
END $$;

-- Product image bucket: create only if missing.
INSERT INTO storage.buckets(id,name,public)
VALUES('product-images','product-images',true)
ON CONFLICT(id) DO NOTHING;

DROP POLICY IF EXISTS smartpos_storage_product_images_insert ON storage.objects;
DROP POLICY IF EXISTS smartpos_storage_product_images_update ON storage.objects;
DROP POLICY IF EXISTS smartpos_storage_product_images_delete ON storage.objects;

CREATE POLICY smartpos_storage_product_images_insert ON storage.objects
FOR INSERT TO anon, authenticated WITH CHECK(bucket_id='product-images');
CREATE POLICY smartpos_storage_product_images_update ON storage.objects
FOR UPDATE TO anon, authenticated USING(bucket_id='product-images')
WITH CHECK(bucket_id='product-images');
CREATE POLICY smartpos_storage_product_images_delete ON storage.objects
FOR DELETE TO anon, authenticated USING(bucket_id='product-images');

-- Documents bucket (external supplier invoices / utility bills uploaded from the
-- "เอกสาร" tab). The app code (uploadGenericFileToSupabase) has always targeted
-- this bucket, but no prior migration created it.
INSERT INTO storage.buckets(id,name,public)
VALUES('documents','documents',true)
ON CONFLICT(id) DO NOTHING;

DROP POLICY IF EXISTS smartpos_storage_documents_insert ON storage.objects;
DROP POLICY IF EXISTS smartpos_storage_documents_update ON storage.objects;
DROP POLICY IF EXISTS smartpos_storage_documents_delete ON storage.objects;

CREATE POLICY smartpos_storage_documents_insert ON storage.objects
FOR INSERT TO anon, authenticated WITH CHECK(bucket_id='documents');
CREATE POLICY smartpos_storage_documents_update ON storage.objects
FOR UPDATE TO anon, authenticated USING(bucket_id='documents')
WITH CHECK(bucket_id='documents');
CREATE POLICY smartpos_storage_documents_delete ON storage.objects
FOR DELETE TO anon, authenticated USING(bucket_id='documents');

INSERT INTO public.smartpos_migrations(version,description)
VALUES('V7.02','Production migration: Import Center, snapshots, field changes, audit/error telemetry, RLS and safety indexes')
ON CONFLICT(version) DO UPDATE
SET description=EXCLUDED.description, applied_at=now();

COMMIT;

-- INSTALLATION REPORT
SELECT
  'SMARTPOS_PRODUCTION_V7_02' AS migration,
  now() AS checked_at,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='smartpos_migrations') AS migrations_table,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='import_batches') AS import_batches,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='import_items') AS import_items,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='import_changes') AS import_changes,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='import_snapshots') AS import_snapshots,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='audit_log') AS audit_log,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='error_logs') AS error_logs,
  EXISTS(SELECT 1 FROM storage.buckets WHERE id='product-images') AS product_images_bucket;

SELECT schemaname,tablename,rowsecurity
FROM pg_tables
WHERE schemaname='public'
AND tablename IN(
 'products','product_variants','product_fractions','categories',
 'brands','suppliers','product_images','audit_log','error_logs',
 'import_batches','import_items','import_changes','import_snapshots'
)
ORDER BY tablename;

-- Optional expiry for explicitly time-limited evaluation users.
-- Normal accounts have no app_metadata.brandguard_access_until and are unaffected.
-- Only the trusted admin can set this field; user_metadata is never consulted.
-- Expiry is an integer Unix timestamp. Backend checks the same field at login/me.
BEGIN;
CREATE OR REPLACE FUNCTION public.bg_access_active()
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN NOT ((SELECT auth.jwt())->'app_metadata' ? 'brandguard_access_until') THEN true
    WHEN jsonb_typeof((SELECT auth.jwt())->'app_metadata'->'brandguard_access_until') = 'number'
      AND ((SELECT auth.jwt())->'app_metadata'->>'brandguard_access_until') ~ '^[0-9]{1,12}$'
    THEN ((SELECT auth.jwt())->'app_metadata'->>'brandguard_access_until')::numeric
      > EXTRACT(EPOCH FROM now())
    ELSE false
  END
$$;
REVOKE ALL ON FUNCTION public.bg_access_active() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bg_access_active() TO authenticated;

DROP POLICY IF EXISTS "brandguard_demo_expiry_read" ON storage.objects;
CREATE POLICY "brandguard_demo_expiry_read" ON storage.objects
AS RESTRICTIVE FOR SELECT TO authenticated
USING (bucket_id <> 'brandguard-files' OR (SELECT public.bg_access_active()));

DROP POLICY IF EXISTS "brandguard_demo_expiry_upload" ON storage.objects;
CREATE POLICY "brandguard_demo_expiry_upload" ON storage.objects
AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (bucket_id <> 'brandguard-files' OR (SELECT public.bg_access_active()));
COMMIT;

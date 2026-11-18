-- Run AFTER migrations/001_core.sql in your Supabase SQL editor.
-- Uses the default bucket name; change all occurrences if you customize it.
-- No service-role/secret key is exposed to the app or required for normal uploads.
BEGIN;
REVOKE ALL ON TABLE public.bg_entities, public.bg_documents FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('brandguard-files', 'brandguard-files', false, 5242880,
        ARRAY['text/plain', 'text/markdown', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "brandguard_own_upload" ON storage.objects;
CREATE POLICY "brandguard_own_upload" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'brandguard-files'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

DROP POLICY IF EXISTS "brandguard_private_read" ON storage.objects;
CREATE POLICY "brandguard_private_read" ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'brandguard-files'
    AND (
        (storage.foldername(name))[1] = (SELECT auth.uid()::text)
        OR (SELECT auth.jwt() -> 'app_metadata' ->> 'brandguard_role') IN ('reviewer', 'admin')
    )
);
-- No overwrite/update/delete policy: uploads use immutable random object keys.
-- Reviewers must be assigned by a server admin, never by user_metadata.
COMMIT;

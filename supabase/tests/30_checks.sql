-- ============================================================================
-- Findora — checks for 30_chat_photos.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 30.
-- Read-only. NOT run by the author.
-- ============================================================================

-- 1. Both tables have the new column (expect 2 rows).
select table_name from information_schema.columns
where table_schema = 'public' and column_name = 'image_path'
  and table_name in ('messages', 'contact_messages');

-- 2. The bucket exists and is private with limits (expect public = false, 5242880).
select id, public, file_size_limit, allowed_mime_types
from storage.buckets where id = 'chat-images';

-- 3. The three storage rules exist (expect 3 rows).
select policyname from pg_policies
where schemaname = 'storage' and tablename = 'objects' and policyname like 'chat images %';

-- 4. A malformed path is "no", never an error (expect false, false).
select public.can_use_chat_folder('nonsense'),
       public.can_use_chat_folder('m/not-a-uuid/x.jpg');

-- 5. Signed-out callers can't run the helper (expect false).
select has_function_privilege('anon', 'public.can_use_chat_folder(text)', 'execute');

-- 6. Photo-only previews: no message may have empty text AND no photo (expect 0).
select count(*) from public.messages where content = '' and image_path is null;

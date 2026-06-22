-- =============================================================
-- 003_message_images_policies.sql
-- Storage policies for the `message-images` bucket.
-- Run once in Supabase → SQL Editor (or via the CLI).
-- =============================================================

-- 1.  Make sure the bucket exists.  Safe to re-run.
insert into storage.buckets (id, name, public)
values ('message-images', 'message-images', true)
on conflict (id) do update set public = excluded.public;

-- 2.  Drop old policies so this script is idempotent.
drop policy if exists "message_images_insert" on storage.objects;
drop policy if exists "message_images_select" on storage.objects;
drop policy if exists "message_images_update" on storage.objects;
drop policy if exists "message_images_delete" on storage.objects;

-- 3.  Any authenticated user can upload to message-images.
--     The conversation participant check is enforced at the
--     messages-table insert level — uploaded files without a
--     matching message row are orphaned and can be cleaned up.
create policy "message_images_insert"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'message-images');

-- 4.  Anyone (incl. anon) can read — bucket is public so AsyncImage works.
create policy "message_images_select"
on storage.objects
for select
to public
using (bucket_id = 'message-images');

-- 5.  Uploader can replace / delete their own files.
create policy "message_images_update"
on storage.objects
for update
to authenticated
using (bucket_id = 'message-images' and owner = auth.uid());

create policy "message_images_delete"
on storage.objects
for delete
to authenticated
using (bucket_id = 'message-images' and owner = auth.uid());

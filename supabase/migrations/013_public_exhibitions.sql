-- Cached site versions read /posts directly. Expose the same public material
-- as the catalogue while keeping member-only story bodies behind sign-in.
begin;
create function public.free_story_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.posts
  where status = 'published' and deleted_at is null
    and coalesce(design->>'section','journal') = 'journal'
  order by published_at desc, id limit 1;
$$;
revoke all on function public.free_story_id() from public;
grant execute on function public.free_story_id() to anon;
create policy public_site_preview on public.posts for select to anon using (
  status = 'published' and deleted_at is null and (
    design->>'section' in ('exhibitions','events','notes') or id = (select public.free_story_id())
  )
);
commit;

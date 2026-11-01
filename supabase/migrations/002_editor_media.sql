-- Run after 001_platform.sql. Media and editable published stories.
alter table public.posts add column images jsonb not null default '[]'::jsonb check(jsonb_typeof(images)='array' and jsonb_array_length(images)<=12);
alter table public.posts add column author text not null default '';
alter table public.posts add column source text not null default '';
alter table public.posts add column links jsonb not null default '[]'::jsonb check(jsonb_typeof(links)='array');
alter table public.posts add column translations jsonb not null default '{}'::jsonb check(jsonb_typeof(translations)='object');
alter table public.posts add column source_id text unique;
grant insert(images,author,source,links,translations,source_id),update(images,author,source,links,translations) on public.posts to authenticated;
drop policy admin_posts_edit on public.posts;
create policy admin_posts_edit on public.posts for update to authenticated using(public.is_admin()) with check(public.is_admin());
-- Clients still cannot modify status, author_id, published_at or source_id.
alter table public.deliveries add column post_snapshot jsonb;
update public.deliveries d set post_snapshot=to_jsonb(p) from public.posts p where p.id=d.post_id;
drop function public.publish_post(uuid);
create function public.publish_post(post_id uuid,send_newsletter boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare p public.posts;
begin
 if not public.is_admin() then raise exception 'Administrator required'; end if;
 select * into p from public.posts where id=post_id for update;
 if p.id is null then raise exception 'Post not found'; end if;
 if p.status='published' then return; end if;
 update public.posts set status='published',published_at=now() where id=post_id;
 if send_newsletter then
  insert into public.deliveries(post_id,user_id,post_snapshot)
  select p.id,s.user_id,to_jsonb(p) from public.subscriptions s join auth.users u on u.id=s.user_id
  where s.subscribed and u.email_confirmed_at is not null
  on conflict do nothing;
 end if;
end;$$;
revoke all on function public.publish_post(uuid,boolean) from public;
grant execute on function public.publish_post(uuid,boolean) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('post-images','post-images',true,10485760,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy admin_image_insert on storage.objects for insert to authenticated with check(bucket_id='post-images' and public.is_admin());
create policy public_image_read on storage.objects for select to anon,authenticated using(bucket_id='post-images');
-- Immutable image names: upload a new image to replace one in a story. No public overwrite/delete.

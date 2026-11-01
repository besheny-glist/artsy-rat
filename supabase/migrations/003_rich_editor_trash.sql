alter table public.posts add column rich_body text not null default '' check(length(rich_body)<=100000);
alter table public.posts add column image_meta jsonb not null default '{}'::jsonb;
alter table public.posts add column design jsonb not null default '{}'::jsonb;
alter table public.posts add column deleted_at timestamptz;
grant insert(rich_body,image_meta,design),update(rich_body,image_meta,design) on public.posts to authenticated;
drop policy public_posts on public.posts;
create policy public_posts on public.posts for select to anon,authenticated using(status='published' and deleted_at is null);
drop policy admin_posts_edit on public.posts;
create policy admin_posts_edit on public.posts for update to authenticated using(public.is_admin() and deleted_at is null) with check(public.is_admin() and deleted_at is null);

create function public.trash_post(post_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator required'; end if;
 perform 1 from public.posts where id=post_id for update;
 update public.posts set deleted_at=now() where id=post_id;
 update public.deliveries set status='cancelled',lease_until=null where public.deliveries.post_id=trash_post.post_id and status in ('pending','failed','sending','review');
end;$$;
create function public.restore_post(post_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator required'; end if;
 update public.posts set deleted_at=null where id=post_id;
end;$$;
revoke all on function public.trash_post(uuid),public.restore_post(uuid) from public;
grant execute on function public.trash_post(uuid),public.restore_post(uuid) to authenticated;
-- Only stable import ids are exposed, never draft content. Prevent the static
-- bootstrap copy from reappearing after its database version is trashed.
create function public.imported_story_state() returns table(source_id text) language sql stable security definer set search_path='' as $$select p.source_id from public.posts p where p.source_id is not null;$$;
revoke all on function public.imported_story_state() from public;
grant execute on function public.imported_story_state() to anon,authenticated;

alter table public.deliveries add column recipient_email text;
alter table public.deliveries add column recipient_language text;
update public.deliveries d set recipient_email=u.email,recipient_language=s.language from auth.users u,public.subscriptions s where d.user_id=u.id and s.user_id=u.id;

create or replace function public.publish_post(post_id uuid,send_newsletter boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare p public.posts;
begin
 if not public.is_admin() then raise exception 'Administrator required'; end if;
 select * into p from public.posts where id=post_id for update;
 if p.id is null or p.deleted_at is not null then raise exception 'Post unavailable'; end if;
 if p.status='published' then return; end if;
 update public.posts set status='published',published_at=now() where id=post_id;
 if send_newsletter then
  insert into public.deliveries(post_id,user_id,post_snapshot,recipient_email,recipient_language)
  select p.id,s.user_id,to_jsonb(p),u.email,s.language from public.subscriptions s join auth.users u on u.id=s.user_id
  where s.subscribed and u.email_confirmed_at is not null on conflict do nothing;
 end if;
end;$$;

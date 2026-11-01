-- Select exactly two optional slots atomically, using existing admin access.
create or replace function public.set_home_wall(left_post uuid default null,right_post uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator required'; end if;
 if left_post is not null and left_post=right_post then raise exception 'Choose two different posts'; end if;
 perform pg_advisory_xact_lock(875310);
 if exists(select 1 from unnest(array[left_post,right_post]) as x(id) where x.id is not null and not exists(select 1 from public.posts p where p.id=x.id and p.status='published' and p.deleted_at is null and coalesce((p.design->'exhibition'->>'demo')::boolean,false)=false)) then raise exception 'Published post required'; end if;
 update public.posts set design=coalesce(design,'{}'::jsonb)-'homeSlot' where design ? 'homeSlot';
 update public.posts set design=jsonb_set(coalesce(design,'{}'::jsonb),'{homeSlot}','"left"') where id=left_post;
 update public.posts set design=jsonb_set(coalesce(design,'{}'::jsonb),'{homeSlot}','"right"') where id=right_post;
end;$$;
revoke all on function public.set_home_wall(uuid,uuid) from public;
grant execute on function public.set_home_wall(uuid,uuid) to authenticated;

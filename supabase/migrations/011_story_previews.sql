create or replace function public.public_catalog() returns setof public.posts language plpgsql stable security definer set search_path='' as $$
declare p public.posts; free_story uuid;
begin
 select id into free_story from public.posts where status='published' and deleted_at is null and coalesce(design->>'section','journal')='journal' order by published_at desc,id limit 1;
 for p in select * from public.posts where status='published' and deleted_at is null and coalesce(design->>'section','journal')<>'newsletter' order by published_at desc loop
  if auth.uid() is null and coalesce(p.design->>'section','journal')='journal' and p.id<>free_story then p.body='';p.rich_body='';p.translations=coalesce((select jsonb_object_agg(key,jsonb_build_object('title',value->>'title','summary',value->>'summary')) from jsonb_each(p.translations)),'{}');p.images=case when jsonb_array_length(p.images)>0 then jsonb_build_array(p.images->0) else '[]'::jsonb end;p.design=p.design||'{"membersOnly":true}';end if;
  return next p;
 end loop;
end;$$;

begin;
create table if not exists public.places (
 id text primary key, name text not null check(length(name) between 1 and 180), type text not null default '', city text not null default '',
 map_url text not null default '', website text not null default '', social_url text not null default '', ticket text not null default '',
 reference_url text not null default '', program jsonb not null default '{}', origin text not null default '', additional_urls jsonb not null default '[]',
 active boolean not null default true
);
alter table public.places enable row level security;
grant select on public.places to anon,authenticated; grant insert,update on public.places to authenticated;
create policy places_read on public.places for select using(active or public.is_admin());
create policy places_write on public.places for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.monitor_sources add column if not exists place_id text references public.places;
alter table public.monitor_sources add column if not exists retired boolean not null default false;
-- Previous entries are archived, not destroyed. Only the supplied catalogue is active.
update public.monitor_sources set retired=true,enabled=false;
create or replace function public.monitor_source_directory() returns setof public.monitor_sources language sql stable security definer set search_path='' as $$
 select s.* from public.monitor_sources s join public.places p on p.id=s.place_id where not s.retired and p.active order by s.id limit 1000;
$$;
create table public.content_submissions (
 id uuid primary key default gen_random_uuid(),user_id uuid not null default auth.uid() references auth.users,
 place_id text references public.places, target_post_id uuid references public.posts,
 kind text not null check(kind in ('exhibitions','events','notes','institution')),
 title text not null check(length(title) between 1 and 180), summary text not null default '', body text not null default '' check(length(body)<=20000),
 image_url text not null default '', source text not null default '',start_date date,end_date date,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 review_note text not null default '', post_id uuid references public.posts,created_at timestamptz not null default now()
);
alter table public.content_submissions enable row level security;
grant select on public.content_submissions to authenticated;
grant insert(place_id,target_post_id,kind,title,summary,body,image_url,source,start_date,end_date) on public.content_submissions to authenticated;
create policy submissions_read on public.content_submissions for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy submissions_insert on public.content_submissions for insert to authenticated with check(user_id=auth.uid() and status='pending' and exists(select 1 from public.places where id=place_id and active));
create table public.place_members(user_id uuid references auth.users,place_id text references public.places,primary key(user_id,place_id));
alter table public.place_members enable row level security;grant select on public.place_members to authenticated;
create policy memberships_read on public.place_members for select to authenticated using(user_id=auth.uid() or public.is_admin());
create function public.review_submission(submission_id uuid,approve boolean,feedback text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare s public.content_submissions; p public.places; new_id uuid; d jsonb;
begin
 if not public.is_admin() then raise exception 'Administrator required';end if;
 select * into s from public.content_submissions where id=submission_id for update;
 if s.id is null or s.status<>'pending' then raise exception 'Submission unavailable';end if;
 if approve then
  if s.kind='institution' then
   insert into public.place_members values(s.user_id,s.place_id) on conflict do nothing;
  else
   select * into p from public.places where id=s.place_id;
   if s.kind='notes' and not exists(select 1 from public.posts where id=s.target_post_id and design->>'placeId'=s.place_id and design->>'section' in ('exhibitions','events') and deleted_at is null) then raise exception 'Choose a programme at this place';end if;
   d=jsonb_build_object('section',s.kind,'placeId',s.place_id,'parentPostId',s.target_post_id,'exhibition',jsonb_build_object('venue',p.name,'mapUrl',p.map_url,'startDate',s.start_date,'endDate',s.end_date));
   if s.target_post_id is not null and s.kind<>'notes' then
    if not exists(select 1 from public.place_members where user_id=s.user_id and place_id=s.place_id) then raise exception 'Place membership required';end if;
    if not exists(select 1 from public.posts where id=s.target_post_id and design->>'placeId'=s.place_id and deleted_at is null) then raise exception 'Invalid target';end if;
    update public.posts set title=s.title,summary=left(coalesce(nullif(s.summary,''),s.body),500),body=s.body,rich_body='',images=case when s.image_url='' then '[]'::jsonb else jsonb_build_array(s.image_url) end,source=s.source,design=d where id=s.target_post_id;
    new_id=s.target_post_id;
   else
    insert into public.posts(title,summary,body,language,author_id,images,source,design)
    values(s.title,left(coalesce(nullif(s.summary,''),nullif(s.body,''),s.title),500),coalesce(nullif(s.body,''),s.title),'en',auth.uid(),case when s.image_url='' then '[]'::jsonb else jsonb_build_array(s.image_url) end,s.source,d) returning id into new_id;
   end if;
  end if;
 end if;
 update public.content_submissions set status=case when approve then 'approved' else 'rejected' end,review_note=left(feedback,2000),post_id=new_id where id=s.id;
 return new_id;
end;$$;
revoke all on function public.review_submission(uuid,boolean,text) from public;grant execute on function public.review_submission(uuid,boolean,text) to authenticated;
-- Publication and mailing are separate operations, including older clients.
create or replace function public.publish_post(post_id uuid,send_newsletter boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator required';end if;
 if not exists(select 1 from public.posts where id=post_id and deleted_at is null) then raise exception 'Post unavailable';end if;
 update public.posts set status='published',published_at=coalesce(published_at,now()) where id=post_id;
end;$$;
create table public.newsletter_issues(id uuid primary key default gen_random_uuid(),title text not null, intro text not null default '',post_ids uuid[] not null default '{}',language text not null default 'en' check(language in ('en','hu','ru')),week_of date not null default current_date,status text not null default 'draft' check(status in ('draft','queued')),post_id uuid references public.posts,created_at timestamptz not null default now());
alter table public.newsletter_issues enable row level security;
grant select,insert(id,title,intro,post_ids,language,week_of),update(id,title,intro,post_ids,language,week_of) on public.newsletter_issues to authenticated;
create policy newsletter_admin on public.newsletter_issues for all to authenticated using(public.is_admin()) with check(public.is_admin() and status='draft');
create table public.editorial_settings(id boolean primary key default true check(id),newsletter_enabled boolean not null default false);
insert into public.editorial_settings values(true,false);
alter table public.editorial_settings enable row level security;grant select on public.editorial_settings to authenticated;create policy settings_read on public.editorial_settings for select to authenticated using(public.is_admin());
create function public.queue_newsletter(issue_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare n public.newsletter_issues; pid uuid; text_body text; first_image jsonb;
begin
 if not public.is_admin() then raise exception 'Administrator required';end if;
 if not exists(select 1 from public.editorial_settings where newsletter_enabled) then raise exception 'NEWSLETTER_NOT_READY';end if;
 select * into n from public.newsletter_issues where id=issue_id for update;
 if n.id is null then raise exception 'Issue not found';end if;
 if n.status='queued' then return n.post_id;end if;
 if cardinality(n.post_ids)=0 or cardinality(n.post_ids)>30 then raise exception 'Choose 1 to 30 posts';end if;
 select n.intro||E'\n\n'||string_agg(p.title||E'\n'||p.summary||E'\nhttps://besheny-glist.github.io/artsy-rat/#post='||p.id,E'\n\n' order by x.ord) into text_body
 from unnest(n.post_ids) with ordinality x(id,ord) join public.posts p on p.id=x.id where p.status='published' and p.deleted_at is null;
 if text_body is null then raise exception 'No published materials selected';end if;
 insert into public.posts(title,summary,body,language,author_id,design) values(n.title,left(coalesce(nullif(n.intro,''),n.title),500),left(text_body,20000),n.language,auth.uid(),'{"section":"newsletter"}') returning id into pid;
 insert into public.deliveries(post_id,user_id,post_snapshot,recipient_email,recipient_language)
 select pid,s.user_id,to_jsonb(p),u.email,s.language from public.posts p,public.subscriptions s join auth.users u on u.id=s.user_id where p.id=pid and s.subscribed and s.language=n.language and u.email_confirmed_at is not null on conflict do nothing;
 update public.newsletter_issues set status='queued',post_id=pid where id=n.id;return pid;
end;$$;
revoke all on function public.queue_newsletter(uuid) from public;grant execute on function public.queue_newsletter(uuid) to authenticated;
create function public.save_counts() returns table(post_id uuid,saves bigint) language sql stable security definer set search_path='' as $$select a.post_id,count(*) from public.art_passport a join public.posts p on p.id=a.post_id where a.saved and p.status='published' and p.deleted_at is null group by a.post_id;$$;
revoke all on function public.save_counts() from public;grant execute on function public.save_counts() to anon,authenticated;
create table public.place_views(place_id text references public.places,user_id uuid references auth.users,view_date date default current_date,primary key(place_id,user_id,view_date));
alter table public.place_views enable row level security;
create function public.record_place_view(venue_id text) returns void language plpgsql security definer set search_path='' as $$begin if auth.uid() is not null then insert into public.place_views values(venue_id,auth.uid(),current_date) on conflict do nothing;end if;end;$$;
create function public.place_statistics() returns table(place_id text,views bigint,saves bigint,exhibitions bigint,events bigint) language sql stable security definer set search_path='' as $$
 select p.id,(select count(*) from public.place_views v where v.place_id=p.id),(select count(*) from public.art_passport a join public.posts x on x.id=a.post_id where a.saved and x.design->>'placeId'=p.id),(select count(*) from public.posts x where x.design->>'placeId'=p.id and x.status='published' and x.deleted_at is null and x.design->>'section'='exhibitions'),(select count(*) from public.posts x where x.design->>'placeId'=p.id and x.status='published' and x.deleted_at is null and x.design->>'section'='events') from public.places p where public.is_admin() or exists(select 1 from public.place_members m where m.place_id=p.id and m.user_id=auth.uid());$$;
revoke all on function public.record_place_view(text),public.place_statistics() from public;grant execute on function public.record_place_view(text),public.place_statistics() to authenticated;
-- Anonymous readers receive one complete editorial story; all others are teasers.
create function public.public_catalog() returns setof public.posts language plpgsql stable security definer set search_path='' as $$
declare p public.posts; free_story uuid;
begin
 select id into free_story from public.posts where status='published' and deleted_at is null and coalesce(design->>'section','journal')='journal' order by published_at desc,id limit 1;
 for p in select * from public.posts where status='published' and deleted_at is null and coalesce(design->>'section','journal')<>'newsletter' order by published_at desc loop
  if auth.uid() is null and coalesce(p.design->>'section','journal')='journal' and p.id<>free_story then p.body='';p.rich_body='';p.translations='{}';p.images='[]';p.design=p.design||'{"membersOnly":true}';end if;
  return next p;
 end loop;
end;$$;
revoke all on function public.public_catalog() from public;grant execute on function public.public_catalog() to anon,authenticated;
drop policy public_posts on public.posts;
create policy public_posts on public.posts for select to authenticated using(status='published' and deleted_at is null and coalesce(design->>'section','journal')<>'newsletter');
-- Public image uploads from contributors are scoped to their own directory.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('submission-images','submission-images',true,10485760,array['image/jpeg','image/png','image/webp']) on conflict do nothing;
create policy submission_image_write on storage.objects for insert to authenticated with check(bucket_id='submission-images' and (storage.foldername(name))[1]=auth.uid()::text);
create policy submission_image_read on storage.objects for select using(bucket_id='submission-images');
create function public.sync_place_sources(venue_id text) returns void language plpgsql security definer set search_path='' as $$
declare p public.places; u text; k text; sid text;
begin
 if not public.is_admin() then raise exception 'Administrator required';end if;
 select * into p from public.places where id=venue_id;
 if p.id is null then raise exception 'Place not found';end if;
 update public.monitor_sources set enabled=false,retired=true where place_id=p.id;
 for u in select distinct x from (select unnest(array[p.website,p.social_url,case when p.website='' and p.social_url='' then p.reference_url else '' end]) x union select jsonb_array_elements_text(p.additional_urls)) urls where x<>'' loop
  if u!~'^https?://' or u~'@' then raise exception 'Invalid public URL';end if;
  k=case when u~'(facebook|instagram)\.com' then 'manual' when u~'exindex.hu/.*/venue/' then 'exindex' else 'webpage' end;
  sid='place-source-'||md5(p.id||u);
  insert into public.monitor_sources(id,name,url,kind,category,city,enabled,place_id,retired) values(sid,p.name,u,k,case when lower(p.type||p.name) like '%museum%' then 'museum' else 'gallery' end,p.city,p.active,p.id,false)
  on conflict(id) do update set name=excluded.name,url=excluded.url,kind=excluded.kind,city=excluded.city,enabled=excluded.enabled,retired=false;
 end loop;
end;$$;
revoke all on function public.sync_place_sources(text) from public;grant execute on function public.sync_place_sources(text) to authenticated;

commit;

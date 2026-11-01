begin;
-- Source URLs and discovery headlines are public data; editorial decisions stay admin-only.
create table public.monitor_sources(
 id text primary key check(length(id)<=80),
 name text not null check(length(name) between 1 and 160),
 url text not null check(length(url)<=1000 and url ~ '^https?://' and url !~ '@'),
 kind text not null check(kind in ('exindex','rss','webpage','telegram','manual')),
 category text not null check(category in ('gallery','museum','social')),
 city text not null default 'Budapest',
 enabled boolean not null default true
);
alter table public.monitor_sources enable row level security;
revoke all on public.monitor_sources from anon,authenticated;
grant select,insert,update on public.monitor_sources to authenticated;
create policy editor_sources on public.monitor_sources for all to authenticated using(public.is_admin()) with check(public.is_admin());
create function public.monitor_source_directory() returns setof public.monitor_sources language sql stable security definer set search_path='' as $$ select * from public.monitor_sources order by id limit 500; $$;
revoke all on function public.monitor_source_directory() from public;
grant execute on function public.monitor_source_directory() to anon,authenticated;
create table public.monitor_reviews(
 item_id text primary key check(length(item_id)=64),
 status text not null check(status in ('new','shortlisted','dismissed','drafted')),
 post_id uuid references public.posts on delete set null
);
alter table public.monitor_reviews enable row level security;
revoke all on public.monitor_reviews from anon,authenticated;
grant select,insert,update on public.monitor_reviews to authenticated;
create policy editor_reviews on public.monitor_reviews for all to authenticated using(public.is_admin()) with check(public.is_admin());
commit;

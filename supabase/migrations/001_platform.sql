-- Run once in a new Supabase project's SQL Editor.
create table public.admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.admins where user_id=auth.uid()); $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create table public.posts(
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 180),
 summary text not null check(length(summary) between 1 and 500), body text not null check(length(body) between 1 and 20000),
 language text not null check(language in ('en','hu','ru')), status text not null default 'draft' check(status in ('draft','published')),
 created_at timestamptz not null default now(), published_at timestamptz,
 author_id uuid not null default auth.uid() references auth.users(id)
);
alter table public.posts enable row level security;
create policy public_posts on public.posts for select to anon,authenticated using(status='published');
create policy admin_posts_read on public.posts for select to authenticated using(public.is_admin());
create policy admin_posts_insert on public.posts for insert to authenticated with check(public.is_admin() and status='draft' and author_id=auth.uid());
create policy admin_posts_edit on public.posts for update to authenticated using(public.is_admin() and status='draft') with check(public.is_admin() and status='draft');
revoke all on public.posts from anon,authenticated;
grant select on public.posts to anon,authenticated;
grant insert(title,summary,body,language),update(title,summary,body,language) on public.posts to authenticated;

create table public.subscriptions(
 user_id uuid primary key references auth.users(id) on delete cascade,
 subscribed boolean not null default false, language text not null default 'en' check(language in ('en','hu','ru')),
 consent_at timestamptz, updated_at timestamptz not null default now(), unsubscribe_token uuid not null unique default gen_random_uuid()
);
alter table public.subscriptions enable row level security;
revoke all on public.subscriptions from anon,authenticated;
create function public.my_subscription() returns table(subscribed boolean,language text) language sql stable security definer set search_path='' as $$select s.subscribed,s.language from public.subscriptions s where s.user_id=auth.uid();$$;
create function public.set_subscription(enabled boolean,preferred_language text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Confirmed account required'; end if;
 if preferred_language not in ('en','hu','ru') then raise exception 'Invalid language'; end if;
 insert into public.subscriptions(user_id,subscribed,language,consent_at) values(auth.uid(),enabled,preferred_language,case when enabled then now() end)
 on conflict(user_id) do update set subscribed=enabled,language=preferred_language,consent_at=case when enabled then now() else public.subscriptions.consent_at end,updated_at=now();
end;$$;
revoke all on function public.my_subscription(),public.set_subscription(boolean,text) from public;
grant execute on function public.my_subscription(),public.set_subscription(boolean,text) to authenticated;

create table public.deliveries(
 id uuid primary key default gen_random_uuid(),post_id uuid not null references public.posts(id),
 user_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','sending','sent','failed','cancelled','review')),
 created_at timestamptz not null default now(),first_attempt_at timestamptz,lease_until timestamptz,attempts int not null default 0,
 provider_id text,unique(post_id,user_id)
);
alter table public.deliveries enable row level security;
create policy admin_delivery_read on public.deliveries for select to authenticated using(public.is_admin());
revoke all on public.deliveries from anon,authenticated;
grant select on public.deliveries to authenticated;
create function public.publish_post(post_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare p public.posts;
begin
 if not public.is_admin() then raise exception 'Administrator required'; end if;
 select * into p from public.posts where id=post_id for update;
 if p.id is null then raise exception 'Post not found'; end if;
 if p.status='published' then return; end if;
 update public.posts set status='published',published_at=now() where id=post_id;
 insert into public.deliveries(post_id,user_id)
 select p.id,s.user_id from public.subscriptions s join auth.users u on u.id=s.user_id
 where s.subscribed and s.language=p.language and u.email_confirmed_at is not null on conflict do nothing;
end;$$;
revoke all on function public.publish_post(uuid) from public;
grant execute on function public.publish_post(uuid) to authenticated;

-- Only the trusted Edge Function may claim work. Recover leases within Resend's
-- idempotency window. Older uncertain deliveries require manual reconciliation.
create function public.claim_deliveries() returns setof public.deliveries language plpgsql security definer set search_path='' as $$
begin
 update public.deliveries set status='review' where status in ('sending','failed') and first_attempt_at < now()-interval '20 hours';
 return query with candidates as (
 select id from public.deliveries where status='pending' or (status='failed' and lease_until<now()) or (status='sending' and lease_until<now())
 order by created_at limit 5 for update skip locked
 ) update public.deliveries d set status='sending',lease_until=now()+interval '5 minutes',first_attempt_at=coalesce(first_attempt_at,now()),attempts=attempts+1
 from candidates c where d.id=c.id returning d.*;
end;$$;
revoke all on function public.claim_deliveries() from public,anon,authenticated;
grant execute on function public.claim_deliveries() to service_role;

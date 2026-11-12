create or replace function public.queue_newsletter(issue_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare n public.newsletter_issues; pid uuid; text_body text; first_image jsonb;
begin
 if not public.is_admin() then raise exception 'Administrator required';end if;
 if not exists(select 1 from public.editorial_settings where newsletter_enabled) then raise exception 'NEWSLETTER_NOT_READY';end if;
 select * into n from public.newsletter_issues where id=issue_id for update;
 if n.id is null then raise exception 'Issue not found';end if;
 if n.status='queued' then return n.post_id;end if;
 if cardinality(n.post_ids)=0 or cardinality(n.post_ids)>30 then raise exception 'Choose 1 to 30 posts';end if;
 select n.intro||E'\n\n'||string_agg(p.title||E'\n'||p.summary||E'\nhttps://artsyrat.eu/#post='||p.id,E'\n\n' order by x.ord) into text_body
 from unnest(n.post_ids) with ordinality x(id,ord) join public.posts p on p.id=x.id where p.status='published' and p.deleted_at is null;
 if text_body is null then raise exception 'No published materials selected';end if;
 insert into public.posts(title,summary,body,language,author_id,design) values(n.title,left(coalesce(nullif(n.intro,''),n.title),500),left(text_body,20000),n.language,auth.uid(),'{"section":"newsletter"}') returning id into pid;
 insert into public.deliveries(post_id,user_id,post_snapshot,recipient_email,recipient_language)
 select pid,s.user_id,to_jsonb(p),u.email,s.language from public.posts p,public.subscriptions s join auth.users u on u.id=s.user_id where p.id=pid and s.subscribed and s.language=n.language and u.email_confirmed_at is not null on conflict do nothing;
 update public.newsletter_issues set status='queued',post_id=pid where id=n.id;return pid;
end;$$;

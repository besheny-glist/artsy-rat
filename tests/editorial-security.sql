begin;
-- Rollback-only integration checks; no test records or messages survive.
set local role anon;
do $$begin
 if (select count(*) from public.places)<>86 then raise exception 'Wrong catalogue size';end if;
 if exists(select 1 from public.monitor_source_directory() where retired or place_id is null) then raise exception 'Legacy source exposed';end if;
 if (select count(*) from public.public_catalog() where coalesce(design->>'section','journal')='journal' and body<>'')<>1 then raise exception 'Expected one free story';end if;
 if exists(select 1 from public.public_catalog() where design->>'membersOnly'='true' and (body<>'' or rich_body<>'')) then raise exception 'Member text exposed';end if;
end;$$;
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admins limit 1),true);
set local role authenticated;
do $$declare p uuid;before_count bigint;issue uuid;
begin
 if not public.is_admin() then raise exception 'Admin context required';end if;
 select count(*) into before_count from public.deliveries;
 insert into public.posts(title,summary,body,language,design) values('QA rollback','QA rollback','QA rollback','en','{"section":"events"}') returning id into p;
 perform public.publish_post(p,true);
 if (select count(*) from public.deliveries)<>before_count then raise exception 'Publish queued an email';end if;
 insert into public.newsletter_issues(title,post_ids) values('QA rollback',array[p]) returning id into issue;
 update public.newsletter_issues set title='QA updated' where id=issue;
 if not exists(select 1 from public.newsletter_issues where id=issue and title='QA updated') then raise exception 'Issue save failed';end if;
end;$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from auth.users where id not in(select user_id from public.admins) limit 1),true);
set local role authenticated;
do $$declare sid uuid;
begin
 if auth.uid() is null then raise exception 'No ordinary account for test';end if;
 insert into public.content_submissions(place_id,kind,title,body) select id,'events','QA pending','QA pending' from public.places limit 1 returning id into sid;
 begin
  perform public.review_submission(sid,true,'');
  raise exception 'PRIVILEGE_ESCALATION';
 exception when others then
  if SQLERRM<>'Administrator required' then raise;end if;
 end;
 if exists(select 1 from public.place_statistics()) then raise exception 'Unlinked member can read stats';end if;
end;$$;
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admins limit 1),true);
set local role authenticated;
do $$declare submission public.content_submissions; event_id uuid; note_id uuid; invitation uuid;
begin
 select * into strict submission from public.content_submissions where title='QA pending' and status='pending';
 event_id=public.review_submission(submission.id,true,'Reviewed');
 if not exists(select 1 from public.posts where id=event_id and status='draft' and design->>'section'='events') then raise exception 'Expected an Art Club draft';end if;
 perform public.publish_post(event_id,false);
 insert into public.content_submissions(place_id,target_post_id,kind,title,body) values(submission.place_id,event_id,'notes','QA note','QA detail') returning id into note_id;
 note_id=public.review_submission(note_id,true,'');
 perform public.publish_post(note_id,false);
 if not exists(select 1 from public.public_catalog() where id=note_id and design->>'parentPostId'=event_id::text) then raise exception 'Note lost its parent';end if;
 insert into public.art_passport(post_id,saved) values(event_id,true);
 if not exists(select 1 from public.save_counts() where post_id=event_id and saves=1) then raise exception 'Event saves failed';end if;
 insert into public.art_invitations(post_id,sender_name,message,style,starts_at) values(event_id,'QA','QA postcard','editorial',now()+interval '1 day') returning id into invitation;
 if public.read_art_invitation(invitation)->>'post_id'<>event_id::text then raise exception 'Postcard failed';end if;
end;$$;
reset role;
rollback;
select 'PASS: catalogue, member gate, publication without email, newsletter drafts, submission permissions' as result;

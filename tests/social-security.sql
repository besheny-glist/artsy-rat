-- Run in a transaction; all fixtures and changes are rolled back.
begin;
insert into auth.users(id) values('11111111-2222-4333-8444-555555555551'),('11111111-2222-4333-8444-555555555552'),('11111111-2222-4333-8444-555555555553');
insert into public.art_invitations(id,owner_id,post_id,sender_name,message,style,starts_at)
select '22222222-2222-4333-8444-555555555551','11111111-2222-4333-8444-555555555551',id,'Test sender','Test invitation','editorial',now()+interval '2 days' from public.posts where status='published' and deleted_at is null limit 1;
do $$
declare invitation jsonb; n int;
begin
 perform set_config('request.jwt.claim.sub','11111111-2222-4333-8444-555555555552',true);
 execute 'set local role authenticated';
 perform public.reply_art_invitation('22222222-2222-4333-8444-555555555551','Test respondent','going',null,'See you there');
 insert into public.art_messages(invitation_id,recipient_id,body) values('22222222-2222-4333-8444-555555555551','11111111-2222-4333-8444-555555555552','Private test message');
 if not public.can_discuss_art_invitation('22222222-2222-4333-8444-555555555551','11111111-2222-4333-8444-555555555552') then raise exception 'Respondent cannot discuss'; end if;
 insert into public.art_passport(post_id,visited_on,note) select post_id,current_date,'Private test note' from (select (public.read_art_invitation('22222222-2222-4333-8444-555555555551')->>'post_id')::uuid post_id) x;
 perform set_config('request.jwt.claim.sub','11111111-2222-4333-8444-555555555553',true);
 if public.can_discuss_art_invitation('22222222-2222-4333-8444-555555555551','11111111-2222-4333-8444-555555555552') then raise exception 'Outsider can discuss'; end if;
 select count(*) into n from public.art_messages; if n<>0 then raise exception 'Outsider sees messages'; end if;
 select count(*) into n from public.art_passport; if n<>0 then raise exception 'Outsider sees passport'; end if;
 select count(*) into n from public.art_replies; if n<>0 then raise exception 'Outsider sees replies'; end if;
 begin
 insert into public.art_messages(invitation_id,recipient_id,body) values('22222222-2222-4333-8444-555555555551','11111111-2222-4333-8444-555555555552','Unauthorized');
 raise exception 'Outsider wrote a message';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub','11111111-2222-4333-8444-555555555551',true);
 select count(*) into n from public.art_replies where invitation_id='22222222-2222-4333-8444-555555555551';if n<>1 then raise exception 'Owner cannot see reply';end if;
 select count(*) into n from public.art_messages where invitation_id='22222222-2222-4333-8444-555555555551';if n<>1 then raise exception 'Owner cannot see conversation';end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub','',true);
 execute 'set local role anon';
 invitation:=public.read_art_invitation('22222222-2222-4333-8444-555555555551');
 if invitation is null or invitation ? 'owner_id' or invitation ? 'email' then raise exception 'Invalid public projection';end if;
 execute 'reset role';
end $$;
rollback;
select 'PASS: owner/respondent access, outsider isolation, public invitation, no persisted test data' as result;

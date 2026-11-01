-- Private art passport; invitations are readable only by possession of an unguessable link.
create table public.art_passport (
 user_id uuid not null default auth.uid() references auth.users on delete cascade,
 post_id uuid not null references public.posts on delete cascade,
 saved boolean not null default false,
 visited_on date check(visited_on<=current_date),
 reaction text check(reaction in ('moved','curious','discuss')),
 note text not null default '' check(length(note)<=500),
 district text not null default '' check(length(district)<=80),
 primary key(user_id,post_id)
);
alter table public.art_passport enable row level security;
create policy own_passport on public.art_passport for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select,insert,update,delete on public.art_passport to authenticated;
create table public.art_invitations (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users on delete cascade,
 post_id uuid not null references public.posts,
 sender_name text not null check(length(sender_name) between 1 and 40),
 message text not null check(length(message) between 1 and 240),
 style text not null check(style in ('editorial','botanical','romantic')),
 starts_at timestamptz not null,
 created_at timestamptz not null default now(),
 cancelled boolean not null default false
);
alter table public.art_invitations enable row level security;
create policy own_invitations on public.art_invitations for select to authenticated using(owner_id=auth.uid());
create policy create_invitations on public.art_invitations for insert to authenticated with check(owner_id=auth.uid() and starts_at>now() and exists(select 1 from public.posts p where p.id=post_id and p.status='published' and p.deleted_at is null));
grant select,insert on public.art_invitations to authenticated;
create table public.art_replies (
 invitation_id uuid not null references public.art_invitations on delete cascade,
 user_id uuid not null default auth.uid() references auth.users on delete cascade,
 name text not null check(length(name) between 1 and 40),
 answer text not null check(answer in ('going','another','decline')),
 proposed_at timestamptz,
 message text not null default '' check(length(message)<=500),
 updated_at timestamptz not null default now(),
 primary key(invitation_id,user_id),
 check(answer<>'another' or proposed_at is not null)
);
alter table public.art_replies enable row level security;
create policy read_replies on public.art_replies for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.art_invitations i where i.id=invitation_id and i.owner_id=auth.uid()));
grant select on public.art_replies to authenticated;
create function public.read_art_invitation(invite_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',i.id,'sender_name',i.sender_name,'message',i.message,'style',i.style,'starts_at',i.starts_at,'cancelled',i.cancelled,'post_id',p.id,'title',p.title,'venue',p.design->'exhibition'->>'venue','image',p.images->>0,'is_owner',i.owner_id=auth.uid())
 from public.art_invitations i join public.posts p on p.id=i.post_id
 where i.id=invite_id and p.status='published' and p.deleted_at is null;
$$;
revoke all on function public.read_art_invitation(uuid) from public;
grant execute on function public.read_art_invitation(uuid) to anon,authenticated;
create function public.reply_art_invitation(invite_id uuid, reply_name text, reply_answer text, reply_time timestamptz default null, reply_message text default '') returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if not exists(select 1 from public.art_invitations where id=invite_id and not cancelled and starts_at>now() and owner_id<>auth.uid()) then raise exception 'Invitation unavailable'; end if;
 if reply_answer='another' and (reply_time is null or reply_time<=now()) then raise exception 'Choose a future time'; end if;
 insert into public.art_replies(invitation_id,user_id,name,answer,proposed_at,message) values(invite_id,auth.uid(),reply_name,reply_answer,reply_time,reply_message)
 on conflict(invitation_id,user_id) do update set name=excluded.name,answer=excluded.answer,proposed_at=excluded.proposed_at,message=excluded.message,updated_at=now();
end;$$;
revoke all on function public.reply_art_invitation(uuid,text,text,timestamptz,text) from public;
grant execute on function public.reply_art_invitation(uuid,text,text,timestamptz,text) to authenticated;
create function public.cancel_art_invitation(invite_id uuid) returns void language sql security definer set search_path='' as $$
 update public.art_invitations set cancelled=true where id=invite_id and owner_id=auth.uid();
$$;
revoke all on function public.cancel_art_invitation(uuid) from public;
grant execute on function public.cancel_art_invitation(uuid) to authenticated;

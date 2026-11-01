-- Only an invitation owner and an individual respondent can read their conversation.
create function public.can_discuss_art_invitation(invite_id uuid, recipient_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.art_invitations i join public.art_replies r on r.invitation_id=i.id and r.user_id=recipient_id where i.id=invite_id and (auth.uid()=i.owner_id or auth.uid()=recipient_id));
$$;
revoke all on function public.can_discuss_art_invitation(uuid,uuid) from public;
grant execute on function public.can_discuss_art_invitation(uuid,uuid) to authenticated;
create table public.art_messages(
 id uuid primary key default gen_random_uuid(),
 invitation_id uuid not null references public.art_invitations on delete cascade,
 recipient_id uuid not null references auth.users on delete cascade,
 sender_id uuid not null default auth.uid() references auth.users on delete cascade,
 body text not null check(length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now()
);
alter table public.art_messages enable row level security;
create policy conversation_read on public.art_messages for select to authenticated using(public.can_discuss_art_invitation(invitation_id,recipient_id));
create policy conversation_write on public.art_messages for insert to authenticated with check(sender_id=auth.uid() and public.can_discuss_art_invitation(invitation_id,recipient_id));
grant select,insert on public.art_messages to authenticated;
create index art_messages_thread on public.art_messages(invitation_id,recipient_id,created_at);

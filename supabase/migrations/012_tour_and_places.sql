begin;
update public.places set city='Győr' where id='place-0e62c28e1373716c2f60';
update public.monitor_sources set city='Győr' where place_id='place-0e62c28e1373716c2f60';
update public.places set city='Székesfehérvár' where id='place-184290d94e0c07deac88';
update public.monitor_sources set city='Székesfehérvár' where place_id='place-184290d94e0c07deac88';
alter table public.content_submissions add column tour_url text not null default '' check(tour_url='' or (kind='events' and tour_url ~ '^https://'));
grant insert(tour_url) on public.content_submissions to authenticated;
create function public.attach_reviewed_tour() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='approved' and old.status='pending' and new.tour_url<>'' and new.post_id is not null then
  update public.posts set links=coalesce(links,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('label','Online art tour','url',new.tour_url)) where id=new.post_id;
 end if;
 return new;
end;
$$;
create trigger attach_reviewed_tour after update on public.content_submissions for each row execute function public.attach_reviewed_tour();
commit;

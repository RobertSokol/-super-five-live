-- SUPER FIVE / DOMARSCHEMA 2.0
-- Kör hela filen i Supabase SQL Editor. Befintliga resultat och matcher bevaras.
create table if not exists public.referee_assignments(
 match_id bigint primary key references public.matches(id) on delete cascade,
 referee_name text not null check(referee_name in ('Elo','Milan','Gabriel','Matteus','Lukas'))
);
create table if not exists public.score_audit(
 id bigint generated always as identity primary key,
 match_id bigint not null references public.matches(id) on delete cascade,
 old_home integer,old_away integer,new_home integer not null,new_away integer not null,
 changed_by uuid not null,changed_at timestamptz not null default now()
);
alter table public.referee_assignments enable row level security;
alter table public.score_audit enable row level security;
drop policy if exists "staff read assignments" on public.referee_assignments;
create policy "staff read assignments" on public.referee_assignments for select to authenticated using (public.is_staff());
drop policy if exists "admin read score audit" on public.score_audit;
create policy "admin read score audit" on public.score_audit for select to authenticated using (public.is_admin());
revoke insert,update,delete on public.referee_assignments from public,anon,authenticated;
revoke insert,update,delete on public.score_audit from public,anon,authenticated;
create or replace function public.auto_assign_referee()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 times text[]:=array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'];
 names text[]:=array['Elo','Milan','Gabriel','Matteus','Lukas'];
 r integer;p integer;
begin
 r:=array_position(times,new.kickoff)-1;
 p:=ascii(right(trim(new.pitch),1))-ascii('A');
 if r is not null and p between 0 and 3 then
  insert into public.referee_assignments(match_id,referee_name)
  values(new.id,names[((r+p+1)%5)+1])
  on conflict(match_id) do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_auto_assign_referee on public.matches;
create trigger trg_auto_assign_referee after insert on public.matches for each row execute function public.auto_assign_referee();
insert into public.referee_assignments(match_id,referee_name)
select m.id,(array['Elo','Milan','Gabriel','Matteus','Lukas'])[((array_position(array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'],m.kickoff)-1+ascii(right(trim(m.pitch),1))-ascii('A')+1)%5)+1]
from public.matches m
where m.kickoff=any(array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'])
and right(trim(m.pitch),1) in ('A','B','C','D')
on conflict(match_id) do nothing;
create or replace function public.set_referee_assignment(p_match_id bigint,p_referee_name text)
returns void language plpgsql security definer set search_path='' as $$
declare m public.matches%rowtype;
begin
 if not public.is_admin() then raise exception 'Endast administratör';end if;
 if p_referee_name not in ('Elo','Milan','Gabriel','Matteus','Lukas') then raise exception 'Ogiltigt domarnamn';end if;
 select * into m from public.matches where id=p_match_id;
 if not found then raise exception 'Match saknas';end if;
 if exists(select 1 from public.referee_assignments a join public.matches x on x.id=a.match_id
  where x.kickoff=m.kickoff and a.referee_name=p_referee_name and a.match_id<>p_match_id) then
  raise exception 'Domaren är redan tilldelad en match samma tid';
 end if;
 insert into public.referee_assignments(match_id,referee_name) values(p_match_id,p_referee_name)
 on conflict(match_id) do update set referee_name=excluded.referee_name;
end $$;
create or replace function public.report_assigned_result(p_match_id bigint,p_home integer,p_away integer)
returns void language plpgsql security definer set search_path='' as $$
declare m public.matches%rowtype; ref_name text; user_name text; admin_ok boolean;
begin
 if auth.uid() is null or not public.is_staff() then raise exception 'Inloggning krävs';end if;
 if p_home is null or p_away is null or p_home not between 0 and 99 or p_away not between 0 and 99 then raise exception 'Ange siffror mellan 0 och 99';end if;
 admin_ok:=public.is_admin();
 select * into m from public.matches where id=p_match_id for update;
 if not found then raise exception 'Match saknas';end if;
 if not admin_ok then
  select display_name into user_name from public.staff where user_id=auth.uid();
  select referee_name into ref_name from public.referee_assignments where match_id=p_match_id;
  if ref_name is null or lower(trim(user_name))<>lower(ref_name) then raise exception 'Du är inte tilldelad denna match';end if;
  if m.phase='initial' and (select finals_published from public.settings where id=true) then
   raise exception 'Gruppspelsresultat är låsta efter kvalificeringen. Kontakta administratören';
  end if;
 end if;
 insert into public.score_audit(match_id,old_home,old_away,new_home,new_away,changed_by)
 values(p_match_id,m.home_score,m.away_score,p_home,p_away,auth.uid());
 update public.matches set home_score=p_home,away_score=p_away,submitted_by=auth.uid(),submitted_at=now() where id=p_match_id;
end $$;
revoke all on function public.set_referee_assignment(bigint,text),public.report_assigned_result(bigint,integer,integer) from public,anon;
grant execute on function public.set_referee_assignment(bigint,text),public.report_assigned_result(bigint,integer,integer) to authenticated;
-- Blockera den äldre rapporteringsvägen så att matchtilldelning inte kan kringgås.
do $$ declare fn record;begin
 for fn in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='report_result' loop
  execute format('revoke execute on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $$;

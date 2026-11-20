-- Super Five: admin-only reset and reversible qualification. Run in dedicated Supabase SQL Editor.
create or replace function public.reset_all_results()
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_admin() then raise exception 'Endast administratör'; end if;
 delete from public.matches where phase='final';
 delete from public.placements where group_name in ('A','B','C','D');
 update public.matches set home_score=null,away_score=null,submitted_by=null,submitted_at=null where phase='initial';
 update public.settings set finals_published=false where id=true;
end $$;

create or replace function public.reset_final_phase()
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_admin() then raise exception 'Endast administratör'; end if;
 delete from public.matches where phase='final';
 delete from public.placements where group_name in ('A','B','C','D');
 update public.settings set finals_published=false where id=true;
end $$;

-- Prevent accidental destruction of reported final scores on requalification.
create or replace function public.publish_finals(p_placements jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare g text; r integer; t text; teams text[]; labels text[] := array['Guld','Silver','Brons','Safir']; k integer; round_no integer; slot integer;
begin
 if not public.is_admin() then raise exception 'Endast administratör'; end if;
 if (select count(*) from public.matches where phase='initial' and home_score is not null) <> 24 then raise exception 'Alla 24 gruppspelsresultat krävs'; end if;
 if exists(select 1 from public.matches where phase='final' and home_score is not null) then raise exception 'Placeringsmatcher har resultat. Återställ först placeringsfasen innan omgruppering.'; end if;
 if jsonb_typeof(p_placements) is distinct from 'array' or jsonb_array_length(p_placements) <> 16 then raise exception 'Exakt 16 placeringar krävs'; end if;
 for g in select unnest(array['A','B','C','D']) loop
  if (select count(*) from jsonb_array_elements(p_placements) x where x->>'group'=g) <> 4 then raise exception 'Felaktig grupp %',g; end if;
  for r in 1..4 loop
   if (select count(*) from jsonb_array_elements(p_placements) x where x->>'group'=g and x->>'rank'=r::text)<>1 then raise exception 'Placering saknas eller är duplicerad'; end if;
   select x->>'team' into t from jsonb_array_elements(p_placements) x where x->>'group'=g and x->>'rank'=r::text;
   if not exists(select 1 from public.matches m where m.phase='initial' and m.group_name=g and (m.home=t or m.away=t)) then raise exception 'Ogiltigt lag'; end if;
   if (select count(*) from jsonb_array_elements(p_placements) x where x->>'group'=g and x->>'team'=t)<>1 then raise exception 'Duplicerat lag'; end if;
  end loop;
 end loop;
 delete from public.matches where phase='final';
 delete from public.placements where group_name in ('A','B','C','D');
 insert into public.placements(group_name,rank,team)
 select x->>'group',(x->>'rank')::integer,x->>'team' from jsonb_array_elements(p_placements) x;
 -- Each placement group stays on one pitch. Six 25-minute slots from 13:35.
 -- First A-B (last initial game 12:40), then C-D (last initial game 13:05).
 for k in 1..4 loop
  select array_agg(team order by group_name) into teams from public.placements where rank=k;
  for slot in 1..6 loop
   insert into public.matches(phase,group_name,kickoff,pitch,home,away)
   values('final',labels[k],
     (array['13:35','14:00','14:25','14:50','15:15','15:40'])[slot],
     (array['Plan A','Plan B','Plan C','Plan D'])[k],
     teams[(array[1,3,1,2,1,2])[slot]],
     teams[(array[2,4,3,4,4,3])[slot]]);
  end loop;
 end loop;
 update public.settings set finals_published=true where id=true;
end $$;
revoke all on function public.reset_all_results(), public.reset_final_phase() from public, anon;
grant execute on function public.reset_all_results(), public.reset_final_phase() to authenticated;

-- Apply the fixed, approved schedule to already-generated placement fixtures.
-- Does not change teams, scores, or fixture IDs.
create or replace function public.assign_final_schedule()
returns void language plpgsql security definer set search_path = '' as $$
declare m record; origin_home text; origin_away text; pair_key text; kickoff_value text; pitch_value text;
begin
 if not public.is_admin() then raise exception 'Endast administratör'; end if;
 if not (select finals_published from public.settings where id=true) then raise exception 'Placeringsgrupperna är inte publicerade'; end if;
 if (select count(*) from public.matches where phase='final') <> 24 then raise exception 'Förväntade 24 placeringsmatcher'; end if;
 for m in select id,group_name,home,away from public.matches where phase='final' loop
  select group_name into origin_home from public.placements where team=m.home;
  select group_name into origin_away from public.placements where team=m.away;
  if origin_home is null or origin_away is null then raise exception 'Kan inte hitta ursprungsgrupp för match %',m.id; end if;
  pair_key := least(origin_home,origin_away)||greatest(origin_home,origin_away);
  kickoff_value := case pair_key when 'AB' then '13:35' when 'CD' then '14:00' when 'AC' then '14:25' when 'BD' then '14:50' when 'AD' then '15:15' when 'BC' then '15:40' else null end;
  pitch_value := case m.group_name when 'Guld' then 'Plan A' when 'Silver' then 'Plan B' when 'Brons' then 'Plan C' when 'Safir' then 'Plan D' else null end;
  if kickoff_value is null or pitch_value is null then raise exception 'Ogiltig matchindelning för match %',m.id; end if;
  update public.matches set kickoff=kickoff_value,pitch=pitch_value where id=m.id;
 end loop;
end $$;
revoke all on function public.assign_final_schedule() from public,anon;
grant execute on function public.assign_final_schedule() to authenticated;
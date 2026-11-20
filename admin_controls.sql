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
 for k in 1..4 loop
  select array_agg(team order by group_name) into teams from public.placements where rank=k;
  for round_no in 1..3 loop
   for slot in 1..2 loop
    insert into public.matches(phase,group_name,kickoff,pitch,home,away)
    values('final',labels[k],'EJ FASTSTÄLLD','EJ FASTSTÄLLD',
      teams[case when round_no=1 then (case when slot=1 then 1 else 2 end) when round_no=2 then (case when slot=1 then 1 else 4 end) else (case when slot=1 then 1 else 3 end) end],
      teams[case when round_no=1 then (case when slot=1 then 4 else 3 end) when round_no=2 then (case when slot=1 then 3 else 2 end) else (case when slot=1 then 2 else 4 end) end]);
   end loop;
  end loop;
 end loop;
 update public.settings set finals_published=true where id=true;
end $$;
revoke all on function public.reset_all_results(), public.reset_final_phase() from public, anon;
grant execute on function public.reset_all_results(), public.reset_final_phase() to authenticated;
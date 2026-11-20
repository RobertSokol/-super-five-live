-- Super Five: reparera saknade domartilldelningar.
-- Kör i Supabase SQL Editor. Ändrar inte matchresultat.
-- Matchar tider som 11:00, 11:00:00 och planer som A / Plan A.
with slots as (
 select m.id,
 array_position(array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'],left(trim(m.kickoff::text),5)) - 1 as round_index,
 ascii(upper(right(trim(m.pitch::text),1)))-ascii('A') as pitch_index
 from public.matches m
), valid_slots as (
 select id,round_index,pitch_index from slots
 where round_index between 0 and 11 and pitch_index between 0 and 3
)
insert into public.referee_assignments(match_id,referee_name)
select id,(array['Elo','Milan','Gabriel','Matteus','Lukas'])[((round_index+pitch_index+1)%5)+1]
from valid_slots
on conflict(match_id) do nothing;

-- Kontrollera antal matcher per domare (ska vara 9 eller 10 om alla 48 matcher finns).
select referee_name,count(*) as antal_matcher from public.referee_assignments
group by referee_name order by referee_name;

-- Kontrollera matcher som saknar domare. Dessa kan vara placeringsmatcher
-- som ännu inte har skapats eller fått tid och plan.
select m.id,m.phase,m.kickoff,m.pitch,m.home,m.away
from public.matches m left join public.referee_assignments a on a.match_id=m.id
where a.match_id is null order by m.kickoff,m.pitch;

-- Säkerställ att framtida placeringsmatcher tilldelas även om klockslaget
-- är lagrat med sekunder (t.ex. 13:35:00).
create or replace function public.auto_assign_referee()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 times text[]:=array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'];
 names text[]:=array['Elo','Milan','Gabriel','Matteus','Lukas'];
 r integer;p integer;
begin
 r:=array_position(times,left(trim(new.kickoff::text),5))-1;
 p:=ascii(upper(right(trim(new.pitch::text),1)))-ascii('A');
 if r between 0 and 11 and p between 0 and 3 then
  insert into public.referee_assignments(match_id,referee_name)
  values(new.id,names[((r+p+1)%5)+1])
  on conflict(match_id) do nothing;
 end if;
 return new;
end $$;

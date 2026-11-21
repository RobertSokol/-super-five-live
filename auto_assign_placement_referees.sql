-- Super Five: auto-assign referees to newly generated placement matches.
-- Run once in Supabase SQL Editor; preserves results and existing manual assignments.
create or replace function public.auto_assign_referee()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 times text[]:=array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'];
 names text[]:=array['Elo','Milan','Gabriel','Matteus','Lukas'];
 r integer; p integer;
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
drop trigger if exists trg_auto_assign_referee on public.matches;
create trigger trg_auto_assign_referee
after insert or update of kickoff,pitch on public.matches
for each row execute function public.auto_assign_referee();

-- Backfill any existing placement fixtures without changing manual assignments.
with slots as (
 select m.id,
 array_position(array['11:00','11:25','11:50','12:15','12:40','13:05','13:35','14:00','14:25','14:50','15:15','15:40'],left(trim(m.kickoff::text),5))-1 as r,
 ascii(upper(right(trim(m.pitch::text),1)))-ascii('A') as p
 from public.matches m
)
insert into public.referee_assignments(match_id,referee_name)
select id,(array['Elo','Milan','Gabriel','Matteus','Lukas'])[((r+p+1)%5)+1]
from slots where r between 0 and 11 and p between 0 and 3
on conflict(match_id) do nothing;

select m.kickoff,m.pitch,m.home,m.away,a.referee_name
from public.matches m left join public.referee_assignments a on a.match_id=m.id
where m.phase='final' order by m.kickoff,m.pitch;

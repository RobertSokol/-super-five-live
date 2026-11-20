-- Run once in Supabase SQL Editor. Public, read-only schedule with no staff data.
create or replace function public.public_super_five_schedule()
returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'phase',m.phase,'group_name',m.group_name,'kickoff',m.kickoff,
  'pitch',m.pitch,'home',m.home,'away',m.away,
  'home_score',m.home_score,'away_score',m.away_score
 ) order by m.kickoff,m.pitch,m.id),'[]'::jsonb)
 from public.matches m
 where m.phase='initial' or (m.phase='final' and exists(select 1 from public.settings s where s.id=true and s.finals_published=true));
$$;
revoke all on function public.public_super_five_schedule() from public;
grant execute on function public.public_super_five_schedule() to anon,authenticated;
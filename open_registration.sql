-- Super Five: open referee self-registration, without invitation codes.
-- Run once in the dedicated Supabase SQL Editor. Existing admin is preserved.
create table if not exists public.registration_settings (
  id boolean primary key default true check (id),
  is_open boolean not null default true
);
insert into public.registration_settings(id,is_open) values (true,true)
on conflict(id) do update set is_open = true;
alter table public.registration_settings enable row level security;
revoke all on public.registration_settings from anon, authenticated;

create or replace function public.register_referee(p_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_open boolean;
begin
  if auth.uid() is null then raise exception 'Du måste vara inloggad'; end if;
  if length(trim(coalesce(p_name,''))) < 2 or length(trim(p_name)) > 80 then
    raise exception 'Ange ett namn på 2–80 tecken';
  end if;
  select is_open into v_open from public.registration_settings where id = true;
  if v_open is distinct from true then raise exception 'Registreringen är stängd'; end if;
  if exists (select 1 from public.staff where user_id=auth.uid()) then
    raise exception 'Kontot är redan registrerat';
  end if;
  insert into public.staff(user_id,display_name,role)
  values (auth.uid(),trim(p_name),'referee');
end $$;
revoke all on function public.register_referee(text) from public, anon;
grant execute on function public.register_referee(text) to authenticated;

-- After all referees have registered, close registration with:
-- update public.registration_settings set is_open = false where id = true;
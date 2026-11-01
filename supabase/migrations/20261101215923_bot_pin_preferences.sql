create table public.opengrok_bot_pins (
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  host_id uuid not null references public.opengrok_devices(id) on delete cascade,
  bot_id uuid not null,
  is_pinned boolean not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (owner_id, host_id, bot_id)
);
create index opengrok_bot_pins_host on public.opengrok_bot_pins(host_id);
alter table public.opengrok_bot_pins enable row level security;
create policy opengrok_pin_read on public.opengrok_bot_pins for select to authenticated
using (owner_id = (select auth.uid()) and exists (
  select 1 from public.opengrok_devices d where d.id = host_id and d.owner_id = (select auth.uid()) and d.kind = 'host'
));
create policy opengrok_pin_insert on public.opengrok_bot_pins for insert to authenticated
with check (owner_id = (select auth.uid()) and exists (
  select 1 from public.opengrok_devices d where d.id = host_id and d.owner_id = (select auth.uid()) and d.kind = 'host'
));
create policy opengrok_pin_update on public.opengrok_bot_pins for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()) and exists (
  select 1 from public.opengrok_devices d where d.id = host_id and d.owner_id = (select auth.uid()) and d.kind = 'host'
));
revoke all on public.opengrok_bot_pins from anon, authenticated;
grant select, insert, update on public.opengrok_bot_pins to authenticated;

create function public.opengrok_set_bot_pin(host_device uuid, bot uuid, pinned boolean, only_if_missing boolean default false)
returns table(bot_id uuid, is_pinned boolean)
language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.opengrok_devices d where d.id = host_device and d.owner_id = auth.uid() and d.kind = 'host'
  ) then raise exception 'Unknown computer'; end if;
  return query
  insert into public.opengrok_bot_pins as current_pin(owner_id, host_id, bot_id, is_pinned)
  values(auth.uid(), host_device, bot, pinned)
  on conflict on constraint opengrok_bot_pins_pkey do update
    set is_pinned = case when only_if_missing then current_pin.is_pinned else excluded.is_pinned end,
        updated_at = case when only_if_missing then current_pin.updated_at else clock_timestamp() end
  returning current_pin.bot_id, current_pin.is_pinned;
end $$;
revoke all on function public.opengrok_set_bot_pin(uuid,uuid,boolean,boolean) from public,anon;
grant execute on function public.opengrok_set_bot_pin(uuid,uuid,boolean,boolean) to authenticated;
notify pgrst, 'reload schema';


-- Isolated from existing applications in this project. No chat plaintext is stored.
create table public.opengrok_devices (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name text not null check (length(name) between 1 and 120),
  kind text not null check (kind in ('host','controller')),
  public_key text not null check (length(public_key) = 44),
  last_seen timestamptz not null default now(),
  available boolean not null default false
);
create index opengrok_devices_owner on public.opengrok_devices(owner_id);
alter table public.opengrok_devices enable row level security;
create policy opengrok_own_devices on public.opengrok_devices for select to authenticated using (owner_id = (select auth.uid()));
revoke all on public.opengrok_devices from anon, authenticated;
grant select on public.opengrok_devices to authenticated;

create table public.opengrok_packets (
  id uuid not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  sender uuid not null references public.opengrok_devices(id) on delete cascade,
  recipient uuid not null references public.opengrok_devices(id) on delete cascade,
  kind text not null check (kind in ('request','response')),
  ciphertext text not null check (length(ciphertext) between 40 and 8000040),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 seconds'),
  primary key (id,kind,recipient)
);
create index opengrok_packets_inbox on public.opengrok_packets(recipient,created_at);
create index opengrok_packets_expiry on public.opengrok_packets(expires_at);
alter table public.opengrok_packets enable row level security;
revoke all on public.opengrok_packets from anon, authenticated;

create function public.opengrok_register_device(device_id uuid, device_name text, device_kind text, device_key text, is_available boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); existing public.opengrok_devices;
begin
  if uid is null then raise exception 'Sign-in required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  select * into existing from public.opengrok_devices where id = device_id;
  if found then
    if existing.owner_id <> uid or existing.public_key <> device_key or existing.kind <> device_kind then raise exception 'Device identity cannot be replaced'; end if;
    update public.opengrok_devices set name = left(device_name,120), last_seen = now(), available = is_available where id = device_id;
  else
    if (select count(*) from public.opengrok_devices where owner_id = uid) >= 32 then raise exception 'Device limit reached'; end if;
    insert into public.opengrok_devices(id,owner_id,name,kind,public_key,available) values(device_id,uid,left(device_name,120),device_kind,device_key,is_available);
  end if;
end $$;

create function public.opengrok_send(packet_id uuid, from_device uuid, to_device uuid, packet_kind text, payload text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); source public.opengrok_devices; destination public.opengrok_devices;
begin
  if uid is null then raise exception 'Sign-in required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  select * into source from public.opengrok_devices where id = from_device and owner_id = uid;
  if not found then raise exception 'Unknown sending device'; end if;
  select * into destination from public.opengrok_devices where id = to_device and owner_id = uid;
  if not found or source.kind = destination.kind then raise exception 'Unknown receiving device'; end if;
  if (packet_kind = 'request' and source.kind <> 'controller') or (packet_kind = 'response' and source.kind <> 'host') or packet_kind not in ('request','response') then raise exception 'Invalid direction'; end if;
  if length(payload) > 8000040 or length(payload) < 40 then raise exception 'Packet size exceeded'; end if;
  delete from public.opengrok_packets where expires_at < now();
  if exists(select 1 from public.opengrok_packets where id = packet_id and kind = packet_kind and recipient = to_device) then return; end if;
  if (select count(*) from public.opengrok_packets where owner_id = uid) >= 40 or (select coalesce(sum(length(ciphertext)),0) from public.opengrok_packets where owner_id = uid) + length(payload) > 32000000 then raise exception 'Mailbox full; retry shortly'; end if;
  insert into public.opengrok_packets(id,owner_id,sender,recipient,kind,ciphertext) values(packet_id,uid,from_device,to_device,packet_kind,payload);
end $$;

create function public.opengrok_poll(device_id uuid)
returns table(id uuid,sender uuid,recipient uuid,kind text,ciphertext text,created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.opengrok_devices d where d.id = device_id and d.owner_id = auth.uid()) then raise exception 'Unknown device'; end if;
  delete from public.opengrok_packets p where p.expires_at < now();
  return query select p.id,p.sender,p.recipient,p.kind,p.ciphertext,p.created_at from public.opengrok_packets p where p.recipient = device_id and p.owner_id = auth.uid() order by p.created_at limit 8;
end $$;

create function public.opengrok_ack(device_id uuid, packet_id uuid, packet_kind text)
returns void language sql security definer set search_path = '' as $$
  delete from public.opengrok_packets where recipient = device_id and id = packet_id and kind = packet_kind and owner_id = auth.uid();
$$;

revoke all on function public.opengrok_register_device(uuid,text,text,text,boolean) from public,anon;
revoke all on function public.opengrok_send(uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.opengrok_poll(uuid) from public,anon;
revoke all on function public.opengrok_ack(uuid,uuid,text) from public,anon;
grant execute on function public.opengrok_register_device(uuid,text,text,text,boolean) to authenticated;
grant execute on function public.opengrok_send(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.opengrok_poll(uuid) to authenticated;
grant execute on function public.opengrok_ack(uuid,uuid,text) to authenticated;

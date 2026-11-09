-- Lets a signed-in user remove one of their own old device entries (for example after reinstalling OpenGrokBot),
-- along with any relay packets still addressed to or from it. A device cannot remove itself while in use; the app only offers offline entries.
create function public.opengrok_forget_device(device_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Sign-in required'; end if;
  delete from public.opengrok_packets where owner_id = uid and (sender = device_id or recipient = device_id);
  delete from public.opengrok_devices where id = device_id and owner_id = uid;
  if not found then raise exception 'No such device on this account'; end if;
end $$;
revoke all on function public.opengrok_forget_device(uuid) from public,anon;
grant execute on function public.opengrok_forget_device(uuid) to authenticated;

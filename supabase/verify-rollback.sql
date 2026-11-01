-- Live smoke test: no email, credentials or persistent test accounts.
-- Everything, including the temporary Auth rows, is rolled back.
begin;
insert into auth.users(id) values ('a0b418e3-8581-4f21-b136-cf0039f1a001'), ('a0b418e3-8581-4f21-b136-cf0039f1a002');
select set_config('request.jwt.claim.sub','a0b418e3-8581-4f21-b136-cf0039f1a001',true);
set local role authenticated;
do $$
declare denied boolean := false; n integer;
begin
  perform public.opengrok_register_device('a0b418e3-8581-4f21-b136-cf0039f1b001','Smoke Mac','host',repeat('A',43)||'=',true);
  perform public.opengrok_register_device('a0b418e3-8581-4f21-b136-cf0039f1b002','Smoke phone','controller',repeat('B',43)||'=',true);
  select count(*) into n from public.opengrok_devices;
  if n <> 2 then raise exception 'Own-device visibility failed'; end if;
  begin
    perform public.opengrok_register_device('a0b418e3-8581-4f21-b136-cf0039f1b001','Replaced','host',repeat('C',43)||'=',true);
  exception when others then denied := true; end;
  if not denied then raise exception 'Key immutability failed'; end if;
  perform public.opengrok_send('a0b418e3-8581-4f21-b136-cf0039f1c001','a0b418e3-8581-4f21-b136-cf0039f1b002','a0b418e3-8581-4f21-b136-cf0039f1b001','request',repeat('X',100));
  perform public.opengrok_send('a0b418e3-8581-4f21-b136-cf0039f1c001','a0b418e3-8581-4f21-b136-cf0039f1b002','a0b418e3-8581-4f21-b136-cf0039f1b001','request',repeat('X',100));
  select count(*) into n from public.opengrok_poll('a0b418e3-8581-4f21-b136-cf0039f1b001');
  if n <> 1 then raise exception 'Queue delivery or deduplication failed'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','a0b418e3-8581-4f21-b136-cf0039f1a002',true);
set local role authenticated;
do $$
declare denied boolean := false; n integer;
begin
  select count(*) into n from public.opengrok_devices;
  if n <> 0 then raise exception 'Cross-account device isolation failed'; end if;
  begin perform * from public.opengrok_poll('a0b418e3-8581-4f21-b136-cf0039f1b001');
  exception when others then denied := true; end;
  if not denied then raise exception 'Cross-account mailbox isolation failed'; end if;
  perform public.opengrok_ack('a0b418e3-8581-4f21-b136-cf0039f1b001','a0b418e3-8581-4f21-b136-cf0039f1c001','request');
end $$;
reset role;
select set_config('request.jwt.claim.sub','a0b418e3-8581-4f21-b136-cf0039f1a001',true);
set local role authenticated;
do $$
declare n integer;
begin
  select count(*) into n from public.opengrok_poll('a0b418e3-8581-4f21-b136-cf0039f1b001');
  if n <> 1 then raise exception 'Cross-account acknowledgment removed packet'; end if;
  perform public.opengrok_ack('a0b418e3-8581-4f21-b136-cf0039f1b001','a0b418e3-8581-4f21-b136-cf0039f1c001','request');
  select count(*) into n from public.opengrok_poll('a0b418e3-8581-4f21-b136-cf0039f1b001');
  if n <> 0 then raise exception 'Acknowledgment failed'; end if;
end $$;
rollback;
select 'PASS: account isolation, immutable keys, delivery, duplicate suppression and acknowledgment; fixtures rolled back' as result;

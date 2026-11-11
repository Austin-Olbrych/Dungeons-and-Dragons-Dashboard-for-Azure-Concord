-- fix-3: Wick's runs happen in real time.
--
-- A player picks the route and sends Wick off. The road roll, the trouble, what he lets slip and the
-- rumor are rolled the moment he leaves, but kept in a DM-only document. Nobody sees the result until
-- the time he's due back. When that time passes, the next person to open the site "brings him home":
-- the shop sells what has an asking price, the gold (less his pay) goes to the party stash, and the run
-- shows up with his news. If the DM marks the table as in session, runs resolve at once.
--
-- Safe to run more than once.

-- Travel times, in real days. Change these here or from the DM tools on the Shop tab.
update public.docs set data = data || jsonb_build_object('travel', coalesce(data->'travel', '{"main":1,"back":2,"shop":1}'::jsonb))
  where id = 'shop';
-- Wick was heading back to the party under the old manual tracker; treat him as arrived so the new runs can start.
update public.docs set data = jsonb_set(data, '{runner,status}', '"party"')
  where id = 'shop' and data->'trip' is null and coalesce(data->'runner'->>'status', '') in ('toParty', 'road', '');

create or replace function public._d(n int) returns int language sql volatile as $$ select 1 + floor(random() * n)::int $$;
revoke all on function public._d(int) from public, anon, authenticated;

-- Bring Wick home if he's due. Anyone may call it (through p_tick); it only acts when the time has come.
create or replace function public._shop_tick(force boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; t jsonb; trip jsonb; c jsonb; cargo jsonb := '[]'::jsonb;
  gold int := 0; pay int; net int; heat int; sold_names text[] := '{}'; lost_names text[] := '{}'; shelf_names text[] := '{}';
  news jsonb := '[]'::jsonb; run jsonb; hist jsonb;
begin
  select data into s from docs where id = 'shop' for update;
  trip := s->'trip';
  if trip is null or trip->>'phase' <> 'out' then return 'idle'; end if;
  select data into t from dm_docs where id = 'trip' for update;
  if t is null or t->>'id' is distinct from trip->>'id' then return 'no secret'; end if;
  if not force and now() < (t->>'returnAt')::timestamptz then return 'on the road'; end if;

  -- Taken: he doesn't come back. The DM decides what happens next.
  if coalesce((t->>'taken')::boolean, false) then
    s := jsonb_set(s, '{trip,phase}', '"missing"');
    s := jsonb_set(s, '{runner,status}', '"missing"');
    update docs set data = s, updated_at = now() where id = 'shop';
    insert into activity(actor, action, detail) values ('system', 'runner_missing', jsonb_build_object('trip', trip->>'id'));
    return 'missing';
  end if;

  -- What he was carrying either reached the shop or was lost on the way.
  for c in select * from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) loop
    if c->>'status' = 'road' and c->>'tripId' = trip->>'id' then
      if coalesce((t->>'lostCargo')::boolean, false) then
        c := c || '{"status":"lost"}'::jsonb; lost_names := lost_names || (c->>'name');
      else
        c := c || '{"status":"atshop"}'::jsonb;
      end if;
    end if;
    -- Steven sells anything at the shop that has an asking price; the rest waits on the shelf.
    if c->>'status' = 'atshop' then
      if c->>'ask' is not null then
        c := c || jsonb_build_object('status', 'sold', 'sold', (c->>'ask')::int, 'soldAt', to_char(now(), 'Mon FMDD'));
        gold := gold + (c->>'ask')::int; sold_names := sold_names || (c->>'name');
      else
        shelf_names := shelf_names || (c->>'name');
      end if;
    end if;
    cargo := cargo || jsonb_build_array(c);
  end loop;

  if coalesce((t->>'hit')::boolean, false) then news := news || to_jsonb(t->>'trouble');
  else news := news || to_jsonb('Made it there and back without trouble.'::text); end if;
  if coalesce((t->>'goldTaken')::boolean, false) and gold > 0 then
    news := news || to_jsonb(format('The %s gp from the sales was taken on the way back.', gold)); gold := 0;
  end if;
  if t->>'rumor' is not null then news := news || to_jsonb('Rumor: ' || (t->>'rumor')); end if;

  pay := coalesce((s->'runner'->>'pay')::int, 0);
  net := gold - pay;
  update docs set data = jsonb_set(data, '{gold}', to_jsonb(coalesce((data->>'gold')::int, 0) + net)), updated_at = now() where id = 'stash';

  heat := coalesce((s->>'heat')::int, 0) + coalesce((t->>'heat')::int, 0);
  if not coalesce((t->>'hit')::boolean, false) and trip->>'route' = 'back' then heat := heat - 1; end if;
  heat := greatest(0, least(10, heat));

  run := jsonb_build_object('id', trip->>'id', 'at', now(), 'when', to_char(now(), 'Mon FMDD'),
    'leftAt', trip->'leftAt', 'route', trip->>'route', 'out', array_to_string(coalesce(array(select jsonb_array_elements_text(trip->'items')), '{}'), ', '),
    'soldItems', array_to_string(sold_names, ', '), 'lostItems', array_to_string(lost_names, ', '), 'shelf', array_to_string(shelf_names, ', '),
    'sold', gold, 'pay', pay, 'news', news, 'late', coalesce((t->>'late')::boolean, false));

  s := s - 'trip';
  s := jsonb_set(s, '{cargo}', cargo);
  s := jsonb_set(s, '{runs}', jsonb_build_array(run) || coalesce(s->'runs', '[]'::jsonb));
  s := jsonb_set(s, '{heat}', to_jsonb(heat));
  s := jsonb_set(s, '{runner,status}', '"party"');
  update docs set data = s, updated_at = now() where id = 'shop';

  hist := coalesce((select data->'history' from dm_docs where id = 'trips'), '[]'::jsonb);
  insert into dm_docs(id, data, updated_at) values ('trips', jsonb_build_object('history', jsonb_build_array(t) || hist), now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  delete from dm_docs where id = 'trip';
  insert into activity(actor, action, detail) values ('system', 'runner_back', jsonb_build_object('trip', trip->>'id', 'sold', gold, 'pay', pay));
  return 'back';
end $$;
revoke all on function public._shop_tick(boolean) from public, anon, authenticated;

create or replace function public.p_tick() returns text
language plpgsql security definer set search_path = public as $$
begin return _shop_tick(false); end $$;

-- A player sends Wick off with whatever is in his pack.
create or replace function public.p_dispatch(route text, actor text) returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; x jsonb; tr jsonb; tid text := gen_random_uuid()::text;
  thr int; d20 int; hit boolean; d6 int := null; tro jsonb := null; loy int; lr int := null; held boolean := null; d4 int := null;
  spill text := null; r6 int := null; rumor text := null; out_days numeric; shop_days numeric;
  left_at timestamptz := now(); arrive timestamptz; ret timestamptz; actual timestamptz; live boolean; items jsonb;
begin
  if route not in ('main', 'back') then raise exception 'Pick the main road or the back roads.'; end if;
  if actor <> 'dm' and not exists (select 1 from docs where id = actor and kind = 'char') then raise exception 'Unknown player.'; end if;
  select data into s from docs where id = 'shop' for update;
  if s->'trip' is not null then raise exception 'Wick is already on the road.'; end if;
  if coalesce(s->'runner'->>'status', 'party') <> 'party' then raise exception 'Wick isn''t with the party right now.'; end if;
  select data into x from dm_docs where id = 'shop';

  tr := coalesce(s->'travel', '{"main":1,"back":2,"shop":1}'::jsonb);
  out_days := coalesce((tr->>route)::numeric, 1); shop_days := coalesce((tr->>'shop')::numeric, 1);
  thr := greatest(1, least(19, coalesce((s->>'base')::int, 2) + coalesce((s->>'heat')::int, 0) - case when route = 'back' then 2 else 0 end));
  d20 := _d(20); hit := d20 <= thr;
  if hit then
    d6 := _d(6); tro := coalesce(x->'trouble'->(d6 - 1), '{}'::jsonb);
    if coalesce((tro->>'question')::boolean, false) then
      loy := coalesce((s->'runner'->>'loyalty')::int, 0); lr := _d(6); held := lr <= loy;
      if not held then d4 := _d(4); spill := x->'spill'->>(d4 - 1); end if;
    end if;
  else
    r6 := _d(6); rumor := x->'rumors'->>(r6 - 1);
  end if;

  live := coalesce((s->>'inSession')::boolean, false);
  arrive := left_at + make_interval(secs => (out_days * 86400)::double precision);
  ret := arrive + make_interval(secs => ((shop_days + out_days) * 86400)::double precision);
  actual := ret + case when hit and d6 in (1, 4, 6) then interval '1 day' else interval '0' end;
  if live then arrive := left_at; ret := left_at; actual := left_at; end if;

  select coalesce(jsonb_agg(c->>'name'), '[]'::jsonb) into items from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c where c->>'status' = 'pack';
  s := jsonb_set(s, '{cargo}', (select coalesce(jsonb_agg(case when c->>'status' = 'pack' then c || jsonb_build_object('status', 'road', 'tripId', tid) else c end), '[]'::jsonb)
                                from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c));
  s := s || jsonb_build_object('trip', jsonb_build_object('id', tid, 'phase', 'out', 'route', route, 'dc', thr + 1, 'by', actor,
         'leftAt', left_at, 'arriveAt', arrive, 'returnAt', ret, 'items', items, 'instant', live));
  s := jsonb_set(s, '{runner,status}', '"road"');
  update docs set data = s, updated_at = now() where id = 'shop';

  insert into dm_docs(id, data, updated_at) values ('trip', jsonb_build_object(
      'id', tid, 'route', route, 'thr', thr, 'd20', d20, 'hit', hit, 'd6', d6, 'trouble', tro->>'t', 'heat', coalesce((tro->>'heat')::int, 0),
      'late', hit and d6 in (1, 4), 'taken', hit and d6 = 6, 'lostCargo', hit and d6 in (2, 5), 'goldTaken', hit and d6 = 1,
      'question', coalesce((tro->>'question')::boolean, false), 'loyRoll', lr, 'held', held, 'd4', d4, 'spill', spill,
      'r6', r6, 'rumor', rumor, 'items', items, 'leftAt', left_at, 'returnAt', actual), now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  insert into activity(actor, action, detail) values (actor, 'dispatch', jsonb_build_object('route', route, 'items', items));
  if live then perform _shop_tick(true); end if;
  return case when live then 'back' else 'sent' end;
end $$;

-- Take something back out of Wick's pack before he leaves. It goes to party loot.
create or replace function public.p_unpack(cargo_id text, actor text) returns void
language plpgsql security definer set search_path = public as $$
declare s jsonb; c jsonb;
begin
  if actor <> 'dm' and not exists (select 1 from docs where id = actor and kind = 'char') then raise exception 'Unknown player.'; end if;
  select data into s from docs where id = 'shop' for update;
  select e into c from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) e where e->>'id' = cargo_id;
  if c is null or c->>'status' <> 'pack' then raise exception 'That isn''t in Wick''s pack any more.'; end if;
  update docs set data = jsonb_set(data, '{cargo}', (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(data->'cargo') e where e->>'id' <> cargo_id)), updated_at = now()
    where id = 'shop';
  update docs set data = jsonb_set(data, '{entries}', coalesce(data->'entries', '[]'::jsonb) || jsonb_build_array(coalesce(c->'entry', jsonb_build_object('id', gen_random_uuid()::text, 'name', c->>'name', 'kind', 'item', 'qty', coalesce((c->>'qty')::int, 1)))) || coalesce(c->'kids', '[]'::jsonb)), updated_at = now()
    where id = 'stash';
  insert into activity(actor, action, detail) values (actor, 'unpack', jsonb_build_object('item', c->>'name'));
end $$;

-- DM: bring Wick home now (in session, or to skip the wait).
create or replace function public.dm_shop_now(pin text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  return _shop_tick(true);
end $$;

-- DM: call the run off before anything happens. His pack is as it was.
create or replace function public.dm_shop_cancel(pin text) returns text
language plpgsql security definer set search_path = public as $$
declare s jsonb;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  select data into s from docs where id = 'shop' for update;
  if s->'trip' is null then return 'No run to cancel.'; end if;
  s := jsonb_set(s, '{cargo}', (select coalesce(jsonb_agg(case when c->>'status' = 'road' then (c - 'tripId') || '{"status":"pack"}'::jsonb else c end), '[]'::jsonb)
                                from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c));
  s := jsonb_set(s - 'trip', '{runner,status}', '"party"');
  update docs set data = s, updated_at = now() where id = 'shop';
  delete from dm_docs where id = 'trip';
  return 'Run called off.';
end $$;

-- DM: Wick turns up again after being taken. Whatever he was carrying is gone.
create or replace function public.dm_shop_found(pin text, note text) returns text
language plpgsql security definer set search_path = public as $$
declare s jsonb; t jsonb; lost text;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  select data into s from docs where id = 'shop' for update;
  if s->'trip' is null then return 'He isn''t missing.'; end if;
  select string_agg(c->>'name', ', ') into lost from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c where c->>'status' = 'road';
  s := jsonb_set(s, '{cargo}', (select coalesce(jsonb_agg(case when c->>'status' = 'road' then (c - 'tripId') || '{"status":"lost"}'::jsonb else c end), '[]'::jsonb)
                                from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c));
  s := jsonb_set(s, '{runs}', jsonb_build_array(jsonb_build_object('id', s->'trip'->>'id', 'at', now(), 'when', to_char(now(), 'Mon FMDD'),
         'route', s->'trip'->>'route', 'out', array_to_string(coalesce(array(select jsonb_array_elements_text(s->'trip'->'items')), '{}'), ', '),
         'lostItems', coalesce(lost, ''), 'sold', 0, 'pay', 0,
         'news', jsonb_build_array(coalesce(nullif(note, ''), 'He was taken on the road. He''s back now, and the goods are gone.')))) || coalesce(s->'runs', '[]'::jsonb));
  s := jsonb_set(s - 'trip', '{runner,status}', '"party"');
  update docs set data = s, updated_at = now() where id = 'shop';
  select data into t from dm_docs where id = 'trip';
  if t is not null then
    insert into dm_docs(id, data, updated_at) values ('trips', jsonb_build_object('history', jsonb_build_array(t) || coalesce((select data->'history' from dm_docs where id = 'trips'), '[]'::jsonb)), now())
      on conflict (id) do update set data = excluded.data, updated_at = now();
    delete from dm_docs where id = 'trip';
  end if;
  return 'He''s back.';
end $$;

-- DM: start or end a session at the table. Starting one collects the shop's upkeep from party loot,
-- and while it's on, Wick's runs resolve the moment he's sent.
create or replace function public.dm_shop_session(pin text, live boolean) returns text
language plpgsql security definer set search_path = public as $$
declare s jsonb; up int;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  select data into s from docs where id = 'shop' for update;
  if live and not coalesce((s->>'inSession')::boolean, false) then
    up := coalesce((s->>'upkeep')::int, 0);
    update docs set data = jsonb_set(data, '{gold}', to_jsonb(coalesce((data->>'gold')::int, 0) - up)), updated_at = now() where id = 'stash';
    s := jsonb_set(s, '{upkeepLog}', jsonb_build_array(jsonb_build_object('at', now(), 'when', to_char(now(), 'Mon FMDD'), 'paid', up)) || coalesce(s->'upkeepLog', '[]'::jsonb));
  end if;
  if live and up is null then return 'Already in session.'; end if;
  s := s || jsonb_build_object('inSession', live);
  update docs set data = s, updated_at = now() where id = 'shop';
  return case when live then format('Session started. Upkeep paid: %s gp.', up) else 'Session ended.' end;
end $$;

grant execute on function public.p_tick() to anon, authenticated;
grant execute on function public.p_dispatch(text, text) to anon, authenticated;
grant execute on function public.p_unpack(text, text) to anon, authenticated;
grant execute on function public.dm_shop_now(text) to anon, authenticated;
grant execute on function public.dm_shop_cancel(text) to anon, authenticated;
grant execute on function public.dm_shop_found(text, text) to anon, authenticated;
grant execute on function public.dm_shop_session(text, boolean) to anon, authenticated;

select 'fix-3 done' as result, data->'travel' as travel_days from public.docs where id = 'shop';

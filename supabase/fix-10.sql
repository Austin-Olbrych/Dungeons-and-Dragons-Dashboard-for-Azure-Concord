-- fix-10: travel times from wherever the party is.
--
--  * A small map: Vaelmar, Odranard (the Nest and the House), the Ashen Covenant camp and Nebulas, with the days
--    each road takes by the main road and by the back roads. The DM can change any of it on the Shop tab.
--  * Wick leaves from wherever the party is (the DM sets it), goes to the Nest and/or Steven's shop by the shortest
--    roads, in whichever order is quicker, and comes back to the party.
--  * Every run that spends time on a road rolls for trouble, the Nest included, and a quiet run on the back roads
--    cools the heat by 1.
--
-- Run after fix-9. Safe to run more than once: it never overwrites a map or a party location you've already set.

create or replace function public._default_map() returns jsonb language sql immutable as $m$
  select '{"places": {
      "vaelmar":  {"name": "Vaelmar", "note": "Steven’s shop and the bank", "x": 100, "y": 100},
      "odranard": {"name": "Odranard", "note": "The Nest and the House", "x": 460, "y": 60},
      "camp":     {"name": "Ashen Covenant Camp", "note": "", "x": 250, "y": 300},
      "nebulas":  {"name": "Nebulas", "note": "", "x": 620, "y": 330}},
    "roads": [
      {"a": "vaelmar", "b": "odranard", "main": 2, "back": 3},
      {"a": "vaelmar", "b": "camp", "main": 2, "back": 3},
      {"a": "odranard", "b": "camp", "main": 1, "back": 2},
      {"a": "camp", "b": "nebulas", "main": 3, "back": 4},
      {"a": "vaelmar", "b": "nebulas", "main": 4, "back": 5},
      {"a": "odranard", "b": "nebulas", "main": 4, "back": 5}],
    "stay": {"shop": 1, "nest": 0.5}}'::jsonb $m$;

update public.docs set data = data || jsonb_build_object('map', coalesce(data->'map', _default_map()), 'partyAt', coalesce(data->'partyAt', '"camp"'::jsonb)), updated_at = now()
  where id = 'shop';

create or replace function public._days(n numeric) returns interval language sql immutable as $$ select make_interval(secs => (coalesce(n, 0) * 86400)::double precision) $$;

-- the fewest days from one place to another on the map, by the main road or the back roads
create or replace function public._rd(mp jsonb, frm text, dst text, mode text) returns numeric
language plpgsql stable as $$
declare r numeric;
begin
  if frm = dst then return 0; end if;
  with recursive e as (
      select x->>'a' a, x->>'b' b, coalesce((x->>mode)::numeric, (x->>'main')::numeric) d from jsonb_array_elements(mp->'roads') x
      union all select x->>'b', x->>'a', coalesce((x->>mode)::numeric, (x->>'main')::numeric) from jsonb_array_elements(mp->'roads') x),
    p(node, dist, seen) as (select frm, 0::numeric, array[frm]
      union all select e.b, p.dist + e.d, p.seen || e.b from p join e on e.a = p.node where not e.b = any(p.seen))
  select min(dist) into r from p where node = dst;
  if r is null then raise exception 'There’s no road from % to % on the map.', coalesce(mp->'places'->frm->>'name', frm), coalesce(mp->'places'->dst->>'name', dst); end if;
  return r;
end $$;

drop function if exists public.p_dispatch(text, text, text);
create or replace function public.p_dispatch(route text, actor text, payout text default 'carry') returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; x jsonb; tr jsonb; tid text := gen_random_uuid()::text; to_shop boolean; to_nest boolean; legs text;
  thr int := null; d20 int := null; hit boolean := false; d6 int := null; tro jsonb := null; loy int; lr int := null; held boolean := null; d4 int := null;
  spill text := null; r6 int := null; rumor text := null; road numeric; shop_days numeric; nest_days numeric;
  mp jsonb; here text; cur text; t timestamptz; dd numeric; road_total numeric := 0; nest_stay numeric; nest_first boolean := true; nest_end timestamptz := null;
  left_at timestamptz := now(); nest_at timestamptz := null; arrive timestamptz := null; shop_end timestamptz := null; ret timestamptz; actual timestamptz; live boolean; items jsonb;
begin
  if route not in ('main', 'back') then raise exception 'Pick the main road or the back roads.'; end if;
  if payout not in ('carry', 'bank') then raise exception 'Choose whether he carries the coin or banks it.'; end if;
  if (select coalesce(sum(_cargo_lb(c)), 0) from docs d, jsonb_array_elements(coalesce(d.data->'cargo', '[]'::jsonb)) c where d.id = 'shop' and c->>'status' = 'pack') > 100 then
    raise exception 'His pack is over 100 lb. Take something back first.'; end if;
  if actor <> 'dm' and not exists (select 1 from docs where id = actor and kind = 'char') then raise exception 'Unknown player.'; end if;
  perform _cool_heat();
  select data into s from docs where id = 'shop' for update;
  if s->'trip' is not null then raise exception 'Wick is already on the road.'; end if;
  if coalesce(s->'runner'->>'status', 'party') <> 'party' then raise exception 'Wick isn''t with the party right now.'; end if;
  select data into x from dm_docs where id = 'shop';
  to_nest := exists (select 1 from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c where c->>'status' = 'pack' and c->>'dest' = 'nest');
  to_shop := not to_nest or exists (select 1 from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c where c->>'status' = 'pack' and coalesce(c->>'dest', 'shop') = 'shop');
  legs := case when to_nest and to_shop then 'both' when to_nest then 'nest' else 'shop' end;

  -- where he goes, in what order, and how long each road takes from wherever the party is
  mp := coalesce(s->'map', _default_map());
  here := coalesce(s->>'partyAt', 'camp');
  shop_days := coalesce((mp->'stay'->>'shop')::numeric, 1);
  nest_stay := coalesce((mp->'stay'->>'nest')::numeric, 0.5);
  if to_nest and to_shop then
    nest_first := _rd(mp, here, 'odranard', route) + _rd(mp, 'odranard', 'vaelmar', route) + _rd(mp, 'vaelmar', here, route)
               <= _rd(mp, here, 'vaelmar', route) + _rd(mp, 'vaelmar', 'odranard', route) + _rd(mp, 'odranard', here, route);
  end if;
  cur := here; t := left_at;
  if to_nest and nest_first then
    dd := _rd(mp, cur, 'odranard', route); road_total := road_total + dd; t := t + _days(dd);
    nest_at := t; t := t + _days(nest_stay); nest_end := t; cur := 'odranard';
  end if;
  if to_shop then
    dd := _rd(mp, cur, 'vaelmar', route); road_total := road_total + dd; t := t + _days(dd);
    arrive := t; t := t + _days(shop_days); shop_end := t; cur := 'vaelmar';
  end if;
  if to_nest and not nest_first then
    dd := _rd(mp, cur, 'odranard', route); road_total := road_total + dd; t := t + _days(dd);
    nest_at := t; t := t + _days(nest_stay); nest_end := t; cur := 'odranard';
  end if;
  dd := _rd(mp, cur, here, route); road_total := road_total + dd; ret := t + _days(dd);

  -- any run that spends time on a road rolls for trouble, the Nest included
  if road_total > 0 then
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
  end if;

  live := coalesce((s->>'inSession')::boolean, false);
  actual := ret + case when hit and d6 in (1, 4, 6) then interval '1 day' else interval '0' end;
  if live then nest_at := case when to_nest then left_at end; nest_end := nest_at; arrive := case when to_shop then left_at end; shop_end := arrive; ret := left_at; actual := left_at; end if;

  perform _market_to(left_at);   -- catch the shelf up to today before anything new arrives

  select coalesce(jsonb_agg(c->>'name'), '[]'::jsonb) into items from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c where c->>'status' = 'pack';
  s := jsonb_set(s, '{cargo}', (select coalesce(jsonb_agg(case when c->>'status' = 'pack' then c || jsonb_build_object('status', 'road', 'tripId', tid) else c end), '[]'::jsonb)
                                from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c));
  s := s || jsonb_build_object('trip', jsonb_strip_nulls(jsonb_build_object('id', tid, 'phase', 'out', 'route', route, 'legs', legs, 'dc', case when thr is null then null else thr + 1 end, 'by', actor,
         'leftAt', left_at, 'nestAt', nest_at, 'arriveAt', arrive, 'shopEnd', shop_end, 'returnAt', ret, 'items', items, 'instant', live, 'payout', payout,
         'from', here, 'nestEnd', nest_end, 'order', case when to_nest and to_shop then case when nest_first then 'nest-shop' else 'shop-nest' end end, 'roadDays', road_total)));
  s := jsonb_set(s, '{runner,status}', '"road"');
  update docs set data = s, updated_at = now() where id = 'shop';

  insert into dm_docs(id, data, updated_at) values ('trip', jsonb_strip_nulls(jsonb_build_object(
      'id', tid, 'route', route, 'legs', legs, 'thr', thr, 'd20', d20, 'hit', hit, 'd6', d6, 'trouble', tro->>'t', 'heat', coalesce((tro->>'heat')::int, 0),
      'late', hit and d6 in (1, 4), 'taken', hit and d6 = 6, 'lostCargo', hit and d6 in (2, 5), 'goldTaken', hit and d6 = 1,
      'question', coalesce((tro->>'question')::boolean, false), 'loyRoll', lr, 'held', held, 'd4', d4, 'spill', spill,
      'r6', r6, 'rumor', rumor, 'items', items, 'payout', payout, 'leftAt', left_at, 'nestAt', nest_at, 'arriveAt', arrive, 'shopEnd', shop_end, 'nestEnd', nest_end, 'returnAt', actual)), now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  insert into activity(actor, action, detail) values (actor, 'dispatch', jsonb_build_object('route', route, 'legs', legs, 'items', items));
  if live then perform _shop_tick(true); end if;
  return case when live then 'back' else 'sent' end;
end $$;
grant execute on function public.p_dispatch(text, text, text) to anon, authenticated;

create or replace function public._shop_tick(force boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; t jsonb; trip jsonb; m jsonb; c jsonb; mi jsonb; cargo jsonb := '[]'::jsonb; ids text[] := '{}';
  till int; pay int; net int; heat int; marks int := 0; gold int := 0;
  sold_names text[] := '{}'; lost_names text[] := '{}'; shelf_names text[] := '{}'; nest_names text[] := '{}'; bought_names text[] := '{}';
  news jsonb := '[]'::jsonb; run jsonb; hist jsonb; lost boolean; to_nest boolean; to_shop boolean; half int;
  banked int := 0; left_behind int := 0; payout text; brought int := 0; cap int;
begin
  select data into s from docs where id = 'shop' for update;
  trip := s->'trip';
  if trip is null then perform _cool_heat(); return 'idle'; end if;
  if trip->>'phase' <> 'out' then return 'idle'; end if;
  select data into t from dm_docs where id = 'trip' for update;
  if t is null or t->>'id' is distinct from trip->>'id' then return 'no secret'; end if;
  if not force and now() < (t->>'returnAt')::timestamptz then return 'on the road'; end if;

  if coalesce((t->>'taken')::boolean, false) then
    s := jsonb_set(s, '{trip,phase}', '"missing"');
    s := jsonb_set(s, '{runner,status}', '"missing"');
    update docs set data = s, updated_at = now() where id = 'shop';
    insert into activity(actor, action, detail) values ('system', 'runner_missing', jsonb_build_object('trip', trip->>'id'));
    return 'missing';
  end if;

  lost := coalesce((t->>'lostCargo')::boolean, false);
  to_nest := trip->>'legs' in ('nest', 'both'); to_shop := trip->>'legs' in ('shop', 'both') or trip->>'legs' is null;
  select data into m from dm_docs where id = 'market' for update;
  if m is null then m := '{"items":{},"till":0,"nest":{"pending":0,"sales":[],"jobs":0},"heatDelta":0}'::jsonb; insert into dm_docs(id, data) values ('market', m); end if;

  -- what he carried reaches the Nest and the shop, or is lost on the road (the Nest drop comes first, so it's safe)
  for c in select * from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) loop
    if c->>'status' = 'road' and c->>'tripId' = trip->>'id' then
      if c->>'dest' = 'nest' then
        m := jsonb_set(m, array['items', c->>'id'], jsonb_strip_nulls(jsonb_build_object('name', c->>'name', 'status', 'nest', 'value', c->'value', 'hot', c->'hot',
               'since', coalesce(t->>'nestAt', t->>'leftAt'), 'next', coalesce(t->>'nestAt', t->>'leftAt'))));
        c := c || '{"status":"atnest"}'::jsonb; nest_names := nest_names || (c->>'name');
      elsif lost then
        c := c || '{"status":"lost"}'::jsonb; lost_names := lost_names || (c->>'name');
      elsif coalesce((c->>'plain')::boolean, false) and c->>'value' is not null then
        half := floor((c->>'value')::numeric / 2)::int;
        c := c || jsonb_build_object('status', 'sold', 'sold', half, 'soldAt', to_char(now(), 'Mon FMDD'), 'how', 'Steven bought it outright at half value');
        gold := gold + half; bought_names := bought_names || format('%s (%s gp)', c->>'name', half); marks := marks + 1;
      else
        m := jsonb_set(m, array['items', c->>'id'], jsonb_strip_nulls(jsonb_build_object('name', c->>'name', 'status', 'shelf', 'value', c->'value', 'hot', c->'hot',
               'ask', c->'ask', 'min', c->'min', 'since', t->>'arriveAt', 'next', t->>'arriveAt')));
        c := c || '{"status":"atshop"}'::jsonb;
      end if;
    elsif c->>'status' = 'atshop' and coalesce((c->>'repriced')::boolean, false) and m->'items' ? (c->>'id') and to_shop and not lost then
      -- Wick carried the new price with him
      m := jsonb_set(m, array['items', c->>'id'], (m->'items'->(c->>'id')) || jsonb_strip_nulls(jsonb_build_object('ask', c->'ask', 'min', c->'min', 'since', t->>'arriveAt'))
             - case when c->'ask' is null then 'ask' else '' end);
      c := c - 'repriced';
    end if;
    cargo := cargo || jsonb_build_array(c);
  end loop;
  update dm_docs set data = m, updated_at = now() where id = 'market';

  -- the shop sells, day by day, until he heads home
  if to_shop and not lost and t->>'shopEnd' is not null then perform _market_to((t->>'shopEnd')::timestamptz); end if;
  select data into m from dm_docs where id = 'market' for update;

  -- report what Steven's shelf has done since Wick was last there
  if to_shop and not lost then
    select jsonb_agg(case
        when m->'items' ? (x->>'id') and (m->'items'->(x->>'id')->>'status') = 'sold' and x->>'status' <> 'sold' then
          x || jsonb_build_object('status', 'sold', 'sold', (m->'items'->(x->>'id')->>'sold')::int, 'soldAt', to_char((m->'items'->(x->>'id')->>'soldAt')::timestamptz, 'Mon FMDD'))
        when m->'items' ? (x->>'id') and (m->'items'->(x->>'id')->>'status') = 'shelf' then
          x || jsonb_strip_nulls(jsonb_build_object('price', m->'items'->(x->>'id')->'price',
               'shelfDays', greatest(0, floor(extract(epoch from (now() - (m->'items'->(x->>'id')->>'since')::timestamptz)) / 86400))::int,
               'offers', m->'items'->(x->>'id')->'offers'))
        else x end)
      into cargo from jsonb_array_elements(cargo) x;
    for mi in select value from jsonb_each(m->'items') where value->>'status' = 'sold' and not coalesce((value->>'reported')::boolean, false) loop
      sold_names := sold_names || format('%s (%s gp)', mi->>'name', mi->>'sold');
      marks := marks + 1 + case when mi->>'value' is not null and (mi->>'sold')::int >= (mi->>'value')::int then 1 else 0 end;
      if mi->>'notice' is not null then news := news || to_jsonb(mi->>'notice'); end if;
    end loop;
    for mi in select value from jsonb_each(m->'items') where value->>'status' = 'shelf' loop
      shelf_names := shelf_names || format('%s at %s gp', mi->>'name', coalesce(mi->>'price', mi->>'ask', 'no price'));
      if jsonb_array_length(coalesce(mi->'offers', '[]'::jsonb)) > 0 then
        news := news || to_jsonb(format('Steven turned down %s for the %s. It’s under your lowest price.',
                 (select string_agg(o::text || ' gp', ', ') from jsonb_array_elements_text(mi->'offers') o), mi->>'name'));
      end if;
    end loop;
    m := jsonb_set(m, '{items}', coalesce((select jsonb_object_agg(key, case when value->>'status' = 'sold' then value || '{"reported":true}'::jsonb else value - 'offers' end)
                                           from jsonb_each(m->'items')), '{}'::jsonb));
    till := coalesce((m->>'till')::int, 0); gold := gold + till; m := jsonb_set(m, '{till}', '0');
  end if;

  if coalesce((t->>'hit')::boolean, false) then news := to_jsonb(t->>'trouble') || news;
  elsif to_shop then news := to_jsonb('Made it there and back without trouble.'::text) || news;
  else news := to_jsonb('A quick trip to the Nest. Nobody looked twice.'::text) || news; end if;
  if array_length(nest_names, 1) > 0 then news := news || to_jsonb(format('Left %s with Orsolo. His money comes in with the House books.', array_to_string(nest_names, ', '))); end if;
  -- the money: carried home as coin (1 lb per 50 coins, and it can be robbed), or banked in Vaelmar and carried as a receipt
  payout := coalesce(t->>'payout', trip->>'payout', 'carry');
  if payout = 'bank' and gold > 0 then
    banked := gold; gold := 0;
    news := news || to_jsonb(format('Steven deposited %s gp in the Vaelmar bank. Wick brought home the receipt.', banked));
  elsif gold > 0 then
    cap := 100 * 50;
    if gold > cap then
      left_behind := gold - greatest(cap, 0); gold := greatest(cap, 0);
      m := jsonb_set(m, '{till}', to_jsonb(coalesce((m->>'till')::int, 0) + left_behind));
      news := news || to_jsonb(format('He could only carry %s gp (100 lb of coin). Steven is holding the other %s gp for the next run.', gold, left_behind));
    end if;
    if coalesce((t->>'goldTaken')::boolean, false) then
      news := news || to_jsonb(format('The %s gp he was carrying was taken on the way back.', gold)); gold := 0;
    end if;
  end if;
  if t->>'rumor' is not null then news := news || to_jsonb('Rumor: ' || (t->>'rumor')); end if;

  pay := coalesce((s->'runner'->>'pay')::int, 0);
  net := gold - pay;
  update docs set data = data || jsonb_build_object('gold', coalesce((data->>'gold')::int, 0) + net, 'bank', coalesce((data->>'bank')::int, 0) + banked), updated_at = now() where id = 'stash';
  brought := _deliver_contracts();
  if brought > 0 then news := news || to_jsonb(format('He brought %s from the House. They’re on the House tab.', case when brought = 1 then 'a contract' else brought || ' contracts' end)); end if;
  news := news || _contract_news();

  heat := coalesce((s->>'heat')::int, 0) + coalesce((t->>'heat')::int, 0) + coalesce((m->>'heatDelta')::int, 0);
  if trip->>'dc' is not null and not coalesce((t->>'hit')::boolean, false) and trip->>'route' = 'back' then heat := heat - 1; end if;
  heat := greatest(0, least(10, heat));
  m := jsonb_set(m, '{heatDelta}', '0');
  update dm_docs set data = m, updated_at = now() where id = 'market';

  run := jsonb_build_object('id', trip->>'id', 'at', now(), 'when', to_char(now(), 'Mon FMDD'), 'leftAt', trip->'leftAt', 'route', trip->>'route', 'legs', trip->>'legs',
    'out', array_to_string(coalesce(array(select jsonb_array_elements_text(trip->'items')), '{}'), ', '),
    'soldItems', array_to_string(bought_names || sold_names, ', '), 'lostItems', array_to_string(lost_names, ', '), 'shelf', array_to_string(shelf_names, ', '),
    'nest', array_to_string(nest_names, ', '), 'sold', gold + banked, 'banked', banked, 'heldBack', left_behind, 'coinLb', round(gold / 50.0, 1), 'contracts', brought, 'pay', pay, 'news', news, 'late', coalesce((t->>'late')::boolean, false));

  s := s - 'trip';
  s := jsonb_set(s, '{cargo}', coalesce(cargo, '[]'::jsonb));
  s := jsonb_set(s, '{runs}', jsonb_build_array(run) || coalesce(s->'runs', '[]'::jsonb));
  s := jsonb_set(s, '{heat}', to_jsonb(heat));
  s := jsonb_set(s, '{runner,status}', '"party"');
  s := jsonb_set(s, '{steven}', jsonb_build_object('marks', coalesce((s->'steven'->>'marks')::int, 0) + marks));
  s := s || jsonb_build_object('quietSince', now(), 'heatCooledAt', now());
  update docs set data = s, updated_at = now() where id = 'shop';

  hist := coalesce((select data->'history' from dm_docs where id = 'trips'), '[]'::jsonb);
  insert into dm_docs(id, data, updated_at) values ('trips', jsonb_build_object('history', jsonb_build_array(t) || hist), now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  delete from dm_docs where id = 'trip';
  insert into activity(actor, action, detail) values ('system', 'runner_back', jsonb_build_object('trip', trip->>'id', 'sold', gold + banked, 'banked', banked, 'pay', pay));
  return 'back';
end $$;
revoke all on function public._shop_tick(boolean) from public, anon, authenticated;

create or replace function public.dm_skip(pin text, hours numeric) returns text
language plpgsql security definer set search_path = public as $$
declare iv interval; s jsonb; t jsonb; m jsonb; k text; before int; after int; r text;
  ts text[] := array['leftAt','nestAt','nestEnd','arriveAt','shopEnd','returnAt'];
  f text;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if hours is null or hours <= 0 or hours > 24 * 60 then return 'Pick a time between an hour and 60 days.'; end if;
  iv := make_interval(secs => (hours * 3600)::double precision);
  select data into s from docs where id = 'shop' for update;
  before := coalesce((s->>'heat')::int, 0);
  -- the past is further away: shift every stored moment back
  if s->'trip' is not null then
    foreach f in array ts loop
      if s->'trip' ? f then s := jsonb_set(s, array['trip', f], to_jsonb((s->'trip'->>f)::timestamptz - iv)); end if;
    end loop;
  end if;
  foreach f in array array['quietSince','heatCooledAt'] loop
    if s ? f then s := jsonb_set(s, array[f], to_jsonb((s->>f)::timestamptz - iv)); end if;
  end loop;
  update docs set data = s, updated_at = now() where id = 'shop';
  select data into t from dm_docs where id = 'trip' for update;
  if t is not null then
    foreach f in array ts loop
      if t ? f then t := jsonb_set(t, array[f], to_jsonb((t->>f)::timestamptz - iv)); end if;
    end loop;
    update dm_docs set data = t, updated_at = now() where id = 'trip';
  end if;
  select data into m from dm_docs where id = 'market' for update;
  if m is not null then
    for k in select jsonb_object_keys(coalesce(m->'items', '{}'::jsonb)) loop
      foreach f in array array['since','next'] loop
        if m->'items'->k ? f then m := jsonb_set(m, array['items', k, f], to_jsonb((m->'items'->k->>f)::timestamptz - iv)); end if;
      end loop;
    end loop;
    update dm_docs set data = m, updated_at = now() where id = 'market';
  end if;
  r := _shop_tick(false);                       -- brings Wick home if he's now due, or lets the heat cool
  if r = 'idle' then null; end if;
  select coalesce((data->>'heat')::int, 0) into after from docs where id = 'shop';
  insert into activity(actor, action, detail) values ('dm', 'skip', jsonb_build_object('hours', hours));
  return format('Skipped ahead %s.%s%s', case when hours < 24 then hours || ' hours' else round(hours / 24, 1) || ' days' end,
    case r when 'back' then ' Wick is back.' when 'missing' then ' Wick hasn''t come back.' else '' end,
    case when after < before then format(' Heat cooled %s → %s.', before, after) else '' end);
end $$;

grant execute on function public.dm_test_start(text) to anon, authenticated;
grant execute on function public.dm_test_end(text, boolean) to anon, authenticated;
grant execute on function public.dm_skip(text, numeric) to anon, authenticated;

select 'fix-10 done' as result;

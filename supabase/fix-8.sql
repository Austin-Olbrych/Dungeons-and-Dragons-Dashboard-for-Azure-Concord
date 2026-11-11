-- fix-8: weight, coin, and the House's contracts.
--
--  * Every item gets a weight in pounds (from D&D Beyond where it has one; homebrew items get the estimates
--    Claude listed for review). The DM can change any weight in the item editor.
--  * Wick carries up to 100 lb. Players can't load his pack past that.
--  * Coming home, Steven's money is either carried as coin (50 coins to the pound, so 5,000 gp at most, and it can
--    be robbed on the road) or banked in Vaelmar, and Wick brings back a receipt. Players choose when they send him.
--  * Contracts: the DM keeps a pool. Wick brings one or two from the House each time he comes home. Players sign,
--    leave it to the captains, or make their own call (the DM resolves those). Each choice moves the captains'
--    loyalty and respect, the heat, and the House books. Anything still unanswered at Settle session is left to the
--    captains. How involved the Seven are is earned at Settle session from how many contracts they decided.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------- weights
create temp table if not exists _wt(pat text primary key, lb numeric);
truncate _wt;
insert into _wt(pat, lb) values
  -- from D&D Beyond
  ('^robes?$', 4), ('^leather( armor)?$', 10), ('^daggers?$', 1), ('^backpack$', 5), ('^fiddle$', 1), ('^(flask of )?oil', 1),
  ('^rations', 2), ('^bedroll$', 7), ('^bell$', 0), ('^tinderbox$', 1), ('^waterskin$', 5), ('mirror', 0.5), ('bullseye lantern', 2),
  ('^costumes?$', 4), ('^ring of protection$', 0), ('^lute$', 2), ('^candles?$', 0), ('disguise kit', 3), ('^chain mail$', 55),
  ('^javelins?$', 2), ('^flails?$', 2), ('^greatswords?$', 6), ('^warhammers?$', 5), ('^rope', 5), ('hempen', 10),
  ('^torch(es)?$', 1), ('caltrops', 2), ('crowbar', 5), ('^shield', 6), ('^plate', 65), ('^handaxes?$', 2), ('^shortbow$', 2),
  ('^battleaxes?$', 4), ('^greataxes?$', 7), ('^arrows?', 0.05), ('^flask$', 1), ('grappling hook', 4), ('healer.s kit', 3),
  ('^pouch', 1), ('^quiver', 1), ('^sack', 0.5), ('woodcarver.s tools', 5), ('^scale mail$', 45), ('^signet ring$', 0),
  ('carpenter.s tools', 6), ('smith.s tools', 8), ('thieves.? tools', 1), ('^staff$', 4), ('fire opal', 0),
  ('calligrapher.s supplies', 5), ('^book', 5), ('^hammer$', 3), ('mess kit', 1), ('pitons?', 0.25), ('cloak of protection', 0),
  ('^quarterstaff', 4), ('gauntlet band', 0),
  -- homebrew: Claude's estimates, for the DM to review
  ('taskmaster barbed whip', 3), ('hotpants', 1), ('archivist.s satchel', 2), ('wolf.s tooth', 1), ('debt collector', 6),
  ('covenant warden.s half.plate', 40), ('second steel', 5), ('cinder vial', 0.5), ('cartographer.s compass', 0.5),
  ('trophy skull', 3), ('honey balm', 0.25), ('ember match', 0.1), ('^small rock$', 1), ('broken dwarven war hammer', 5),
  ('stone token', 0.25), ('five carved stones', 1), ('everwarm tea', 1), ('rod of absorption', 2), ('ring of mind shielding', 0),
  ('cloak of displacement', 1), ('periapt', 0), ('silver wolf signet', 0), ('pre.covenant orb', 3), ('^the key$', 0.25),
  ('rune', 1), ('field journal', 1), ('contract', 0), ('coded note', 0), ('^deed', 0), ('invitation', 0), ('land grant', 0);

create or replace function pg_temp._lb(n text) returns numeric language sql stable as $$
  select lb from _wt where n ~* pat order by length(pat) desc limit 1 $$;

-- only items with no weight yet get one, so the DM's own numbers are never overwritten
update public.docs set data = jsonb_set(data, '{entries}', (
    select coalesce(jsonb_agg(case when coalesce(e->>'kind', 'item') = 'item' and not (e ? 'weight') and pg_temp._lb(e->>'name') is not null
                                  then e || jsonb_build_object('weight', pg_temp._lb(e->>'name')) else e end), '[]'::jsonb)
    from jsonb_array_elements(data->'entries') e)), updated_at = now()
  where kind in ('char', 'stash') and jsonb_typeof(data->'entries') = 'array';

update public.docs set data = jsonb_set(data, '{cargo}', (
    select coalesce(jsonb_agg(case when c ? 'entry' and not (c->'entry' ? 'weight') and pg_temp._lb(c->>'name') is not null
                                  then jsonb_set(c, '{entry,weight}', to_jsonb(pg_temp._lb(c->>'name'))) else c end), '[]'::jsonb)
    from jsonb_array_elements(data->'cargo') c)), updated_at = now()
  where id = 'shop' and jsonb_typeof(data->'cargo') = 'array';

-- items still without a weight (the DM can set these in the item editor)
select string_agg(distinct e->>'name', ', ') as no_weight_yet
  from public.docs d, jsonb_array_elements(d.data->'entries') e
  where d.kind in ('char', 'stash') and coalesce(e->>'kind', 'item') = 'item' and not (e ? 'weight');
drop table _wt;

-- how much something in the shop ledger weighs, with whatever is packed inside it
create or replace function public._cargo_lb(c jsonb) returns numeric language sql immutable as $$
  select coalesce((c->'entry'->>'weight')::numeric, 0) * coalesce((c->>'qty')::numeric, 1)
       + coalesce((select sum(coalesce((k->>'weight')::numeric, 0) * coalesce((k->>'qty')::numeric, 1)) from jsonb_array_elements(coalesce(c->'kids', '[]'::jsonb)) k), 0) $$;

-- ---------------------------------------------------------------- sending: Wick carries up to 100 lb
drop function if exists public.p_send_to_shop(text, text, int, text, int, text);
create or replace function public.p_send_to_shop(from_id text, entry_id text, asking int, actor text, min_price int default null, dest text default 'shop') returns void
language plpgsql security definer set search_path = public as $$
declare src jsonb; top jsonb; kids jsonb; keep jsonb; lb numeric; now_lb numeric;
begin
  if dest not in ('shop', 'nest') then raise exception 'Send it to the shop or to the Nest.'; end if;
  select data into src from docs where id = from_id and kind in ('char','stash') for update;
  if src is null then raise exception 'Unknown holder: %', from_id; end if;
  perform 1 from docs where id = 'shop' for update;
  select e into top from jsonb_array_elements(coalesce(src->'entries','[]'::jsonb)) e where e->>'id' = entry_id and coalesce(e->>'kind','item') = 'item';
  if top is null then raise exception 'That item is not there any more.'; end if;
  if coalesce((top->>'quest')::boolean, false) then raise exception '% is a quest item. It can’t be sold.', top->>'name'; end if;
  if exists (select 1 from jsonb_array_elements(src->'entries') e where coalesce(e->>'in', '') = entry_id and coalesce((e->>'quest')::boolean, false)) then
    raise exception 'Something inside % is a quest item. Take it out first.', top->>'name'; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into kids from jsonb_array_elements(src->'entries') e where coalesce(e->>'in', '') = entry_id;
  lb := coalesce((top->>'weight')::numeric, 0) * coalesce((top->>'qty')::numeric, 1)
        + coalesce((select sum(coalesce((e->>'weight')::numeric, 0) * coalesce((e->>'qty')::numeric, 1)) from jsonb_array_elements(kids) e), 0);
  select coalesce(sum(_cargo_lb(c)), 0) into now_lb from docs d, jsonb_array_elements(coalesce(d.data->'cargo', '[]'::jsonb)) c where d.id = 'shop' and c->>'status' = 'pack';
  if now_lb + lb > 100 then
    raise exception 'Wick can carry 100 lb. His pack is at % lb, and % would make it % lb.', round(now_lb, 1), top->>'name', round(now_lb + lb, 1);
  end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into keep from jsonb_array_elements(src->'entries') e where not (e->>'id' = entry_id or coalesce(e->>'in', '') = entry_id);
  update docs set data = jsonb_set(data, '{entries}', keep), updated_at = now() where id = from_id;
  update docs set data = jsonb_set(data, '{cargo}', coalesce(data->'cargo', '[]'::jsonb) || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'id', gen_random_uuid()::text, 'name', top->>'name', 'qty', coalesce((top->>'qty')::int, 1),
      'fromId', from_id, 'lb', round(lb, 2), 'from', src->>'name', 'status', 'pack', 'dest', dest,
      'ask', case when dest = 'nest' or asking is null or asking < 0 then null else asking end,
      'min', case when dest = 'nest' or min_price is null or min_price < 0 then null else least(min_price, coalesce(asking, min_price)) end,
      'value', top->'value', 'hot', coalesce((top->>'hot')::boolean, false), 'plain', coalesce((top->>'plain')::boolean, false),
      'sentAt', to_char(now(), 'Mon FMDD'), 'by', actor,
      'entry', (top - 'in') || '{"attuned": false}'::jsonb, 'kids', kids)))), updated_at = now()
    where id = 'shop';
  insert into activity(actor, action, detail) values (actor, 'send_to_shop', jsonb_build_object('item', top->>'name', 'from', from_id, 'asking', asking, 'dest', dest));
end $$;
grant execute on function public.p_send_to_shop(text, text, int, text, int, text) to anon, authenticated;

-- ---------------------------------------------------------------- dispatch: coin or a bank receipt
drop function if exists public.p_dispatch(text, text);
create or replace function public.p_dispatch(route text, actor text, payout text default 'carry') returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; x jsonb; tr jsonb; tid text := gen_random_uuid()::text; to_shop boolean; to_nest boolean; legs text;
  thr int := null; d20 int := null; hit boolean := false; d6 int := null; tro jsonb := null; loy int; lr int := null; held boolean := null; d4 int := null;
  spill text := null; r6 int := null; rumor text := null; road numeric; shop_days numeric; nest_days numeric;
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

  tr := coalesce(s->'travel', '{}'::jsonb);
  road := coalesce((tr->>route)::numeric, case when route = 'back' then 2 else 1 end);
  shop_days := coalesce((tr->>'shop')::numeric, 1); nest_days := coalesce((tr->>'nest')::numeric, 1);

  if to_shop then
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
  if to_nest then nest_at := left_at + make_interval(secs => (nest_days * 86400)::double precision); end if;
  if to_shop then
    arrive := coalesce(nest_at, left_at) + make_interval(secs => (road * 86400)::double precision);
    shop_end := arrive + make_interval(secs => (shop_days * 86400)::double precision);
    ret := shop_end + make_interval(secs => (road * 86400)::double precision);
  else
    ret := nest_at + make_interval(secs => (nest_days * 86400)::double precision);
  end if;
  actual := ret + case when hit and d6 in (1, 4, 6) then interval '1 day' else interval '0' end;
  if live then nest_at := case when to_nest then left_at end; arrive := case when to_shop then left_at end; shop_end := arrive; ret := left_at; actual := left_at; end if;

  perform _market_to(left_at);   -- catch the shelf up to today before anything new arrives

  select coalesce(jsonb_agg(c->>'name'), '[]'::jsonb) into items from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c where c->>'status' = 'pack';
  s := jsonb_set(s, '{cargo}', (select coalesce(jsonb_agg(case when c->>'status' = 'pack' then c || jsonb_build_object('status', 'road', 'tripId', tid) else c end), '[]'::jsonb)
                                from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) c));
  s := s || jsonb_build_object('trip', jsonb_strip_nulls(jsonb_build_object('id', tid, 'phase', 'out', 'route', route, 'legs', legs, 'dc', case when thr is null then null else thr + 1 end, 'by', actor,
         'leftAt', left_at, 'nestAt', nest_at, 'arriveAt', arrive, 'shopEnd', shop_end, 'returnAt', ret, 'items', items, 'instant', live, 'payout', payout)));
  s := jsonb_set(s, '{runner,status}', '"road"');
  update docs set data = s, updated_at = now() where id = 'shop';

  insert into dm_docs(id, data, updated_at) values ('trip', jsonb_strip_nulls(jsonb_build_object(
      'id', tid, 'route', route, 'legs', legs, 'thr', thr, 'd20', d20, 'hit', hit, 'd6', d6, 'trouble', tro->>'t', 'heat', coalesce((tro->>'heat')::int, 0),
      'late', hit and d6 in (1, 4), 'taken', hit and d6 = 6, 'lostCargo', hit and d6 in (2, 5), 'goldTaken', hit and d6 = 1,
      'question', coalesce((tro->>'question')::boolean, false), 'loyRoll', lr, 'held', held, 'd4', d4, 'spill', spill,
      'r6', r6, 'rumor', rumor, 'items', items, 'payout', payout, 'leftAt', left_at, 'nestAt', nest_at, 'arriveAt', arrive, 'shopEnd', shop_end, 'returnAt', actual)), now())
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

  heat := coalesce((s->>'heat')::int, 0) + coalesce((t->>'heat')::int, 0) + coalesce((m->>'heatDelta')::int, 0);
  if to_shop and not coalesce((t->>'hit')::boolean, false) and trip->>'route' = 'back' then heat := heat - 1; end if;
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

-- ---------------------------------------------------------------- contracts
-- The pool lives in the DM-only "contracts" document. Each one looks like:
--   {"id", "title", "desk", "told", "dm", "ready": true, "used": false,
--    "sign":  {"label", "result", "fx": {...}},
--    "leave": {"label", "result", "fx": {...}}}
-- fx: {"people": {"vesna": {"loyalty": 1, "respect": -1}}, "heat": 1, "mood": 0, "gold": 200, "income": 50, "sessions": 3}
--   gold is paid into the House books once; income is paid every session for that many sessions.
insert into public.dm_docs(id, data, updated_at) values ('contracts', '{"pool": []}'::jsonb, now()) on conflict (id) do nothing;
update public.docs set data = data || jsonb_build_object('offers', coalesce(data->'offers', '[]'::jsonb))
  || jsonb_build_object('fin', coalesce(data->'fin', '{}'::jsonb) || jsonb_build_object('extra', coalesce(data->'fin'->'extra', '[]'::jsonb))), updated_at = now()
  where id = 'house';

create or replace function public._contract_fx(fx jsonb, title text) returns text
language plpgsql security definer set search_path = public as $$
declare h jsonb; k text; v jsonb; f text; d int; nm text; parts text[] := '{}'; g int; inc int; heat int; mood int;
begin
  if fx is null or jsonb_typeof(fx) <> 'object' or fx = '{}'::jsonb then return ''; end if;
  select data into h from docs where id = 'house' for update;
  for k, v in select * from jsonb_each(coalesce(fx->'people', '{}'::jsonb)) loop
    foreach f in array array['loyalty', 'respect', 'influence'] loop
      d := coalesce((v->>f)::int, 0);
      if d <> 0 then
        h := jsonb_set(h, '{people}', (select jsonb_agg(case when p->>'id' = k then p || jsonb_build_object(f, greatest(0, least(5, coalesce((p->>f)::int, 0) + d))) else p end)
                                       from jsonb_array_elements(h->'people') p));
        nm := coalesce((select p->>'name' from jsonb_array_elements(h->'people') p where p->>'id' = k), k);
        parts := parts || format('%s %s %s', nm, f, case when d > 0 then '+' || d else d::text end);
      end if;
    end loop;
  end loop;
  mood := coalesce((fx->>'mood')::int, 0);
  if mood <> 0 then
    h := jsonb_set(h, '{mood}', to_jsonb(greatest(-5, least(5, coalesce((h->>'mood')::int, 0) + mood))));
    parts := parts || format('House mood %s', case when mood > 0 then '+' || mood else mood::text end);
  end if;
  h := jsonb_set(h, '{fin}', coalesce(h->'fin', '{}'::jsonb));
  g := coalesce((fx->>'gold')::int, 0); inc := coalesce((fx->>'income')::int, 0);
  if g <> 0 then
    h := jsonb_set(h, '{fin,extra}', coalesce(h->'fin'->'extra', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('name', title, 'gp', g, 'left', 1, 'once', true)));
    parts := parts || format('%s gp %s the House books once', abs(g), case when g > 0 then 'into' else 'out of' end);
  end if;
  if inc <> 0 then
    h := jsonb_set(h, '{fin,extra}', coalesce(h->'fin'->'extra', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('name', title, 'gp', inc, 'left', greatest(1, coalesce((fx->>'sessions')::int, 3)))));
    parts := parts || format('%s gp a session for %s sessions', inc, greatest(1, coalesce((fx->>'sessions')::int, 3)));
  end if;
  heat := coalesce((fx->>'heat')::int, 0);
  if heat <> 0 then
    update docs set data = jsonb_set(data, '{heat}', to_jsonb(greatest(0, least(10, coalesce((data->>'heat')::int, 0) + heat)))), updated_at = now() where id = 'shop';
    parts := parts || format('heat %s', case when heat > 0 then '+' || heat else heat::text end);
  end if;
  if array_length(parts, 1) > 0 then
    h := jsonb_set(h, '{log}', (coalesce(h->'log', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('when', to_char(now(), 'Mon FMDD'), 'text', title || ': ' || array_to_string(parts, ', ')))));
  end if;
  update docs set data = h, updated_at = now() where id = 'house';
  return array_to_string(parts, ', ');
end $$;
revoke all on function public._contract_fx(jsonb, text) from public, anon, authenticated;

-- Wick brings one or two (never more than four waiting on the table at once)
create or replace function public._deliver_contracts(how_many int default null) returns int
language plpgsql security definer set search_path = public as $$
declare pool jsonb; h jsonb; n int; got int := 0; pick jsonb; open_n int;
begin
  select data into pool from dm_docs where id = 'contracts' for update;
  if pool is null then return 0; end if;
  select data into h from docs where id = 'house' for update;
  open_n := (select count(*) from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) o where o->>'status' = 'open');
  n := least(coalesce(how_many, _d(2)), 4 - open_n);
  if n <= 0 then return 0; end if;
  for pick in select e from jsonb_array_elements(coalesce(pool->'pool', '[]'::jsonb)) e
              where coalesce((e->>'ready')::boolean, true) and not coalesce((e->>'used')::boolean, false) order by random() limit n loop
    h := jsonb_set(h, '{offers}', coalesce(h->'offers', '[]'::jsonb) || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
           'id', pick->>'id', 'title', pick->>'title', 'desk', pick->>'desk', 'told', pick->>'told',
           'sign', pick->'sign'->>'label', 'leave', pick->'leave'->>'label', 'status', 'open', 'at', to_char(now(), 'Mon FMDD')))));
    pool := jsonb_set(pool, '{pool}', (select jsonb_agg(case when e->>'id' = pick->>'id' then e || '{"used": true}'::jsonb else e end) from jsonb_array_elements(pool->'pool') e));
    got := got + 1;
  end loop;
  if got > 0 then
    update docs set data = h, updated_at = now() where id = 'house';
    update dm_docs set data = pool, updated_at = now() where id = 'contracts';
  end if;
  return got;
end $$;
revoke all on function public._deliver_contracts(int) from public, anon, authenticated;

-- A player decides: sign it, leave it to the captains, or make their own call (the DM resolves that one)
create or replace function public.p_contract_choose(offer_id text, choice text, note text, actor text) returns text
language plpgsql security definer set search_path = public as $$
declare h jsonb; o jsonb; pe jsonb; res text; fxt text;
begin
  if not exists (select 1 from docs where id = actor and kind = 'char') then raise exception 'Unknown player.'; end if;
  if choice not in ('sign', 'leave', 'own') then raise exception 'Sign it, leave it, or make your own call.'; end if;
  select data into h from docs where id = 'house' for update;
  select x into o from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) x where x->>'id' = offer_id;
  if o is null then raise exception 'That contract isn’t on the table.'; end if;
  if o->>'status' <> 'open' then raise exception 'Someone already decided that one.'; end if;
  if choice = 'own' and coalesce(btrim(note), '') = '' then raise exception 'Say what you want done.'; end if;
  select x into pe from dm_docs d, jsonb_array_elements(coalesce(d.data->'pool', '[]'::jsonb)) x where d.id = 'contracts' and x->>'id' = offer_id;
  if choice = 'own' then
    res := null;
  else
    fxt := _contract_fx(pe->choice->'fx', o->>'title');
    res := coalesce(pe->choice->>'result', '');
    select data into h from docs where id = 'house' for update;
  end if;
  update docs set data = jsonb_set(data, '{offers}', (select jsonb_agg(case when x->>'id' = offer_id then jsonb_strip_nulls(x || jsonb_build_object(
      'status', case when choice = 'own' then 'waiting' else 'done' end, 'choice', choice, 'by', actor, 'note', nullif(btrim(coalesce(note, '')), ''),
      'result', res, 'decidedAt', to_char(now(), 'Mon FMDD'))) else x end) from jsonb_array_elements(h->'offers') x)), updated_at = now()
    where id = 'house';
  insert into activity(actor, action, detail) values (actor, 'contract', jsonb_build_object('title', o->>'title', 'choice', choice));
  return case when choice = 'own' then 'Sent to the DM.' else coalesce(nullif(res, ''), 'Done.') end;
end $$;
grant execute on function public.p_contract_choose(text, text, text, text) to anon, authenticated;

-- The DM settles an "own call" (or any open contract): apply the sign or leave effects, or none, and tell the table what happened
create or replace function public.dm_contract_resolve(pin text, offer_id text, as_choice text, result text) returns text
language plpgsql security definer set search_path = public as $$
declare h jsonb; o jsonb; pe jsonb;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if as_choice not in ('sign', 'leave', 'none') then return 'Pick sign, leave or none.'; end if;
  select data into h from docs where id = 'house' for update;
  select x into o from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) x where x->>'id' = offer_id;
  if o is null or o->>'status' = 'done' then return 'That contract is already settled.'; end if;
  select x into pe from dm_docs d, jsonb_array_elements(coalesce(d.data->'pool', '[]'::jsonb)) x where d.id = 'contracts' and x->>'id' = offer_id;
  if as_choice <> 'none' then perform _contract_fx(pe->as_choice->'fx', o->>'title'); end if;
  select data into h from docs where id = 'house' for update;
  update docs set data = jsonb_set(data, '{offers}', (select jsonb_agg(case when x->>'id' = offer_id then jsonb_strip_nulls(x || jsonb_build_object(
      'status', 'done', 'choice', coalesce(x->>'choice', as_choice), 'by', coalesce(x->>'by', 'dm'),
      'result', coalesce(nullif(btrim(coalesce(result, '')), ''), case when as_choice = 'none' then null else pe->as_choice->>'result' end),
      'decidedAt', coalesce(x->>'decidedAt', to_char(now(), 'Mon FMDD')))) else x end) from jsonb_array_elements(h->'offers') x)), updated_at = now()
    where id = 'house';
  return 'Settled.';
end $$;
grant execute on function public.dm_contract_resolve(text, text, text, text) to anon, authenticated;

-- The pool: add, ready or hold back, delete, put back in the deck, or deliver one right now
create or replace function public.dm_contract_pool(pin text, op text, cid text, c jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  insert into dm_docs(id, data, updated_at) values ('contracts', '{"pool": []}'::jsonb, now()) on conflict (id) do nothing;
  if op = 'add' then
    update dm_docs set data = jsonb_set(data, '{pool}', coalesce(data->'pool', '[]'::jsonb) || jsonb_build_array(
      c || jsonb_build_object('id', gen_random_uuid()::text, 'ready', coalesce((c->>'ready')::boolean, true), 'used', false))), updated_at = now() where id = 'contracts';
    return 'Added to the pool.';
  elsif op in ('ready', 'hold', 'reuse', 'delete') then
    update dm_docs set data = jsonb_set(data, '{pool}', coalesce((select jsonb_agg(case when e->>'id' <> cid then e
        when op = 'ready' then e || '{"ready": true}'::jsonb when op = 'hold' then e || '{"ready": false}'::jsonb
        when op = 'reuse' then e || '{"used": false}'::jsonb else e end) from jsonb_array_elements(data->'pool') e
        where not (op = 'delete' and e->>'id' = cid)), '[]'::jsonb)), updated_at = now() where id = 'contracts';
    return 'Saved.';
  elsif op = 'deliver' then
    n := _deliver_contracts(1);
    return case when n = 0 then 'Nothing to deliver: the pool has no ready contracts, or four are already waiting.' else 'Wick dropped one off.' end;
  end if;
  return 'Unknown action.';
end $$;
grant execute on function public.dm_contract_pool(text, text, text, jsonb) to anon, authenticated;

-- Settle session: pay contract income for the session (the page adds it to the books), let the captains handle anything
-- unanswered, and set how involved the Seven are from what they decided since the last settle.
create or replace function public.dm_contracts_settle(pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h jsonb; o jsonb; pe jsonb; total int; decided int; inv text; newinv text; auto int := 0;
begin
  if not _pin_ok(pin) then return jsonb_build_object('error', 'Wrong PIN.'); end if;
  select data into h from docs where id = 'house' for update;
  -- this session's contract money was just paid into the books; count it down
  h := jsonb_set(h, '{fin,extra}', coalesce((select jsonb_agg(e || jsonb_build_object('left', (e->>'left')::int - 1))
         from jsonb_array_elements(coalesce(h->'fin'->'extra', '[]'::jsonb)) e where coalesce((e->>'left')::int, 1) > 1), '[]'::jsonb));
  update docs set data = h, updated_at = now() where id = 'house';
  -- nobody answered: the captains handle it
  for o in select x from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) x where x->>'status' = 'open' loop
    select x into pe from dm_docs d, jsonb_array_elements(coalesce(d.data->'pool', '[]'::jsonb)) x where d.id = 'contracts' and x->>'id' = o->>'id';
    perform _contract_fx(pe->'leave'->'fx', o->>'title');
    select data into h from docs where id = 'house' for update;
    update docs set data = jsonb_set(data, '{offers}', (select jsonb_agg(case when x->>'id' = o->>'id' then jsonb_strip_nulls(x || jsonb_build_object(
        'status', 'done', 'choice', 'leave', 'by', 'captains', 'decidedAt', to_char(now(), 'Mon FMDD'),
        'result', btrim(coalesce(pe->'leave'->>'result', '') || ' Nobody answered by the end of the session, so the captains handled it.'))) else x end)
        from jsonb_array_elements(h->'offers') x)), updated_at = now() where id = 'house';
    auto := auto + 1;
  end loop;
  select data into h from docs where id = 'house' for update;
  select count(*), count(*) filter (where x->>'choice' in ('sign', 'own')) into total, decided
    from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) x where x->>'status' in ('done', 'waiting') and not coalesce((x->>'settled')::boolean, false);
  inv := coalesce(h->'fin'->>'involve', 'hands');
  newinv := case when total = 0 then inv when decided = 0 then case when inv = 'liaison' then 'liaison' else 'hands' end when decided < total then 'check' else 'run' end;
  h := jsonb_set(h, '{offers}', coalesce((select jsonb_agg(case when x->>'status' in ('done', 'waiting') then x || '{"settled": true}'::jsonb else x end)
         from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) x), '[]'::jsonb));
  -- keep everything still in play, and the last dozen settled ones
  h := jsonb_set(h, '{offers}', coalesce((select jsonb_agg(x order by i) from (
         select x, i, row_number() over (partition by (x->>'status' = 'done') order by i desc) rn from jsonb_array_elements(h->'offers') with ordinality t(x, i)) q
         where x->>'status' <> 'done' or rn <= 12), '[]'::jsonb));
  if newinv <> inv then
    h := jsonb_set(h, '{fin,involve}', to_jsonb(newinv));
    h := jsonb_set(h, '{log}', coalesce(h->'log', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('when', to_char(now(), 'Mon FMDD'),
           'text', format('The Seven decided %s of %s contracts this session. The House now treats them as %s.', decided, total,
             case newinv when 'hands' then 'hands off' when 'liaison' then 'working through Bellamy' when 'check' then 'checking in' else 'running it' end))));
  end if;
  update docs set data = h, updated_at = now() where id = 'house';
  return jsonb_build_object('total', total, 'decided', decided, 'involve', newinv, 'changed', newinv <> inv, 'auto', auto);
end $$;
grant execute on function public.dm_contracts_settle(text) to anon, authenticated;

select 'fix-8 done' as result;

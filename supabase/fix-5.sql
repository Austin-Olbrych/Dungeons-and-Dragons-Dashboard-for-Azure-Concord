-- fix-5: selling the way we talked it through.
--
--  * Every item can carry a value, a "hot" tag and a "quest" tag. Quest items can't be sent to sell.
--  * Players send an item to Steven (the Vaelmar shop) or to Orsolo (the Nest), with an asking price and the lowest
--    price they'll take. Steven rolls to find a buyer each day an item sits on his shelf; the greedier the price,
--    the harder the roll. He marks stuck things down as he levels up, and gets better at spotting cheap sales.
--  * Orsolo sells at value on a DC 10, or 15% over on an 18+. He keeps 15% and may skim more if his loyalty is low.
--    His money comes in with the House books at Settle session.
--  * Wick goes to the Nest, the shop, or both, depending on what's in his pack.
--  * Heat cools on its own while the party lies low, and a House captain can be paid to quiet things down.
--
-- Everything players shouldn't know yet lives in the DM-only "market" document until Wick comes home.
-- Safe to run more than once.

-- ---------------------------------------------------------------- settings
update public.docs set data = data
  || jsonb_build_object('travel', coalesce(data->'travel', '{}'::jsonb) || jsonb_build_object('nest', coalesce(data->'travel'->'nest', '1'::jsonb)))
  || jsonb_build_object('steven', coalesce(data->'steven', jsonb_build_object('marks', 2 * coalesce(jsonb_array_length(data->'upkeepLog'), 0)
        + (select count(*) from jsonb_array_elements(coalesce(data->'cargo', '[]'::jsonb)) c where c->>'status' = 'sold'))))
  || jsonb_build_object('quietSince', coalesce(data->'quietSince', to_jsonb(now())), 'heatCooledAt', coalesce(data->'heatCooledAt', to_jsonb(now())))
  where id = 'shop';
insert into public.dm_docs(id, data, updated_at) values ('market', '{"items":{},"till":0,"nest":{"pending":0,"sales":[],"jobs":0},"heatDelta":0}'::jsonb, now())
  on conflict (id) do nothing;

-- ---------------------------------------------------------------- item values and tags (by name, everywhere)
-- Official magic items have no price on D&D Beyond, so they use the rarity values: uncommon 400, rare 4,000, very rare 40,000.
-- Homebrew values are the middle of the ranges we agreed. Change any of them from the DM item editor.
drop table if exists _vals;
create temp table _vals(name text primary key, value int, hot boolean, quest boolean, plain boolean);
insert into _vals values
 ('robe',1,false,false,true),('leather armor',10,false,false,true),('dagger',2,false,false,true),('costumes',5,false,false,true),('oil',0,false,false,true),
 ('ring of mind shielding',400,false,false,false),('cloak of displacement',4000,false,false,false),('periapt of wound closure',400,false,false,false),
 ('hotpants of distraction',450,false,false,false),('ring of protection',4000,false,false,false),('taskmaster barbed whip',700,false,false,false),
 ('silver wolf signet',null,true,true,false),('trophy skull on a stick',150,false,false,false),('cartographer''s compass',500,false,false,false),
 ('archivist''s satchel',350,false,false,false),('beekeeper''s honey balm',110,false,false,false),('lantern keeper''s ember match',100,false,false,false),
 ('small rock',0,false,false,true),
 ('chain mail',75,false,false,true),('greatsword',50,false,false,true),('flail',10,false,false,true),('javelin',1,false,false,true),('warhammer',15,false,false,true),
 ('wolf''s tooth',14000,true,false,false),('debt collector',5000,true,false,false),('covenant warden''s half-plate',2250,true,false,false),
 ('plate of resistance (necrotic)',5500,false,false,false),('shield',10,false,false,true),('battleaxe',10,false,false,true),('greataxe',30,false,false,true),
 ('handaxe',5,false,false,true),('shortbow',25,false,false,true),('cinder vial',2000,true,false,false),('kael''s warhammer “second steel”',5500,true,false,false),
 ('broken dwarven war hammer',30,false,false,false),('mason''s stone token',15,false,false,false),
 ('scale mail',50,false,false,true),('five carved stones',250,false,false,false),('staff',5,false,false,true),('fire opal',1000,false,false,false),('signet ring',5,false,false,true),
 ('rod of absorption',40000,false,false,false),('cloak of protection',400,false,false,false),('quarterstaff',0,false,false,true),('grandmother maeve''s everwarm tea',275,false,false,false),
 ('twin king''s gauntlet band',null,false,true,false),('the key',null,false,true,false),('the completed rune',null,false,true,false),('the anchoring rune',null,false,true,false),
 ('pre-covenant orb',null,false,true,false),('kael''s field journal',null,false,true,false),
 ('deed to the vaelmar shop',null,false,true,false),('land grant from lord valen',null,false,true,false),('ashen covenant contract',null,false,true,false),
 ('mabbis crane''s contract',null,false,true,false),('coded note from g',null,false,true,false),('invitation to nebulas',null,false,true,false);

update public.docs d set data = jsonb_set(d.data, '{entries}', (
  select coalesce(jsonb_agg(case when v.name is null or e ? 'value' or e ? 'quest' then e
           else e || jsonb_strip_nulls(jsonb_build_object('value', v.value)) || jsonb_build_object('hot', v.hot, 'quest', v.quest, 'plain', v.plain) end
         order by ord), '[]'::jsonb)
  from jsonb_array_elements(coalesce(d.data->'entries', '[]'::jsonb)) with ordinality as x(e, ord)
  left join _vals v on v.name = lower(x.e->>'name')))
where d.kind in ('char', 'stash');
-- documents are quest items whatever they're called
update public.docs d set data = jsonb_set(d.data, '{entries}', (
  select coalesce(jsonb_agg(case when e->>'rarity' in ('Document', 'Quest item', 'Artifact') and not (e ? 'quest') then e || '{"quest":true}'::jsonb else e end order by ord), '[]'::jsonb)
  from jsonb_array_elements(coalesce(d.data->'entries', '[]'::jsonb)) with ordinality as x(e, ord)))
where d.kind in ('char', 'stash');
-- carry values onto anything already in the shop ledger
update public.docs d set data = jsonb_set(d.data, '{cargo}', (
  select coalesce(jsonb_agg(case when v.name is null or c ? 'value' then c else c || jsonb_strip_nulls(jsonb_build_object('value', v.value)) || jsonb_build_object('hot', v.hot, 'plain', v.plain) end order by ord), '[]'::jsonb)
  from jsonb_array_elements(coalesce(d.data->'cargo', '[]'::jsonb)) with ordinality as x(c, ord)
  left join _vals v on v.name = lower(x.c->>'name')))
where d.id = 'shop';

drop table if exists _vals;

-- ---------------------------------------------------------------- helpers
create or replace function public._steven_level(marks int) returns int language sql immutable as $$
  select case when marks >= 60 then 4 when marks >= 36 then 3 when marks >= 18 then 2 when marks >= 6 then 1 else 0 end $$;
create or replace function public._greed_dc(price numeric, val numeric) returns int language sql immutable as $$
  select case when val is null or val <= 0 then 12 else
    case when price <= val * 0.5 then 5 when price <= val * 0.8 then 8 when price <= val then 12
         when price <= val * 1.25 then 15 when price <= val * 1.5 then 18 else 22 end end $$;
revoke all on function public._steven_level(int) from public, anon, authenticated;
revoke all on function public._greed_dc(numeric, numeric) from public, anon, authenticated;

-- Heat cools while nobody sends Wick: 1 point every 7 days, every 4 days while it's 7 or more.
create or replace function public._cool_heat() returns void
language plpgsql security definer set search_path = public as $$
declare s jsonb; h int; base timestamptz; step interval; start int;
begin
  select data into s from docs where id = 'shop' for update;
  if s->'trip' is not null then return; end if;
  h := coalesce((s->>'heat')::int, 0); start := h;
  base := greatest(coalesce((s->>'quietSince')::timestamptz, now()), coalesce((s->>'heatCooledAt')::timestamptz, now()));
  loop
    step := case when h >= 7 then interval '4 days' else interval '7 days' end;
    exit when h <= 0 or now() - base < step;
    h := h - 1; base := base + step;
  end loop;
  if h <> start then
    s := s || jsonb_build_object('heat', h, 'heatCooledAt', base);
    s := jsonb_set(s, '{heatLog}', jsonb_build_array(jsonb_build_object('when', to_char(now(), 'Mon FMDD'), 'text', format('Lying low: heat cooled from %s to %s.', start, h))) || coalesce(s->'heatLog', '[]'::jsonb));
    update docs set data = s, updated_at = now() where id = 'shop';
  end if;
end $$;
revoke all on function public._cool_heat() from public, anon, authenticated;

-- Roll every buyer check due up to a moment in time. Results stay in the DM-only market until Wick reports them.
create or replace function public._market_to(upto timestamptz) returns void
language plpgsql security definer set search_path = public as $$
declare m jsonb; s jsonb; h jsonb; k text; it jsonb; lv int; bonus int; heat int; nxt timestamptz; days int; price int; val int; mn int;
  d20 int; tot int; dc int; miss int; offer int; sold int; cutp int; skim int; loy int; d6 int; att jsonb; n int := 0;
begin
  select data into m from dm_docs where id = 'market' for update;
  select data into s from docs where id = 'shop';
  select data into h from docs where id = 'house';
  heat := coalesce((s->>'heat')::int, 0);
  for k, it in select key, value from jsonb_each(coalesce(m->'items', '{}'::jsonb)) loop
    nxt := (it->>'next')::timestamptz;
    while it->>'status' in ('shelf', 'nest') and nxt is not null and nxt <= upto and n < 2000 loop
      n := n + 1;
      val := (it->>'value')::int;
      if it->>'status' = 'shelf' then
        lv := _steven_level(coalesce((s->'steven'->>'marks')::int, 0) + coalesce((s->>'stevenAdj')::int, 0));
        bonus := (array[2,3,3,4,5])[lv + 1] - heat / 3;
        days := floor(extract(epoch from (nxt - (it->>'since')::timestamptz)) / 86400)::int;
        price := (it->>'ask')::int; mn := coalesce((it->>'min')::int, 0);
        if price is null then nxt := nxt + interval '1 day'; continue; end if;           -- waiting for a price
        if lv >= 1 and days >= 3 then price := greatest(mn, round(price * power(0.9, days / 3))::int); end if;
        it := it || jsonb_build_object('price', price);
        d20 := _d(20); tot := d20 + bonus; dc := _greed_dc(price, val); sold := null; offer := null;
        if d20 = 1 then
          m := jsonb_set(m, '{heatDelta}', to_jsonb(coalesce((m->>'heatDelta')::int, 0) + 1));
          att := jsonb_build_object('at', nxt, 'd20', d20, 'tot', tot, 'dc', dc, 'res', 'bad buyer: heat +1');
        elsif d20 = 20 or (d20 = 19 and lv >= 4) then
          sold := greatest(price, coalesce(round(val * 1.25)::int, price));
          att := jsonb_build_object('at', nxt, 'd20', d20, 'tot', tot, 'dc', dc, 'res', 'collector', 'sold', sold);
        elsif tot >= dc then
          sold := price; att := jsonb_build_object('at', nxt, 'd20', d20, 'tot', tot, 'dc', dc, 'res', 'sold', 'sold', sold);
        else
          miss := dc - tot;
          if miss <= 5 then
            offer := least(price, round(coalesce(val, price) * (1 - 0.1 * (miss - 1)))::int);
            if offer >= mn and not (lv >= 4 and val is not null and offer < val * 0.7) then
              sold := offer; att := jsonb_build_object('at', nxt, 'd20', d20, 'tot', tot, 'dc', dc, 'res', 'took an offer', 'sold', sold);
            else
              att := jsonb_build_object('at', nxt, 'd20', d20, 'tot', tot, 'dc', dc, 'res', case when lv >= 4 and offer >= mn then 'held it, worth more' else 'turned down an offer' end, 'offer', offer);
              it := jsonb_set(it, '{offers}', coalesce(it->'offers', '[]'::jsonb) || to_jsonb(offer));
            end if;
          else
            att := jsonb_build_object('at', nxt, 'd20', d20, 'tot', tot, 'dc', dc, 'res', 'no buyer');
          end if;
        end if;
        it := jsonb_set(it, '{tries}', coalesce(it->'tries', '[]'::jsonb) || att);
        if sold is not null then
          it := it || jsonb_build_object('status', 'sold', 'sold', sold, 'soldAt', nxt);
          m := jsonb_set(m, '{till}', to_jsonb(coalesce((m->>'till')::int, 0) + sold));
          if coalesce((it->>'hot')::boolean, false) then m := jsonb_set(m, '{heatDelta}', to_jsonb(coalesce((m->>'heatDelta')::int, 0) + 1)); end if;
          -- does Steven notice he sold it cheap?
          if lv >= 2 and val is not null and sold < val * 0.7 then
            d20 := _d(20);
            if (d20 + (case when lv >= 3 then 5 else 2 end)) >= 15 then
              it := it || jsonb_build_object('notice', case when lv >= 3
                then format('Steven: “I think we sold the %s cheap. Something like that should go for around %s.”', it->>'name', round(val * (0.9 + random() * 0.2) / 50) * 50)
                else format('Steven: “The buyer didn’t even haggle over the %s. I think we sold it cheap.”', it->>'name') end);
            end if;
          end if;
        end if;
      else
        -- Orsolo at the Nest
        if val is null then nxt := nxt + interval '1 day'; continue; end if;            -- he won't move it until someone values it
        d20 := _d(20);
        if d20 >= 10 then
          sold := case when d20 >= 18 then round(val * 1.15)::int else val end;
          cutp := round(sold * 0.15)::int;
          loy := coalesce((select (p->>'loyalty')::int from jsonb_array_elements(coalesce(h->'people', '[]'::jsonb)) p where p->>'id' = 'orsolo'), 3);
          d6 := _d(6); skim := case when d6 > loy then round(sold * least(0.2, 0.1 * (d6 - loy)))::int else 0 end;
          it := it || jsonb_build_object('status', 'nestsold', 'sold', sold, 'cut', cutp, 'skim', skim, 'net', sold - cutp - skim, 'soldAt', nxt);
          it := jsonb_set(it, '{tries}', coalesce(it->'tries', '[]'::jsonb) || jsonb_build_object('at', nxt, 'd20', d20, 'dc', 10, 'res', case when d20 >= 18 then 'sold 15% over value' else 'sold at value' end, 'sold', sold, 'skimRoll', d6, 'skim', skim));
          m := jsonb_set(m, '{nest,pending}', to_jsonb(coalesce((m->'nest'->>'pending')::int, 0) + sold - cutp - skim));
          m := jsonb_set(m, '{nest,jobs}', to_jsonb(coalesce((m->'nest'->>'jobs')::int, 0) + 1));
        else
          it := jsonb_set(it, '{tries}', coalesce(it->'tries', '[]'::jsonb) || jsonb_build_object('at', nxt, 'd20', d20, 'dc', 10, 'res', 'no buyer yet'));
        end if;
      end if;
      nxt := nxt + interval '1 day';
    end loop;
    it := it || jsonb_build_object('next', nxt);
    m := jsonb_set(m, array['items', k], it);
  end loop;
  update dm_docs set data = m, updated_at = now() where id = 'market';
end $$;
revoke all on function public._market_to(timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------- sending things to sell
drop function if exists public.p_send_to_shop(text, text, int, text);
create or replace function public.p_send_to_shop(from_id text, entry_id text, asking int, actor text, min_price int default null, dest text default 'shop') returns void
language plpgsql security definer set search_path = public as $$
declare src jsonb; top jsonb; kids jsonb; keep jsonb;
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
  select coalesce(jsonb_agg(e), '[]'::jsonb) into keep from jsonb_array_elements(src->'entries') e where not (e->>'id' = entry_id or coalesce(e->>'in', '') = entry_id);
  update docs set data = jsonb_set(data, '{entries}', keep), updated_at = now() where id = from_id;
  update docs set data = jsonb_set(data, '{cargo}', coalesce(data->'cargo', '[]'::jsonb) || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'id', gen_random_uuid()::text, 'name', top->>'name', 'qty', coalesce((top->>'qty')::int, 1),
      'fromId', from_id, 'from', src->>'name', 'status', 'pack', 'dest', dest,
      'ask', case when dest = 'nest' or asking is null or asking < 0 then null else asking end,
      'min', case when dest = 'nest' or min_price is null or min_price < 0 then null else least(min_price, coalesce(asking, min_price)) end,
      'value', top->'value', 'hot', coalesce((top->>'hot')::boolean, false), 'plain', coalesce((top->>'plain')::boolean, false),
      'sentAt', to_char(now(), 'Mon FMDD'), 'by', actor,
      'entry', (top - 'in') || '{"attuned": false}'::jsonb, 'kids', kids)))), updated_at = now()
    where id = 'shop';
  insert into activity(actor, action, detail) values (actor, 'send_to_shop', jsonb_build_object('item', top->>'name', 'from', from_id, 'asking', asking, 'dest', dest));
end $$;
grant execute on function public.p_send_to_shop(text, text, int, text, int, text) to anon, authenticated;

-- Change the asking price or lowest price on something in Wick's pack (players), or anywhere it's waiting (DM).
create or replace function public.p_reprice(cargo_id text, asking int, min_price int, actor text) returns void
language plpgsql security definer set search_path = public as $$
declare s jsonb; c jsonb; m jsonb;
begin
  select data into s from docs where id = 'shop' for update;
  select e into c from jsonb_array_elements(coalesce(s->'cargo', '[]'::jsonb)) e where e->>'id' = cargo_id;
  if c is null then raise exception 'That isn’t on the ledger.'; end if;
  if c->>'dest' = 'nest' then raise exception 'Orsolo sets his own prices.'; end if;
  if c->>'status' not in ('pack', 'atshop') then raise exception 'It can’t be repriced now.'; end if;
  if c->>'status' = 'atshop' and s->'trip' is not null then raise exception 'Wick is on the road. Change it when he’s back.'; end if;
  update docs set data = jsonb_set(data, '{cargo}', (select jsonb_agg(case when e->>'id' = cargo_id then jsonb_strip_nulls(e || jsonb_build_object(
      'ask', case when asking < 0 then null else asking end, 'min', case when min_price < 0 then null else min_price end, 'repriced', true)) else e end)
      from jsonb_array_elements(data->'cargo') e)), updated_at = now() where id = 'shop';
  -- an item already on the shelf gets the new price when Wick next arrives; store it for him to carry
  insert into activity(actor, action, detail) values (actor, 'reprice', jsonb_build_object('item', c->>'name', 'asking', asking, 'min', min_price));
end $$;
grant execute on function public.p_reprice(text, int, int, text) to anon, authenticated;

-- ---------------------------------------------------------------- dispatch and return
drop function if exists public.p_dispatch(text, text);
create or replace function public.p_dispatch(route text, actor text) returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; x jsonb; tr jsonb; tid text := gen_random_uuid()::text; to_shop boolean; to_nest boolean; legs text;
  thr int := null; d20 int := null; hit boolean := false; d6 int := null; tro jsonb := null; loy int; lr int := null; held boolean := null; d4 int := null;
  spill text := null; r6 int := null; rumor text := null; road numeric; shop_days numeric; nest_days numeric;
  left_at timestamptz := now(); nest_at timestamptz := null; arrive timestamptz := null; shop_end timestamptz := null; ret timestamptz; actual timestamptz; live boolean; items jsonb;
begin
  if route not in ('main', 'back') then raise exception 'Pick the main road or the back roads.'; end if;
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
         'leftAt', left_at, 'nestAt', nest_at, 'arriveAt', arrive, 'shopEnd', shop_end, 'returnAt', ret, 'items', items, 'instant', live)));
  s := jsonb_set(s, '{runner,status}', '"road"');
  update docs set data = s, updated_at = now() where id = 'shop';

  insert into dm_docs(id, data, updated_at) values ('trip', jsonb_strip_nulls(jsonb_build_object(
      'id', tid, 'route', route, 'legs', legs, 'thr', thr, 'd20', d20, 'hit', hit, 'd6', d6, 'trouble', tro->>'t', 'heat', coalesce((tro->>'heat')::int, 0),
      'late', hit and d6 in (1, 4), 'taken', hit and d6 = 6, 'lostCargo', hit and d6 in (2, 5), 'goldTaken', hit and d6 = 1,
      'question', coalesce((tro->>'question')::boolean, false), 'loyRoll', lr, 'held', held, 'd4', d4, 'spill', spill,
      'r6', r6, 'rumor', rumor, 'items', items, 'leftAt', left_at, 'nestAt', nest_at, 'arriveAt', arrive, 'shopEnd', shop_end, 'returnAt', actual)), now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  insert into activity(actor, action, detail) values (actor, 'dispatch', jsonb_build_object('route', route, 'legs', legs, 'items', items));
  if live then perform _shop_tick(true); end if;
  return case when live then 'back' else 'sent' end;
end $$;
grant execute on function public.p_dispatch(text, text) to anon, authenticated;

create or replace function public._shop_tick(force boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; t jsonb; trip jsonb; m jsonb; c jsonb; mi jsonb; cargo jsonb := '[]'::jsonb; ids text[] := '{}';
  till int; pay int; net int; heat int; marks int := 0; gold int := 0;
  sold_names text[] := '{}'; lost_names text[] := '{}'; shelf_names text[] := '{}'; nest_names text[] := '{}'; bought_names text[] := '{}';
  news jsonb := '[]'::jsonb; run jsonb; hist jsonb; lost boolean; to_nest boolean; to_shop boolean; half int;
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
  if coalesce((t->>'goldTaken')::boolean, false) and gold > 0 then
    news := news || to_jsonb(format('The %s gp he was carrying was taken on the way back.', gold)); gold := 0;
  end if;
  if t->>'rumor' is not null then news := news || to_jsonb('Rumor: ' || (t->>'rumor')); end if;

  pay := coalesce((s->'runner'->>'pay')::int, 0);
  net := gold - pay;
  update docs set data = jsonb_set(data, '{gold}', to_jsonb(coalesce((data->>'gold')::int, 0) + net)), updated_at = now() where id = 'stash';

  heat := coalesce((s->>'heat')::int, 0) + coalesce((t->>'heat')::int, 0) + coalesce((m->>'heatDelta')::int, 0);
  if to_shop and not coalesce((t->>'hit')::boolean, false) and trip->>'route' = 'back' then heat := heat - 1; end if;
  heat := greatest(0, least(10, heat));
  m := jsonb_set(m, '{heatDelta}', '0');
  update dm_docs set data = m, updated_at = now() where id = 'market';

  run := jsonb_build_object('id', trip->>'id', 'at', now(), 'when', to_char(now(), 'Mon FMDD'), 'leftAt', trip->'leftAt', 'route', trip->>'route', 'legs', trip->>'legs',
    'out', array_to_string(coalesce(array(select jsonb_array_elements_text(trip->'items')), '{}'), ', '),
    'soldItems', array_to_string(bought_names || sold_names, ', '), 'lostItems', array_to_string(lost_names, ', '), 'shelf', array_to_string(shelf_names, ', '),
    'nest', array_to_string(nest_names, ', '), 'sold', gold, 'pay', pay, 'news', news, 'late', coalesce((t->>'late')::boolean, false));

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
  insert into activity(actor, action, detail) values ('system', 'runner_back', jsonb_build_object('trip', trip->>'id', 'sold', gold, 'pay', pay));
  return 'back';
end $$;
revoke all on function public._shop_tick(boolean) from public, anon, authenticated;

create or replace function public.p_tick() returns text
language plpgsql security definer set search_path = public as $$
begin return _shop_tick(false); end $$;

-- ---------------------------------------------------------------- heat: send a House captain to quiet things down
create or replace function public.p_quiet_heat(captain text, actor text, source text default 'party') returns text
language plpgsql security definer set search_path = public as $$
declare s jsonb; h jsonb; p jsonb; heat int; cost int; d20 int; tot int; dc int; ok boolean; fld text; bal int; msg text; nh int;
begin
  if actor <> 'dm' and not exists (select 1 from docs where id = actor and kind = 'char') then raise exception 'Unknown player.'; end if;
  if source not in ('party', 'bank') then raise exception 'Pay from party loot or the bank.'; end if;
  select data into s from docs where id = 'shop' for update;
  select data into h from docs where id = 'house' for update;
  select e into p from jsonb_array_elements(coalesce(h->'people', '[]'::jsonb)) e where e->>'id' = captain and e->>'tier' = 'captain';
  if p is null then raise exception 'Pick one of the House captains.'; end if;
  heat := coalesce((s->>'heat')::int, 0);
  if heat <= 0 then raise exception 'There’s no heat to quiet.'; end if;
  cost := 100 * heat; fld := case when source = 'bank' then 'bank' else 'gold' end;
  select coalesce((data->>fld)::int, 0) into bal from docs where id = 'stash' for update;
  if bal < cost then raise exception 'That costs % gp, and there’s only % gp there.', cost, bal; end if;
  update docs set data = jsonb_set(data, array[fld], to_jsonb(bal - cost)), updated_at = now() where id = 'stash';
  d20 := _d(20); tot := d20 + coalesce((p->>'loyalty')::int, 0); dc := 10 + heat; ok := tot >= dc;
  nh := greatest(0, heat - case when ok then 2 else 1 end);
  if ok then
    msg := format('%s paid off the right people (%s vs DC %s). Heat %s → %s.', p->>'name', tot, dc, heat, nh);
  else
    msg := format('%s did it, but grudgingly (%s vs DC %s). Heat %s → %s, and their respect for the party drops by 1.', p->>'name', tot, dc, heat, nh);
    h := jsonb_set(h, '{people}', (select jsonb_agg(case when e->>'id' = captain then e || jsonb_build_object('respect', greatest(0, coalesce((e->>'respect')::int, 0) - 1)) else e end)
                                   from jsonb_array_elements(h->'people') e));
  end if;
  h := jsonb_set(h, '{log}', coalesce(h->'log', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('when', to_char(now(), 'Mon FMDD'), 'text', format('Paid %s gp %s to quiet the roads. %s', cost, case when source = 'bank' then 'from the bank' else 'from party loot' end, msg))));
  update docs set data = h, updated_at = now() where id = 'house';
  s := s || jsonb_build_object('heat', nh);
  s := jsonb_set(s, '{heatLog}', jsonb_build_array(jsonb_build_object('when', to_char(now(), 'Mon FMDD'), 'text', msg)) || coalesce(s->'heatLog', '[]'::jsonb));
  update docs set data = s, updated_at = now() where id = 'shop';
  insert into activity(actor, action, detail) values (actor, 'quiet_heat', jsonb_build_object('captain', captain, 'cost', cost, 'ok', ok));
  return msg;
end $$;
grant execute on function public.p_quiet_heat(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------- DM tools
-- Set an item's value, hot and quest tags wherever it is (a sheet, party loot, or the ledger).
create or replace function public.dm_set_value(pin text, holder text, item_id text, val int, is_hot boolean, is_quest boolean) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if holder = 'shop' then
    update docs set data = jsonb_set(data, '{cargo}', (select jsonb_agg(case when e->>'id' = item_id then jsonb_strip_nulls(e || jsonb_build_object('value', val, 'hot', is_hot)) - case when val is null then 'value' else '' end else e end)
           from jsonb_array_elements(data->'cargo') e)), updated_at = now() where id = 'shop';
    update dm_docs set data = jsonb_set(data, array['items', item_id], (data->'items'->item_id) || jsonb_strip_nulls(jsonb_build_object('value', val, 'hot', is_hot))), updated_at = now()
      where id = 'market' and data->'items' ? item_id;
  else
    update docs set data = jsonb_set(data, '{entries}', (select jsonb_agg(case when e->>'id' = item_id then jsonb_strip_nulls(e || jsonb_build_object('value', val, 'hot', is_hot, 'quest', is_quest)) - case when val is null then 'value' else '' end else e end)
           from jsonb_array_elements(data->'entries') e)), updated_at = now() where id = holder and kind in ('char', 'stash');
  end if;
  return 'Saved.';
end $$;
grant execute on function public.dm_set_value(text, text, text, int, boolean, boolean) to anon, authenticated;

-- Settle session: Orsolo's sales since last time come in with the House books.
create or replace function public.dm_settle_nest(pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m jsonb; s jsonb; h jsonb; pend int; mi jsonb; k text; lines jsonb := '[]'::jsonb; jobs int; ups int; loy int;
begin
  if not _pin_ok(pin) then return jsonb_build_object('error', 'Wrong PIN.'); end if;
  perform _market_to(now());
  select data into m from dm_docs where id = 'market' for update;
  select data into s from docs where id = 'shop' for update;
  select data into h from docs where id = 'house' for update;
  pend := coalesce((m->'nest'->>'pending')::int, 0);
  for k, mi in select key, value from jsonb_each(m->'items') where value->>'status' = 'nestsold' loop
    lines := lines || to_jsonb(format('Orsolo sold the %s for %s gp, kept %s gp, and paid in %s gp.', mi->>'name', mi->>'sold', (mi->>'cut')::int + (mi->>'skim')::int, mi->>'net'));
    s := jsonb_set(s, '{cargo}', (select jsonb_agg(case when e->>'id' = k then e || jsonb_build_object('status', 'sold', 'sold', (mi->>'net')::int, 'soldAt', to_char(now(), 'Mon FMDD'), 'how', 'through Orsolo, after his cut') else e end)
                                  from jsonb_array_elements(s->'cargo') e));
    m := jsonb_set(m, array['items', k], mi || '{"status":"nestdone"}'::jsonb);
  end loop;
  -- every three jobs through the Nest earns a point of Orsolo's loyalty
  jobs := coalesce((m->'nest'->>'jobs')::int, 0); ups := jobs / 3;
  if ups > 0 then
    h := jsonb_set(h, '{people}', (select jsonb_agg(case when e->>'id' = 'orsolo' then e || jsonb_build_object('loyalty', least(6, coalesce((e->>'loyalty')::int, 0) + ups)) else e end) from jsonb_array_elements(h->'people') e));
    lines := lines || to_jsonb(format('Routing business through the Nest pleased Orsolo: loyalty +%s.', ups));
    m := jsonb_set(m, '{nest,jobs}', to_jsonb(jobs % 3));
  end if;
  if jsonb_array_length(lines) > 0 then
    h := jsonb_set(h, '{log}', coalesce(h->'log', '[]'::jsonb) || (select jsonb_agg(jsonb_build_object('when', to_char(now(), 'Mon FMDD'), 'text', l)) from jsonb_array_elements_text(lines) l));
  end if;
  update docs set data = jsonb_set(data, '{gold}', to_jsonb(coalesce((data->>'gold')::int, 0) + pend)), updated_at = now() where id = 'stash';
  m := jsonb_set(m, '{nest,pending}', '0');
  update dm_docs set data = m, updated_at = now() where id = 'market';
  update docs set data = s, updated_at = now() where id = 'shop';
  update docs set data = h, updated_at = now() where id = 'house';
  return jsonb_build_object('gold', pend, 'lines', lines);
end $$;
grant execute on function public.dm_settle_nest(text) to anon, authenticated;

-- Starting a session: upkeep (party loot or bank), 2 marks for Steven, and the lie-low clock restarts.
create or replace function public.dm_shop_session(pin text, live boolean, source text default 'party') returns text
language plpgsql security definer set search_path = public as $$
declare s jsonb; up int; fld text;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if source not in ('party', 'bank') then return 'Pay from party loot or the bank.'; end if;
  perform _cool_heat();
  select data into s from docs where id = 'shop' for update;
  if live and coalesce((s->>'inSession')::boolean, false) then return 'Already in session.'; end if;
  if live then
    up := coalesce((s->>'upkeep')::int, 0);
    fld := case when source = 'bank' then 'bank' else 'gold' end;
    update docs set data = jsonb_set(data, array[fld], to_jsonb(coalesce((data->>fld)::int, 0) - up)), updated_at = now() where id = 'stash';
    s := jsonb_set(s, '{upkeepLog}', jsonb_build_array(jsonb_build_object('at', now(), 'when', to_char(now(), 'Mon FMDD'), 'paid', up, 'source', source)) || coalesce(s->'upkeepLog', '[]'::jsonb));
    s := jsonb_set(s, '{steven}', jsonb_build_object('marks', coalesce((s->'steven'->>'marks')::int, 0) + 2));
  end if;
  s := s || jsonb_build_object('inSession', live, 'quietSince', now(), 'heatCooledAt', now());
  update docs set data = s, updated_at = now() where id = 'shop';
  insert into activity(actor, action, detail) values ('dm', case when live then 'session_start' else 'session_end' end,
    case when live then jsonb_build_object('upkeep', up, 'source', source) else '{}'::jsonb end);
  return case when live then format('Session started. Upkeep paid: %s gp from %s.', up, case when source = 'bank' then 'the Vaelmar bank' else 'Party loot' end) else 'Session ended.' end;
end $$;

-- Calling a run off also has to leave the market alone (nothing reached it yet), so the old version still works.

select 'fix-5 done' as result,
  (select count(*) from public.docs d, jsonb_array_elements(d.data->'entries') e where d.kind in ('char','stash') and e ? 'value') as items_with_value,
  (select count(*) from public.docs d, jsonb_array_elements(d.data->'entries') e where d.kind in ('char','stash') and coalesce((e->>'quest')::boolean, false)) as quest_items,
  (select count(*) from public.docs d, jsonb_array_elements(d.data->'entries') e where d.kind in ('char','stash') and coalesce((e->>'hot')::boolean, false)) as hot_items;

-- DM: take something off the market (it was sold by hand or returned), so the daily rolls leave it alone.
create or replace function public.dm_market_drop(pin text, cargo_id text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  update dm_docs set data = jsonb_set(data, '{items}', (data->'items') - cargo_id), updated_at = now() where id = 'market';
  return 'Done.';
end $$;
grant execute on function public.dm_market_drop(text, text) to anon, authenticated;
select 'fix-5 done (all parts)' as result;

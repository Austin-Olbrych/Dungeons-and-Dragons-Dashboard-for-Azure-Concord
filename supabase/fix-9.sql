-- fix-9: news from the House.
--
--  * Each time Wick comes home he brings word on the contracts the party has been read, and on the ones he delivered
--    that have been decided: a small update each run, then the outcome the DM picked.
--  * The DM picks outcomes from a ready-made list (or writes one) and sees how each one moves the captains.
--  * Bellamy can be with the party or at the House. At the House, the news is her report and Wick carries it.
--    With the party, Wick brings word and she chimes in. The DM can have Wick bring word that the House wants her.
--
-- Run after fix-8. Safe to run more than once: it never overwrites an outcome you've already picked.
-- ---------------------------------------------------------------- Bellamy: with the party, or at the House
update public.docs set data = data || jsonb_build_object('bellamy', coalesce(data->'bellamy', '{"where": "party"}'::jsonb)), updated_at = now() where id = 'house';

-- ---------------------------------------------------------------- what happens next, contract by contract (DM only)
-- jobs: "read:<contract name>" for contracts the party has been read, or an offer's id for ones Wick brought.
--   beats: small updates Wick brings home, one per run, until the DM picks an outcome
--   outcomes: what the DM can pick from; pick: the one Wick brings next (then the job is closed)
insert into public.dm_docs(id, data, updated_at) values ('ctrnews', '{"jobs": {}}'::jsonb, now()) on conflict (id) do nothing;
update public.dm_docs set data = jsonb_set(data, '{jobs}', ($j${"jobs": {"read:The Marrender Job": {"title": "The Marrender Job", "beats": [{"update": "Vesna’s crew has been buying saffron. A lot of it. Wick says the whole Dock Ward smells like a wedding, and Vola Marrender has started locking her warehouse at noon.", "bellamy": "She’s learning the business before she breaks it. That’s Vesna being careful, which should worry you more than Vesna being angry."}], "outcomes": [{"id": "fire", "title": "Stopped, not killed", "update": "Marrender’s warehouse burned on a quiet night. Nobody was inside; Vesna made sure of that. Marrender has sold her stock at a loss and is leaving Odranard. The client paid the second half on time.", "bellamy": "It was done under the Wolf’s mark. Everyone on the docks knows whose fire that was, and that it was yours.", "fx": {"people": {"vesna": {"loyalty": 1}}, "heat": 1, "gold": 150}, "dm": "Marrender is heading to Vaelmar with a cart of spices and a grudge. She could turn up at Steven’s shop as a supplier, or a problem."}, {"id": "third", "title": "Vesna found a third way", "update": "No fire, no blood. Vesna bought up Marrender’s debts and made her an offer: keep importing, under House protection, for a cut. Marrender signed. The client got his prices back and doesn’t know why.", "bellamy": "Vesna is going to tell everyone the third way was her idea. It was. Let her have it.", "fx": {"people": {"vesna": {"loyalty": 1, "respect": 1}, "orsolo": {"loyalty": -1}}, "income": 40, "sessions": 3}, "dm": "Orsolo hates contracts touching the market, and now the Red Ledger owns a spice importer. Expect him to complain the next time the party visits the Nest."}, {"id": "wrong", "title": "It went sideways", "update": "Marrender had hired guards. One of Vesna’s people was taken by the Watch, and before he was let go he said the word “Wolf” to the wrong sergeant. The job’s done, badly. Marrender is still in business and furious.", "bellamy": "Nobody told the crew whether this was a warning or a burial, so they guessed. That’s what “business as usual” costs.", "fx": {"people": {"vesna": {"respect": -1}}, "heat": 1, "mood": -1}, "dm": "The Watch sergeant now has a name for the new bosses. Good place to raise the Watch bribe next session, or have the sergeant ask for GoGeezle by name."}, {"id": "stiffed", "title": "The client won’t pay", "update": "Vesna’s crew scared Marrender off the saffron trade. Then the client refused the second half: he says the Wolf’s mark makes it look like the Guild had its own grudge, so why should he pay for it? Vesna wants permission to collect.", "bellamy": "She’s asking. Vesna doesn’t ask. I’d answer her.", "fx": {"people": {"vesna": {"loyalty": -1}}}, "dm": "A ready-made contract decision: let Vesna collect (heat, loyalty up) or eat the loss (loyalty down, respect up from Orsolo). Good to hand them at the table."}], "next": 0, "pick": null, "closed": false}, "read:The Road Captain": {"title": "The Road Captain", "beats": [{"update": "Hesper’s watchers have Ilvers’s route: three stops between the eastern camp and the pass, and the same inn every fourth night. He tips well and drinks alone.", "bellamy": "Surveillance pays in boredom first. They’re close to the part that isn’t boring."}], "outcomes": [{"id": "paid", "title": "Delivered, and paid again", "update": "The route went into the intake box for the client. The next morning the payment drawer held a second jar, still warm. Nobody saw who brought it.", "bellamy": "Clients who pay early are buying something besides the job. I don’t know what yet.", "fx": {"people": {"hesper": {"loyalty": 1}, "mabbis": {"respect": -1}}}, "dm": "A second warm ash jar is now in the House vault. Mabbis is unsettled: it’s the same feel as the four jars. The Emberwright is mapping the Covenant’s supply lines."}, {"id": "spotted", "title": "Ilvers noticed", "update": "Ilvers spotted one of Hesper’s watchers and bought him a drink. The next day the Covenant doubled its road patrols around the eastern camp. The client got the route anyway, and the Ears lost a good watcher’s cover.", "bellamy": "He bought our man a drink. Then he bought three more guards.", "fx": {"people": {"hesper": {"respect": -1}}, "heat": 1}, "dm": "The party is near the Covenant camp. Make the roads around it tighter this session: more patrols, more questions."}, {"id": "missing", "title": "Ilvers went missing", "update": "The route was delivered. Two nights later Ilvers never reached his inn. His horse came back to the camp alone. Hesper has gone very quiet.", "bellamy": "We sold a man’s route. Someone used it. That’s what routes are for, but you should know it was us.", "fx": {"people": {"hesper": {"loyalty": -1}}, "mood": -1}, "dm": "Ilvers can turn up later: alive and talking at the camp, or as a pile of fine gray ash on the road. Either way the Emberwright is moving against the Covenant’s supply lines."}, {"id": "copy", "title": "Hesper kept a copy", "update": "The job went cleanly and the client paid. Hesper kept a copy of the route for the Seven: three Covenant supply stops near the camp, with times. She’s offering it to you.", "bellamy": "Hesper doesn’t offer. Take it before she remembers who she is.", "fx": {"people": {"hesper": {"loyalty": 1, "respect": 1}}}, "dm": "Hand them a small map of the three stops. Useful for the Ashen Covenant path."}], "next": 0, "pick": null, "closed": false}, "read:STEVEN — VAELMAR": {"title": "STEVEN — VAELMAR", "beats": [{"update": "Steven says a woman in gray bought a single candle, paid in very old coin, and asked how his cousin was doing. He didn’t know which cousin she meant. He has a lot of cousins.", "bellamy": "That wasn’t a customer. That was somebody checking the address."}, {"update": "Hesper’s people found a second paper in the intake box. Same neat hand: “STILL VAELMAR.” Fine gray dust in the fold, and nobody logged it in.", "bellamy": "Whoever is writing these wants you to know they’re patient."}], "outcomes": [{"id": "jar", "title": "Something left on the counter", "update": "Steven opened the shop to find a warm ash jar sitting on the counter. The door was still locked. Nothing was taken. He has put it on a high shelf and won’t go near it.", "bellamy": "Locked doors don’t mean much to some clients. I’d ask Rina to look at the locks, and I wouldn’t sell that jar.", "fx": {}, "dm": "The Emberwright is marking the shop as known. Decide whether the jar is a gift, a beacon or a receipt. It stays warm."}, {"id": "runner", "title": "Hesper caught the messenger", "update": "Hesper’s crew caught the kid who dropped the papers. He was paid two silver by a man whose hands left gray dust on everything, a man the kid swears never breathed the whole time they talked.", "bellamy": "Mabbis went very quiet when Wick told him. Mabbis is never quiet.", "fx": {"people": {"hesper": {"loyalty": 1}}}, "dm": "Same description as the courier who delivered the four jars (Mabbis’s secret). Good moment for Mabbis to finally tell the party what he heard."}, {"id": "offer", "title": "An offer for the shop", "update": "A polite man in a good coat offered Steven 500 gp for the shop deed. Steven said no, he thinks. He also says the man knew the shop’s upkeep to the copper.", "bellamy": "He said no. Probably. Steven says a lot of things. The deed is in GoGeezle’s satchel, so whoever wants it has to come through you.", "fx": {}, "dm": "The buyer is a front. Covenant or Emberwright, your call. The deed is in GoGeezle’s Archivist’s Satchel."}, {"id": "faded", "title": "The name faded", "update": "The paper in the intake box has gone blank. The ink faded overnight, name and all. Mabbis says it hasn’t faded from the book. “Nothing fades there.”", "bellamy": "Something wrote that name in ink that burns away. I’d rather it had written a threat. Threats you can read.", "fx": {"mood": -1}, "dm": "The threat isn’t gone; the message was delivered. Keep the Steven thread warm for a later session."}], "next": 0, "pick": null, "closed": false}, "read:Nixie Vane": {"title": "Nixie Vane", "beats": [{"update": "Nixie hasn’t been on her corner in four days. The street runners say she sleeps somewhere different every night and won’t say where.", "bellamy": "The contract is still open because you said business as usual. She knows it, and she knows who said it."}], "outcomes": [{"id": "comes", "title": "She comes to you", "update": "Nixie found the party on her own: two days of walking, a bandaged arm, and one question. Why didn’t you strike it?", "bellamy": "She walked two days to ask you that. I’d have a better answer ready than “business as usual.”", "fx": {"people": {"nixie": {"loyalty": -3}, "mabbis": {"loyalty": -1}}}, "dm": "Matches your Guild clock (she arrives hurt; keep it light). Striking the contract now gives Mabbis his loyalty back and starts Nixie climbing. She can become a runner for the party."}, {"id": "mabbis", "title": "Mabbis struck it himself", "update": "Mabbis struck Nixie’s name from the ledger without asking anyone, then told Wick so the Seven would hear it from him first. Vesna is furious about the fee.", "bellamy": "The Ledgerkeeper made a call the Seven wouldn’t. The captains noticed. So did I.", "fx": {"people": {"vesna": {"loyalty": -1}, "nixie": {"loyalty": 1}}}, "dm": "A test. Overrule Mabbis and he loses faith; back him and Hesper and Tannic see the book deciding things. Either way it’s a conversation for the table."}, {"id": "hesper", "title": "Hesper took her in", "update": "Hesper pulled Nixie into the Ears as a courier, somewhere the contract crew can’t reach her. Nixie is safe for now. She owes Hesper, not you.", "bellamy": "Hesper collects people who owe her. She just collected a good one.", "fx": {"people": {"hesper": {"loyalty": 1}, "nixie": {"loyalty": -1}}}, "dm": "Hesper gains a loyal runner who knows the Nest. Nixie can still be won back if the party strikes the contract."}, {"id": "sold", "title": "The contract was sold on", "update": "Vesna’s desk sold the contract to a crew from out of town, so it isn’t the Guild’s job any more, officially. Nixie has gone to ground.", "bellamy": "It’s not ours anymore. That’s how Vesna put it to me, like it was good news.", "fx": {"people": {"vesna": {"loyalty": 1}, "mabbis": {"loyalty": -1}}, "mood": -1}, "dm": "An outside crew is now in Odranard hunting a Guild runner. A hook if the party wants to step in; strangers working the Wolf’s streets also looks bad for the House."}], "next": 0, "pick": null, "closed": false}}}$j$::jsonb)->'jobs' || coalesce(data->'jobs', '{}'::jsonb)), updated_at = now() where id = 'ctrnews';

-- Put one update (or the outcome) on a contract: apply its effects, record who brought it, and close it if it's the outcome
create or replace function public._deliver_job(job_key text, item jsonb, closing boolean, via text) returns text
language plpgsql security definer set search_path = public as $$
declare h jsonb; nm text; upd jsonb; title text;
begin
  select coalesce(data->'jobs'->job_key->>'title', '') into title from dm_docs where id = 'ctrnews';
  if job_key like 'read:%' then nm := substr(job_key, 6); else nm := null; end if;
  select data into h from docs where id = 'house';
  if title = '' then
    title := coalesce(nm, (select o->>'title' from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) o where o->>'id' = job_key), 'A contract');
  end if;
  perform _contract_fx(item->'fx', title);
  select data into h from docs where id = 'house' for update;
  upd := jsonb_strip_nulls(jsonb_build_object('when', to_char(now(), 'Mon FMDD'), 'text', item->>'update', 'bellamy', nullif(item->>'bellamy', ''),
           'via', via, 'outcome', case when closing then item->>'title' end));
  if nm is not null then
    h := jsonb_set(h, '{contracts}', coalesce((select jsonb_agg(case when c->>'name' = nm then c || jsonb_build_object(
           'update', item->>'update', 'updates', coalesce(c->'updates', '[]'::jsonb) || jsonb_build_array(upd),
           'status', case when closing then coalesce(item->>'status', 'closed') else c->>'status' end) else c end)
         from jsonb_array_elements(coalesce(h->'contracts', '[]'::jsonb)) c), '[]'::jsonb));
  else
    h := jsonb_set(h, '{offers}', coalesce((select jsonb_agg(case when o->>'id' = job_key then o || jsonb_build_object(
           'latest', item->>'update', 'updates', coalesce(o->'updates', '[]'::jsonb) || jsonb_build_array(upd)) || case when closing then '{"over": true}'::jsonb else '{}'::jsonb end else o end)
         from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) o), '[]'::jsonb));
  end if;
  update docs set data = h, updated_at = now() where id = 'house';
  return title;
end $$;
revoke all on function public._deliver_job(text, jsonb, boolean, text) from public, anon, authenticated;

-- What Wick brings home from the House: the outcome the DM picked for each contract, or the next small update.
-- If Bellamy is at the House, it's her report and Wick carries it. If she's with the party, Wick brings word and she chimes in.
create or replace function public._contract_news() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n jsonb; k text; j jsonb; titles text[] := '{}'; via text; h jsonb; news jsonb := '[]'::jsonb; nx int;
begin
  select data into n from dm_docs where id = 'ctrnews' for update;
  select data into h from docs where id = 'house';
  via := case when coalesce(h->'bellamy'->>'where', 'party') = 'house' then 'bellamy' else 'wick' end;
  if n is not null then
    for k, j in select * from jsonb_each(coalesce(n->'jobs', '{}'::jsonb)) loop
      if coalesce((j->>'closed')::boolean, false) then continue; end if;
      if j->'pick' is not null and jsonb_typeof(j->'pick') = 'object' then
        titles := titles || _deliver_job(k, j->'pick', true, via);
        n := jsonb_set(n, array['jobs', k, 'closed'], 'true');
      else
        nx := coalesce((j->>'next')::int, 0);
        if nx < jsonb_array_length(coalesce(j->'beats', '[]'::jsonb)) then
          titles := titles || _deliver_job(k, j->'beats'->nx, false, via);
          n := jsonb_set(n, array['jobs', k, 'next'], to_jsonb(nx + 1));
        end if;
      end if;
    end loop;
    update dm_docs set data = n, updated_at = now() where id = 'ctrnews';
  end if;
  if array_length(titles, 1) > 0 then
    news := news || to_jsonb(format('%s from the House on %s. It’s on the House tab.', case when via = 'bellamy' then 'Bellamy sent word' else 'He brought word' end, array_to_string(titles, ', ')));
  end if;
  select data into h from docs where id = 'house' for update;
  if h->'bellamy'->>'summon' = 'queued' then
    h := jsonb_set(h, '{bellamy,summon}', '"delivered"');
    h := jsonb_set(h, '{bellamy,summonedAt}', to_jsonb(to_char(now(), 'Mon FMDD')));
    update docs set data = h, updated_at = now() where id = 'house';
    news := news || to_jsonb(format('The House asks for Bellamy. %s', coalesce(nullif(h->'bellamy'->>'reason', ''), 'Mabbis wants her back on the contract floor as soon as she can be spared.')));
  end if;
  return news;
end $$;
revoke all on function public._contract_news() from public, anon, authenticated;

-- DM: pick what happens (a ready-made outcome or one you write), clear the pick, or tell the table right now
create or replace function public.dm_contract_outcome(pin text, job_key text, outcome jsonb, now_too boolean) returns text
language plpgsql security definer set search_path = public as $$
declare n jsonb; h jsonb; via text; title text;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  insert into dm_docs(id, data, updated_at) values ('ctrnews', '{"jobs": {}}'::jsonb, now()) on conflict (id) do nothing;
  select data into n from dm_docs where id = 'ctrnews' for update;
  if not (n->'jobs' ? job_key) then
    select data into h from docs where id = 'house';
    title := case when job_key like 'read:%' then substr(job_key, 6) else (select o->>'title' from jsonb_array_elements(coalesce(h->'offers', '[]'::jsonb)) o where o->>'id' = job_key) end;
    if title is null then return 'That contract isn’t on the books.'; end if;
    n := jsonb_set(n, array['jobs', job_key], jsonb_build_object('title', title, 'beats', '[]'::jsonb, 'outcomes', '[]'::jsonb, 'next', 0, 'closed', false));
  end if;
  if coalesce((n->'jobs'->job_key->>'closed')::boolean, false) then return 'That one is already settled.'; end if;
  n := jsonb_set(n, array['jobs', job_key, 'pick'], coalesce(outcome, 'null'::jsonb));
  update dm_docs set data = n, updated_at = now() where id = 'ctrnews';
  if now_too and outcome is not null then
    perform _deliver_job(job_key, outcome, true, 'table');
    update dm_docs set data = jsonb_set(data, array['jobs', job_key, 'closed'], 'true'), updated_at = now() where id = 'ctrnews';
    return 'Told the table.';
  end if;
  return case when outcome is null then 'Cleared.' else 'Wick brings it home next run.' end;
end $$;
grant execute on function public.dm_contract_outcome(text, text, jsonb, boolean) to anon, authenticated;

-- DM: where Bellamy is, and whether Wick should carry word that the House wants her
create or replace function public.dm_bellamy(pin text, where_now text, summon boolean, reason text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if where_now not in ('party', 'house') then return 'With the party or at the House.'; end if;
  update docs set data = jsonb_set(data, '{bellamy}', jsonb_strip_nulls(jsonb_build_object('where', where_now,
      'summon', case when summon then 'queued' when where_now = 'house' then null else data->'bellamy'->>'summon' end,
      'reason', case when summon then nullif(btrim(coalesce(reason, '')), '') else data->'bellamy'->>'reason' end))), updated_at = now()
    where id = 'house';
  return 'Saved.';
end $$;
grant execute on function public.dm_bellamy(text, text, boolean, text) to anon, authenticated;

-- ---------------------------------------------------------------- Wick's return now brings the news
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

select 'fix-9 done' as result;

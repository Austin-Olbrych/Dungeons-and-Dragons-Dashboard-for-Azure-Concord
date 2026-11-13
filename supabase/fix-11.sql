-- fix-11: load the twelve House contracts into the DM-only contract pool.
--
-- Source: the "House Contracts Pool" doc (Nov 11). Wick brings one or two home on each run (never more than four
-- waiting at once). Each contract has a sign side and a leave side with effects the site applies on its own; a
-- "make your own call" answer goes to the DM, who settles it on the House tab. Anything the site can't apply by
-- itself (a death roll, a sealed jar, Wick's loyalty, an extra rumor) is in the contract's DM-only note.
--
-- People are matched by name in the House roster (Vesna, Tannic, Orsolo, Hesper, Mabbis). If one can't be found,
-- nothing is loaded. Repeating income runs for 12 sessions.
--
-- Run after fix-10. Safe to run more than once: a contract whose title is already in the pool is skipped.

do $fix$
declare
  src jsonb := $j$[
  {"title": "The salt warehouse dues", "desk": "Vesna Kell's desk",
   "told": "Corlin Vash, who runs a salt warehouse on the river, is three months behind on what he owes the House. Vesna wants the Wolf's signature on a collection. Bellamy: \"Corlin has a sick daughter and a loud mouth. Both will matter.\"",
   "dm": "Own call: forgive half, take a share of the warehouse, or find out who else he owes. If it still pays 150+, Vesna respect +1. Spark: Corlin owes the Covenant too.",
   "sign": {"label": "Sign it: Vesna collects", "result": "Vesna collected in full, politely.", "fx": {"gold": 300, "people": {"Vesna": {"respect": 1}}}},
   "leave": {"label": "Leave it to Vesna", "result": "Vesna sent Tannic's crews to collect. Corlin is talking about it in every tavern.", "fx": {"gold": 300, "heat": 1}}},

  {"title": "The glassblower's protection", "desk": "Vesna Kell's desk",
   "told": "A new glassblower, Ilse Marrow, opened near the House's streets. Vesna wants her on the protection books: 100 gp every session from now on. Bellamy: \"She paid her first month in coin that was still warm.\"",
   "dm": "Own call: meet Ilse first, or turn her down. Turning her down: Vesna respect -1. Spark: the warm coin points to the ash jars. Hesper wants to know.",
   "sign": {"label": "Sign it: Ilse goes on the books", "result": "Ilse pays, and the House watches her shop.", "fx": {"income": 100, "sessions": 12, "people": {"Vesna": {"loyalty": 1}}}},
   "leave": {"label": "Leave it to Vesna", "result": "Vesna signed her anyway, at a lower rate.", "fx": {"income": 50, "sessions": 12}}},

  {"title": "The toll post on the north road", "desk": "Tannic Roe's Knives",
   "told": "A Covenant toll post squeezes everything going north, Wick included. Tannic wants the Seven's word to hit it: take the strongbox and scare the guards off the road. Bellamy: \"He's asked twice. He won't ask a third time.\"",
   "dm": "If signed, roll a d6: on a 1 someone doesn't come back. Then Tannic loses 1 loyalty and the respect +1 doesn't happen (undo it in the House tab). Own call: give him a plan, pick the night, or go with him. A plan he can say out loud: Tannic loyalty +1. Spark: the strongbox holds Covenant survey maps.",
   "sign": {"label": "Sign it: the Knives hit the post", "result": "The Knives hit the toll post and took the strongbox.", "fx": {"gold": 400, "heat": 2, "people": {"Tannic": {"respect": 1}}}},
   "leave": {"label": "Leave it to Tannic", "result": "Tannic won't move without orders. Nothing happened, and he noticed.", "fx": {"people": {"Tannic": {"respect": -1}}}}},

  {"title": "New blood", "desk": "Tannic Roe's Knives",
   "told": "A rival crew broke up after their boss vanished. Tannic wants to take on six of their fighters: 200 gp now to buy them in, more take later. Bellamy: \"Two of them used to work for Kael.\"",
   "dm": "Own call: meet them first, or turn them away. Spark: Kael's two still ask about him, and know the party's faces.",
   "sign": {"label": "Sign it: all six join", "result": "The six joined the Knives.", "fx": {"gold": -200, "income": -100, "sessions": 12, "people": {"Tannic": {"loyalty": 1}}}},
   "leave": {"label": "Leave it to Tannic", "result": "Tannic hired the cheapest two.", "fx": {"gold": -50, "income": -25, "sessions": 12}}},

  {"title": "First look", "desk": "Orsolo's Nest",
   "told": "Orsolo asks that every relic the party finds go past him before it reaches Steven's shelf, so he can price it first. Bellamy: \"He means every relic. Including the ones you'd rather keep quiet.\"",
   "dm": "If signed: relics go to the Nest first and Orsolo names a price within a day; Steven earns no marks on relics. Own call: first look on hot items only, or items over a set value. A fair split: Orsolo loyalty +1, Steven untouched.",
   "sign": {"label": "Sign it: Orsolo sees relics first", "result": "Relics go past Orsolo before they reach Steven's shelf.", "fx": {"people": {"Orsolo": {"loyalty": 1}}}},
   "leave": {"label": "Leave it", "result": "Nothing changed. Orsolo took it as a sign you don't need him.", "fx": {"people": {"Orsolo": {"respect": -1}}}}},

  {"title": "The Twin Kings relics", "desk": "Orsolo's Nest",
   "told": "Orsolo has a crate of forged Twin Kings trinkets. He wants them sold through the Vaelmar shop, where the party's fame makes them easy money. Bellamy: \"They're good fakes. Too good. Someone will check.\"",
   "dm": "If signed: each session roll a d6; on a 1 the fakes are exposed and the party's name takes the hit. Own call: refuse, or have Rina inspect the crate. Refusing: Orsolo respect -1. Spark: one of the fakes isn't fake. It hums near warm ash.",
   "sign": {"label": "Sign it: Steven sells the fakes", "result": "Steven is selling the Twin Kings trinkets.", "fx": {"gold": 500, "heat": 1}},
   "leave": {"label": "Leave it to Orsolo", "result": "Orsolo moved them through other fences.", "fx": {"gold": 200}}},

  {"title": "Two masters for Wick", "desk": "Hesper Lark's Ears",
   "told": "Hesper asks that Wick report to her as well as to the party: where he goes, who he sees, what he hears on the road. Bellamy: \"Wick will do it. He won't like it.\"",
   "dm": "If signed: lower Wick's loyalty by 1 on the Shop tab, and each run's rumor comes with a second one from Hesper. Own call: share the reports yourselves (Hesper respect +1, Wick untouched), or refuse (Hesper loyalty -1).",
   "sign": {"label": "Sign it: Wick reports to Hesper", "result": "Wick reports to Hesper after each run.", "fx": {"people": {"Hesper": {"loyalty": 1, "respect": 1}}}},
   "leave": {"label": "Leave it to Hesper", "result": "Hesper put her own watcher on Wick's route. Someone spotted him.", "fx": {"heat": 1}}},

  {"title": "The Covenant courier", "desk": "Hesper Lark's Ears",
   "told": "Hesper's people have spotted a Covenant courier who carries small sealed jars through Odranard every ten days. She wants a crew on the next one. Bellamy: \"The jars are warm. Hesper wouldn't touch one.\"",
   "dm": "If signed: add one sealed jar to Party loot. If left: the next run's rumor names where the courier goes. Own call: follow the courier instead of robbing him. Spark: a direct line into the ash-jar network and the Emberwright.",
   "sign": {"label": "Sign it: take the satchel", "result": "Hesper's crew took the courier's satchel. One sealed jar is on its way to you.", "fx": {"heat": 1, "people": {"Hesper": {"respect": 1}}}},
   "leave": {"label": "Leave it to Hesper", "result": "Hesper is only watching the courier for now.", "fx": {}}},

  {"title": "The struck names", "desk": "Mabbis Crane",
   "told": "Mabbis asks permission to put three names back in the ledger: people the old Guildmistress struck off, Nixie's family among them. Protecting them costs 150 gp a session. Bellamy: \"He's never asked for anything before.\"",
   "dm": "If signed: Nixie hears. Own call: restore only Nixie's family, or pay for it from party gold. Restoring any: Mabbis respect +1. Spark: one of the three is alive, and hiding from someone.",
   "sign": {"label": "Sign it: put the names back", "result": "The names are back in the ledger, and the House protects them.", "fx": {"income": -150, "sessions": 12, "people": {"Mabbis": {"loyalty": 1, "respect": 1}}}},
   "leave": {"label": "Leave them struck", "result": "The names stay struck. Mabbis said nothing more about it.", "fx": {"people": {"Mabbis": {"respect": -1}}}}},

  {"title": "Read the contract", "desk": "Mabbis Crane",
   "told": "Mabbis asks, again, whether anyone has read the contract he handed them on the way in. It's in GoGeezle's satchel. Bellamy: \"Page four. He's underlined it.\"",
   "dm": "If signed: reveal the clause on page four. If left: Mabbis asks again in two sessions (put it back in the deck). Own call: read it but don't sign, or ask him what it says. Asking him directly: Mabbis respect +1.",
   "sign": {"label": "Read it and countersign", "result": "The Seven read the contract and countersigned it.", "fx": {"people": {"Mabbis": {"loyalty": 1}}}},
   "leave": {"label": "Leave it in the satchel", "result": "It stays in GoGeezle's satchel.", "fx": {}}},

  {"title": "Who takes the docks", "desk": "Tannic and Vesna",
   "told": "The river docks' tolls are up for grabs. Tannic wants them for the Knives; Vesna wants them on her books. Both have asked Bellamy to bring it to the Seven. To give them to Tannic, make your own call. Bellamy: \"Whoever you pick, the other one will remember.\"",
   "dm": "Own call for Tannic: +150 gp every session, Tannic loyalty +1, Vesna respect -1. A split that holds, or Bellamy running them: no rating loss, +150 gp every session.",
   "sign": {"label": "Give the docks to Vesna", "result": "Vesna's desk runs the docks.", "fx": {"income": 200, "sessions": 12, "people": {"Vesna": {"loyalty": 1}, "Tannic": {"respect": -1}}}},
   "leave": {"label": "Let them fight it out", "result": "Tannic and Vesna fought over the docks, and the House's take suffered.", "fx": {"gold": -100, "people": {"Tannic": {"respect": -1}, "Vesna": {"respect": -1}}}}},

  {"title": "Doss's offer", "desk": "Outsiders",
   "told": "Doss, who sells information out of the Crooked Coin, offers to cancel the favor the party owes him. His price: the names of Hesper's three best informants. Bellamy: \"Doss remembers every threat. He also remembers every gift.\"",
   "dm": "If signed: Doss becomes friendly; Hesper's -2 is applied now (she will find out). If left: Hesper loses one informant. Own call: pay him in other information, or tell Hesper. Telling Hesper: Hesper loyalty +1, Doss cools. Spark: who else Doss sold to.",
   "sign": {"label": "Sign it: give Doss the names", "result": "The names went to Doss, and the favor is cleared.", "fx": {"people": {"Hesper": {"loyalty": -2}}}},
   "leave": {"label": "Leave it", "result": "Doss sold the question somewhere else. Hesper lost an informant.", "fx": {"people": {"Hesper": {"respect": -1}}}}}
  ]$j$;
  roster jsonb; ids jsonb := '{}'::jsonb; nm text; pid text; c jsonb; side text; fx jsonb; ppl jsonb; k text; added int := 0; skipped int := 0;
begin
  select data->'people' into roster from public.docs where id = 'house';
  if roster is null then raise exception 'The House roster is missing. Nothing was loaded.'; end if;

  -- match each name to its id in the House roster
  foreach nm in array array['Vesna', 'Tannic', 'Orsolo', 'Hesper', 'Mabbis'] loop
    select p->>'id' into pid from jsonb_array_elements(roster) p
      where p->>'id' = lower(nm) or p->>'name' ilike '%' || nm || '%' order by (p->>'id' = lower(nm)) desc limit 1;
    if pid is null then raise exception 'Couldn''t find % in the House roster. Nothing was loaded.', nm; end if;
    ids := ids || jsonb_build_object(nm, pid);
  end loop;

  insert into public.dm_docs(id, data, updated_at) values ('contracts', '{"pool": []}'::jsonb, now()) on conflict (id) do nothing;

  for c in select e from jsonb_array_elements(src) e loop
    if exists (select 1 from public.dm_docs d, jsonb_array_elements(coalesce(d.data->'pool', '[]'::jsonb)) x
               where d.id = 'contracts' and lower(x->>'title') = lower(c->>'title')) then
      skipped := skipped + 1; continue;
    end if;
    foreach side in array array['sign', 'leave'] loop
      fx := coalesce(c->side->'fx', '{}'::jsonb);
      if fx ? 'people' then
        ppl := '{}'::jsonb;
        for k in select jsonb_object_keys(fx->'people') loop
          ppl := ppl || jsonb_build_object(ids->>k, fx->'people'->k);
        end loop;
        c := jsonb_set(c, array[side, 'fx', 'people'], ppl);
      end if;
    end loop;
    update public.dm_docs set data = jsonb_set(data, '{pool}', coalesce(data->'pool', '[]'::jsonb) ||
             jsonb_build_array(c || jsonb_build_object('id', gen_random_uuid()::text, 'ready', true, 'used', false))), updated_at = now()
      where id = 'contracts';
    added := added + 1;
  end loop;

  raise notice 'Added % contracts to the pool (% already there).', added, skipped;
end $fix$;

select 'Fix 11 applied: ' || (select count(*) from public.dm_docs d, jsonb_array_elements(d.data->'pool') x where d.id = 'contracts')
       || ' contracts in the pool, ' || (select count(*) from public.dm_docs d, jsonb_array_elements(d.data->'pool') x
       where d.id = 'contracts' and coalesce((x->>'ready')::boolean, true) and not coalesce((x->>'used')::boolean, false)) || ' ready.' as result;

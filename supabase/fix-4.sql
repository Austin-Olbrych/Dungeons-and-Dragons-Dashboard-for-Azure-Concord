-- fix-4: "Start session" can pay the shop's upkeep from Party loot or from the Vaelmar bank.
-- Paying from the bank takes it off the bank balance; Wick just carries a receipt. Safe to run more than once.

drop function if exists public.dm_shop_session(text, boolean);

create or replace function public.dm_shop_session(pin text, live boolean, source text default 'party') returns text
language plpgsql security definer set search_path = public as $$
declare s jsonb; up int; fld text;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if source not in ('party', 'bank') then return 'Pay from party loot or the bank.'; end if;
  select data into s from docs where id = 'shop' for update;
  if live and coalesce((s->>'inSession')::boolean, false) then return 'Already in session.'; end if;
  if live then
    up := coalesce((s->>'upkeep')::int, 0);
    fld := case when source = 'bank' then 'bank' else 'gold' end;
    update docs set data = jsonb_set(data, array[fld], to_jsonb(coalesce((data->>fld)::int, 0) - up)), updated_at = now() where id = 'stash';
    s := jsonb_set(s, '{upkeepLog}', jsonb_build_array(jsonb_build_object('at', now(), 'when', to_char(now(), 'Mon FMDD'), 'paid', up, 'source', source))
                                     || coalesce(s->'upkeepLog', '[]'::jsonb));
  end if;
  s := s || jsonb_build_object('inSession', live);
  update docs set data = s, updated_at = now() where id = 'shop';
  insert into activity(actor, action, detail) values ('dm', case when live then 'session_start' else 'session_end' end,
    case when live then jsonb_build_object('upkeep', up, 'source', source) else '{}'::jsonb end);
  return case when live then format('Session started. Upkeep paid: %s gp from %s.', up, case when source = 'bank' then 'the Vaelmar bank' else 'Party loot' end) else 'Session ended.' end;
end $$;
grant execute on function public.dm_shop_session(text, boolean, text) to anon, authenticated;

select 'fix-4 done' as result;

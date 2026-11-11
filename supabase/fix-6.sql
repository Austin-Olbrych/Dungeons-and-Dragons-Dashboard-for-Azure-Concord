-- fix-6: test mode and skipping time.
--
--  * Start test (DM) saves a copy of everything: sheets, party loot, the shop, the House, the journal and notes,
--    the DM-only documents and the activity log. Everyone sees a "test in progress" banner.
--  * End test either puts everything back exactly as it was, or keeps the changes and throws the copy away.
--  * Skip ahead (DM, any time) moves every timer forward: Wick's trip, the shelf, lying low.
--
-- Safe to run more than once.

create table if not exists public.snapshots (
  id text primary key,
  taken_at timestamptz not null default now(),
  docs jsonb not null,
  dm_docs jsonb not null,
  notes jsonb not null,
  activity_max bigint not null default 0
);
alter table public.snapshots enable row level security;   -- no policies: only the DM functions below can touch it
revoke all on public.snapshots from anon, authenticated;

create or replace function public.dm_test_start(pin text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if exists (select 1 from snapshots where id = 'test') then return 'A test is already running.'; end if;
  insert into snapshots(id, docs, dm_docs, notes, activity_max) values ('test',
    (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'data', data)), '[]'::jsonb) from docs),
    (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'data', data)), '[]'::jsonb) from dm_docs),
    (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb) from notes n),
    coalesce((select max(id) from activity), 0));
  update docs set data = data || jsonb_build_object('testSince', now()), updated_at = now() where id = 'shop';
  return 'Test started. Everything as of now is saved.';
end $$;

create or replace function public.dm_test_end(pin text, undo boolean) returns text
language plpgsql security definer set search_path = public as $$
declare snap snapshots%rowtype;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  select * into snap from snapshots where id = 'test' for update;
  if not found then
    update docs set data = data - 'testSince', updated_at = now() where id = 'shop';
    return 'No test was running.';
  end if;
  if undo then
    delete from docs where id not in (select x->>'id' from jsonb_array_elements(snap.docs) x);
    insert into docs(id, kind, data, updated_at)
      select x->>'id', x->>'kind', x->'data', now() from jsonb_array_elements(snap.docs) x
      on conflict (id) do update set kind = excluded.kind, data = excluded.data, updated_at = now();
    delete from dm_docs where true;
    insert into dm_docs(id, data, updated_at) select x->>'id', x->'data', now() from jsonb_array_elements(snap.dm_docs) x;
    delete from notes where true;
    insert into notes(id, session, author, body, created_at)
      select (x->>'id')::uuid, (x->>'session')::int, x->>'author', x->>'body', (x->>'created_at')::timestamptz from jsonb_array_elements(snap.notes) x;
    delete from activity where id > snap.activity_max;
  else
    update docs set data = data - 'testSince', updated_at = now() where id = 'shop';
  end if;
  delete from snapshots where id = 'test';
  return case when undo then format('Test undone. Everything is back to %s.', to_char(snap.taken_at, 'Mon FMDD, HH12:MI AM')) else 'Test ended. The changes were kept.' end;
end $$;

-- Move every clock forward by some hours: the trip, the shelf, and lying low.
create or replace function public.dm_skip(pin text, hours numeric) returns text
language plpgsql security definer set search_path = public as $$
declare iv interval; s jsonb; t jsonb; m jsonb; k text; before int; after int; r text;
  ts text[] := array['leftAt','nestAt','arriveAt','shopEnd','returnAt'];
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

select 'fix-6 done' as result;

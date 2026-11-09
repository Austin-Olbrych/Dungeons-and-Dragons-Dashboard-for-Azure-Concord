-- Azure Concord ledger: database setup for Supabase.
-- Run once in the Supabase SQL editor. Safe to run again: it replaces functions and keeps data.
--
-- Security model:
--   * docs        player-visible data. Anyone with the site can READ it. Nobody can write it directly.
--   * dm_docs     DM-only data. No direct access at all; only dm_get() with the right PIN returns it.
--   * notes       journal notes. Anyone can read and add; only the DM can delete (dm_delete_note).
--   * activity    a log of every player change (who, what, when). Read-only to the site.
--   * Player changes go through a few p_* functions that only touch whitelisted fields.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.docs (
  id text primary key,
  kind text not null check (kind in ('char','stash','shop','house','journal')),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.dm_docs (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  session int not null,
  author text not null,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create table if not exists public.activity (
  id bigserial primary key,
  actor text,
  action text not null,
  detail jsonb,
  created_at timestamptz not null default now()
);
create table if not exists public.settings (key text primary key, value text not null);
create table if not exists public.pin_fail (at timestamptz not null default now());

alter table public.docs     enable row level security;
alter table public.dm_docs  enable row level security;
alter table public.notes    enable row level security;
alter table public.activity enable row level security;
alter table public.settings enable row level security;
alter table public.pin_fail enable row level security;

drop policy if exists docs_read on public.docs;
create policy docs_read on public.docs for select to anon, authenticated using (true);
drop policy if exists notes_read on public.notes;
create policy notes_read on public.notes for select to anon, authenticated using (true);
drop policy if exists notes_add on public.notes;
create policy notes_add on public.notes for insert to anon, authenticated
  with check (author = 'dm' or exists (select 1 from public.docs d where d.id = author and d.kind = 'char'));
drop policy if exists activity_read on public.activity;
create policy activity_read on public.activity for select to anon, authenticated using (true);
-- dm_docs, settings and pin_fail have no policies on purpose: the site cannot read or write them directly.

-- ---------- DM PIN ----------
create or replace function public.set_dm_pin(new_pin text) returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  if char_length(new_pin) < 6 then raise exception 'Use at least 6 characters for the PIN.'; end if;
  insert into settings(key, value) values ('dm_pin', crypt(new_pin, gen_salt('bf')))
  on conflict (key) do update set value = excluded.value;
  delete from pin_fail;
  return 'DM PIN saved.';
end $$;

create or replace function public._pin_ok(p text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if (select count(*) from pin_fail where at > now() - interval '15 minutes') >= 10 then
    raise exception 'Too many wrong PINs. Wait 15 minutes and try again.';
  end if;
  select value into h from settings where key = 'dm_pin';
  if h is null then raise exception 'No DM PIN has been set yet.'; end if;
  if crypt(coalesce(p, ''), h) = h then return true; end if;
  insert into pin_fail default values;
  return false;
end $$;

-- A wrong PIN must not raise an error: an error would roll back the failure record and the
-- lockout would never trigger. The DM functions return a result saying the PIN was wrong instead.

-- Returns every DM-only document. The site calls this after the DM enters the PIN.
create or replace function public.dm_get(pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return jsonb_build_object('error', 'Wrong PIN.'); end if;
  return jsonb_build_object('docs', coalesce((select jsonb_object_agg(id, data) from dm_docs), '{}'::jsonb));
end $$;

-- DM writes: replace a whole document, player-visible (secret = false) or DM-only (secret = true).
drop function if exists public.dm_put(text, text, text, jsonb, boolean);
create or replace function public.dm_put(pin text, doc_id text, doc_kind text, doc_data jsonb, secret boolean default false) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if secret then
    insert into dm_docs(id, data, updated_at) values (doc_id, doc_data, now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  else
    insert into docs(id, kind, data, updated_at) values (doc_id, doc_kind, doc_data, now())
    on conflict (id) do update set data = excluded.data, kind = excluded.kind, updated_at = now();
  end if;
  insert into activity(actor, action, detail) values ('dm', 'dm_put', jsonb_build_object('doc', doc_id, 'secret', secret));
  return 'Saved.';
end $$;

drop function if exists public.dm_delete_note(text, uuid);
create or replace function public.dm_delete_note(pin text, note_id uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  delete from notes where id = note_id;
  return 'Deleted.';
end $$;

-- ---------- player actions ----------
-- Holders are character sheets or the party stash.
create or replace function public._holder(doc_id text) returns jsonb
language sql security definer set search_path = public as $$
  select data from docs where id = doc_id and kind in ('char', 'stash');
$$;

-- Move an item (and anything stored inside it) between characters and the party stash.
create or replace function public.p_move_item(from_id text, to_id text, entry_id text, actor text) returns void
language plpgsql security definer set search_path = public as $$
declare src jsonb; moving jsonb; keep jsonb; item_name text;
begin
  if from_id = to_id then return; end if;
  select data into src from docs where id = from_id and kind in ('char','stash') for update;
  if src is null then raise exception 'Unknown holder: %', from_id; end if;
  perform 1 from docs where id = to_id and kind in ('char','stash') for update;
  if not found then raise exception 'Unknown holder: %', to_id; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into moving from jsonb_array_elements(coalesce(src->'entries','[]'::jsonb)) e
    where (e->>'id' = entry_id or coalesce(e->>'in', '') = entry_id) and coalesce(e->>'kind','item') = 'item';
  if jsonb_array_length(moving) = 0 then raise exception 'That item is not there any more.'; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into keep from jsonb_array_elements(src->'entries') e
    where not coalesce((e->>'id' = entry_id or coalesce(e->>'in', '') = entry_id) and coalesce(e->>'kind','item') = 'item', false);
  select e->>'name' into item_name from jsonb_array_elements(moving) e where e->>'id' = entry_id;
  select jsonb_agg(case when e->>'id' = entry_id then (e - 'in' - 'slot') || '{"attuned": false}'::jsonb else e end) into moving
    from jsonb_array_elements(moving) e;
  update docs set data = jsonb_set(data, '{entries}', keep), updated_at = now() where id = from_id;
  update docs set data = jsonb_set(data, '{entries}', coalesce(data->'entries', '[]'::jsonb) || moving), updated_at = now() where id = to_id;
  insert into activity(actor, action, detail) values (actor, 'move', jsonb_build_object('item', item_name, 'from', from_id, 'to', to_id));
end $$;

-- Hand an item to Wick for the shop. It leaves the holder and lands in the shop ledger as "In Wick's pack".
create or replace function public.p_send_to_shop(from_id text, entry_id text, asking int, actor text) returns void
language plpgsql security definer set search_path = public as $$
declare src jsonb; top jsonb; kids jsonb; keep jsonb;
begin
  select data into src from docs where id = from_id and kind in ('char','stash') for update;
  if src is null then raise exception 'Unknown holder: %', from_id; end if;
  perform 1 from docs where id = 'shop' for update;
  select e into top from jsonb_array_elements(coalesce(src->'entries','[]'::jsonb)) e where e->>'id' = entry_id and coalesce(e->>'kind','item') = 'item';
  if top is null then raise exception 'That item is not there any more.'; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into kids from jsonb_array_elements(src->'entries') e where coalesce(e->>'in', '') = entry_id;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into keep from jsonb_array_elements(src->'entries') e where not (e->>'id' = entry_id or coalesce(e->>'in', '') = entry_id);
  update docs set data = jsonb_set(data, '{entries}', keep), updated_at = now() where id = from_id;
  update docs set data = jsonb_set(data, '{cargo}', coalesce(data->'cargo', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'id', gen_random_uuid()::text, 'name', top->>'name', 'qty', coalesce((top->>'qty')::int, 1),
      'fromId', from_id, 'from', src->>'name', 'status', 'pack',
      'ask', case when asking is null or asking < 0 then null else asking end, 'sold', null,
      'sentAt', to_char(now(), 'Mon FMDD'), 'by', actor,
      'entry', (top - 'in') || '{"attuned": false}'::jsonb, 'kids', kids))), updated_at = now()
    where id = 'shop';
  insert into activity(actor, action, detail) values (actor, 'send_to_shop', jsonb_build_object('item', top->>'name', 'from', from_id, 'asking', asking));
end $$;

-- Change a few fields on one item: worn or packed, where it sits, which container it is in, uses left.
create or replace function public.p_update_entry(holder_id text, entry_id text, patch jsonb, actor text) returns void
language plpgsql security definer set search_path = public as $$
declare clean jsonb;
begin
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into clean from jsonb_each(patch) as t(k, v)
    where k in ('active', 'slot', 'in', 'left');
  if clean = '{}'::jsonb then return; end if;
  update docs set data = jsonb_set(data, '{entries}', (
      select coalesce(jsonb_agg(case when e->>'id' = entry_id then e || clean else e end), '[]'::jsonb)
      from jsonb_array_elements(coalesce(data->'entries','[]'::jsonb)) e)), updated_at = now()
    where id = holder_id and kind in ('char','stash');
  insert into activity(actor, action, detail) values (actor, 'update_item', jsonb_build_object('holder', holder_id, 'item', entry_id, 'change', clean));
end $$;

-- Change a few numbers on a sheet or the stash: current HP, gold, ash jars (and the bank, for the stash).
create or replace function public.p_update_sheet(holder_id text, patch jsonb, actor text) returns void
language plpgsql security definer set search_path = public as $$
declare clean jsonb;
begin
  select coalesce(jsonb_object_agg(k, to_jsonb(greatest(0, (v #>> '{}')::numeric)::int)), '{}'::jsonb) into clean
    from jsonb_each(patch) as t(k, v)
    where k in ('hp', 'gold', 'jars', 'bank') and jsonb_typeof(v) = 'number';
  if clean = '{}'::jsonb then return; end if;
  update docs set data = data || clean, updated_at = now() where id = holder_id and kind in ('char','stash');
  insert into activity(actor, action, detail) values (actor, 'update_sheet', jsonb_build_object('holder', holder_id, 'change', clean));
end $$;

-- Who may call what.
revoke all on function public.set_dm_pin(text) from public, anon, authenticated;
revoke all on function public._pin_ok(text) from public, anon, authenticated;
drop function if exists public._need_dm(text);
revoke all on function public._holder(text) from public, anon, authenticated;
grant execute on function public.dm_get(text) to anon, authenticated;
grant execute on function public.dm_put(text, text, text, jsonb, boolean) to anon, authenticated;
grant execute on function public.dm_delete_note(text, uuid) to anon, authenticated;
grant execute on function public.p_move_item(text, text, text, text) to anon, authenticated;
grant execute on function public.p_send_to_shop(text, text, int, text) to anon, authenticated;
grant execute on function public.p_update_entry(text, text, jsonb, text) to anon, authenticated;
grant execute on function public.p_update_sheet(text, jsonb, text) to anon, authenticated;

select 'Setup complete. Next: run seed.sql, then set your PIN with select set_dm_pin(''your-pin'');' as next_step;

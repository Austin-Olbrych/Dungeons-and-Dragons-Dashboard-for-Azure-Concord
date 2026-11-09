-- Azure Concord ledger, fix 1: moving or sending an item no longer removes the holder's other items.
-- Paste all of this into a new SQL Editor query and click Run. Safe to run more than once.

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

-- Hesper's public line gave away part of her secret. Reword it.
update public.docs set data = jsonb_set(data, '{people}', (
  select jsonb_agg(case when p->>'id' = 'hesper' then p || '{"sees": "Watches Cramaris more closely than anyone else, and won’t say why."}'::jsonb else p end)
  from jsonb_array_elements(data->'people') p)), updated_at = now()
where id = 'house';

select 'Fix 1 applied.' as result;

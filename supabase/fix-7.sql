-- fix-7: "End test: undo everything" failed with "DELETE requires a WHERE clause".
-- Supabase blocks deletes without a WHERE as a safety net; this version says "where true" on purpose.
-- Nothing was changed by the failed attempt: your test is still running, and undo will work after this.

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

select 'fix-7 done' as result;

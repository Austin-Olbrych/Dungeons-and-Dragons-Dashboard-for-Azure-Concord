-- fix-12: session handouts for the Journal (maps, letters, posters, sketches).
--
-- Each handout is one picture tied to one session. Players only ever see handouts the DM has revealed;
-- hidden ones can only be read through the dm_* functions below, which check the DM PIN.
-- Pictures are stored as data URLs (the site shrinks them before upload), plus a small thumbnail,
-- so the Journal list loads fast and the full picture is fetched only when someone opens it.
--
-- Run after fix-11. Safe to run more than once.

create table if not exists public.handouts (
  id uuid primary key default gen_random_uuid(),
  session int not null,
  title text not null check (char_length(title) between 1 and 120),
  kind text not null default 'Map',
  caption text not null default '',
  hidden boolean not null default true,
  sort int not null default 0,
  w int, h int,
  thumb text not null,
  img text not null,
  created_at timestamptz not null default now()
);
create index if not exists handouts_session on public.handouts(session, sort);

alter table public.handouts enable row level security;
drop policy if exists handouts_read on public.handouts;
create policy handouts_read on public.handouts for select to anon, authenticated using (hidden = false);
grant select on public.handouts to anon, authenticated;
-- No insert/update/delete policies on purpose: only the DM functions below can change handouts.

-- Every handout's details and thumbnail, hidden ones included (DM only).
create or replace function public.dm_handouts(pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return jsonb_build_object('error', 'Wrong PIN.'); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'session', session, 'title', title, 'kind', kind,
    'caption', caption, 'hidden', hidden, 'sort', sort, 'w', w, 'h', h, 'thumb', thumb) order by session, sort, created_at)
    from handouts), '[]'::jsonb);
end $$;

-- The full picture of any handout, hidden or not (DM only).
create or replace function public.dm_handout_img(pin text, handout_id uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  return (select img from handouts where id = handout_id);
end $$;

create or replace function public.dm_handout_add(pin text, p_session int, p_title text, p_kind text, p_caption text,
  p_hidden boolean, p_w int, p_h int, p_thumb text, p_img text) returns text
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  if p_img is null or p_img not like 'data:image/%' then raise exception 'That file is not a picture.'; end if;
  if char_length(p_img) > 8000000 then raise exception 'That picture is too large, even after shrinking it.'; end if;
  select coalesce(max(sort), 0) + 1 into n from handouts where session = p_session;
  insert into handouts(session, title, kind, caption, hidden, sort, w, h, thumb, img)
    values (p_session, left(coalesce(nullif(trim(p_title), ''), 'Handout'), 120), coalesce(nullif(p_kind, ''), 'Map'),
            coalesce(p_caption, ''), coalesce(p_hidden, true), n, p_w, p_h, p_thumb, p_img);
  -- The activity log is public, so only handouts the players can already see are logged.
  if not coalesce(p_hidden, true) then
    insert into activity(actor, action, detail) values ('dm', 'handout_reveal', jsonb_build_object('session', p_session, 'title', p_title));
  end if;
  return 'Handout added.';
end $$;

-- Change a handout's title, kind, caption or whether players can see it. Pass null to leave a field alone.
create or replace function public.dm_handout_set(pin text, handout_id uuid, p_title text, p_kind text, p_caption text,
  p_hidden boolean) returns text
language plpgsql security definer set search_path = public as $$
declare t text; was boolean;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  select title, hidden into t, was from handouts where id = handout_id for update;
  if t is null then raise exception 'That handout is not there any more.'; end if;
  update handouts set
    title = coalesce(left(nullif(trim(p_title), ''), 120), title),
    kind = coalesce(nullif(p_kind, ''), kind),
    caption = coalesce(p_caption, caption),
    hidden = coalesce(p_hidden, hidden)
  where id = handout_id;
  if p_hidden = false and was then
    insert into activity(actor, action, detail) values ('dm', 'handout_reveal', jsonb_build_object('title', coalesce(left(nullif(trim(p_title), ''), 120), t)));
  end if;
  -- Hiding it again (or removing it, below) also clears its line from the public activity log.
  if p_hidden and not was then
    delete from activity where action = 'handout_reveal' and detail->>'title' = t
      and not exists (select 1 from handouts h where h.title = t and not h.hidden);
  end if;
  return case when p_hidden = false and was then 'Revealed to the players.' when p_hidden and not was then 'Hidden from the players.' else 'Saved.' end;
end $$;

create or replace function public.dm_handout_del(pin text, handout_id uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  delete from handouts where id = handout_id;
  delete from activity where action = 'handout_reveal' and detail->>'title' is not null
    and not exists (select 1 from handouts h where h.title = activity.detail->>'title' and not h.hidden);
  return 'Handout removed.';
end $$;

-- Move a handout one place earlier (-1) or later (+1) within its session.
create or replace function public.dm_handout_move(pin text, handout_id uuid, dir int) returns text
language plpgsql security definer set search_path = public as $$
declare me handouts; other handouts;
begin
  if not _pin_ok(pin) then return 'Wrong PIN.'; end if;
  select * into me from handouts where id = handout_id for update;
  if me.id is null then raise exception 'That handout is not there any more.'; end if;
  if dir < 0 then
    select * into other from handouts where session = me.session and (sort, created_at) < (me.sort, me.created_at) order by sort desc, created_at desc limit 1;
  else
    select * into other from handouts where session = me.session and (sort, created_at) > (me.sort, me.created_at) order by sort, created_at limit 1;
  end if;
  if other.id is null then return 'Saved.'; end if;
  update handouts set sort = other.sort where id = me.id;
  update handouts set sort = me.sort where id = other.id;
  if me.sort = other.sort then update handouts set sort = sort + dir where id = me.id; end if;
  return 'Saved.';
end $$;

revoke all on function public.dm_handouts(text) from public;
revoke all on function public.dm_handout_img(text, uuid) from public;
revoke all on function public.dm_handout_add(text, int, text, text, text, boolean, int, int, text, text) from public;
revoke all on function public.dm_handout_set(text, uuid, text, text, text, boolean) from public;
revoke all on function public.dm_handout_del(text, uuid) from public;
revoke all on function public.dm_handout_move(text, uuid, int) from public;
grant execute on function public.dm_handouts(text) to anon, authenticated;
grant execute on function public.dm_handout_img(text, uuid) to anon, authenticated;
grant execute on function public.dm_handout_add(text, int, text, text, text, boolean, int, int, text, text) to anon, authenticated;
grant execute on function public.dm_handout_set(text, uuid, text, text, text, boolean) to anon, authenticated;
grant execute on function public.dm_handout_del(text, uuid) to anon, authenticated;
grant execute on function public.dm_handout_move(text, uuid, int) to anon, authenticated;

notify pgrst, 'reload schema';

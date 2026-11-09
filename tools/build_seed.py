"""Build supabase/seed.sql from the DM ledger dump.

Splits every record into a player-visible part (table docs) and a DM-only part
(table dm_docs). The output contains DM secrets: never commit seed.sql.

Usage: python3 tools/build_seed.py <dump_dir> supabase/seed.sql
"""
import json, os, sys, glob

def load(p):
    d = json.load(open(p)); return d.get('data', d)

def strip(d, keys):
    return {k: v for k, v in d.items() if k not in keys}

def lit(obj):
    s = json.dumps(obj, ensure_ascii=False)
    assert '$ac$' not in s
    return "$ac$" + s + "$ac$::jsonb"

def main(dump, out):
    docs, dm = [], {}
    cr = {os.path.basename(p)[:-5]: load(p) for p in glob.glob(os.path.join(dump, 'creatures', '*.json'))}
    foes = []
    for cid, c in sorted(cr.items()):
        c = dict(c); c['id'] = cid
        side = c.get('side')
        if side == 'foe':
            foes.append(c); continue
        asks = {e['id']: e['ask'] for e in c.get('entries', []) if e.get('ask')}
        pub = strip(c, ['notes'])
        pub['entries'] = [strip(e, ['ask']) for e in c.get('entries', [])]
        docs.append((cid, 'stash' if side == 'stash' else 'char', pub))
        if asks or c.get('notes'):
            dm[cid] = {'notes': c.get('notes', ''), 'asks': asks}
    dm['foes'] = {'list': foes}

    S = load(os.path.join(dump, 'shop', 'state.json'))
    r = S.get('runner', {})
    shop = strip(S, ['trouble', 'spill', 'rumors', 'upgrades', 'runner'])
    shop['runner'] = strip(r, ['weak', 'knows'])
    shop['upgrades'] = [u for u in S.get('upgrades', []) if u.get('status') in ('active', 'building')]
    shop['runs'] = [load(p) for p in glob.glob(os.path.join(dump, 'runs', '*.json'))]
    shop.setdefault('cargo', [])
    docs.append(('shop', 'shop', shop))
    dm['shop'] = {'runner': {'weak': r.get('weak', ''), 'knows': r.get('knows', '')},
                  'trouble': S.get('trouble', []), 'spill': S.get('spill', []), 'rumors': S.get('rumors', []),
                  'upgrades': S.get('upgrades', [])}

    H = load(os.path.join(dump, 'house', 'state.json'))
    hp = strip(H, ['ties', 'clock', 'policy', 'contracts', 'people'])
    hp['people'] = [strip(p, ['secret', 'up', 'down', 'notes']) for p in H.get('people', [])]
    hp['contracts'] = [strip(c, ['dm']) for c in H.get('contracts', [])]
    pol = H.get('policy') or {}
    hp['policy'] = {k: pol[k] for k in ('name', 'said') if k in pol}
    hp['delivered'] = []
    docs.append(('house', 'house', hp))
    dm['house'] = {'people': {p['id']: {k: p.get(k, '') for k in ('secret', 'up', 'down', 'notes')} for p in H.get('people', [])},
                   'contracts': {c['name']: c.get('dm', '') for c in H.get('contracts', [])},
                   'ties': H.get('ties', []), 'clock': H.get('clock'),
                   'policy': {k: pol[k] for k in ('story', 'quiet') if k in pol}}

    J = load(os.path.join(dump, 'journal', 'state.json'))
    docs.append(('journal', 'journal', {'sessions': [strip(s, ['dm']) for s in J.get('sessions', [])]}))
    dm['journal'] = {'dm': {str(i): s.get('dm', '') for i, s in enumerate(J.get('sessions', [])) if s.get('dm')}}

    notes = [load(p) for p in glob.glob(os.path.join(dump, 'jnotes', '*.json'))]

    with open(out, 'w') as f:
        f.write('-- Azure Concord ledger: starting data. Contains DM secrets. Do not commit or share.\n')
        f.write('-- Run after setup.sql. Running it again overwrites these records with this snapshot.\n\n')
        for i, k, d in docs:
            f.write(f"insert into public.docs(id, kind, data) values ('{i}', '{k}', {lit(d)})\n  on conflict (id) do update set kind = excluded.kind, data = excluded.data, updated_at = now();\n\n")
        for i, d in dm.items():
            f.write(f"insert into public.dm_docs(id, data) values ('{i}', {lit(d)})\n  on conflict (id) do update set data = excluded.data, updated_at = now();\n\n")
        for n in notes:
            f.write(f"insert into public.notes(session, author, body) values ({int(n.get('session', 0))}, '{n.get('by','dm')}', $ac${n.get('text','')}$ac$);\n")
        f.write("\nselect 'Seed loaded: ' || (select count(*) from public.docs) || ' player records, ' || (select count(*) from public.dm_docs) || ' DM records.' as result;\n")
    print('wrote', out, len(docs), 'docs,', len(dm), 'dm docs')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

"""Turn tools/ddb_sheets.json (pulled from D&D Beyond) into supabase/fix-2.sql.
Each character doc gets a `dnd` key; nothing else on the sheet changes."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
src = json.loads((root / 'tools/ddb_sheets.json').read_text())
SK = ["acrobatics","animal-handling","arcana","athletics","deception","history","insight","intimidation","investigation","medicine","nature","perception","performance","persuasion","religion","sleight-of-hand","stealth","survival"]
T = {'a':'action','b':'bonus','r':'reaction','m':'move','o':'other'}
R = {0:'',1:'SR',2:'LR'}
out = ["-- fix-2: adds the D&D Beyond details (skills, actions, spells, weapons, speeds) to each character.",
       "-- Safe to run more than once. It only sets the `dnd` field; HP, gold, gear and everything players changed stay as they are.",""]
for cid, c in src.items():
    d = {"pb": 4,
         "skills": {k: int(c['sk'][i]) for i, k in enumerate(SK)},
         "adv": c['adv'], "half": bool(c['half']),
         "profs": c['pr'], "langs": c['la'], "senses": c['se'], "speed": c['sp'],
         "acts": [{"n": n, "t": T[t], "u": u, "r": R.get(r, ''), "d": s} for n, t, u, r, s in c['a']],
         "spells": [{"n": n, "l": l, "t": T[t], "c": bool(cc), "r": rg} for n, l, t, cc, rg in c['m']],
         "weapons": [{"n": n, "eq": bool(eq), "dmg": dmg, "dt": dt, "props": p, "range": rg} for n, eq, dmg, dt, p, rg in c['w']]}
    js = json.dumps({"dnd": d}, ensure_ascii=False)
    assert '$dnd$' not in js
    out.append(f"update public.docs set data = data || $dnd${js}$dnd$::jsonb, updated_at = now() where id = '{cid}' and kind = 'char';")
out += ["", "select id, jsonb_array_length(data->'dnd'->'acts') as actions, jsonb_array_length(data->'dnd'->'spells') as spells from public.docs where kind = 'char' order by id;"]
(root / 'supabase/fix-2.sql').write_text("\n".join(out) + "\n")
print('wrote supabase/fix-2.sql')

# Azure Concord — party ledger

The Three Roads campaign's shared ledger. Each player picks their character and sees their full sheet, encounter reminders, the party, party loot, the shop ledger, the Odranard Guild and the session journal. Players can update their HP and gold, wear or pack items, hand items to and from the party loot, send items to the shop with Wick, and add journal notes. The DM unlocks DM-only details with a PIN.

- `index.html` — the whole site (no build step). It reads and writes the Supabase database.
- `supabase/setup.sql` — tables, row-level security, the DM PIN check and the player actions. Safe to run again.
- `supabase/fix-*.sql` — small patches to run once in the Supabase SQL Editor.
- `tools/build_seed.py` — builds the starting data from the DM ledger. Its output (`seed.sql`, `install.sql`) contains DM secrets and is git-ignored.

The publishable key in `index.html` is meant to be public; the database's security rules decide what it can do. Never commit a secret or service_role key.

## Character sheet details from D&D Beyond

`tools/ddb_sheets.json` holds skills, actions, spells, weapons and speeds pulled from each character's D&D Beyond page. `python3 tools/build_fix2.py` turns it into `supabase/fix-2.sql`, which sets a `dnd` field on each character and leaves everything else alone. Run it in the Supabase SQL editor whenever the file is refreshed.

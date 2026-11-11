# Azure Concord — party ledger

The Three Roads campaign's shared ledger. Each player picks their character and sees their full sheet, encounter reminders, the party, party loot, the shop ledger, the Odranard Guild and the session journal. Players can update their HP and gold, wear or pack items, hand items to and from the party loot, send items to the shop with Wick, and add journal notes. The DM unlocks DM-only details with a PIN.

- `index.html` — the whole site (no build step). It reads and writes the Supabase database.
- `supabase/setup.sql` — tables, row-level security, the DM PIN check and the player actions. Safe to run again.
- `supabase/fix-*.sql` — small patches to run once in the Supabase SQL Editor.
- `tools/build_seed.py` — builds the starting data from the DM ledger. Its output (`seed.sql`, `install.sql`) contains DM secrets and is git-ignored.

The publishable key in `index.html` is meant to be public; the database's security rules decide what it can do. Never commit a secret or service_role key.

## What lives where

D&D Beyond is the character sheet: stats, skills, HP, attacks, spells, and anything that changes a roll. This site tracks inventory, item lore, gold and ash jars, the shop, the House and the journal. `supabase/fix-2.sql` (already run) added a `dnd` field with skills and actions from D&D Beyond; the site no longer shows it.

## Wick's runs

`supabase/fix-3.sql` makes the shop runs happen in real time. Players load Wick's pack, pick a road and send him. The road roll, trouble, what he lets slip and the rumor are rolled when he leaves and kept DM-only until he's due back; then the shop sells what has an asking price and his gold (less pay) lands in Party loot. Travel days are set on the Shop tab (DM tools). "Start session" pays the shop's upkeep and makes runs resolve at once until "End session".

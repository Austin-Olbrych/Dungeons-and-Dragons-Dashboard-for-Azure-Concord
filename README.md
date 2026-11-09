# Azure Concord — party ledger

The Three Roads campaign's shared ledger. Each player picks their character and sees their full sheet, encounter reminders, the party, party loot, the shop ledger, the Odranard Guild and the session journal. Players can update their HP and gold, wear or pack items, hand items to and from the party loot, send items to the shop with Wick, and add journal notes. The DM unlocks DM-only details with a PIN.

- `index.html` — the whole site (no build step). It reads and writes the Supabase database.
- `supabase/setup.sql` — tables, row-level security, the DM PIN check and the player actions. Safe to run again.
- `supabase/fix-*.sql` — small patches to run once in the Supabase SQL Editor.
- `tools/build_seed.py` — builds the starting data from the DM ledger. Its output (`seed.sql`, `install.sql`) contains DM secrets and is git-ignored.

The publishable key in `index.html` is meant to be public; the database's security rules decide what it can do. Never commit a secret or service_role key.

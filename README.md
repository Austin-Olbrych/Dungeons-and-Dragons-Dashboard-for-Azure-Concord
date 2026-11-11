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

## Selling (fix-5)

`supabase/fix-5.sql` adds item values, hot and quest tags, Steven's shelf (daily buyer rolls, greed-based DCs, offers vs. the player's lowest price, markdowns and his levels), Orsolo's fence (sells at value or +15%, keeps 15%, may skim by loyalty; paid at Settle session), Wick's Nest stop, lying low, and paying a House captain to cool the heat. All rolls stay in the DM-only `market` document until Wick reports back.

## Weight, coin and contracts (fix-8)

- Every item has a weight in pounds (D&D Beyond's where it has one; homebrew items have estimates the DM can change in the item editor).
- Wick carries up to 100 lb. Players can't load his pack past that.
- Coming home, Steven's money is either carried as coin (50 coins to the pound, up to 5,000 gp, and it can be robbed) or banked in Vaelmar, with Wick bringing back a receipt.
- The House books: each captain keeps the base cut for how involved the Seven are, plus 3% for each point of loyalty under 3 (less above). Respect moves what a division brings in by 5% a point. Each point of Mabbis's loyalty over 3 takes a point off everyone's cut. Bellamy stays out of the math.
- Contracts come from a DM-only pool. Wick brings one or two each time he comes home. Players sign, leave it to the captains, or make their own call (the DM resolves those). Anything unanswered at Settle session is left to the captains, and how many the Seven decided sets how involved the House thinks they are.

## News from the House (fix-9)

- Each time Wick comes home he brings word on the contracts: a small update each run, then the outcome the DM picked from a ready-made list (or wrote).
- The DM sees each outcome's impact on the captains and anything of note before picking it, and can tell the table right away instead of waiting for Wick.
- Bellamy is either with the party (Wick brings word and she chimes in) or at the House (the news is her report). The DM can have Wick bring word that the House wants her.
- Item weights show next to every item, and the sell form shows how full Wick's pack will be.

## Travel times (fix-10)

- The Shop tab has a map of the roads: Vaelmar, Odranard (the Nest and the House), the Ashen Covenant camp and Nebulas, with days by the main road and by the back roads.
- Wick leaves from wherever the party is, goes to the Nest and/or Steven's shop by the shortest roads in the quicker order, and comes back to the party.
- Any run that spends time on a road rolls for trouble, the Nest included. A quiet run on the back roads cools the heat by 1.
- The DM sets where the party is on the Shop tab, or with "Party ended the session at" on the latest journal session. Road days and stop lengths are editable on the Shop tab.

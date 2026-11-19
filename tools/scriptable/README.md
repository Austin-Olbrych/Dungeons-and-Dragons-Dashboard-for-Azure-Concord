# Azure Concord widgets (Scriptable)

Home-screen widgets for the party: Wick's run, the House's books, and Steven's shop.

## Set up on an iPhone

1. Install **Scriptable** from the App Store.
2. In Scriptable, tap **+**, name the script **Azure Concord**, and paste in everything from `azure-concord-loader.js`.
   Run it once from the app: it downloads the widget and lets you preview any of them.
3. On the home screen, long-press, tap **+**, add a **Scriptable** widget (small, medium or large), then long-press it,
   **Edit Widget**, and set:
   - **Script:** Azure Concord
   - **When Interacting:** Open URL (tapping it opens the site)
   - **Parameter:** `wick`, `house` or `steven`
4. Optional, for the retro look: install the **VT323** and **Silkscreen** fonts from Google Fonts with a font
   installer app (for example Fontcase). Without them the widgets use the iPhone's own font.

The widgets refresh about every 15 to 30 minutes (iOS decides exactly when). They only read what players can see on
the site, so Wick's road roll stays secret until he's home.

## What each one shows

| Parameter | Small | Medium | Large |
|---|---|---|---|
| `wick` | Where he is and when he's home, or the back-road odds when he's with the party | Road strip with his stops, or main vs back road odds | Road strip, each stop, pack, money, time home |
| `house` | This session's take | Take, in vs out, where it goes | The full ledger |
| `steven` | His level and marks | Level and the top of his shelf | His whole shelf, Orsolo's items, last sale |

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
| `wick` | Traveling: when he's back with the party and what he could bring home. With the party: where he is and his heat | Road strip, back-with-party time, potential gold; or main vs back road odds | Road strip, each stop, pack, money, time home |
| `house` | This session's take and open contracts | Coming in vs going out, with a one-line breakdown each | The full ledger |
| `steven` | Items for sale, what they could bring in, level in the corner | Count and potential, top 3 shelf items, level | His whole shelf, Orsolo's items, last sale, marks |

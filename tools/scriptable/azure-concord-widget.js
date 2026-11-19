// Azure Concord · iPhone widgets for Scriptable
//
// One script, three widgets. Long-press a widget, Edit Widget, pick this script, and set Parameter to:
//   wick    Wick's run: where he is, his stops, heat, and whether it's worth sending him (small, medium, large)
//   house   The House's books: this session's take, what's coming in and going out (small, medium, large)
//   steven  Steven's shop: his level, and what's on his shelf (small, medium, large)
//
// It only reads what players can already see on the site. It never uses the DM PIN, so Wick's secret road
// roll stays hidden until he's home.
//
// Fonts: the widgets use VT323 and Silkscreen. Install both on the phone (a font installer app such as Fontcase,
// with the files from Google Fonts) to get the retro look; without them iOS falls back to its own font.

const SB_URL = 'https://yvdmorqaieqlduqplckm.supabase.co';
const SB_KEY = 'sb_publishable_qW8mC2-abmbxWLUMsIwXyQ_Ar9uchsy';
const SITE = 'https://austin-olbrych.github.io/dungeons-and-dragons-dashboard-for-azure-concord/';

let MODE = String(args.widgetParameter || 'wick').trim().toLowerCase();
let SIZE = config.widgetFamily || 'medium';
// run from the Scriptable app: pick one to preview
if (!config.runsInWidget) {
  const a = new Alert(); a.title = 'Preview a widget';
  const opts = [['wick', 'small'], ['wick', 'medium'], ['wick', 'large'], ['house', 'small'], ['house', 'medium'], ['house', 'large'], ['steven', 'small'], ['steven', 'medium'], ['steven', 'large']];
  opts.forEach(([m, z]) => a.addAction(`${m[0].toUpperCase() + m.slice(1)} · ${z}`)); a.addCancelAction('Cancel');
  const i = await a.presentSheet(); if (i < 0) Script.complete(); else [MODE, SIZE] = opts[i];
}
const DAY = 86400000;

// ---------------------------------------------------------------- look
const C = {
  night: '#18202b', panel: '#222c39', ink: '#f3e9d2', mute: '#9fb0bf', soft: '#cfe0ef', line: '#3a4a5c',
  gold: '#e8b04a', warm: '#ffc56b', hot: '#ff9277', red: '#e4572e', amber: '#f2a541', pipOff: '#2c3a4a',
  hBg: '#0f1411', hPanel: '#1d241f', hInk: '#ece6d3', hMute: '#b4b8a4', hGold: '#d4aa4f', good: '#7cc49a', bad: '#e58a76',
  goodBg: '#173022', badBg: '#3a201b', cut: '#d9a04a', crew: '#e58a76', run: '#a99ad6', ctr: '#8fb7d6',
  sBg: '#2a1c0e', sPanel: '#3a2814', sInk: '#f6ead2', sMute: '#cdb38b', missBg: '#1f1618', missInk: '#e6cfcb'
};
const col = h => new Color(h);
const num = s => new Font('VT323-Regular', s);       // numbers and body text
const head = s => new Font('Silkscreen-Regular', s); // headings

// ---------------------------------------------------------------- data
async function load() {
  const r = new Request(`${SB_URL}/rest/v1/docs?select=id,data&id=in.(shop,house,stash)`);
  r.headers = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };
  const rows = await r.loadJSON();
  const by = {};
  for (const x of rows || []) by[x.id] = x.data || {};
  return by;
}

const fmt = n => Math.round(+n || 0).toLocaleString('en-US');
const sgn = n => (n < 0 ? '−' : '+') + fmt(Math.abs(n));
const dayTxt = n => { const v = Math.round(n * 10) / 10; return v + ' day' + (v === 1 ? '' : 's'); };
function when(iso) {
  if (!iso) return '';
  const d = new Date(iso), diff = Math.abs(d - Date.now()) / DAY;
  const df = new DateFormatter();
  df.dateFormat = diff < 6 ? 'EEE h a' : 'MMM d';
  return df.string(d);
}
function until(iso) {
  const ms = new Date(iso) - Date.now();
  if (ms <= 0) return 'any time now';
  const h = Math.round(ms / 3600000);
  return h < 36 ? `in ${h}h` : `in ${Math.floor(h / 24)}d ${h % 24}h`;
}

// the map and the run math, the same as the site
const DEF_MAP = {
  places: { vaelmar: { name: 'Vaelmar' }, odranard: { name: 'Odranard' }, camp: { name: 'Ashen Covenant Camp' }, nebulas: { name: 'Nebulas' } },
  roads: [{ a: 'vaelmar', b: 'odranard', main: 2, back: 3 }, { a: 'vaelmar', b: 'camp', main: 2, back: 3 }, { a: 'odranard', b: 'camp', main: 1, back: 2 },
          { a: 'camp', b: 'nebulas', main: 3, back: 4 }, { a: 'vaelmar', b: 'nebulas', main: 4, back: 5 }, { a: 'odranard', b: 'nebulas', main: 4, back: 5 }],
  stay: { shop: 1, nest: 0.5 }
};
const mapOf = S => S.map || DEF_MAP;
const hereOf = S => S.partyAt || 'camp';
const placeName = (S, k) => ((mapOf(S).places || {})[k] || {}).name || k;
const runThr = (S, route) => Math.max(1, Math.min(19, (+(S.base ?? 2)) + (+S.heat || 0) - (route === 'back' ? 2 : 0)));
function shortest(mp, a, b, mode) {
  if (a === b) return 0;
  const dist = { [a]: 0 }, left = new Set(Object.keys(mp.places || {})); left.add(a);
  while (left.size) {
    let u = null; for (const k of left) if (dist[k] != null && (u == null || dist[k] < dist[u])) u = k;
    if (u == null) break; left.delete(u); if (u === b) break;
    for (const r of mp.roads || []) { const v = r.a === u ? r.b : r.b === u ? r.a : null; if (v == null) continue;
      const nd = dist[u] + (+(r[mode] ?? r.main) || 0); if (dist[v] == null || nd < dist[v]) dist[v] = nd; }
  }
  return dist[b] ?? 0;
}
function planRun(S, mode, toNest, toShop) {
  const mp = mapOf(S), h = hereOf(S), st = { shop: 1, nest: 0.5, ...(mp.stay || {}) }, R = (a, b) => shortest(mp, a, b, mode);
  let order = toNest && toShop ? (R(h, 'odranard') + R('odranard', 'vaelmar') + R('vaelmar', h) <= R(h, 'vaelmar') + R('vaelmar', 'odranard') + R('odranard', h) ? ['odranard', 'vaelmar'] : ['vaelmar', 'odranard']) : toNest ? ['odranard'] : ['vaelmar'];
  let cur = h, road = 0, days = 0;
  for (const o of order) { const d = R(cur, o); road += d; days += d + (o === 'vaelmar' ? +st.shop : +st.nest); cur = o; }
  const back = R(cur, h); road += back; days += back;
  return { road, days, order };
}
function nextHeatDrop(S) {
  const heat = +S.heat || 0; if (!heat || S.trip) return null;
  const step = heat >= 7 ? 4 : 7;
  const base = Math.max(+new Date(S.quietSince || Date.now()), +new Date(S.heatCooledAt || Date.now()));
  return new Date(base + step * DAY);
}
function tripStops(S) {
  const T = S.trip; const st = [];
  if (T.nestAt) st.push({ k: 'nest', l: 'Nest', at: T.nestAt, end: T.nestEnd || T.nestAt });
  if (T.arriveAt) st.push({ k: 'shop', l: 'Shop', at: T.arriveAt, end: T.shopEnd || T.arriveAt });
  st.sort((a, b) => new Date(a.at) - new Date(b.at));
  const SHORT = { camp: 'Camp', vaelmar: 'Vaelmar', odranard: 'Odranard', nebulas: 'Nebulas' };
  const from = T.from ? (SHORT[T.from] || placeName(S, T.from).split(' ')[0]) : 'Party';
  return [{ k: 'party', l: from, at: T.leftAt }, ...st, { k: 'back', l: 'Home', at: T.returnAt }];
}
function tripNow(S) {
  const T = S.trip, now = Date.now(), l = +new Date(T.leftAt), r = +new Date(T.returnAt);
  const f = Math.max(0, Math.min(1, (now - l) / Math.max(1, r - l)));
  const stops = tripStops(S).slice(1, -1);
  const at = stops.find(x => now >= +new Date(x.at) && now < +new Date(x.end));
  const nx = stops.find(x => now < +new Date(x.at));
  const nm = x => x.k === 'nest' ? 'the Nest' : 'Steven’s shop';
  if (T.phase === 'missing') return { f, phase: 'missing', line: 'Wick is missing' };
  if (at) return { f, phase: at.k, line: at.k === 'shop' ? 'At Steven’s' : 'At the Nest', sub: `moves on ${when(at.end)}` };
  if (nx) return { f, phase: 'out', line: `To ${nm(nx)}`, sub: `arrives ${when(nx.at)}` };
  if (now < r) return { f, phase: 'back', line: 'Heading home', sub: `back ${when(T.returnAt)}` };
  return { f: 1, phase: 'late', line: 'Overdue', sub: `due ${when(T.returnAt)}` };
}

// the House's books, the same as the site
function houseBooks(H) {
  const fin = H.fin || {}, ps = H.people || [], inv = fin.involve || 'hands', base = +((fin.skim || {})[inv]) || 0;
  const mab = ps.find(p => p.tier === 'ledger'), trim = mab ? Math.max(0, (+mab.loyalty || 0) - 3) : 0;
  const caps = ps.filter(p => p.tier === 'captain').map(p => {
    const L = +p.loyalty || 0, R = +p.respect || 0, pct = Math.max(0, Math.min(90, base + (3 - L) * 3 - trim));
    const earn = Math.round((+p.take || 0) * (1 + (R - 3) * 0.05));
    return { p, earn, keep: Math.round(earn * pct / 100), cost: +p.cost || 0 };
  });
  const over = (fin.overhead || []).filter(o => !o.when || o.when === inv), extra = fin.extra || [];
  const divs = caps.map(c => ({ l: (c.p.div || '').split('·')[0].trim() || c.p.name, v: c.earn }));
  const ctrIn = extra.filter(o => +o.gp > 0).map(o => ({ l: 'Contract: ' + o.name, v: +o.gp }));
  const ctrOut = extra.filter(o => +o.gp < 0).map(o => ({ l: 'Contract: ' + o.name, v: -o.gp }));
  const groups = [
    { l: 'Captains’ cuts', s: 'Cuts', v: caps.reduce((t, c) => t + c.keep, 0), c: C.cut },
    { l: 'Paying the crews', s: 'Crews', v: caps.reduce((t, c) => t + c.cost, 0), c: C.crew },
    { l: 'Running the House', s: 'House', v: over.reduce((t, o) => t + (+o.gp || 0), 0), c: C.run },
    { l: 'Contracts', s: 'Contracts', v: ctrOut.reduce((t, o) => t + o.v, 0), c: C.ctr }
  ].filter(g => g.v > 0);
  const tin = [...divs, ...ctrIn].reduce((t, x) => t + x.v, 0), tout = groups.reduce((t, g) => t + g.v, 0);
  const INV = { hands: 'hands off', liaison: 'through Bellamy', check: 'checking in', run: 'running it' };
  return { ins: [...divs, ...ctrIn], ctrOut, groups, tin, tout, net: tin - tout, inv: INV[inv] || inv };
}

// Steven
const STEVEN_LV = [{ m: 0, t: 'The cousin behind the counter', b: 2 }, { m: 6, t: 'Knows the regulars', b: 3 }, { m: 18, t: 'Learning to haggle', b: 3 },
                   { m: 36, t: 'A trader', b: 4 }, { m: 60, t: 'Merchant of the plaza', b: 5 }];
function steven(S) {
  const mk = (+((S.steven || {}).marks) || 0) + (+S.stevenAdj || 0);
  let lv = 0; STEVEN_LV.forEach((L, i) => { if (mk >= L.m) lv = i; });
  const L = STEVEN_LV[lv], N = STEVEN_LV[lv + 1], hp = Math.floor((+S.heat || 0) / 3);
  return { mk, lv, L, N, bonus: L.b - hp, hp, pct: N ? (mk - L.m) / (N.m - L.m) : 1 };
}

// ---------------------------------------------------------------- pixel art
const PAL = { K: '#2b1d14', H: '#6b3b1f', S: '#f1c08c', E: '#1a1a1a', T: '#3f7a4a', t: '#2d5a36', B: '#5a3a1a', P: '#4a4e6b', F: '#3a2416', A: '#d9b878', a: '#b08f52',
              O: '#f2a541', R: '#e4572e', Y: '#ffe08a', L: '#6b4320', W: '#efe6d2', w: '#cfc3a6', M: '#7a3b2e', h: '#b88a2a', G: '#d4aa4f', g: '#a07a2a', C: '#f5d98a' };
const SPR = {
  run: ['......KKKK......', '.....KHHHHK.....', '....KHHHHHHK....', '....KHSSSESK....', '....KSSSSSSK....', '..KAAKSSSSK.....', '.KAAaAKTTTTK....', '.KAAaAKTTTtTK...',
        '.KAaaAKTTTTSK...', '..KAAKBBBBBK....', '...KK.KPPPPK....', '.....KPPK.KPK...', '....KPPK...KPK..', '...KFFK.....KFK.', '...KFFK....KFFK.', '................'],
  run2: ['......KKKK......', '.....KHHHHK.....', '....KHHHHHHK....', '....KHSSSESK....', '....KSSSSSSK....', '..KAAKSSSSK.....', '.KAAaAKTTTTK....', '.KAAaAKTTTtTK...',
         '.KAaaAKTTTTSK...', '..KAAKBBBBBK....', '...KK.KPPPPK....', '......KPPPK.....', '......KPKPK.....', '.....KFFKFK.....', '.....KFFKFFK....', '................'],
  sit: ['......KKKK......', '.....KHHHHK.....', '....KHHHHHHK....', '....KHSSSESK....', '....KSSSSSSK....', '.....KSSSSK.....', '....KTTTTTTK....', '...KSTTTTTTSK...',
        '...KSTTtTTTSK...', '....KBBBBBBK....', '..KPPPPPPPPPPK..', '..KPPPPPPPPPPK..', '...KKKKFFKKKK...', '.AAa.....FF.....', 'AAAAa...........', 'AAAAa...........'],
  fire: ['...R....', '..ROR...', '..OYOR..', '.ROYYOR.', '.ROYYOR.', 'LLLLLLLL', '.L.LL.L.'],
  sack: ['....KK.....', '...KaaK....', '..KAAAAK...', '.KAAAAAaK..', 'KAAAAAAAaK.', 'KAAAAAAAaK.', 'KAAAAAAaaK.', '.KAAAAaaK..', '..KKKKKK...'],
  steven: ['.....KKKKK......', '....KCCCCCK.....', '...KChCCCCCK....', '...KCSSSSSCK....', '...KSESSESK.....', '...KSSSSSSK.....', '....KSMMSK......', '...KMKSSKMK.....',
           '..KMMWWWWMMK....', '..KMSWWWWSMK....', '..KMSWwwWSMK....', '...KKWWWWKK.....', '....KWWWWK......', '....KPPKPPK.....', '....KFFKFFK.....', '................'],
  coins: ['..KKKK..', '.KCGGGK.', '.KgGGgK.', '.KKKKKK.', 'KCGGGGK.', 'KgGGGgKK', 'KKKKKKCK', '.KgGGGgK']
};
function sprite(rows, px) {
  const w = rows[0].length, h = rows.length, d = new DrawContext();
  d.size = new Size(w * px, h * px); d.opaque = false; d.respectScreenScale = true;
  rows.forEach((r, y) => { for (let x = 0; x < r.length; x++) { const c = PAL[r[x]]; if (c) { d.setFillColor(col(c)); d.fillRect(new Rect(x * px, y * px, px, px)); } } });
  return d.getImage();
}
function pips(n, w, h, gap) {
  const d = new DrawContext(); d.size = new Size(10 * w + 9 * gap, h); d.opaque = false; d.respectScreenScale = true;
  for (let i = 0; i < 10; i++) { d.setFillColor(col(i < n ? (i < 2 ? C.amber : C.red) : C.pipOff)); d.fillRect(new Rect(i * (w + gap), 0, w, h)); }
  return d.getImage();
}
function bar(width, h, parts, bg) {
  const d = new DrawContext(); d.size = new Size(width, h); d.opaque = false; d.respectScreenScale = true;
  d.setFillColor(col(bg)); d.fillRect(new Rect(0, 0, width, h));
  let x = 0; for (const [frac, c] of parts) { const w = Math.max(0, frac * width); d.setFillColor(col(c)); d.fillRect(new Rect(x, 0, w, h)); x += w; }
  return d.getImage();
}
// the road strip: dashed road, the part he's covered in gold, a square per stop, Wick at his spot
function roadStrip(S, width, height, labels) {
  const T = S.trip, stops = tripStops(S), l = +new Date(T.leftAt), r = +new Date(T.returnAt), tot = Math.max(1, r - l);
  const now = tripNow(S), pad = 8, roadY = height - (labels ? 26 : 12), span = width - pad * 2;
  const d = new DrawContext(); d.size = new Size(width, height); d.opaque = false; d.respectScreenScale = true;
  d.setFillColor(col(C.line)); for (let x = pad; x < width - pad; x += 10) d.fillRect(new Rect(x, roadY, 6, 4));
  d.setFillColor(col(C.gold)); d.fillRect(new Rect(pad, roadY, span * now.f, 4));
  stops.forEach((s, i) => {
    const pos = i === 0 ? 0 : i === stops.length - 1 ? 1 : (+new Date(s.at) - l) / tot, x = pad + span * pos, done = Date.now() >= +new Date(s.at);
    d.setFillColor(col(C.ink)); d.fillRect(new Rect(x - 6, roadY - 4, 12, 12));
    d.setFillColor(col(done ? C.gold : C.night)); d.fillRect(new Rect(x - 4, roadY - 2, 8, 8));
    if (labels) {
      d.setFont(num(13)); d.setTextColor(col(done ? C.ink : C.mute));
      const tx = i === 0 ? x - 6 : i === stops.length - 1 ? x - 40 : x - 20;
      d.setTextAlignedCenter(); if (i === 0) d.setTextAlignedLeft(); if (i === stops.length - 1) d.setTextAlignedRight();
      d.drawTextInRect(`${s.l} ${when(s.at).split(' ')[0]}`, new Rect(tx, roadY + 10, 46, 16));
    }
  });
  const pose = Math.floor(Date.now() / (15 * 60000)) % 2 ? SPR.run2 : SPR.run;   // switches pose each refresh
  const px = 3, sw = 16 * px, sx = Math.max(0, Math.min(width - sw, pad + span * now.f - sw / 2));
  d.drawImageAtPoint(sprite(pose, px), new Point(sx, roadY - sw - 2));
  return d.getImage();
}

// ---------------------------------------------------------------- building blocks
function txt(stack, s, font, color, opts = {}) {
  const t = stack.addText(String(s)); t.font = font; t.textColor = col(color);
  if (opts.lines) t.lineLimit = opts.lines; if (opts.min) t.minimumScaleFactor = opts.min; if (opts.right) t.rightAlignText();
  return t;
}
function hstack(parent, gap = 6) { const s = parent.addStack(); s.layoutHorizontally(); s.spacing = gap; s.centerAlignContent(); return s; }
function vstack(parent, gap = 3) { const s = parent.addStack(); s.layoutVertically(); s.spacing = gap; return s; }
function box(parent, bg, pad = 6) { const s = parent.addStack(); s.layoutVertically(); s.spacing = 2; s.backgroundColor = col(bg); s.cornerRadius = 6; s.setPadding(pad, pad + 2, pad, pad + 2); return s; }
function widgetBase(bg) { const w = new ListWidget(); w.backgroundColor = col(bg); w.setPadding(12, 14, 12, 14); w.url = SITE; w.refreshAfterDate = new Date(Date.now() + 15 * 60000); return w; }

// ---------------------------------------------------------------- Wick
function wickWidget(S) {
  const heat = +S.heat || 0, T = S.trip;
  if (T && T.phase === 'missing') return wickMissing(S);
  const w = widgetBase(C.night);
  const top = hstack(w, 6);
  txt(top, 'WICK', head(SIZE === 'small' ? 13 : 15), C.gold);
  if (SIZE !== 'small') { const chip = top.addStack(); chip.backgroundColor = col('#2c3a4a'); chip.cornerRadius = 3; chip.setPadding(1, 6, 1, 6);
    txt(chip, T ? (T.dc ? `${T.route === 'back' ? 'back roads' : 'main road'} · DC ${T.dc}` : 'no road roll') : 'with the party', num(14), C.soft); }
  top.addSpacer();
  if (SIZE !== 'small') txt(top, 'HEAT', head(9), C.mute);
  top.addImage(pips(heat, SIZE === 'small' ? 4 : 6, SIZE === 'small' ? 9 : 10, 2));
  if (SIZE !== 'small') txt(top, String(heat), num(16), C.amber);
  w.addSpacer(SIZE === 'large' ? 8 : 4);
  return T ? wickOnRoad(w, S) : wickHome(w, S);
}
function wickOnRoad(w, S) {
  const T = S.trip, now = tripNow(S);
  if (SIZE === 'small') {
    const row = hstack(w, 6); row.addImage(sprite(now.phase === 'shop' ? SPR.sit : SPR.run, 3)).imageSize = new Size(48, 48);
    w.addSpacer(4);
    txt(w, now.line, num(20), C.ink, { lines: 1, min: 0.7 });
    if (now.sub) txt(w, now.sub, num(14), C.soft, { lines: 1, min: 0.8 });
    txt(w, `home ${when(T.returnAt)}`, num(14), C.mute, { lines: 1 });
    return w;
  }
  const width = 310, img = w.addImage(roadStrip(S, width, SIZE === 'large' ? 84 : 80, true)); img.imageSize = new Size(width, SIZE === 'large' ? 84 : 80);
  w.addSpacer(4);
  const line = hstack(w, 8); txt(line, `${now.line}${now.sub ? ' · ' + now.sub : ''}`, num(16), C.ink, { lines: 1, min: 0.7 }); line.addSpacer();
  txt(line, `home ${when(T.returnAt).split(' ')[0]}`, num(15), C.mute);
  if (SIZE === 'large') {
    w.addSpacer(8);
    const cargo = (S.cargo || []).filter(x => x.tripId === T.id || x.status === 'road');
    const stops = tripStops(S);
    for (const s of stops) {
      const done = Date.now() >= +new Date(s.at), r = hstack(w, 8);
      const what = s.k === 'party' ? 'Left ' + placeName(S, T.from || hereOf(S)) : s.k === 'nest' ? 'The Nest' : s.k === 'shop' ? 'Steven’s shop' : 'Back with the party';
      txt(r, done ? '■' : '□', num(14), done ? C.gold : C.ink); txt(r, what, num(16), done ? C.mute : C.ink, { lines: 1 }); r.addSpacer(); txt(r, when(s.at), num(15), done ? C.mute : C.ink);
    }
    w.addSpacer();
    const foot = hstack(w, 6);
    const lb = cargo.reduce((t, x) => t + (x.lb != null ? +x.lb : 0), 0);
    for (const [k, v] of [['PACK', `${(T.items || []).length} items${lb ? ' · ' + Math.round(lb) + ' lb' : ''}`], ['MONEY', T.payout === 'bank' ? 'Bank receipt' : 'Carrying coin'], ['HOME', until(T.returnAt)]]) {
      const b = box(foot, C.panel); txt(b, k, head(8), C.mute); txt(b, v, num(15), C.ink, { lines: 1, min: 0.7 });
    }
  }
  return w;
}
function wickHome(w, S) {
  const pack = (S.cargo || []).filter(x => x.status === 'pack'), toNest = pack.some(x => x.dest === 'nest'), toShop = !toNest || pack.some(x => x.dest !== 'nest');
  const M = planRun(S, 'main', toNest, toShop), B = planRun(S, 'back', toNest, toShop), drop = nextHeatDrop(S), heat = +S.heat || 0;
  const tm = M.road ? runThr(S, 'main') * 5 : 0, tb = B.road ? runThr(S, 'back') * 5 : 0;
  if (SIZE === 'small') {
    const row = hstack(w, 4); row.addImage(sprite(SPR.sit, 3)).imageSize = new Size(48, 48); row.addImage(sprite(SPR.fire, 3)).imageSize = new Size(24, 21);
    txt(w, 'With the party', num(17), C.ink, { lines: 1 });
    txt(w, `Back roads ${tb}% · ${dayTxt(B.days)}`, num(15), C.warm, { lines: 1, min: 0.7 });
    if (drop) txt(w, `heat ${heat - 1} ${when(drop).split(' ')[0]}`, num(14), C.mute);
    return w;
  }
  const body = hstack(w, 12); body.topAlignContent();
  const left = vstack(body, 4); const art = hstack(left, 0); art.addImage(sprite(SPR.sit, 3)).imageSize = new Size(48, 48); art.addImage(sprite(SPR.fire, 3)).imageSize = new Size(24, 21);
  txt(left, 'With the party', num(14), C.mute); txt(left, placeName(S, hereOf(S)), num(14), C.mute, { lines: 2 });
  const right = vstack(body, 6);
  const g = hstack(right, 6);
  for (const [k, p, d, c, on] of [['MAIN ROAD', tm, M.days, C.hot, false], ['BACK ROADS', tb, B.days, C.warm, true]]) {
    const b = box(g, C.panel); if (on) { b.borderColor = col(C.gold); b.borderWidth = 2; }
    txt(b, k, head(9), '#b9c6d3'); txt(b, `${p}%`, num(28), c); txt(b, `trouble · ${dayTxt(d)}`, num(14), '#e3ecf4', { lines: 1, min: 0.7 });
  }
  const verdict = heat === 0 ? 'The roads are quiet. Good time to send him.' : tb <= 15 ? `Back roads are the safer bet.${drop ? ` Heat drops to ${heat - 1} ${when(drop).split(' ')[0]}.` : ''}` : `Heat is high.${drop ? ` It drops to ${heat - 1} ${when(drop).split(' ')[0]}.` : ''}`;
  txt(right, verdict, num(15), C.ink, { lines: 2, min: 0.7 });
  if (SIZE === 'large') {
    right.addSpacer(6);
    txt(right, 'IN HIS PACK', head(9), C.mute);
    if (!pack.length) txt(right, 'Nothing yet.', num(15), C.soft);
    for (const x of pack.slice(0, 8)) txt(right, `${x.name}${x.dest === 'nest' ? ' · for Orsolo' : ''}`, num(15), C.ink, { lines: 1 });
  }
  return w;
}
function wickMissing(S) {
  const w = widgetBase(C.missBg), T = S.trip;
  const top = hstack(w, 6); txt(top, 'WICK', head(13), C.red); top.addSpacer(); { const h = Math.max(0, Math.round((Date.now() - new Date(T.returnAt)) / 3600000)); txt(top, h < 36 ? `overdue ${h}h` : `overdue ${Math.floor(h / 24)}d`, num(14), '#c9a9a4'); }
  w.addSpacer(4);
  const row = hstack(w, 10); row.addImage(sprite(SPR.sack, 4)).imageSize = new Size(44, 36); txt(row, '?', head(36), C.red);
  w.addSpacer(4);
  txt(w, 'Wick is missing', num(20), C.ink, { lines: 1 });
  txt(w, `Last seen leaving ${placeName(S, T.from || hereOf(S))} by the ${T.route === 'back' ? 'back roads' : 'main road'}`, num(14), C.missInk, { lines: SIZE === 'small' ? 3 : 2 });
  return w;
}

// ---------------------------------------------------------------- the House
function houseWidget(H, S) {
  const B = houseBooks(H), w = widgetBase(C.hBg), open = (H.offers || []).filter(o => o.status === 'open').length;
  const nest = (S.cargo || []).filter(x => x.status === 'atnest').length, netC = B.net < 0 ? C.bad : C.good;
  const foot = [open ? `${open} contract${open === 1 ? '' : 's'} waiting` : '', nest ? `Orsolo is selling ${nest}` : ''].filter(Boolean).join(' · ');
  const top = hstack(w, 6);
  top.addImage(sprite(SPR.coins, 3)).imageSize = new Size(24, 24);
  txt(top, SIZE === 'large' ? 'THE HOUSE’S BOOKS' : 'THE HOUSE', head(13), C.hGold, { lines: 1 }); top.addSpacer();
  if (SIZE !== 'small') { const chip = top.addStack(); chip.backgroundColor = col(C.hPanel); chip.cornerRadius = 3; chip.setPadding(1, 6, 1, 6); txt(chip, B.inv, num(14), C.hMute); }
  if (SIZE === 'small') {
    w.addSpacer(6); txt(w, 'This session’s take', num(14), C.hMute);
    txt(w, `${sgn(B.net)} gp`, num(34), netC, { lines: 1, min: 0.6 });
    const io = hstack(w, 4); txt(io, sgn(B.tin), num(14), C.good); txt(io, 'in ·', num(14), C.hInk); txt(io, '−' + fmt(B.tout), num(14), C.bad); txt(io, 'out', num(14), C.hInk);
    w.addSpacer(); if (foot) txt(w, foot, num(14), C.hGold, { lines: 1, min: 0.7 });
    return w;
  }
  if (SIZE === 'medium') {
    w.addSpacer(6);
    const body = hstack(w, 14); body.topAlignContent();
    const left = vstack(body, 2); left.size = new Size(100, 0);
    txt(left, 'This session', num(14), C.hMute); txt(left, sgn(B.net), num(36), netC, { lines: 1, min: 0.6 }); txt(left, 'gp', num(14), C.hMute);
    const right = vstack(body, 4);
    const big = Math.max(B.tin, B.tout) || 1;
    const r1 = hstack(right, 4); txt(r1, 'COMING IN', head(9), C.good); r1.addSpacer(); txt(r1, sgn(B.tin), num(16), C.good);
    right.addImage(bar(190, 8, [[B.tin / big, C.good]], C.hPanel));
    const r2 = hstack(right, 4); txt(r2, 'GOING OUT', head(9), C.bad); r2.addSpacer(); txt(r2, '−' + fmt(B.tout), num(16), C.bad);
    right.addImage(bar(190, 8, B.groups.map(g => [g.v / big, g.c]), C.hPanel));
    const legend = hstack(right, 8); for (const g of B.groups) { const it = hstack(legend, 3); it.addImage(bar(7, 7, [[1, g.c]], g.c)); txt(it, g.s, num(13), C.hInk); }
    w.addSpacer(); if (foot) txt(w, foot, num(14), C.hGold, { lines: 1, min: 0.7 });
    return w;
  }
  // large: the ledger
  w.addSpacer(6);
  const section = (title, total, color, bg, rows) => {
    const s = w.addStack(); s.layoutVertically(); s.backgroundColor = col(C.hBg); s.borderColor = col(bg); s.borderWidth = 1; s.cornerRadius = 6;
    const h = s.addStack(); h.backgroundColor = col(bg); h.setPadding(4, 8, 4, 8); txt(h, title, head(9), color); h.addSpacer(); txt(h, total, num(16), color);
    for (const r of rows) { const row = s.addStack(); row.setPadding(1, 8, 1, 8); txt(row, r.l, num(16), C.hInk, { lines: 1, min: 0.7 }); row.addSpacer(); txt(row, r.v, num(16), color); }
  };
  section('COMING IN', sgn(B.tin), C.good, C.goodBg, B.ins.slice(0, 6).map(x => ({ l: x.l, v: '+' + fmt(x.v) })));
  w.addSpacer(6);
  section('GOING OUT', '−' + fmt(B.tout), C.bad, C.badBg, B.groups.map(g => ({ l: g.l, v: '−' + fmt(g.v) })));
  w.addSpacer(6);
  const net = w.addStack(); net.borderColor = col('#2a312b'); net.borderWidth = 2; net.cornerRadius = 6; net.setPadding(4, 10, 4, 10); net.centerAlignContent();
  txt(net, 'The House’s take', num(17), C.hInk); net.addSpacer(); txt(net, `${sgn(B.net)} gp`, num(28), netC);
  w.addSpacer(); if (foot) txt(w, foot, num(14), C.hGold, { lines: 1, min: 0.7 });
  return w;
}

// ---------------------------------------------------------------- Steven
function stevenWidget(S) {
  const V = steven(S), w = widgetBase(C.sBg), cg = S.cargo || [];
  const shelf = cg.filter(x => x.status === 'atshop'), nest = cg.filter(x => x.status === 'atnest');
  const last = cg.filter(x => x.status === 'sold' && x.dest !== 'nest').sort((a, b) => new Date(b.soldAt || 0) - new Date(a.soldAt || 0))[0];
  const head2 = hstack(w, 8); head2.topAlignContent();
  head2.addImage(sprite(SPR.steven, 3)).imageSize = new Size(48, 48);
  const id = vstack(head2, 2);
  if (SIZE === 'small') {
    txt(id, 'STEVEN', head(12), C.gold); txt(id, `Lv ${V.lv}`, num(34), C.sInk);
    w.addSpacer(2);
    txt(w, V.L.t, num(16), C.sInk, { lines: 1, min: 0.7 });
    w.addImage(bar(130, 8, [[V.pct, C.gold]], C.sPanel));
    txt(w, V.N ? `${V.mk} of ${V.N.m} marks to Lv ${V.lv + 1}` : `${V.mk} marks · top level`, num(13), C.sMute, { lines: 1 });
    w.addSpacer();
    txt(w, `Market bonus ${V.bonus >= 0 ? '+' : ''}${V.bonus}${V.hp ? ` (−${V.hp} heat)` : ''}`, num(14), C.sInk, { lines: 1, min: 0.7 });
    return w;
  }
  const r = hstack(id, 8); txt(r, SIZE === 'large' ? 'STEVEN’S SHELF' : 'STEVEN', head(13), C.gold); r.addSpacer(); txt(r, `Lv ${V.lv} · bonus ${V.bonus >= 0 ? '+' : ''}${V.bonus}`, num(16), C.sInk);
  id.addImage(bar(SIZE === 'large' ? 250 : 250, 6, [[V.pct, C.gold]], C.sPanel));
  txt(id, V.N ? `${V.mk} of ${V.N.m} marks to Lv ${V.lv + 1}, ${V.N.t}` : 'Top level', num(13), C.sMute, { lines: 1, min: 0.7 });
  w.addSpacer(6);
  const rows = shelf.slice(0, SIZE === 'large' ? 6 : 2);
  if (!rows.length) txt(w, 'Nothing on the shelf right now.', num(16), C.sMute);
  for (const x of rows) {
    const row = hstack(w, 8);
    const l = vstack(row, 0); txt(l, x.name + ((+x.qty || 1) > 1 ? ' ×' + x.qty : ''), num(16), C.sInk, { lines: 1, min: 0.7 });
    if (SIZE === 'large') txt(l, [x.min != null ? `lowest ${fmt(x.min)}` : '', x.price != null && x.price !== x.ask ? `marked down to ${fmt(x.price)}` : ''].filter(Boolean).join(' · ') || ' ', num(13), C.sMute, { lines: 1 });
    row.addSpacer();
    const rr = vstack(row, 0); txt(rr, x.ask != null ? `${fmt(x.ask)} gp` : 'no price', num(16), C.gold, { right: true });
    if (SIZE === 'large' && x.shelfDays) txt(rr, `${x.shelfDays} day${x.shelfDays === 1 ? '' : 's'}`, num(13), C.sMute, { right: true });
  }
  if (shelf.length > rows.length) txt(w, `+ ${shelf.length - rows.length} more`, num(14), C.sMute);
  if (SIZE === 'large') {
    w.addSpacer();
    if (nest.length) { const b = box(w, C.sPanel); txt(b, 'WITH ORSOLO AT THE NEST', head(9), C.sMute); txt(b, nest.map(x => x.name).join(', '), num(15), C.sInk, { lines: 2, min: 0.7 }); w.addSpacer(6); }
    if (last) txt(w, `Last sale: ${last.name}, ${fmt(last.sold)} gp`, num(14), C.sMute, { lines: 1, min: 0.7 });
  }
  return w;
}

// ---------------------------------------------------------------- run
function errorWidget(msg) {
  const w = widgetBase(C.night); txt(w, 'AZURE CONCORD', head(12), C.gold); w.addSpacer(4); txt(w, msg, num(15), C.ink, { lines: 4 }); return w;
}
async function build() {
  let D;
  try { D = await load(); } catch (e) { return errorWidget('Couldn’t reach the ledger. It will try again soon.'); }
  const S = D.shop || {}, H = D.house || {};
  if (MODE === 'house') return houseWidget(H, S);
  if (MODE === 'steven') return stevenWidget(S);
  return wickWidget(S);
}

const widget = await build();
if (config.runsInWidget) Script.setWidget(widget);
else if (SIZE === 'small') await widget.presentSmall();
else if (SIZE === 'large') await widget.presentLarge();
else await widget.presentMedium();
Script.complete();

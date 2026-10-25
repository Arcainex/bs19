// bs_atlas - panel logic for the node atlas. map.js paints

'use strict';

// 1. The bridge

// One page, two hosts: in game it is bs_atlas's NUI page (fetch https://bs_atlas/<endpoint>)
const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'bs_atlas';

const NUI_HOST = {
    kind: 'nui',
    caps: { me: true, waypoint: true, close: true, calibrate: false },
    async post(endpoint, data) {
        const r = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return r.json();
    },
};

const HOST = (typeof window !== 'undefined' && window.AtlasHost) ? window.AtlasHost : NUI_HOST;

function post(endpoint, data) { return HOST.post(endpoint, data); }

// One server call; the only function touching freshness state. ok:true to server agreed.
async function call(name, args) {
    try {
        const res = await post('call', { name, args: args || {} });
        return res || { ok: false, error: AT('atlas.empty_resp', 'empty response') };
    } catch (e) {
        // A throw means the NUI fetch itself failed (resource stopped). Treated like a timeout.
        return { ok: false, error: AT('atlas.bridge_failed', 'nui bridge failed: {err}', { err: e }), timedOut: true };
    }
}

// 2. State

const ST = {
    open: false,
    cfg: null,              // the settings Lua sent on open

    pollMs: 500,
    pollTimer: null,
    misses: 0,              // consecutive failed polls
    stale: true,            // starts true: nothing has answered yet
    lastGood: 0,

    me: null,               // pushed by Lua at 4Hz while open
    lastSnapshot: null,
    selected: null,         // { cx, cy } currently inspected
    inspect: null,          // the last inspect response
    rect: null,             // the repopulate rectangle

    observer: null,         // what the server accepted, not what was requested
    obsRadius: 300,

    simConfig: null,        // the config tree
    writable: null,         // the numeric whitelist, from the server
    booleans: [],           // dotted keys of every boolean leaf in config
    pending: {},            // key to new value, not yet applied
};

const $  = id => document.getElementById(id);
const el = (tag, cls, txt) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (txt != null) n.textContent = txt;
    return n;
};
const fmt = n => (n == null ? '-' : Number(n).toLocaleString('en-GB'));
const f1  = n => (n == null ? '-' : Number(n).toFixed(1));

// 3. Layers and legend

// Each layer names something the simulation does
const LAYERS = [
    ['map',     'GTA V MAP',     '#c9b98a', 'The real map image (nodes/html/img/map.png), aligned by nodes/calibration.json. Opacity is in the MAP card.'],
    ['cells',   'DENSITY CELLS', '#5ee08a', 'The far field: one head count per 50m square. Colour is how many; an outline means locked, cleared, thin or promoted.'],
    ['agents',  'INDIVIDUALS',   '#8fa6bd', 'The near field: one dot per zombie, with its own position and state. A white ring means it is a real ped in the world right now.'],
    ['virtual', 'NOT SPAWNED',   '#4a5866', 'Simulated zombies that are not real peds yet. Off by default - only real entities are shown.'],
    ['targets', 'TARGET LINES',  '#ffd24a', 'Where an individual has decided to go. To a POINT means it heard something; to a PLAYER means sight, scent or damage fired.'],
    ['herds',   'HERDS',         '#ff6ec7', 'Not objects - an OBSERVATION. A ring is drawn where 20+ individuals happen to be standing together.'],
    ['noise',   'NOISE PINGS',   '#4fd0ff', 'The sense board. Ring radius is how far it actually carries; it fades as it ages out.'],
    ['cars',    'WORLD CARS',    '#f5c542', 'Cars placed by the world car spawn system: position, model and state (free, locked, stored, wrecked).'],
    ['players', 'PLAYERS',       '#ffffff', 'Real players in view, with heading, and a tag for crouch, prone or vehicle.'],
    ['heat',    'ZONE HEAT',     '#ff5a3c', 'The director: how much violence each spawn zone remembers. Fill is heat against the maximum; a full zone throws a horde.'],
    ['hordes',  'HORDES',        '#ff2d55', 'Active hordes. Solid ring = a heat wave from the director; dashed = a crowd that walked to a noise and gathered.'],
    ['places',  'PLACE NAMES',   '#5b7286', 'ZAtlas.points from bs_zombies. Label size is the density weight the far field uses for that area.'],
    ['grid',    'KM GRID',       '#33414f', 'World coordinates. Spacing adapts to zoom.'],
];

function buildLayers() {
    const box = $('layers');
    box.innerHTML = '';
    LAYERS.forEach(([key, name, colour, why]) => {
        const row = el('div', 'lyr');
        row.title = AT('atlas.l.' + key + '.d', why);
        const sw = el('span', 'lyr__sw'); sw.style.background = colour;
        row.append(sw, el('span', 'lyr__n', AT('atlas.l.' + key + '.n', name)), el('span', 'lyr__c', ''));
        const sync = () => row.classList.toggle('is-off', !AtlasMap.layers[key]);
        row.addEventListener('click', () => { AtlasMap.layers[key] = !AtlasMap.layers[key]; sync(); });
        sync();
        row.dataset.k = key;
        box.appendChild(row);
    });
}

// The legend is built from AtlasMap.COLOURS, the same tables the renderer uses, so it cannot go stale
function buildLegend() {
    const box = $('legend');
    box.innerHTML = '';

    const section = (title, obj, notes) => {
        box.appendChild(el('div', 'sub', title));
        Object.keys(obj).forEach(k => {
            const row = el('div', 'lgd');
            const sw = el('span', 'lgd__sw'); sw.style.background = obj[k];
            const note = (notes && notes[k]) || '';
            row.append(sw, el('span', null, AT('atlas.s.' + k, k.toUpperCase())),
                       el('span', 'lgd__t', note ? AT('atlas.sn.' + k, note) : ''));
            box.appendChild(row);
        });
    };

    section(AT('atlas.lg.agent', 'AGENT STATE'), AtlasMap.COLOURS.agent, {
        wander: 'drifting', lurk: 'standing still', investigate: 'heard something',
        drawn: 'pulled along', hunt: 'has a player', feed: 'on a corpse',
    });
    section(AT('atlas.lg.cars', 'WORLD CARS'), AtlasMap.CAR_COLOURS, {});
    section(AT('atlas.lg.cell', 'CELL STATE'), AtlasMap.COLOURS.cell, {
        locked: 'staff pinned', cleared: 'farmed, healing', thin: 'under half',
        promoted: 'live individuals', full: 'at baseline', normal: '', empty: '',
    });

    // Density ramp swatches, as the renderer produces them.
    box.appendChild(el('div', 'sub', AT('atlas.lg.density', 'DENSITY (PER CELL)')));
    [0, 1, 3, 6, 12, 20, 35, 60].forEach(n => {
        const row = el('div', 'lgd');
        const sw = el('span', 'lgd__sw'); sw.style.background = AtlasMap.rampColour(n);
        row.append(sw, el('span', null, n === 60 ? '60+' : String(n)));
        box.appendChild(row);
    });
}

// 4. The live poll

// Only the current view rect (plus a small margin) is requested
function requestRect() {
    const v = AtlasMap.viewRect();
    const m = (ST.cfg && ST.cfg.fetchMargin) || 0.15;
    const dx = (v.x2 - v.x1) * m, dy = (v.y2 - v.y1) * m;
    return { x1: v.x1 - dx, y1: v.y1 - dy, x2: v.x2 + dx, y2: v.y2 + dy,
             zoom: AtlasMap.view.ppm };
}

// setTimeout chain, not setInterval
function scheduleNextPoll() {
    clearTimeout(ST.pollTimer);
    if (!ST.open) return;
    ST.pollTimer = setTimeout(poll, ST.pollMs);
}

async function poll() {
    if (!ST.open) return;

    const res = await call('zombies:atlas:snapshot', requestRect());

    if (!ST.open) return;   // closed while we were waiting

    if (res && res.ok) {
        arrayify(res);
        ST.misses = 0;
        ST.lastGood = Date.now();
        ST.stale = false;
        ST.lastSnapshot = res;
        AtlasMap.setSnapshot(res);
        AtlasMap.setStale(false);
        setStale(null);
        renderStats(res);
        renderSampling(res);
    } else {
        // A refusal is not a timeout (see call())
        ST.misses++;
        const after = (ST.cfg && ST.cfg.staleAfterPolls) || 2;
        if (res && res.ok === false && !res.timedOut) {
            setStale(AT('atlas.stale_refused', 'SIMULATION REFUSED: {err}', { err: res.error || AT('atlas.unknown', 'unknown') }));
            $('simState').textContent = res.error || AT('atlas.refused', 'refused');
        } else if (ST.misses >= after) {
            setStale(AT('atlas.stale_missed', 'NO ANSWER FROM THE SIMULATION - {n} MISSED POLLS', { n: ST.misses }));
            $('simState').textContent = AT('atlas.not_answering', 'not answering');
        }
        if (ST.misses >= after || (res && res.ok === false)) {
            ST.stale = true;
            AtlasMap.setStale(true);
        }
    }

    scheduleNextPoll();
}

// An empty Lua table can arrive as {} instead of []
function arrayify(snap) {
    ['cells', 'agents', 'herds', 'noise', 'players'].forEach(k => {
        if (!Array.isArray(snap[k])) snap[k] = snap[k] ? Object.values(snap[k]) : [];
    });
}

// The banner: null lowers it, a string raises it with the reason
function setStale(text) {
    const b = $('staleBanner');
    if (!text) { b.hidden = true; return; }
    $('staleText').textContent = text;
    b.hidden = false;
}

// 5. The HUD

function renderStats(snap) {
    const s = snap.stats || {};
    $('simState').textContent =
        AT('atlas.live', 'live · {total} zombies · {ind} individuals', { total: fmt(s.total), ind: fmt(s.individuals) });

    const box = $('stats');
    box.innerHTML = '';
    const add = (k, v, title) => {
        const n = el('span', null);
        n.innerHTML = `${k} <b>${v}</b>`;
        if (title) n.title = title;
        box.appendChild(n);
    };
    const S_ = (k, lab, v, tip, vars) => add(AT('atlas.st.' + k, lab), v, AT('atlas.st.' + k + '.d', tip, vars));
    S_('total', 'TOTAL', fmt(s.total), 'Every zombie in the world - far field counts plus live individuals.');
    S_('ind', 'IND', fmt(s.individuals), 'Promoted to individual records right now: near a player, or inside an observer.');
    S_('records', 'RECORDS', fmt(s.spawnedPeds), 'Walker RECORDS on the server. Not a measurement of real peds - the server writes these before any client draws anything. Compare with STREAMED.');
    S_('confirmed', 'CONFIRMED', fmt(s.confirmedRecords), 'Current server records acknowledged as created by at least one client. Not a guarantee they remain visible.');
    S_('waiting', 'WAITING', fmt(s.unconfirmedRecords), 'Current records never acknowledged by a client; released after 45 seconds without counting a kill.');
    S_('clientpeds', 'CLIENT PEDS', fmt(s.clientRenderedSum), 'Live zombie copies reported by {n} clients in the last 10 seconds. Shared zombies count once per viewing client; not unique world population.', { n: s.reportingClients || 0 });
    S_('created', 'CREATED TOTAL', fmt(s.streamSpawned), 'Cumulative records created by the planner this session, including records subsequently killed or removed.');
    S_('refused', 'REFUSED', fmt(s.streamRefused), 'Candidates a client refused - usually no cover, or the player was looking. High with an empty world means the placement gate, not the population.');
    S_('cells', 'CELLS', fmt(s.cells), 'Total 50m cells in the grid. Fixed at seed time - this is the size of the world, not how much of it is occupied.');
    S_('herds', 'HERDS', fmt(s.herds), '20+ individuals standing together. An observation, not an object.');
    S_('obs', 'OBS', fmt(s.observers), 'Atlas observers registered server-wide, including yours.');
    S_('mode', 'MODE', String(s.spawnMode || '?').toUpperCase(),
        'Which system is placing walkers: SIMULATION (nodes, depletion, migration) or LOCAL (a plain ring, no simulation). Switch it from the staff menu.');
    S_('tick', 'TICK', f1(s.tickMs) + 'ms', 'Agent tick cost. Rising here means Sim.near.maxAgents is the dial.');
    S_('celltick', 'CELLTICK', f1(s.cellTickMs) + 'ms', 'Grid sweep slice cost.');
    S_('regrow', 'REGROW', f1(s.regrowthPerHour) + '/h', 'Per cell per hour, 0 when regrowth is off.');

    $('lastPoll').textContent = AT('atlas.updated', 'updated {t}', { t: new Date().toLocaleTimeString('en-GB') });
}

// Sampling is shown visibly. stride > 1 means every Nth cell was sampled
function renderSampling(snap) {
    const strideChip = $('chipStride');
    const n = snap.stride || 1;
    strideChip.hidden = false;
    strideChip.textContent = n > 1 ? AT('atlas.sam.part', 'SAMPLED 1:{n} - NOT EVERY CELL', { n }) : AT('atlas.sam.full', 'SAMPLED 1:1 - EVERY CELL');
    strideChip.classList.toggle('chip--warn', n > 1);
    strideChip.title = n > 1
        ? AT('atlas.sam.part.d', 'This view is larger than the server will walk cell by cell (4,000). Every {n}th cell in both axes was read and drawn at its full footprint. Empty-looking ground here may not be empty - zoom in to see it exactly.', { n })
        : AT('atlas.sam.full.d', 'Every cell in view was read. What you see is what is there.');

    const t = $('chipTrunc');
    t.hidden = !snap.truncated;
    t.textContent = AT('atlas.trunc', 'AGENT CAP REACHED - MORE ZOMBIES THAN DOTS');
    t.title = AT('atlas.trunc.d', 'The snapshot stops at 1,500 individuals. There are more in this rectangle than are drawn. Zoom in to see a complete picture of a smaller area.');
}

// 6. Inspect and edit

async function inspectCell(cx, cy) {
    ST.selected = { cx, cy };
    AtlasMap.setSelected(ST.selected);
    showTab('inspect');

    const res = await call('zombies:atlas:inspect', { cx, cy });
    if (!res.ok) {
        ST.inspect = null;
        $('editBlock').hidden = true;
        $('inspectBody').innerHTML = '';
        $('inspectBody').appendChild(el('p', 'note note--warn',
            AT('atlas.i.err', 'Cell {cx},{cy}: {err}', { cx, cy, err: res.error || AT('atlas.no_answer', 'no answer') })));
        return;
    }
    ST.inspect = res;
    renderInspect(res);
}

function kv(parent, k, v, cls, title) {
    const row = el('div', 'kv');
    const kn = el('span', 'kv__k', k);
    const vn = el('span', 'kv__v' + (cls ? ' ' + cls : ''), v);
    if (title) row.title = title;
    row.append(kn, vn);
    parent.appendChild(row);
}

// Everything inspect returns is shown, not a subset, so staff can see every field the server knows
function renderInspect(r) {
    const b = $('inspectBody');
    b.innerHTML = '';
    const c = r.cell, h = r.history, g = r.regrowth;

    const I = (k, fb) => AT('atlas.i.' + k, fb);
    b.appendChild(el('div', 'sub', AT('atlas.i.cell', 'CELL {cx}, {cy}', { cx: c.cx, cy: c.cy })));
    kv(b, I('centre', 'world centre'), `${Math.round(c.x)}, ${Math.round(c.y)}`);
    kv(b, I('size', 'size'), c.size + 'm');
    kv(b, I('state', 'state'), AT('atlas.s.' + c.state, String(c.state).toUpperCase()),
       c.state === 'cleared' || c.state === 'thin' ? 'is-warn'
       : (c.state === 'promoted' ? 'is-go' : null),
       I('state.d', 'locked / cleared / thin / promoted / full / normal / empty - see the legend.'));
    kv(b, I('locked', 'locked'), c.locked ? I('yes', 'YES') : I('no', 'no'), c.locked ? 'is-warn' : null,
       I('locked.d', 'A locked cell is skipped by regrowth AND by migration. Nothing but a staff edit changes it.'));
    kv(b, I('count', 'count (far field)'), fmt(c.n), null, I('count.d', 'Simulated as a number only - nobody has a position.'));
    kv(b, I('individuals', 'individuals'), fmt(c.individuals), c.individuals > 0 ? 'is-go' : null,
       I('individuals.d', 'Promoted to real records with their own position and state.'));
    kv(b, I('total', 'total'), fmt(c.total));
    kv(b, I('baseline', 'baseline'), fmt(c.baseline), null, I('baseline.d', 'What this cell regrows towards.'));
    kv(b, I('weight', 'weight'), f1(c.weight), null, I('weight.d', 'How built-up the density map thinks this is. Repopulate spreads by this.'));

    b.appendChild(el('div', 'sub', I('history', 'HISTORY')));
    kv(b, I('killed', 'killed here'), fmt(h.killed), h.killed > 0 ? 'is-warn' : null);
    kv(b, I('migin', 'migrated in'),  fmt(h.migratedIn));
    kv(b, I('migout', 'migrated out'), fmt(h.migratedOut));
    kv(b, I('since', 'since last kill'),
       h.secondsSinceKill == null ? I('never', 'never') : Math.round(h.secondsSinceKill) + 's');

    b.appendChild(el('div', 'sub', I('regrowth', 'REGROWTH')));
    kv(b, I('enabled', 'enabled'), g.enabled ? I('yes2', 'yes') : I('no2', 'NO'), g.enabled ? 'is-go' : 'is-warn',
       I('enabled.d', 'False here can mean regrowth is off globally OR that this cell is locked.'));
    kv(b, I('perhour', 'per hour'), f1(g.perHour));
    kv(b, I('cap', 'cap'), fmt(g.cap), null, I('cap.d', 'Regrowth stops here - baseline x capFraction.'));
    kv(b, I('banked', 'banked'), f1(g.banked), null, I('banked.d', 'Fractional zombies accumulated but not yet whole.'));
    kv(b, I('grace', 'grace remaining'),
       g.graceRemaining == null ? I('grace_none', 'none - growing') : Math.round(g.graceRemaining) + 's',
       g.graceRemaining == null ? 'is-go' : 'is-warn',
       I('grace.d', 'After a cell is farmed out it is held empty for a grace period so the area stays cleared for a while. REPOPULATE ends it immediately.'));

    let inds = r.individuals || [];
    if (!Array.isArray(inds)) inds = Object.values(inds);   // same reason as arrayify()
    b.appendChild(el('div', 'sub', AT('atlas.i.inds', 'INDIVIDUALS IN THIS CELL ({n})', { n: inds.length })));
    if (!inds.length) {
        b.appendChild(el('p', 'note',
            I('none', 'None promoted. This cell is a number right now - no player is near it and no observer covers it. Register an observer on it to watch it come alive.')));
    } else {
        const list = el('div', 'inds');
        inds.forEach(a => {
            const row = el('div', 'ind');
            row.title = a.target
                ? AT('atlas.i.target', 'target: {kind}{src} at {x}, {y}', { kind: a.target.kind, src: a.target.src ? ' #' + a.target.src : '', x: Math.round(a.target.x), y: Math.round(a.target.y) })
                : I('notarget', 'no target');
            const sw = el('span', 'ind__sw');
            sw.style.background = AtlasMap.COLOURS.agent[a.state] || '#8fa6bd';
            row.append(sw,
                el('span', 'ind__id', '#' + a.id),
                el('span', 'ind__st', (a.state || '?') + (a.stim ? '/' + a.stim : '')),
                el('span', 'ind__x', (a.ped ? I('ped', 'PED') + ' ' : '') + AT('atlas.i.drift', 'drift {n}m', { n: Math.round(a.driftFromOrigin || 0) })));
            list.appendChild(row);
        });
        b.appendChild(list);
        b.appendChild(el('p', 'note',
            I('drift.d', 'DRIFT is how far this zombie has wandered from where it was promoted. It is leashed by Sim.move.maxDriftFromOrigin - a whole cell sitting at the leash length means the leash is what is holding them, not the world.')));
    }

    $('editBlock').hidden = false;
    $('editN').value = c.n;
    $('editBase').value = c.baseline;
    $('btnLock').classList.toggle('is-on', !!c.locked);
}

// Every edit goes through here and therefore through confirm(), and the response is shown.
async function editCell(patch, describe) {
    if (!ST.selected) return;
    const { cx, cy } = ST.selected;

    const yes = await confirmAction(AT('atlas.e.title', 'EDIT CELL {cx}, {cy}', { cx, cy }), describe);
    if (!yes) return;

    const res = await call('zombies:atlas:edit', { cx, cy, patch });
    toast(res, res.ok
        ? AT('atlas.e.result', 'Cell {cx},{cy} is now n={n} individuals={ind} baseline={base} state={state}{lock}', { cx, cy, n: res.cell.n, ind: res.cell.individuals, base: res.cell.baseline, state: res.cell.state, lock: res.cell.locked ? ' ' + AT('atlas.e.lockflag', 'LOCKED') : '' })
        : null);
    if (res.ok) inspectCell(cx, cy);   // re-read rather than trusting our patch
}

// 7. Repopulate

function onRect(r) {
    ST.rect = r;
    AtlasMap.setRect(r);
    $('btnRectMode').classList.remove('is-on');
    const w = Math.round(Math.abs(r.x2 - r.x1)), h = Math.round(Math.abs(r.y2 - r.y1));
    $('rectReadout').textContent =
        AT('atlas.r.readout', '{w}m x {h}m - about {c} cells.', { w, h, c: Math.max(1, Math.round((w / 50) * (h / 50))) });
    $('btnRepop').disabled = false;
    showTab('inspect');
}

async function doRepopulate() {
    if (!ST.rect) return;
    const amount = parseInt($('repopN').value, 10);
    if (!(amount > 0)) return toast({ ok: false, error: AT('atlas.r.badamount', 'amount must be positive') });

    const w = Math.round(Math.abs(ST.rect.x2 - ST.rect.x1));
    const h = Math.round(Math.abs(ST.rect.y2 - ST.rect.y1));

    const yes = await confirmAction(AT('atlas.r.confirm', 'REPOPULATE'),
        AT('atlas.r.text', 'Add <b>{n}</b> zombies across a <b>{w}m x {h}m</b> area.\n\nThey are spread BY DENSITY WEIGHT, so streets get more than hillsides. Locked cells are skipped. Any grace period in that area ENDS - the ground is declared open again and natural regrowth resumes on top of this.\n\nThis is immediate, it is logged to the server console with your name, and there is no undo button.',
            { n: fmt(amount), w, h }));
    if (!yes) return;

    const res = await call('zombies:atlas:repopulate', {
        x1: ST.rect.x1, y1: ST.rect.y1, x2: ST.rect.x2, y2: ST.rect.y2, amount,
    });
    toast(res, res.ok
        ? AT('atlas.r.result', 'Added {added} across {cells} editable cells. World total is now {total}.', { added: fmt(res.added), cells: fmt(res.cells), total: fmt(res.stats && res.stats.total) })
        : null);

    if (res.ok && ST.selected) inspectCell(ST.selected.cx, ST.selected.cy);
}

// 8. Observer

async function registerObserver(x, y) {
    const res = await post('observer', { on: true, x, y, radius: ST.obsRadius });

    if (!res || !res.ok) {
        ST.observer = null;
        AtlasMap.setObserver(null);
        $('chipObs').hidden = true;
        $('obsState').textContent = AT('atlas.o.refused', 'REFUSED: {err}', { err: (res && res.error) || AT('atlas.no_answer', 'no answer') });
        return toast(res || { ok: false, error: AT('atlas.no_answer', 'no answer') });
    }

    // Draw what the server accepted: it clamps the radius at Sim.observer.maxRadius.
    ST.observer = res.observer || { x: res.x, y: res.y, radius: res.radius };
    AtlasMap.setObserver(ST.observer);
    $('chipObs').hidden = false;
    $('chipObs').textContent = AT('atlas.chip_obs', 'OBSERVING {r}m', { r: Math.round(ST.observer.radius) });

    const clamped = Math.abs(ST.observer.radius - ST.obsRadius) > 0.5;
    $('obsState').textContent =
        AT('atlas.o.watching', 'Watching {x}, {y} at {r}m', { x: Math.round(ST.observer.x), y: Math.round(ST.observer.y), r: Math.round(ST.observer.radius) }) +
        (clamped ? ' ' + AT('atlas.o.clamped', '(you asked for {a}m - the server clamped it)', { a: ST.obsRadius }) : '') +
        '. ' + AT('atlas.o.tail', '{n} observer(s) server-wide. Expires in {s}s unless this panel refreshes it - it does, automatically, while the atlas is open.', { n: res.observers, s: res.expiresIn });

    toast(res, AT('atlas.o.registered', 'Observer registered. That region is now promoting to individuals with nobody standing in it.'));
}

async function clearObserver() {
    const res = await post('observer', { on: false });
    ST.observer = null;
    AtlasMap.setObserver(null);
    $('chipObs').hidden = true;
    $('obsState').textContent = AT('atlas.obs_none', 'No observer registered.');
    toast(res, AT('atlas.o.cleared', 'Observer cleared. That region will de-promote on the next sweep.'));
}

// 9. Config

// Collect every boolean leaf of the config tree as a dotted key (writable only covers numerics)
function findBooleans(cfg) {
    const out = [];
    Object.keys(cfg || {}).forEach(k => {
        if (k === 'writable' || k === 'persisted') return;
        const v = cfg[k];
        if (typeof v === 'boolean') out.push(k);
        else if (v && typeof v === 'object' && !Array.isArray(v)) {
            Object.keys(v).forEach(k2 => {
                if (typeof v[k2] === 'boolean') out.push(k + '.' + k2);
            });
        }
    });
    return out;
}

function getDotted(cfg, key) {
    const parts = key.split('.');
    let n = cfg;
    for (const p of parts) { if (n == null) return undefined; n = n[p]; }
    return n;
}

async function loadConfig() {
    const res = await call('zombies:atlas:config', {});
    if (!res.ok) {
        $('cfgBody').innerHTML = '';
        $('cfgBody').appendChild(el('p', 'note note--warn',
            AT('atlas.c.unavail', 'Config unavailable: {err}', { err: res.error || AT('atlas.no_answer', 'no answer') })));
        return;
    }
    ST.simConfig = res.config;
    ST.writable  = res.config.writable || {};
    ST.booleans  = findBooleans(res.config);
    ST.pending   = {};
    renderConfig();
    markDirty();
}

function renderConfig() {
    const body = $('cfgBody');
    body.innerHTML = '';

    // Booleans first: they are the master switches.
    body.appendChild(el('div', 'cfg__sec', AT('atlas.c.switches', 'SWITCHES')));
    ST.booleans.forEach(key => {
        const cur = !!getDotted(ST.simConfig, key);
        const lab = el('label', 'cfg__bool');
        const box = document.createElement('input');
        box.type = 'checkbox';
        box.checked = cur;
        box.addEventListener('change', () => {
            if (box.checked === cur) delete ST.pending[key];
            else ST.pending[key] = box.checked;
            markDirty();
        });
        lab.append(box, el('span', 'cfg__k', key));
        body.appendChild(lab);
    });

    // Numerics, grouped by the section in their dotted key. Built entirely from writable.
    const keys = Object.keys(ST.writable).sort();
    let section = null;
    keys.forEach(key => {
        const sec = key.includes('.') ? key.split('.')[0] : 'general';
        if (sec !== section) {
            section = sec;
            body.appendChild(el('div', 'cfg__sec', sec.toUpperCase()));
        }

        // Lua's { min, max } arrives as a JSON array, but an object is accepted too; failing to read it would make every slider 0..1
        const range = ST.writable[key];
        const min = Array.isArray(range) ? Number(range[0]) : Number(range.min);
        const max = Array.isArray(range) ? Number(range[1]) : Number(range.max);
        const cur = Number(getDotted(ST.simConfig, key));

        const wrap = el('div', 'cfg');
        wrap.appendChild(el('div', 'cfg__k', key));

        const row = el('div', 'cfg__rng');
        const sl = document.createElement('input');
        sl.type = 'range'; sl.className = 'rng';
        sl.min = min; sl.max = max;
        // 200 steps across the range, floored at 1 for integer-looking dials.
        sl.step = (max - min) > 400 ? 1 : ((max - min) / 200);
        sl.value = isFinite(cur) ? cur : min;

        const nb = document.createElement('input');
        nb.type = 'number'; nb.className = 'cfg__in';
        nb.min = min; nb.max = max; nb.step = sl.step;
        nb.value = sl.value;

        const change = v => {
            const num = Number(v);
            sl.value = num; nb.value = num;
            const dirty = Math.abs(num - cur) > 1e-9;
            nb.classList.toggle('is-dirty', dirty);
            if (dirty) ST.pending[key] = num; else delete ST.pending[key];
            markDirty();
        };
        sl.addEventListener('input', () => change(sl.value));
        nb.addEventListener('change', () => change(nb.value));

        row.append(sl, nb);
        wrap.appendChild(row);
        wrap.appendChild(el('div', 'cfg__lim',
            AT('atlas.c.limits', 'min {min}   max {max}   live {cur}', { min, max, cur: isFinite(cur) ? cur : '?' })));
        body.appendChild(wrap);
    });
}

function markDirty() {
    const n = Object.keys(ST.pending).length;
    $('btnCfgApply').disabled = n === 0;
    $('cfgDirty').textContent = n === 0
        ? AT('atlas.cfg_none', 'No pending changes.')
        : AT('atlas.cfg_pending', '{n} pending change(s). Nothing has been sent yet.', { n });
}

async function applyConfig() {
    const patch = ST.pending;
    const keys = Object.keys(patch);
    if (!keys.length) return;

    const yes = await confirmAction(AT('atlas.c.confirm', 'APPLY TO THE LIVE SIMULATION'),
        keys.map(k => `${k} -> ${patch[k]}`).join('\n') +
        '\n\n' + AT('atlas.c.confirm_text', 'These take effect <b>immediately</b> on the running server and are <b>NOT saved</b> - a restart returns every one of them to config_sim.lua.'));
    if (!yes) return;

    const res = await call('zombies:atlas:config', { patch });
    const out = $('cfgResult');
    out.hidden = false;

    if (!res.ok) {
        out.textContent = AT('atlas.c.failed', 'FAILED: {err}', { err: res.error || AT('atlas.no_answer', 'no answer') });
        return;
    }

    // Applied and rejected are both shown
    const lines = [];
    const applied = res.applied || {}, rejected = res.rejected || {};
    const ak = Object.keys(applied), rk = Object.keys(rejected);

    lines.push(ak.length ? AT('atlas.c.applied', 'APPLIED:') : AT('atlas.c.applied_none', 'APPLIED: (nothing)'));
    ak.forEach(k => lines.push('  ' + k + ' = ' + applied[k]));
    if (rk.length) {
        lines.push('', AT('atlas.c.rejected', 'REJECTED / CLAMPED:'));
        rk.forEach(k => lines.push('  ' + k + ' - ' + rejected[k]));
    }
    lines.push('', AT('atlas.c.persisted', 'persisted = false - none of this survives a restart.'));
    out.textContent = lines.join('\n');

    // Re-read from the server rather than assuming.
    ST.simConfig = res.config || ST.simConfig;
    ST.writable  = (res.config && res.config.writable) || ST.writable;
    ST.pending   = {};
    renderConfig();
    markDirty();
}

// 10. Modal and toast

let modalResolve = null;

// One confirm path for every destructive action
function confirmAction(title, text) {
    $('modalTitle').textContent = title;
    $('modalText').innerHTML = String(text).replace(/\n/g, '<br>');
    $('modal').hidden = false;
    return new Promise(res => { modalResolve = res; });
}
function closeModal(v) {
    $('modal').hidden = true;
    if (modalResolve) { modalResolve(v); modalResolve = null; }
}

let toastTimer = null;
async function teleportTo(x, y) {
    const yes = await confirmAction(AT('atlas.t.tp_title', 'TELEPORT'), AT('atlas.t.tp_confirm', 'Teleport to {x}, {y}?', { x: Math.round(x), y: Math.round(y) }));
    if (!yes) return;
    const res = await post('teleport', { x, y });
    toast(res, AT('atlas.t.tp_done', 'Teleported to {x}, {y}.', { x: Math.round(x), y: Math.round(y) }));
}

// The raw response is printed under the summary line, since a summary written before the call cannot know what the server decided
function toast(res, summary) {
    const t = $('toast');
    const ok = !!(res && res.ok);
    t.className = 'toast ' + (ok ? 'is-good' : 'is-bad');
    t.textContent = (ok ? (summary || AT('atlas.t.ok', 'OK')) : AT('atlas.c.failed', 'FAILED: {err}', { err: (res && res.error) || AT('atlas.no_answer', 'no answer') }))
        + '\n\n' + JSON.stringify(res, null, 1);
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 11000);
}

// 11. Tabs and wiring

function showTab(name) {
    document.querySelectorAll('.tab').forEach(b =>
        b.classList.toggle('is-on', b.dataset.tab === name));
    document.querySelectorAll('.pane').forEach(p =>
        p.classList.toggle('is-on', p.dataset.pane === name));
}

function wire() {
    document.querySelectorAll('.tab').forEach(b =>
        b.addEventListener('click', () => showTab(b.dataset.tab)));

    $('btnClose').addEventListener('click', doClose);

    // ESC closes
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        if (!$('modal').hidden) return closeModal(false);
        doClose();
    });

    $('modalYes').addEventListener('click', () => closeModal(true));
    $('modalNo').addEventListener('click',  () => closeModal(false));

    $('pollMs').addEventListener('input', e => {
        ST.pollMs = parseInt(e.target.value, 10);
        $('pollMsOut').textContent = ST.pollMs + 'ms';
        scheduleNextPoll();
    });

    $('btnFindMe').addEventListener('click', () => {
        const m = ST.me;
        if (m) AtlasMap.centreOn(m.x, m.y, 900);
    });
    $('btnWorld').addEventListener('click', () => AtlasMap.fitWorld());
    // Teleport mode: arm the picker, the next map click asks the server (admin only, logged).
    $('btnTeleport').addEventListener('click', () => {
        AtlasMap.pick(true, 'teleport');
        toast({ ok: true }, AT('atlas.t.tp_armed', 'Click the map to teleport there.'));
    });
    $('btnWaypoint').addEventListener('click', () => {
        const c = AtlasMap.centre();
        post('waypoint', { x: c.x, y: c.y });
        toast({ ok: true }, AT('atlas.t.waypoint', 'Waypoint set at {x}, {y}.', { x: Math.round(c.x), y: Math.round(c.y) }));
    });

    // edit
    $('btnSetN').addEventListener('click', () => {
        const n = parseInt($('editN').value, 10);
        editCell({ n }, AT('atlas.e.setn', "Set this cell's COUNT to <b>{n}</b>.\n\nThe server caps a single cell well below anything silly, and it will tell you what it actually set.", { n: fmt(n) }));
    });
    $('btnSetBase').addEventListener('click', () => {
        const b = parseInt($('editBase').value, 10);
        editCell({ baseline: b }, AT('atlas.e.setbase', "Set this cell's BASELINE to <b>{n}</b>.\n\nBaseline is what regrowth aims at. Changing it does not change what is standing there now.", { n: fmt(b) }));
    });
    $('btnLock').addEventListener('click', () =>
        editCell({ lock: true }, AT('atlas.e.lock', 'LOCK this cell.\n\nRegrowth and migration will both skip it until it is unlocked. Nothing but a staff edit will change its count again.')));
    $('btnUnlock').addEventListener('click', () =>
        editCell({ lock: false }, AT('atlas.e.unlock', 'UNLOCK this cell and hand it back to the simulation.')));
    $('btnClear').addEventListener('click', () =>
        editCell({ clear: true }, AT('atlas.e.clear', 'CLEAR this cell.\n\nIts count goes to zero and the grace period starts, so it stays empty for a while before regrowth touches it.\n\nIt does <b>not</b> despawn zombies that are already live peds in front of a player - those belong to the registry, and yanking them here would leave a ped alive with nothing behind it.')));

    // repopulate
    $('btnRectMode').addEventListener('click', e => {
        const on = !e.target.classList.contains('is-on');
        e.target.classList.toggle('is-on', on);
        AtlasMap.armRect(on);
    });
    $('btnRepop').addEventListener('click', doRepopulate);

    // observer
    $('obsRadius').addEventListener('input', e => {
        ST.obsRadius = parseInt(e.target.value, 10);
        $('obsRadiusOut').textContent = ST.obsRadius + 'm';
    });
    $('btnObserveCentre').addEventListener('click', () => {
        const c = AtlasMap.centre();
        registerObserver(c.x, c.y);
    });
    $('btnObservePick').addEventListener('click', () => {
        AtlasMap.pick(true);
        $('obsState').textContent = AT('atlas.o.pick', 'Click a point on the map to watch it.');
    });
    $('btnObserveClear').addEventListener('click', clearObserver);

    // config
    $('btnCfgRead').addEventListener('click', loadConfig);
    $('btnCfgApply').addEventListener('click', applyConfig);
}

// 12. Open / close and the Lua message pump

// 11b. The map image card

// Status line under the opacity slider, fed by map.js's onMapState hook so it shows what the renderer is doing
function renderMapState(state, note) {
    const box = $('mapState');
    if (!box) return;
    const words = {
        none: AT('atlas.m.none', 'No map image configured - plain plane.'),
        loading: AT('atlas.m.loading', 'Loading the map image...'),
        ok: AT('atlas.m.ok', 'Map image drawn under the data, aligned by calibration.json.'),
        failed: AT('atlas.m.failed', 'MAP IMAGE FAILED TO LOAD - showing the plain plane.'),
        uncalibrated: AT('atlas.m.uncal', 'No calibration - image NOT drawn, it would be misaligned.'),
    };
    box.textContent = (words[state] || state) + (note ? ' ' + note : '');
    box.classList.toggle('note--warn', state !== 'ok' && state !== 'loading');
}

// Called on open with what the host found: { url, calib, note } or { error }
function applyMap(map) {
    if (!map || !map.url) {
        AtlasMap.setMapImage(null, null, (map && map.error) ? map.error : '');
        return;
    }
    AtlasMap.setMapImage(map.url, map.calib || null, map.note || '');
}

function doClose() {
    // The web page has nothing to close; ESC only dismisses the modal (see wire()).
    if (HOST.caps && HOST.caps.close === false) return;

    // Tell Lua: it owns NUI focus and the server-side observer, so hiding silently would leave no mouse focus and a stale observer
    post('close', {});
    onClosed();
}

function onClosed() {
    ST.open = false;
    clearTimeout(ST.pollTimer);
    $('atlas').hidden = true;
    // Local mirror only: Lua clears the real one.
    ST.observer = null;
    AtlasMap.setObserver(null);
    $('chipObs').hidden = true;
}

function onOpen(msg) {
    ST.cfg = msg.cfg || {};
    ST.pollMs = ST.cfg.pollMs || 500;
    ST.obsRadius = ST.cfg.observerRadius || 300;

    $('atlas').hidden = false;
    ST.open = true;
    ST.misses = 0;

    // Starts stale: nothing has answered yet. The first successful poll lowers the banner.
    ST.stale = true;
    AtlasMap.setStale(true);
    setStale(AT('atlas.stale_wait', 'WAITING FOR THE FIRST SNAPSHOT...'));
    $('simState').textContent = AT('atlas.connecting', 'connecting...');

    AtlasMap.setWorld(msg.world, msg.points || [],
        { min: ST.cfg.minSpanMetres, max: ST.cfg.maxSpanMetres });

    const pm = $('pollMs');
    pm.min = ST.cfg.pollMsMin || 150;
    pm.max = ST.cfg.pollMsMax || 5000;
    pm.value = ST.pollMs;
    $('pollMsOut').textContent = ST.pollMs + 'ms';

    const or = $('obsRadius');
    or.min = ST.cfg.observerRadiusMin || 50;
    or.max = ST.cfg.observerRadiusMax || 1200;
    or.value = ST.obsRadius;
    $('obsRadiusOut').textContent = ST.obsRadius + 'm';
    renderObsNote();

    applyMap(msg.map);

    if (msg.me) {
        ST.me = msg.me;
        AtlasMap.setMe(msg.me);
        AtlasMap.centreOn(msg.me.x, msg.me.y, ST.cfg.openSpanMetres || 3000);
    } else {
        AtlasMap.fitWorld();
    }

    poll();
    loadConfig();
}

window.addEventListener('message', ev => {
    const m = ev.data || {};
    switch (m.action) {
        case 'open':  onOpen(m); break;
        case 'close': onClosed(); break;
        case 'map':   applyMap(m.map); break;   // recalibration (web panel)
        case 'me':
            ST.me = { x: m.x, y: m.y, h: m.h };
            AtlasMap.setMe(ST.me);
            break;
        case 'observerState':
            // A refresh landed or failed
            if (m.ok) {
                ST.observer = m.observer;
                AtlasMap.setObserver(m.observer);
                $('obsState').textContent = AT('atlas.o.refreshed', 'Refreshed at {t} - watching {x}, {y} at {r}m.',
                    { t: new Date().toLocaleTimeString('en-GB'), x: Math.round(m.observer.x), y: Math.round(m.observer.y), r: Math.round(m.observer.radius) });
            } else {
                $('obsState').textContent = AT('atlas.o.refreshfail', 'REFRESH FAILED: {err} - the region will stop being watched when its 300s expires.',
                    { err: (m.res && m.res.error) || AT('atlas.no_answer', 'no answer') });
            }
            break;
    }
});

// The observer note carries a live number, so it is rendered here instead of through data-i18n.
function renderObsNote() {
    const n = $('obsNote2');
    if (n) n.innerHTML = AT('atlas.obs_note2',
        'It is <b>time limited on purpose</b>: the server gives it <b>300 seconds</b> and this panel re-registers it about every <span id="obsRefreshEvery">{s}</span>s while the atlas is open. <b>Closing the atlas clears it.</b> One observer per staff member - registering a new one replaces the old.',
        { s: (ST.cfg && ST.cfg.observerRefreshSeconds) || 100 });
}

// Re-render dynamic text when the language changes.
if (window.BSI18n && window.BSI18n.onChange) {
    window.BSI18n.onChange(() => {
        buildLayers(); buildLegend(); renderObsNote(); markDirty();
        if (ST.lastSnapshot) { renderStats(ST.lastSnapshot); renderSampling(ST.lastSnapshot); }
        if (ST.inspect) renderInspect(ST.inspect);
        if (ST.simConfig) renderConfig();
    });
}

// World cars: polled slowly, only while the layer is on and the atlas is open.
let carsBusy = false;
setInterval(async () => {
    if (!ST.open || !AtlasMap.layers.cars || carsBusy) return;
    carsBusy = true;
    try {
        const res = await call('bs_atlas:cars', {});
        if (res && res.ok) AtlasMap.setCars(Array.isArray(res.cars) ? res.cars : Object.values(res.cars || {}));
        else AtlasMap.setCars([]);
    } finally { carsBusy = false; }
}, 4000);

// 13. Boot

AtlasMap.init($('map'), {
    onCellClick: (cx, cy) => inspectCell(cx, cy),
    onCarClick:  car => teleportTo(car.x + 4.0, car.y),
    onRect:      onRect,
    onPick:      (x, y, kind) => (kind === 'teleport' ? teleportTo(x, y) : registerObserver(x, y)),
    onCursor:    (x, y) => {
        $('cursorPos').textContent = `${Math.round(x)}, ${Math.round(y)}`;
    },
    onMapState: renderMapState,
    onView: () => {
        const span = Math.round(AtlasMap.spanMetres());
        const c = AtlasMap.centre();
        $('viewReadout').textContent = AT('atlas.v.centre', 'Centre {x}, {y} · {span}m across (about {cells} cells wide).',
            { x: Math.round(c.x), y: Math.round(c.y), span: fmt(span), cells: Math.round(span / 50) });
    },
});

buildLayers();
buildLegend();
wire();

// Map opacity. Same slider on both hosts.
(function wireMapCard() {
    const r = $('mapOpacity');
    if (!r) return;
    const sync = () => {
        AtlasMap.setMapOpacity(Number(r.value) / 100);
        $('mapOpacityOut').textContent = r.value + '%';
    };
    r.addEventListener('input', sync);
    sync();
})();

// Hide what the host cannot do (see HOST at the top).
(function applyCaps() {
    const caps = HOST.caps || {};
    const hide = id => { const n = $(id); if (n) n.hidden = true; };
    if (caps.me === false) hide('btnFindMe');
    if (caps.waypoint === false) hide('btnWaypoint');
    if (caps.waypoint === false) hide('btnTeleport');
    if (caps.close === false) hide('btnClose');
    document.querySelectorAll('[data-host]').forEach(n => {
        n.hidden = n.dataset.host !== HOST.kind;
    });
})();

// Survey - drop ZAtlas points where you stand (server op 'survey').
function svArgs(action) {
    const a = { action, id: ($('svId').value || '').trim() };
    const d = parseFloat($('svD').value); if (!isNaN(d)) a.d = d;
    a.t = $('svT').value;
    const n = ($('svN').value || '').split(',').map(x => parseInt(x, 10)).filter(x => !isNaN(x));
    if (n.length) a.n = n;
    return a;
}
function svRender(res) {
    if (!res || !res.ok) { $('svState').textContent = AT('atlas.sv.refused', 'Refused: {err}', { err: (res && res.error) || AT('atlas.no_answer', 'no answer') }); return; }
    const pts = res.points || [];
    $('svState').textContent = AT('atlas.sv.points', '{n} points', { n: pts.filter(p => !p.removed).length }) + (res.dirty ? ' - ' + AT('atlas.sv.dirty', 'UNSAVED CHANGES') : '') + (res.note ? ' - ' + res.note : '');
    const box = $('svList'); box.innerHTML = '';
    pts.forEach(p => {
        const row = el('div', 'lyr' + (p.removed ? ' is-off' : ''));
        row.title = AT('atlas.sv.click', 'Click to load into the form');
        row.append(el('span', 'lyr__n', `${p.i}. ${p.id}${p.surveyed ? ' *' : ''}`),
                   el('span', 'lyr__c', `${p.t || ''} d${(p.d || 0).toFixed ? (p.d || 0).toFixed(1) : p.d}`));
        row.addEventListener('click', () => {
            $('svId').value = p.id; $('svD').value = p.d || 0; $('svT').value = p.t || 'town';
            $('svN').value = (p.n || []).join(',');
            if (typeof AtlasMap !== "undefined") AtlasMap.centreOn(p.x, p.y, 900);
        });
        box.appendChild(row);
    });
}
async function svDo(action) {
    if (action !== 'list' && action !== 'save' && !svArgs(action).id) { $('svState').textContent = AT('atlas.sv.needid', 'Type a point id first.'); return; }
    svRender(await call('zombies:atlas:survey', action === 'list' || action === 'save' ? { action } : svArgs(action)));
}
(function wireSurvey() {
    const on = (id, a) => { const b = $(id); if (b) b.addEventListener('click', () => svDo(a)); };
    on('btnSvAdd', 'add'); on('btnSvMove', 'move'); on('btnSvSet', 'set');
    on('btnSvRemove', 'remove'); on('btnSvSave', 'save');
    document.querySelectorAll('.tab').forEach(b => {
        if (b.dataset.tab === 'survey') b.addEventListener('click', () => svDo('list'));
    });
})();

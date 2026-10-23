// hud.js - renders the survival cluster and XP strip. Holds presentational state only; all numbers come from Lua.

const hudEl   = document.getElementById('hud');
const barsEl  = document.getElementById('hud-bars');
const xpEl    = document.getElementById('xpbar');
const popsEl  = document.getElementById('xp-pops');

let BARS = [];
let MINIMAL = [];
let SETTINGS = {};
let XPCFG = {};
let barNodes = {};
let idleTimer = null;

// Settings

BS.on('settings', ({ settings = {}, theme = {}, bars = [], minimal = [], xp = {}, paletteVars = false }) => {
    SETTINGS = settings;
    BARS = bars;
    MINIMAL = minimal;
    XPCFG = xp;

    const root = document.documentElement.style;
    const map = {
        accent: '--bs-accent', accentGood: '--bs-good', accentDanger: '--bs-danger',
        accentWarn: '--bs-warn', blood: '--bs-blood', background: '--bs-bg',
        text: '--bs-text', textMuted: '--bs-text-muted', radius: '--bs-radius',
        fontMono: '--bs-font', fontSerif: '--bs-serif',
    };
    for (const [key, cssVar] of Object.entries(map)) {
        if (theme[key]) root.setProperty(cssVar, theme[key]);
    }

    // Menu palette wins over the config theme for the colours it sets.
    if (window.BSPalette) BSPalette.apply(paletteVars || null, settings.menuPalette);

    root.setProperty('--bs-hud-opacity', String(settings.hudOpacity ?? 0.72));
    root.setProperty('--bs-xp-opacity',  String(settings.xpOpacity ?? 0.55));
    root.setProperty('--bs-xp-width',    `${xp.width ?? 46}%`);

    hudEl.dataset.anchor = settings.hudAnchor || 'bottom-left';
    hudEl.dataset.mode   = settings.hudMode || 'full';
    hudEl.dataset.style  = settings.hudStyle || 'classic';
    xpEl.dataset.position = settings.xpPosition || 'top';

    // The quick bar and XP bar share the bottom of the screen; the bar lifts itself clear only when it has to.
    if (hotbarEl) {
        hotbarEl.dataset.xp = xpEl.dataset.position;
    }
    xpEl.dataset.disabled = xp.enabled === false ? '1' : '0';
    xpEl.classList.toggle('hidden', xp.enabled === false);

    buildBars();
});

// Bars

function visibleBars() {
    if ((SETTINGS.hudMode || 'full') !== 'minimal') return BARS.filter((b) => b.show !== false);
    return BARS.filter((b) => b.show !== false && MINIMAL.includes(b.key));
}

// Bar names come from config in English; the locale key wins when it exists.
function barLabel(bar) {
    const s = t('ui.bar_' + bar.key, { fallback: bar.label || bar.key });
    return String(s).toLocaleUpperCase((window.BSI18n && BSI18n.lang()) || 'en');
}

// Language change: relabel in place, so the values stay put until the next tick.
if (window.BSI18n) {
    BSI18n.onChange(() => {
        for (const node of Object.values(barNodes)) {
            const el = node.row.querySelector('.hud__bar-label');
            if (el) el.textContent = barLabel(node.cfg);
        }
    });
}

function buildBars() {
    barsEl.innerHTML = '';
    barNodes = {};

    for (const bar of visibleBars()) {
        const row = document.createElement('div');
        row.className = 'hud__bar';
        row.innerHTML = `
            ${BS.icon(bar.icon, 'hud__bar-icon')}
            <span class="hud__bar-label">${barLabel(bar)}</span>
            <div class="hud__bar-track">
                <div class="hud__bar-fill" style="background-color:${bar.color}"></div>
            </div>
            <span class="hud__bar-value">0</span>`;
        barsEl.appendChild(row);

        barNodes[bar.key] = {
            cfg: bar,
            row,
            fill: row.querySelector('.hud__bar-fill'),
            value: row.querySelector('.hud__bar-value'),
        };
    }
}

// The XP strip lives outside the HUD element (its position is a player setting), so both are hidden from the same message.
BS.on('hud', ({ visible }) => {
    hudEl.classList.toggle('hidden', !visible);

    // Never re-show a bar the player turned off in settings.
    const xpOff = xpEl.dataset.disabled === '1';
    xpEl.classList.toggle('hidden', !visible || xpOff);
});

BS.on('hudData', ({ data }) => {
    if (!data) return;

    for (const [key, node] of Object.entries(barNodes)) {
        const raw = Math.max(0, Math.min(100, Math.round(data[key] ?? 0)));
        node.fill.style.width = `${raw}%`;
        // Every bar reads as a percent so the columns line up; real HP (e.g. 190/190) lives in the tooltip.
        node.value.textContent = `${raw}%`;
        node.row.style.setProperty('--bs-fill', `${raw}%`);
        if (key === 'health' && data.healthMax > 0) {
            node.row.title = `${Math.round(data.healthNow)}/${Math.round(data.healthMax)} HP`;
        }

        // Infection is inverted: a HIGH value is the emergency.
        const cfg = node.cfg;
        const critical = cfg.inverted
            ? raw >= (cfg.critical ?? 101)
            : raw <= (cfg.critical ?? -1);
        node.row.classList.toggle('is-critical', critical);

        // Armour and infection vanish at zero rather than sitting there empty.
        const hide = (cfg.hideAtZero && raw === 0) ||
                     (SETTINGS.hideWhenFull && !cfg.inverted && raw >= 100);
        node.row.classList.toggle('is-hidden', !!hide);
    }

    document.getElementById('hud-name').textContent = data.name || '';
    document.getElementById('hud-class').textContent = data.class || '';
    document.getElementById('hud-cash').textContent = BS.money(data.cash);

    setXP(data.xp, data.xpToNext, data.level);
});

// XP bar

let lastPct = 0;

function setXP(xp, toNext, level) {
    const pct = toNext ? Math.max(0, Math.min(100, (xp / toNext) * 100)) : 0;
    document.getElementById('xp-fill').style.width = `${pct}%`;
    document.getElementById('xp-edge').style.left = `${pct}%`;
    document.getElementById('xp-level').textContent = level ?? 1;
    document.getElementById('xp-value').textContent =
        `${Number(xp || 0).toLocaleString('en-US')} / ${Number(toNext || 0).toLocaleString('en-US')}`;
    lastPct = pct;
}

// Fires on every XP award: surges the earned slice and floats the number.
BS.on('xpGain', ({ amount, xp, xpToNext, level }) => {
    const before = lastPct;
    setXP(xp, xpToNext, level);
    const after = lastPct;

    // Levelling wraps the bar round, so only surge when it moved right.
    if (after > before) {
        const surge = document.getElementById('xp-gain');
        surge.style.left = `${before}%`;
        surge.style.width = `${after - before}%`;
        surge.classList.remove('is-live');
        void surge.offsetWidth;             // restart the animation
        surge.classList.add('is-live');

        const edge = document.getElementById('xp-edge');
        edge.classList.remove('is-pulsing');
        void edge.offsetWidth;
        edge.classList.add('is-pulsing');
    }

    if (XPCFG.popups === false) return;

    const pop = document.createElement('div');
    pop.className = 'xppop' + (amount >= 100 ? ' xppop--big' : '');
    pop.textContent = `+${Number(amount).toLocaleString('en-US')} ${t('ui.xp', { fallback: 'XP' })}`;
    popsEl.appendChild(pop);
    setTimeout(() => pop.remove(), XPCFG.popupDuration || 2200);

    wake();
});

// Level-up card: shows the old level briefly, then swaps to the new one. `from` is the level left, `level` the one reached. CSS delays both number animations by the same 380ms the Lua side waits (cl_levelup.lua sequences the audio). `skill` = skill-tree level: smaller, shorter, no music.
BS.on('levelUp', ({ level, from, skill }) => {
    const el = document.getElementById('levelup');
    const fromEl = document.getElementById('levelup-from');
    const toEl = document.getElementById('levelup-value');

    // Fall back to level 1 if `from` is missing.
    fromEl.textContent = (typeof from === 'number' && from > 0) ? from : Math.max(0, level - 1);
    toEl.textContent = level;

    el.classList.toggle('is-skill', skill === true);
    el.classList.remove('hidden');

    // Restart every animation on the card. `animation: none` on the parent does not retrigger children, so each element is reset and offsetWidth is read in between to force a reflow.
    [el, fromEl, toEl].forEach((node) => {
        node.style.animation = 'none';
        void node.offsetWidth;
        node.style.animation = '';
    });

    const hold = skill ? 3000 : 5200;
    clearTimeout(el._hideTimer);
    el._hideTimer = setTimeout(() => el.classList.add('hidden'), hold);

    // The chevron spins once on a level.
    xpEl.classList.add('is-levelup');
    setTimeout(() => xpEl.classList.remove('is-levelup'), 700);

    wake();
});

// Optional idle fade: dims the bar when nothing has happened for a while.
function wake() {
    if (!XPCFG.idleFade) return;
    xpEl.classList.remove('is-idle');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => xpEl.classList.add('is-idle'), XPCFG.idleFade);
}

// Hotbar
// Five slots driven by bs_inventory. Drawn here because it must be visible while the bag is closed.

const hotbarEl = document.getElementById('hotbar');

BS.on('hotbar', ({ slots, visible }) => {
    if (!hotbarEl) return;

    const list = slots || {};
    let html = '';

    for (let i = 1; i <= 5; i++) {
        const slot = list[i] || list[String(i)];

        const bound = !!slot;
        const empty = bound && slot.empty;

        const icon = (bound && typeof BSIcons !== 'undefined')
            ? BSIcons.get(slot.item, slot.category) : '';

        html += `<div class="hotbar__slot${bound ? ' is-bound' : ''}${empty ? ' is-empty' : ''}"
                      data-slot="${i}" title="${bound ? String(slot.label || '').replace(/[&<>"']/g, '') : ''}">
                    <span class="hotbar__key">${i}</span>
                    ${bound ? `<span class="hotbar__icon">${icon}</span>` : ''}
                    ${bound ? `<span class="hotbar__count">${slot.capacity
                        ? Math.round(((slot.fill || 0) / slot.capacity) * 100) + '%'
                        : (slot.count ?? 0)}</span>` : ''}
                 </div>`;
    }

    hotbarEl.innerHTML = html;

    // Always five slots. Empty slots show the keys and right-clicking an item in the bag offers to fill one. Hidden only when a menu is up.
    hotbarEl.classList.toggle('hidden', visible === false);
});

// Map frame
// Follows the radar's visibility. Pure overlay around the map, so nothing else to do.

const mapEl = document.getElementById('mapframe');

BS.on('mapframe', ({ show }) => {
    if (!mapEl) return;
    mapEl.classList.toggle('hidden', !show);
});

// Field map
// The M-key full map; cl_fieldmap.lua moves a live minimap behind this frame, so only show/hide is needed.

const fieldmapEl = document.getElementById('fieldmap');

BS.on('fieldmap', ({ show }) => {
    if (!fieldmapEl) return;
    fieldmapEl.classList.toggle('hidden', !show);
});

// Dash HUD
// Speed, RPM, gear, heading, status icons, fuel and condition while driving, as a compact technical panel. bs_vehicles (cl_hud.lua) sends one message per frame while driving; this only draws what it is given.

const dashEl = document.getElementById('dashhud');
const dashCtx = dashEl && dashEl.getContext('2d');

const DASH = {
    ink:    '#d6cea8',
    dim:    'rgba(214, 206, 168, 0.35)',
    accent: '#c8763a',
    good:   '#a89e60',
    worn:   '#d09e40',
    poor:   '#c46c30',
    gone:   '#a8342c',
};
const DASH_COLOR = { GOOD: DASH.good, WORN: DASH.worn, POOR: DASH.poor, GONE: DASH.gone };
// bs_vehicles sends GOOD/WORN/POOR/GONE as codes; show them translated.
function dashCond(code) {
    if (!code) return '--';
    return t('ui.dash_' + String(code).toLowerCase(), { fallback: code });
}

// Read the HUD font once; getComputedStyle on every line forces a style recalculation.
let DASH_FONT = null;
function dashFont(weight, px) {
    if (DASH_FONT === null) {
        DASH_FONT = (getComputedStyle(document.documentElement)
            .getPropertyValue('--bs-font') || '').trim() || 'monospace';
    }
    return `${weight} ${Math.round(px)}px ${DASH_FONT}`;
}

// Slim segmented bar. Ticks every 'major' segments make it countable at a glance.
function dashBar(x, y, w, h, frac, segs, colorAt, major) {
    const gap = Math.max(1, w * 0.006);
    const segW = (w - gap * (segs - 1)) / segs;
    const filled = Math.max(0, Math.min(1, frac)) * segs;
    for (let i = 0; i < segs; i++) {
        const sx = x + i * (segW + gap);
        dashCtx.fillStyle = 'rgba(20, 18, 14, 0.72)';
        dashCtx.fillRect(sx, y, segW, h);
        const fill = Math.max(0, Math.min(1, filled - i));
        if (fill > 0) {
            dashCtx.fillStyle = colorAt(i / segs);
            dashCtx.fillRect(sx, y, segW * fill, h);
        }
        if (major && i % major === 0) {
            dashCtx.fillStyle = DASH.dim;
            dashCtx.fillRect(sx, y + h + 2, 1.5, h * 0.6);
        }
    }
}

// Percent to colour: amber under 35, red under 15. Same ladder for fuel, engine and hull.
function dashLevelColor(pct) {
    return pct <= 15 ? DASH.gone : pct <= 35 ? DASH.poor : pct < 60 ? DASH.worn : DASH.good;
}

// Label left, value right, slim bar under.
function dashGauge(x, y, w, label, pct, valueText, color) {
    dashCtx.textBaseline = 'alphabetic';
    dashCtx.font = dashFont(600, w * 0.06);
    dashCtx.textAlign = 'left';
    dashCtx.fillStyle = DASH.dim;
    dashCtx.fillText(label, x, y);
    dashCtx.font = dashFont(700, w * 0.062);
    dashCtx.textAlign = 'right';
    dashCtx.fillStyle = color;
    dashCtx.fillText(valueText, x + w, y);
    dashBar(x, y + w * 0.03, w, w * 0.026, pct / 100, 20, () => color, 0);
}

// Tiny line icons for the status row. on = lit, warn = red.
function dashIcon(kind, x, y, s, color) {
    dashCtx.strokeStyle = color;
    dashCtx.fillStyle = color;
    dashCtx.lineWidth = Math.max(1.5, s * 0.1);
    dashCtx.lineCap = 'round';
    dashCtx.beginPath();
    if (kind === 'engine') {
        // Power symbol.
        dashCtx.arc(x, y, s * 0.42, -Math.PI * 0.32, Math.PI * 1.32);
        dashCtx.moveTo(x, y - s * 0.55);
        dashCtx.lineTo(x, y - s * 0.05);
    } else if (kind === 'lights') {
        // Headlamp: half disc with three beams.
        dashCtx.arc(x - s * 0.15, y, s * 0.32, Math.PI * 0.5, Math.PI * 1.5);
        dashCtx.closePath();
        for (let i = -1; i <= 1; i++) {
            dashCtx.moveTo(x + s * 0.1, y + i * s * 0.25);
            dashCtx.lineTo(x + s * 0.5, y + i * s * 0.25);
        }
    } else if (kind === 'lock') {
        dashCtx.rect(x - s * 0.35, y - s * 0.05, s * 0.7, s * 0.5);
        dashCtx.moveTo(x - s * 0.2, y - s * 0.05);
        dashCtx.arc(x, y - s * 0.2, s * 0.2, Math.PI, 0);
        dashCtx.lineTo(x + s * 0.2, y - s * 0.05);
    }
    dashCtx.stroke();
}

// Compass letters come from the locale (ui.dash_compass), split once per language.
let dashCompassSrc = null, dashCompass = [];
function dashCardinal(deg) {
    const src = t('ui.dash_compass', { fallback: 'N,NE,E,SE,S,SW,W,NW' });
    if (src !== dashCompassSrc) { dashCompassSrc = src; dashCompass = src.split(','); }
    return dashCompass[Math.round(deg / 45) % 8] || '';
}

// Sweeps from 135deg to 405deg: a 3/4 ring open at the bottom, like a real tachometer.
function dashArc(cx, cy, r, frac, color, width, trackColor) {
    const start = Math.PI * 0.75;
    const sweep = Math.PI * 1.5;
    frac = Math.max(0, Math.min(1, frac));

    dashCtx.lineCap = 'round';
    dashCtx.lineWidth = width;

    dashCtx.strokeStyle = trackColor || 'rgba(20, 18, 14, 0.7)';
    dashCtx.beginPath();
    dashCtx.arc(cx, cy, r, start, start + sweep);
    dashCtx.stroke();

    if (frac > 0.003) {
        dashCtx.strokeStyle = color;
        dashCtx.beginPath();
        dashCtx.arc(cx, cy, r, start, start + sweep * frac);
        dashCtx.stroke();
    }
}

// One readout row: label left, value right, optional segmented bar under it.
function dashRow(x, y, w, label, value, valueColor, frac, barColor) {
    dashCtx.textBaseline = 'alphabetic';

    dashCtx.font = dashFont(600, w * 0.055);
    dashCtx.textAlign = 'left';
    dashCtx.fillStyle = DASH.dim;
    dashCtx.fillText(label, x, y);

    dashCtx.font = dashFont(700, w * 0.075);
    dashCtx.textAlign = 'right';
    dashCtx.fillStyle = valueColor || DASH.ink;
    dashCtx.fillText(value, x + w, y);

    if (frac === undefined) return;

    // Segmented bar, matching the zombie health and survival bars. Countable notches read better than a length.
    const segs = 12;
    const gap = w * 0.008;
    const segW = (w - gap * (segs - 1)) / segs;
    const barY = y + w * 0.035;
    const barH = w * 0.022;

    const filled = Math.max(0, Math.min(1, frac)) * segs;
    for (let i = 0; i < segs; i++) {
        const fill = Math.max(0, Math.min(1, filled - i));
        dashCtx.fillStyle = 'rgba(20, 18, 14, 0.72)';
        dashCtx.fillRect(x + i * (segW + gap), barY, segW, barH);
        if (fill > 0) {
            dashCtx.fillStyle = barColor || DASH.good;
            dashCtx.fillRect(x + i * (segW + gap), barY, segW * fill, barH);
        }
    }
}

// Dash styles. The player picks one in the inventory Settings tab; bs_vehicles sends it as data.style.
// Each style draws the same facts its own way. All are plain fills and strokes, no shadows or filters, so a frame stays cheap.

// Field: the technical panel (default).
function dashDrawField(data, W, H) {

    // Layout, top to bottom: heading + status icons, gear + big speed, RPM bar, then FUEL / ENGINE / HULL gauges.
    dashCtx.fillStyle = 'rgba(14, 13, 10, 0.5)';
    dashCtx.fillRect(0, 0, W, H);
    dashCtx.fillStyle = DASH.accent;
    dashCtx.fillRect(0, 0, W, 3);

    const pad = W * 0.07;
    const inner = W - pad * 2;

    // Heading. GTA heading turns counter-clockwise, so flip it for a compass.
    const hdg = ((360 - (data.heading || 0)) % 360 + 360) % 360;
    dashCtx.textBaseline = 'middle';
    dashCtx.textAlign = 'left';
    dashCtx.font = dashFont(700, W * 0.075);
    dashCtx.fillStyle = DASH.ink;
    const card = dashCardinal(hdg);
    dashCtx.fillText(card, pad, H * 0.075);
    const cardW = dashCtx.measureText(card + ' ').width;
    dashCtx.font = dashFont(600, W * 0.06);
    dashCtx.fillStyle = DASH.dim;
    dashCtx.fillText(String(Math.round(hdg) % 360).padStart(3, '0') + '°', pad + cardW, H * 0.075);

    // Status icons, right aligned: engine (red when off), lights (lit when on, accent on high beams), lock.
    const is = W * 0.075, iy = H * 0.075;
    let ix = W - pad - is * 0.5;
    dashIcon('lock', ix, iy, is, data.locked ? DASH.worn : DASH.dim);
    ix -= is * 1.6;
    dashIcon('lights', ix, iy, is, data.lights === 2 ? DASH.accent : data.lights ? DASH.ink : DASH.dim);
    ix -= is * 1.6;
    dashIcon('engine', ix, iy, is, data.engineOn === false ? DASH.gone : DASH.dim);

    // Gear box on the left.
    const gx = pad, gy = H * 0.15, gs = W * 0.2;
    dashCtx.strokeStyle = DASH.dim;
    dashCtx.lineWidth = 1.5;
    dashCtx.strokeRect(gx, gy, gs, gs);
    dashCtx.textAlign = 'center';
    dashCtx.font = dashFont(700, gs * 0.6);
    dashCtx.fillStyle = data.gear === 0 ? DASH.worn : DASH.ink;
    dashCtx.fillText(data.gear === 0 ? 'R' : String(data.gear ?? '-'), gx + gs / 2, gy + gs / 2 + 2);

    // Speed: large, right aligned so digits do not jump around, padded to 3 places with dim zeros.
    const speed = Math.max(0, Math.min(999, Math.round(data.speed || 0)));
    const digits = String(speed);
    const ghost = '000'.slice(digits.length);
    dashCtx.textAlign = 'right';
    dashCtx.textBaseline = 'alphabetic';
    dashCtx.font = dashFont(700, W * 0.3);
    const sy = gy + gs;
    dashCtx.fillStyle = DASH.ink;
    dashCtx.fillText(digits, W - pad, sy);
    if (ghost) {
        const dw = dashCtx.measureText(digits).width;
        dashCtx.fillStyle = 'rgba(214, 206, 168, 0.12)';
        dashCtx.fillText(ghost, W - pad - dw, sy);
    }
    dashCtx.font = dashFont(600, W * 0.055);
    dashCtx.fillStyle = DASH.accent;
    dashCtx.fillText(data.unit === 'mph' ? 'MPH' : 'KM/H', W - pad, sy + W * 0.075);

    // RPM: segmented bar with a tick every 4 segments; the last slice is the redline.
    const rpm = Math.max(0, Math.min(1, data.rpm || 0));
    const ry = H * 0.5;
    dashCtx.textAlign = 'left';
    dashCtx.font = dashFont(600, W * 0.055);
    dashCtx.fillStyle = DASH.dim;
    dashCtx.fillText(t('ui.dash_rpm', { fallback: 'RPM' }), pad, ry - W * 0.02);
    dashCtx.textAlign = 'right';
    dashCtx.fillStyle = rpm > 0.85 ? DASH.gone : DASH.ink;
    dashCtx.fillText(String(Math.round(rpm * 100)).padStart(3, ' ') + '%', W - pad, ry - W * 0.02);
    dashBar(pad, ry, inner, W * 0.04, rpm, 24, (f) => (f >= 0.83 ? DASH.gone : DASH.accent), 4);

    // Gauges. Engine and hull show the condition word plus the exact percent.
    let y = H * 0.66;
    const step = H * 0.12;
    const fuel = Math.max(0, Math.min(100, data.fuel ?? 60));
    const fc = dashLevelColor(fuel);
    dashGauge(pad, y, inner, t('ui.dash_fuel', { fallback: 'FUEL' }), fuel, `${Math.round(fuel)}%`, fc);

    y += step;
    const eng = Math.max(0, Math.min(100, data.enginePct ?? 100));
    const ec = DASH_COLOR[data.engine] || dashLevelColor(eng);
    dashGauge(pad, y, inner, t('ui.dash_engine', { fallback: 'ENGINE' }), eng, `${dashCond(data.engine)} ${Math.round(eng)}%`, ec);

    y += step;
    const hull = Math.max(0, Math.min(100, data.hullPct ?? 100));
    const hc = DASH_COLOR[data.hull] || dashLevelColor(hull);
    dashGauge(pad, y, inner, t('ui.dash_hull', { fallback: 'HULL' }), hull, `${dashCond(data.hull)} ${Math.round(hull)}%`, hc);
}

// Classic: the old round dial with the readout strip under it.
function dashDrawClassic(data, W, H) {
    // Layout: the dial holds the big speed number and the RPM sweep; facts (engine, hull, gear, fuel) sit below in a labelled readout strip.

    const cx = W / 2;
    const dialR = W * 0.47;
    const cy = dialR;                 // dial occupies the top square

    // Backing: dark, faintly warm disc.
    dashCtx.fillStyle = 'rgba(14, 13, 10, 0.5)';
    dashCtx.beginPath();
    dashCtx.arc(cx, cy, dialR, 0, Math.PI * 2);
    dashCtx.fill();

    // RPM: outer ring. Redlines the last slice.
    const rpm = Math.max(0, Math.min(1, data.rpm || 0));
    dashArc(cx, cy, W * 0.42, rpm, rpm > 0.85 ? DASH.gone : DASH.accent, W * 0.05);

    // Speed: big number at dial centre.
    dashCtx.fillStyle = DASH.ink;
    dashCtx.textAlign = 'center';
    dashCtx.textBaseline = 'alphabetic';
    dashCtx.font = dashFont(700, W * 0.26);
    dashCtx.fillText(String(Math.round(data.speed || 0)), cx, cy + W * 0.07);

    dashCtx.font = dashFont(600, W * 0.058);
    dashCtx.fillStyle = DASH.accent;
    dashCtx.fillText(data.unit === 'mph' ? 'MPH' : 'KM/H', cx, cy + W * 0.155);

    // Gear sits inside the dial near the bottom of the ring so it does not overlap the edge.
    const gy = cy + W * 0.30;
    dashCtx.strokeStyle = DASH.dim;
    dashCtx.lineWidth = 1.5;
    dashCtx.beginPath();
    dashCtx.arc(cx, gy, W * 0.068, 0, Math.PI * 2);
    dashCtx.stroke();
    dashCtx.fillStyle = DASH.ink;
    dashCtx.font = dashFont(700, W * 0.07);
    dashCtx.textBaseline = 'middle';
    dashCtx.fillText(data.gear === 0 ? 'R' : String(data.gear ?? '-'), cx, gy + 1);
    dashCtx.textBaseline = 'alphabetic';

    // The strip

    const pad = W * 0.09;
    const stripW = W - pad * 2;
    let y = dialR * 2 + W * 0.10;

    // Fuel gets a number as well as a bar, since it is what you plan around. Colour ladder matches other condition colours in the UI.
    const fuel = Math.max(0, Math.min(1, (data.fuel ?? 60) / 100));
    const fuelColor = fuel <= 0.15 ? DASH.gone : fuel <= 0.35 ? DASH.poor : DASH.good;
    dashRow(pad, y, stripW, t('ui.dash_fuel', { fallback: 'FUEL' }), `${Math.round(fuel * 100)}%`, fuelColor, fuel, fuelColor);

    y += W * 0.135;
    dashRow(pad, y, stripW, t('ui.dash_engine', { fallback: 'ENGINE' }), dashCond(data.engine),
        DASH_COLOR[data.engine] || DASH.ink);

    y += W * 0.10;
    dashRow(pad, y, stripW, t('ui.dash_hull', { fallback: 'HULL' }), dashCond(data.hull),
        DASH_COLOR[data.hull] || DASH.ink);
}

// Scrap: rusty analog speedo with a swinging needle and a small fuel dial.
const SCRAP = { plate: 'rgba(52, 34, 22, 0.78)', rim: '#7a4a2a', rust: '#a3592e', ink: '#e3cfa4', needle: '#d8452c', rivet: '#5c3a22' };
function dashDrawScrap(data, W, H) {
    const cx = W / 2, cy = W * 0.5, R = W * 0.46;
    const mph = data.unit === 'mph';
    const max = mph ? 120 : 200;
    const speed = Math.max(0, Math.min(max, data.speed || 0));
    const start = Math.PI * 0.75, sweep = Math.PI * 1.5;

    // face and rim
    dashCtx.fillStyle = SCRAP.plate;
    dashCtx.beginPath(); dashCtx.arc(cx, cy, R, 0, Math.PI * 2); dashCtx.fill();
    dashCtx.strokeStyle = SCRAP.rim; dashCtx.lineWidth = W * 0.03;
    dashCtx.beginPath(); dashCtx.arc(cx, cy, R - W * 0.015, 0, Math.PI * 2); dashCtx.stroke();
    // rust blotches on the rim, fixed spots so nothing flickers
    dashCtx.fillStyle = 'rgba(163, 89, 46, 0.55)';
    for (const a of [0.3, 1.9, 2.6, 4.1, 5.2]) {
        dashCtx.beginPath();
        dashCtx.arc(cx + Math.cos(a) * (R - W * 0.02), cy + Math.sin(a) * (R - W * 0.02), W * 0.025, 0, Math.PI * 2);
        dashCtx.fill();
    }

    // ticks and numbers
    dashCtx.strokeStyle = SCRAP.ink; dashCtx.fillStyle = SCRAP.ink;
    dashCtx.textAlign = 'center'; dashCtx.textBaseline = 'middle';
    dashCtx.font = dashFont(700, W * 0.055);
    const stepMinor = mph ? 5 : 10, stepMajor = mph ? 20 : 40;
    dashCtx.beginPath();
    for (let v = 0; v <= max; v += stepMinor) {
        const a = start + sweep * (v / max);
        const major = v % stepMajor === 0;
        const r1 = R * (major ? 0.78 : 0.84), r2 = R * 0.9;
        dashCtx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
        dashCtx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2);
        if (major) dashCtx.fillText(String(v), cx + Math.cos(a) * R * 0.64, cy + Math.sin(a) * R * 0.64);
    }
    dashCtx.lineWidth = 2; dashCtx.stroke();

    // redline band from the RPM, painted as a short arc near the top
    const rpm = Math.max(0, Math.min(1, data.rpm || 0));
    dashCtx.strokeStyle = rpm > 0.85 ? SCRAP.needle : 'rgba(216, 69, 44, 0.35)';
    dashCtx.lineWidth = W * 0.02;
    dashCtx.beginPath(); dashCtx.arc(cx, cy, R * 0.94, start, start + sweep * rpm); dashCtx.stroke();

    // needle
    const na = start + sweep * (speed / max);
    dashCtx.strokeStyle = SCRAP.needle; dashCtx.lineWidth = W * 0.018; dashCtx.lineCap = 'round';
    dashCtx.beginPath();
    dashCtx.moveTo(cx - Math.cos(na) * R * 0.12, cy - Math.sin(na) * R * 0.12);
    dashCtx.lineTo(cx + Math.cos(na) * R * 0.8, cy + Math.sin(na) * R * 0.8);
    dashCtx.stroke();
    dashCtx.fillStyle = SCRAP.rivet;
    dashCtx.beginPath(); dashCtx.arc(cx, cy, W * 0.045, 0, Math.PI * 2); dashCtx.fill();

    // odometer-style readout and gear
    dashCtx.fillStyle = 'rgba(15, 10, 6, 0.8)';
    dashCtx.fillRect(cx - W * 0.14, cy + R * 0.32, W * 0.28, W * 0.1);
    dashCtx.fillStyle = SCRAP.ink;
    dashCtx.font = dashFont(700, W * 0.075);
    dashCtx.fillText(String(Math.round(speed)).padStart(3, '0'), cx, cy + R * 0.32 + W * 0.05);
    dashCtx.font = dashFont(600, W * 0.045);
    dashCtx.fillStyle = SCRAP.rust;
    dashCtx.fillText((mph ? 'MPH' : 'KM/H') + '  ' + (data.gear === 0 ? 'R' : String(data.gear ?? '-')), cx, cy + R * 0.66);

    // fuel dial below: E to F, half circle
    const fy = W * 1.1, fr = W * 0.2;
    const fuel = Math.max(0, Math.min(100, data.fuel ?? 60)) / 100;
    dashCtx.fillStyle = SCRAP.plate;
    dashCtx.beginPath(); dashCtx.arc(W * 0.3, fy, fr, Math.PI, 0); dashCtx.closePath(); dashCtx.fill();
    dashCtx.strokeStyle = SCRAP.rim; dashCtx.lineWidth = 2; dashCtx.stroke();
    dashCtx.fillStyle = SCRAP.ink; dashCtx.font = dashFont(700, W * 0.045);
    dashCtx.fillText('E', W * 0.3 - fr * 0.75, fy - W * 0.025);
    dashCtx.fillText('F', W * 0.3 + fr * 0.75, fy - W * 0.025);
    const fa = Math.PI + Math.PI * fuel;
    dashCtx.strokeStyle = fuel <= 0.15 ? DASH.gone : SCRAP.needle; dashCtx.lineWidth = W * 0.012;
    dashCtx.beginPath(); dashCtx.moveTo(W * 0.3, fy);
    dashCtx.lineTo(W * 0.3 + Math.cos(fa) * fr * 0.85, fy + Math.sin(fa) * fr * 0.85); dashCtx.stroke();

    // engine and hull as stamped warning lamps
    const lamp = (x, y, label, code) => {
        const c = DASH_COLOR[code] || SCRAP.ink;
        dashCtx.fillStyle = 'rgba(15, 10, 6, 0.7)';
        dashCtx.fillRect(x, y, W * 0.36, W * 0.09);
        dashCtx.fillStyle = c;
        dashCtx.fillRect(x, y, W * 0.02, W * 0.09);
        dashCtx.textAlign = 'left'; dashCtx.font = dashFont(700, W * 0.045);
        dashCtx.fillText(label + ' ' + dashCond(code), x + W * 0.04, y + W * 0.047);
    };
    lamp(W * 0.56, fy - W * 0.2, t('ui.dash_engine', { fallback: 'ENGINE' }), data.engine);
    lamp(W * 0.56, fy - W * 0.08, t('ui.dash_hull', { fallback: 'HULL' }), data.hull);

    // rivets
    dashCtx.fillStyle = SCRAP.rivet;
    for (const [x, y] of [[W * 0.06, W * 0.06], [W * 0.94, W * 0.06], [W * 0.06, H - W * 0.06], [W * 0.94, H - W * 0.06]]) {
        dashCtx.beginPath(); dashCtx.arc(x, y, W * 0.018, 0, Math.PI * 2); dashCtx.fill();
    }
}

// Night Ops: green night-vision panel with segment digits and block bars.
const NV = { on: '#7dff8a', mid: 'rgba(125, 255, 138, 0.55)', off: 'rgba(125, 255, 138, 0.10)', bg: 'rgba(4, 18, 8, 0.72)', warn: '#e8ff6a' };
// Seven-segment digit: segments a..g as a bit mask per number.
const SEG7 = [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f];
function nvDigit(x, y, w, h, n) {
    const t2 = w * 0.18, mask = n === null ? 0 : SEG7[n];
    const segs = [
        [x + t2, y, w - t2 * 2, t2], [x + w - t2, y + t2, t2, h / 2 - t2 * 1.5], [x + w - t2, y + h / 2 + t2 / 2, t2, h / 2 - t2 * 1.5],
        [x + t2, y + h - t2, w - t2 * 2, t2], [x, y + h / 2 + t2 / 2, t2, h / 2 - t2 * 1.5], [x, y + t2, t2, h / 2 - t2 * 1.5],
        [x + t2, y + h / 2 - t2 / 2, w - t2 * 2, t2],
    ];
    for (let i = 0; i < 7; i++) {
        dashCtx.fillStyle = (mask >> i) & 1 ? NV.on : NV.off;
        const s = segs[i]; dashCtx.fillRect(s[0], s[1], s[2], s[3]);
    }
}
function dashDrawNight(data, W, H) {
    const pad = W * 0.07;
    dashCtx.fillStyle = NV.bg; dashCtx.fillRect(0, 0, W, H);
    // scanlines in one path
    dashCtx.strokeStyle = 'rgba(125, 255, 138, 0.05)'; dashCtx.lineWidth = 1;
    dashCtx.beginPath();
    for (let y = 2; y < H; y += 5) { dashCtx.moveTo(0, y); dashCtx.lineTo(W, y); }
    dashCtx.stroke();
    // corner brackets
    dashCtx.strokeStyle = NV.mid; dashCtx.lineWidth = 2; dashCtx.beginPath();
    const b = W * 0.08;
    dashCtx.moveTo(2, b); dashCtx.lineTo(2, 2); dashCtx.lineTo(b, 2);
    dashCtx.moveTo(W - b, 2); dashCtx.lineTo(W - 2, 2); dashCtx.lineTo(W - 2, b);
    dashCtx.moveTo(2, H - b); dashCtx.lineTo(2, H - 2); dashCtx.lineTo(b, H - 2);
    dashCtx.moveTo(W - b, H - 2); dashCtx.lineTo(W - 2, H - 2); dashCtx.lineTo(W - 2, H - b);
    dashCtx.stroke();

    // header: heading and gear
    const hdg = ((360 - (data.heading || 0)) % 360 + 360) % 360;
    dashCtx.textBaseline = 'middle'; dashCtx.textAlign = 'left';
    dashCtx.font = dashFont(700, W * 0.06); dashCtx.fillStyle = NV.mid;
    dashCtx.fillText(t('ui.dash_hdg', { fallback: 'HDG' }) + ' ' + String(Math.round(hdg) % 360).padStart(3, '0') + ' ' + dashCardinal(hdg), pad, H * 0.07);
    dashCtx.textAlign = 'right'; dashCtx.fillStyle = data.gear === 0 ? NV.warn : NV.on;
    dashCtx.fillText(t('ui.dash_gear', { fallback: 'GR' }) + ' ' + (data.gear === 0 ? 'R' : String(data.gear ?? '-')), W - pad, H * 0.07);

    // three big segment digits
    const speed = Math.max(0, Math.min(999, Math.round(data.speed || 0)));
    const str = String(speed).padStart(3, ' ');
    const dw = W * 0.2, dh = W * 0.36, gap = W * 0.05;
    let x = W - pad - (dw * 3 + gap * 2) - W * 0.02;
    for (let i = 0; i < 3; i++) {
        const c = str[i];
        nvDigit(x, H * 0.13, dw, dh, c === ' ' ? null : Number(c));
        x += dw + gap;
    }
    dashCtx.textAlign = 'right'; dashCtx.font = dashFont(600, W * 0.05); dashCtx.fillStyle = NV.mid;
    dashCtx.fillText(data.unit === 'mph' ? 'MPH' : 'KM/H', W - pad, H * 0.13 + dh + W * 0.05);

    // RPM as a ladder of blocks
    const rpm = Math.max(0, Math.min(1, data.rpm || 0));
    const n = 16, bw = (W - pad * 2) / n, by = H * 0.5;
    for (let i = 0; i < n; i++) {
        const lit = rpm * n > i;
        dashCtx.fillStyle = lit ? (i >= n - 3 ? NV.warn : NV.on) : NV.off;
        dashCtx.fillRect(pad + i * bw + 1, by - (i + 4) * W * 0.004, bw - 3, (i + 4) * W * 0.004 + W * 0.02);
    }

    // FUEL / ENG / HULL rows of blocks
    const row = (y, label, pct, code) => {
        dashCtx.textAlign = 'left'; dashCtx.font = dashFont(700, W * 0.05);
        const low = pct <= 15 || code === 'GONE' || code === 'POOR';
        dashCtx.fillStyle = low ? NV.warn : NV.mid;
        dashCtx.fillText(label, pad, y);
        dashCtx.textAlign = 'right';
        dashCtx.fillText(String(Math.round(pct)).padStart(3, '0'), W - pad, y);
        const segs = 10, x0 = pad + W * 0.22, w = W - pad * 2 - W * 0.36, sw = w / segs;
        for (let i = 0; i < segs; i++) {
            dashCtx.fillStyle = pct / 10 > i ? (low ? NV.warn : NV.on) : NV.off;
            dashCtx.fillRect(x0 + i * sw, y - W * 0.02, sw - 3, W * 0.04);
        }
    };
    row(H * 0.66, t('ui.dash_fuel', { fallback: 'FUEL' }), Math.max(0, Math.min(100, data.fuel ?? 60)), null);
    row(H * 0.78, t('ui.dash_engine', { fallback: 'ENGINE' }), Math.max(0, Math.min(100, data.enginePct ?? 100)), data.engine);
    row(H * 0.9, t('ui.dash_hull', { fallback: 'HULL' }), Math.max(0, Math.min(100, data.hullPct ?? 100)), data.hull);
}

// Tactical: one thin strip along the bottom, nothing else on screen.
function dashDrawTactical(data, W, H) {
    const h = W * 0.34, y0 = H - h;
    const pad = W * 0.05;
    // fading backing: one gradient, built once
    if (!dashDrawTactical.grad) {
        const g = dashCtx.createLinearGradient(0, 0, W, 0);
        g.addColorStop(0, 'rgba(10, 10, 8, 0)');
        g.addColorStop(0.15, 'rgba(10, 10, 8, 0.55)');
        g.addColorStop(0.85, 'rgba(10, 10, 8, 0.55)');
        g.addColorStop(1, 'rgba(10, 10, 8, 0)');
        dashDrawTactical.grad = g;
    }
    dashCtx.fillStyle = dashDrawTactical.grad;
    dashCtx.fillRect(0, y0, W, h);

    // RPM line on top of the strip
    const rpm = Math.max(0, Math.min(1, data.rpm || 0));
    dashCtx.fillStyle = 'rgba(214, 206, 168, 0.15)'; dashCtx.fillRect(pad, y0, W - pad * 2, 3);
    dashCtx.fillStyle = rpm > 0.85 ? DASH.gone : DASH.ink; dashCtx.fillRect(pad, y0, (W - pad * 2) * rpm, 3);

    // speed + unit + gear
    const speed = Math.max(0, Math.min(999, Math.round(data.speed || 0)));
    dashCtx.textBaseline = 'alphabetic'; dashCtx.textAlign = 'left';
    dashCtx.font = dashFont(700, W * 0.17); dashCtx.fillStyle = DASH.ink;
    dashCtx.fillText(String(speed), pad, y0 + h * 0.62);
    const sw = dashCtx.measureText(String(speed)).width;
    dashCtx.font = dashFont(600, W * 0.045); dashCtx.fillStyle = DASH.dim;
    dashCtx.fillText(data.unit === 'mph' ? 'MPH' : 'KMH', pad + sw + W * 0.02, y0 + h * 0.62);
    dashCtx.fillStyle = data.gear === 0 ? DASH.worn : DASH.accent;
    dashCtx.font = dashFont(700, W * 0.06);
    dashCtx.fillText(data.gear === 0 ? 'R' : String(data.gear ?? '-'), pad + sw + W * 0.02, y0 + h * 0.35);

    // F / E / H ticks on the right: letter and a short bar each
    const bx = W * 0.58, bw = W - pad - bx - W * 0.06;
    const items = [
        ['F', Math.max(0, Math.min(100, data.fuel ?? 60)), null],
        ['E', Math.max(0, Math.min(100, data.enginePct ?? 100)), data.engine],
        ['H', Math.max(0, Math.min(100, data.hullPct ?? 100)), data.hull],
    ];
    dashCtx.font = dashFont(700, W * 0.045);
    items.forEach(([label, pct, code], i) => {
        const y = y0 + h * (0.28 + i * 0.25);
        const c = DASH_COLOR[code] || dashLevelColor(pct);
        dashCtx.fillStyle = DASH.dim; dashCtx.textAlign = 'left'; dashCtx.textBaseline = 'middle';
        dashCtx.fillText(label, bx, y);
        dashCtx.fillStyle = 'rgba(214, 206, 168, 0.12)'; dashCtx.fillRect(bx + W * 0.06, y - 2, bw, 4);
        dashCtx.fillStyle = c; dashCtx.fillRect(bx + W * 0.06, y - 2, bw * pct / 100, 4);
    });
    dashCtx.textBaseline = 'alphabetic';
}

// ---- Extra dash styles: gauge, slate, cipher (VIP), hologram (VIP). SVG icons are Path2D (24x24 box).
const DASH_SVG = {
    fuel:   'M4 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16M3 21h12M6 7h6v4H6zM14 9h2.5a1.5 1.5 0 0 1 1.5 1.5V16a1.5 1.5 0 0 0 3 0V8l-3-3',
    engine: 'M3 11v4M6.5 9h3l1.5-2.5h5V9H19l2 2v5l-2 2H9l-2.5-2.5z',
    hull:   'M12 3l7 3v5c0 4.4-3 8.3-7 10-4-1.7-7-5.6-7-10V6l7-3z',
    gear:   'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2',
    lights: 'M9 6a6 6 0 0 0 0 12h1V6H9zM13 8h8M13 12h8M13 16h8',
};
const DASH_P2D = {};
function dashSvg(name, x, y, s, color, alpha) {
    const p = DASH_P2D[name] || (DASH_P2D[name] = new Path2D(DASH_SVG[name]));
    dashCtx.save();
    dashCtx.translate(x - s / 2, y - s / 2);
    dashCtx.scale(s / 24, s / 24);
    dashCtx.strokeStyle = color; dashCtx.lineWidth = 1.9;
    dashCtx.lineCap = 'round'; dashCtx.lineJoin = 'round';
    dashCtx.globalAlpha = alpha === undefined ? 1 : alpha;
    dashCtx.stroke(p);
    dashCtx.restore();
}

// Server palette (bs_ui CSS vars), re-read once a second.
let dashPalAt = 0, dashPalV = null;
function dashPal() {
    const now = Date.now();
    if (!dashPalV || now - dashPalAt > 1000) {
        dashPalAt = now;
        const cs = getComputedStyle(document.documentElement);
        const g = (n, f) => (cs.getPropertyValue(n) || '').trim() || f;
        dashPalV = { acc: g('--bs-accent', DASH.accent), ink: g('--bs-text', DASH.ink), mut: g('--bs-text-muted', DASH.ink), blood: g('--bs-blood', DASH.gone) };
    }
    return dashPalV;
}
function dashRound(x, y, w, h, r) {
    dashCtx.beginPath();
    dashCtx.moveTo(x + r, y); dashCtx.arcTo(x + w, y, x + w, y + h, r); dashCtx.arcTo(x + w, y + h, x, y + h, r);
    dashCtx.arcTo(x, y + h, x, y, r); dashCtx.arcTo(x, y, x + w, y, r); dashCtx.closePath();
}
function dashData(data) {
    return {
        speed: Math.max(0, Math.min(999, Math.round(data.speed || 0))),
        rpm: Math.max(0, Math.min(1, data.rpm || 0)),
        gear: data.gear === 0 ? 'R' : String(data.gear ?? '-'),
        fuel: Math.max(0, Math.min(100, data.fuel ?? 60)),
        eng: Math.max(0, Math.min(100, data.enginePct ?? 100)),
        hull: Math.max(0, Math.min(100, data.hullPct ?? 100)),
        unit: data.unit === 'mph' ? 'MPH' : 'KM/H',
    };
}

// Gauge: round 3/4 dial with ticks, icon row under it.
function dashDrawGauge(data, W, H) {
    const d = dashData(data), P = dashPal();
    const cx = W / 2, cy = H * 0.5, r = W * 0.38;
    dashCtx.fillStyle = 'rgba(14, 13, 10, 0.55)'; dashRound(4, H * 0.1, W - 8, H * 0.88, 26); dashCtx.fill();
    dashArc(cx, cy, r, 1, 'rgba(0,0,0,0)', W * 0.05, 'rgba(255,255,255,0.1)');
    dashArc(cx, cy, r, d.rpm, d.rpm > 0.85 ? P.blood : P.acc, W * 0.05);
    // ticks
    dashCtx.strokeStyle = P.mut; dashCtx.globalAlpha = 0.5; dashCtx.lineWidth = 2; dashCtx.beginPath();
    for (let i = 0; i <= 10; i++) {
        const a = Math.PI * 0.75 + Math.PI * 1.5 * i / 10, r1 = r - W * 0.06, r2 = r - W * (i % 5 ? 0.09 : 0.11);
        dashCtx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); dashCtx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2);
    }
    dashCtx.stroke(); dashCtx.globalAlpha = 1;
    dashCtx.textAlign = 'center'; dashCtx.textBaseline = 'middle';
    dashCtx.font = dashFont(700, W * 0.24); dashCtx.fillStyle = P.ink; dashCtx.fillText(String(d.speed), cx, cy - W * 0.02);
    dashCtx.font = dashFont(600, W * 0.06); dashCtx.fillStyle = P.mut; dashCtx.fillText(d.unit, cx, cy + W * 0.15);
    dashSvg('gear', cx - W * 0.07, cy + r * 0.92, W * 0.075, P.mut);
    dashCtx.font = dashFont(700, W * 0.09); dashCtx.fillStyle = data.gear === 0 ? DASH.worn : P.acc; dashCtx.fillText(d.gear, cx + W * 0.04, cy + r * 0.92);
    // icon row
    const items = [['fuel', d.fuel], ['engine', d.eng], ['hull', d.hull]];
    items.forEach(([ic, pct], i) => {
        const x = W * (0.2 + i * 0.3), y = H * 0.86, c = dashLevelColor(pct);
        dashSvg(ic, x, y, W * 0.1, c);
        dashCtx.fillStyle = 'rgba(255,255,255,0.12)'; dashCtx.fillRect(x - W * 0.09, y + W * 0.075, W * 0.18, 3);
        dashCtx.fillStyle = c; dashCtx.fillRect(x - W * 0.09, y + W * 0.075, W * 0.18 * pct / 100, 3);
    });
    if (data.lights) dashSvg('lights', W * 0.86, H * 0.16, W * 0.09, data.lights === 2 ? '#8ec5ff' : P.acc);
}

// Slate: flat card, speed on the left, icon rows with bars on the right.
function dashDrawSlate(data, W, H) {
    const d = dashData(data), P = dashPal();
    const y0 = H * 0.55, h = H * 0.44;
    dashCtx.fillStyle = 'rgba(16, 16, 14, 0.62)'; dashRound(4, y0, W - 8, h, 14); dashCtx.fill();
    dashCtx.fillStyle = P.acc; dashCtx.fillRect(4, y0 + 14, 4, h - 28);
    dashCtx.textBaseline = 'alphabetic'; dashCtx.textAlign = 'left';
    dashCtx.font = dashFont(700, W * 0.27); dashCtx.fillStyle = P.ink; dashCtx.fillText(String(d.speed), W * 0.07, y0 + h * 0.52);
    dashCtx.font = dashFont(600, W * 0.06); dashCtx.fillStyle = P.mut; dashCtx.fillText(d.unit, W * 0.08, y0 + h * 0.7);
    dashSvg('gear', W * 0.11, y0 + h * 0.88, W * 0.08, P.mut);
    dashCtx.font = dashFont(700, W * 0.08); dashCtx.fillStyle = data.gear === 0 ? DASH.worn : P.acc; dashCtx.fillText(d.gear, W * 0.17, y0 + h * 0.93);
    const rows = [['fuel', d.fuel], ['engine', d.eng], ['hull', d.hull]];
    rows.forEach(([ic, pct], i) => {
        const y = y0 + h * (0.24 + i * 0.26), c = dashLevelColor(pct), bx = W * 0.6;
        dashSvg(ic, W * 0.53, y, W * 0.085, c);
        dashCtx.fillStyle = 'rgba(255,255,255,0.12)'; dashRound(bx, y - 3, W * 0.3, 6, 3); dashCtx.fill();
        dashCtx.fillStyle = c; dashRound(bx, y - 3, Math.max(6, W * 0.3 * pct / 100), 6, 3); dashCtx.fill();
    });
    dashCtx.fillStyle = 'rgba(255,255,255,0.12)'; dashCtx.fillRect(W * 0.07, y0 + 8, W - W * 0.14, 3);
    dashCtx.fillStyle = d.rpm > 0.85 ? P.blood : P.acc; dashCtx.fillRect(W * 0.07, y0 + 8, (W - W * 0.14) * d.rpm, 3);
    if (data.lights) dashSvg('lights', W * 0.9, y0 + h * 0.88, W * 0.075, data.lights === 2 ? '#8ec5ff' : P.acc);
}

// Cipher (VIP): segmented RPM ring around the speed, angled gear plate.
function dashDrawCipher(data, W, H) {
    const d = dashData(data), P = dashPal();
    const cx = W / 2, cy = H * 0.62, r = W * 0.36, n = 30;
    dashCtx.fillStyle = 'rgba(12, 12, 14, 0.5)'; dashCtx.beginPath(); dashCtx.arc(cx, cy, r + W * 0.08, 0, Math.PI * 2); dashCtx.fill();
    dashCtx.lineWidth = W * 0.045; dashCtx.lineCap = 'butt';
    for (let i = 0; i < n; i++) {
        const a0 = Math.PI * 0.75 + Math.PI * 1.5 * i / n, a1 = a0 + Math.PI * 1.5 / n * 0.7;
        const lit = d.rpm * n > i;
        dashCtx.strokeStyle = lit ? (i > n * 0.85 ? P.blood : P.acc) : P.mut;
        dashCtx.globalAlpha = lit ? 1 : 0.18;
        dashCtx.beginPath(); dashCtx.arc(cx, cy, r, a0, a1); dashCtx.stroke();
    }
    dashCtx.globalAlpha = 1;
    dashCtx.textAlign = 'center'; dashCtx.textBaseline = 'middle';
    dashCtx.font = dashFont(700, W * 0.25); dashCtx.fillStyle = P.ink; dashCtx.fillText(String(d.speed), cx, cy - W * 0.03);
    dashCtx.font = dashFont(600, W * 0.058); dashCtx.fillStyle = P.mut; dashCtx.fillText(d.unit, cx, cy + W * 0.14);
    // gear plate
    dashCtx.fillStyle = P.acc; dashCtx.beginPath();
    dashCtx.moveTo(cx - W * 0.1, cy + r + W * 0.02); dashCtx.lineTo(cx + W * 0.1, cy + r + W * 0.02);
    dashCtx.lineTo(cx + W * 0.07, cy + r + W * 0.12); dashCtx.lineTo(cx - W * 0.07, cy + r + W * 0.12); dashCtx.fill();
    dashCtx.font = dashFont(700, W * 0.08); dashCtx.fillStyle = '#111'; dashCtx.fillText(d.gear, cx, cy + r + W * 0.07);
    [['fuel', d.fuel, 0.1], ['engine', d.eng, 0.1 + 0.0], ['hull', d.hull, 0.1]].forEach(([ic, pct], i) => {
        const x = W * 0.09, y = cy - r * 0.9 + i * W * 0.15 + W * 0.05, c = dashLevelColor(pct);
        dashSvg(ic, x, y, W * 0.085, c);
        dashCtx.fillStyle = 'rgba(255,255,255,0.15)'; dashCtx.fillRect(x - W * 0.04, y + W * 0.06, W * 0.08, 2);
        dashCtx.fillStyle = c; dashCtx.fillRect(x - W * 0.04, y + W * 0.06, W * 0.08 * pct / 100, 2);
    });
    if (data.lights) dashSvg('lights', W * 0.91, cy - r * 0.9 + W * 0.05, W * 0.085, data.lights === 2 ? '#8ec5ff' : P.acc);
}

// Hologram (VIP): floating translucent 7-seg digits in the server palette, scanlines, soft flicker.
function dashHoloDigit(x, y, w, h, n, col, alpha) {
    const t2 = w * 0.16, mask = n === null ? 0 : SEG7[n];
    const s = [[x + t2, y, w - t2 * 2, t2], [x + w - t2, y + t2, t2, h / 2 - t2 * 1.5], [x + w - t2, y + h / 2 + t2 / 2, t2, h / 2 - t2 * 1.5],
        [x + t2, y + h - t2, w - t2 * 2, t2], [x, y + h / 2 + t2 / 2, t2, h / 2 - t2 * 1.5], [x, y + t2, t2, h / 2 - t2 * 1.5],
        [x + t2, y + h / 2 - t2 / 2, w - t2 * 2, t2]];
    dashCtx.fillStyle = col;
    for (let i = 0; i < 7; i++) {
        const on = (mask >> i) & 1;
        dashCtx.globalAlpha = on ? alpha : alpha * 0.1;
        const q = s[i];
        if (on) { dashCtx.globalAlpha = alpha * 0.25; dashCtx.fillRect(q[0] - 2, q[1] - 2, q[2] + 4, q[3] + 4); dashCtx.globalAlpha = alpha; }
        dashCtx.fillRect(q[0], q[1], q[2], q[3]);
    }
}
function dashDrawHologram(data, W, H) {
    const d = dashData(data), P = dashPal(), now = Date.now();
    const flick = 0.9 + 0.1 * Math.sin(now / 53) * Math.sin(now / 197) + (now % 2300 < 60 ? -0.25 : 0);
    const base = Math.max(0.4, flick) * 0.82;
    const pad = W * 0.08;
    // projection base: thin glowing ellipse
    dashCtx.globalAlpha = 0.5 * base; dashCtx.strokeStyle = P.acc; dashCtx.lineWidth = 2;
    dashCtx.beginPath(); dashCtx.ellipse(W / 2, H * 0.93, W * 0.4, W * 0.05, 0, 0, Math.PI * 2); dashCtx.stroke();
    // beam
    const g = dashCtx.createLinearGradient(0, H * 0.35, 0, H * 0.93);
    g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, P.acc);
    dashCtx.globalAlpha = 0.1 * base; dashCtx.fillStyle = g;
    dashCtx.fillRect(W * 0.1, H * 0.35, W * 0.8, H * 0.58);
    // digits
    const str = String(d.speed).padStart(3, ' ');
    const dw = W * 0.22, dh = W * 0.4, gap = W * 0.05;
    let x = W / 2 - (dw * 3 + gap * 2) / 2, y = H * 0.4;
    for (let i = 0; i < 3; i++) { dashHoloDigit(x, y, dw, dh, str[i] === ' ' ? null : Number(str[i]), P.ink, base); x += dw + gap; }
    dashCtx.textAlign = 'center'; dashCtx.textBaseline = 'middle'; dashCtx.globalAlpha = base;
    dashCtx.font = dashFont(600, W * 0.055); dashCtx.fillStyle = P.mut; dashCtx.fillText(d.unit, W / 2, y + dh + W * 0.07);
    // gear indicator
    dashSvg('gear', W * 0.12, y - W * 0.08, W * 0.08, P.mut, base);
    dashCtx.font = dashFont(700, W * 0.11); dashCtx.fillStyle = data.gear === 0 ? P.blood : P.acc; dashCtx.globalAlpha = base;
    dashCtx.fillText(d.gear, W * 0.25, y - W * 0.08);
    // icons
    [['fuel', d.fuel], ['engine', d.eng], ['hull', d.hull]].forEach(([ic, pct], i) => {
        dashSvg(ic, W * (0.62 + i * 0.12), y - W * 0.08, W * 0.075, pct <= 15 ? P.blood : pct <= 35 ? DASH.worn : P.ink, base);
    });
    // thin progress bar (rpm)
    const by = y + dh + W * 0.14;
    dashCtx.globalAlpha = 0.15 * base; dashCtx.fillStyle = P.ink; dashCtx.fillRect(pad, by, W - pad * 2, 3);
    dashCtx.globalAlpha = base; dashCtx.fillStyle = d.rpm > 0.85 ? P.blood : P.acc; dashCtx.fillRect(pad, by, (W - pad * 2) * d.rpm, 3);
    // scanlines + moving band
    dashCtx.globalAlpha = 0.07; dashCtx.strokeStyle = P.ink; dashCtx.lineWidth = 1; dashCtx.beginPath();
    for (let yy = H * 0.3 + 1; yy < H * 0.97; yy += 4) { dashCtx.moveTo(pad, yy); dashCtx.lineTo(W - pad, yy); }
    dashCtx.stroke();
    const band = H * 0.3 + ((now / 18) % (H * 0.67));
    dashCtx.globalAlpha = 0.1; dashCtx.fillStyle = P.ink; dashCtx.fillRect(pad, band, W - pad * 2, 6);
    dashCtx.globalAlpha = 1;
}

const DASH_STYLES = { field: dashDrawField, classic: dashDrawClassic, scrap: dashDrawScrap, nightops: dashDrawNight, tactical: dashDrawTactical, gauge: dashDrawGauge, slate: dashDrawSlate, cipher: dashDrawCipher, hologram: dashDrawHologram };
let dashOpacity = null;

BS.on('dashhud', (data) => {
    if (!dashEl || !dashCtx) return;

    if (!data.show) {
        dashEl.classList.add('hidden');
        return;
    }
    dashEl.classList.remove('hidden');
    dashEl.dataset.side = data.side === 'L' ? 'L' : 'R';
    // Resizable via bs_carhud_scale. Scaled from its bottom corner so growing it never pushes it off screen.
    dashEl.style.transform = `scale(${Math.max(0.4, Math.min(3, data.scale || 1))})`;
    // Player opacity on top of the HUD opacity; only touch the style when it changes.
    const op = Math.max(0.1, Math.min(1, (data.opacity ?? 100) / 100));
    if (op !== dashOpacity) { dashOpacity = op; dashEl.style.setProperty('--dash-op', String(op)); }

    const W = dashEl.width, H = dashEl.height;
    dashCtx.clearRect(0, 0, W, H);
    (DASH_STYLES[data.style] || dashDrawField)(data, W, H);
});

// Short lift when a slot fires.
BS.on('hotbarFire', ({ index }) => {
    const el = hotbarEl && hotbarEl.querySelector(`.hotbar__slot[data-slot="${index}"]`);
    if (!el) return;
    el.classList.add('is-firing');
    setTimeout(() => el.classList.remove('is-firing'), 260);
});

// Medical condition icons from bs_medical: small marks under the bars, a tooltip-free label beside each.
const MED_ICONS = {
    bleed:    '<path d="M12 3s6 6.5 6 10.5A6 6 0 0 1 6 13.5C6 9.5 12 3 12 3z"/>',
    fracture: '<path d="M7 4l3 3-1.5 1.5 3 3L13 10l4 4M6.5 14.5l3 3M14.5 6.5l3 3"/><path d="M5 19l3-3M16 8l3-3"/>',
    infected: '<path d="M12 6a6 6 0 1 0 0 12 6 6 0 0 0 0-12zM12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5M17.5 17.5 19 19M19 5l-1.5 1.5M6.5 17.5 5 19"/>',
    sick:     '<path d="M8 10c0-2.5 1.8-4 4-4s4 1.5 4 4"/><path d="M6 14h12M8 18h8"/><circle cx="9.5" cy="10.5" r=".6"/><circle cx="14.5" cy="10.5" r=".6"/>',
    cold:     '<path d="M12 3v18M4.5 7.5l15 9M19.5 7.5l-15 9"/><path d="M10 5l2 2 2-2M10 19l2-2 2 2"/>',
    pain:     '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
    blood:    '<path d="M12 3s6 6.5 6 10.5A6 6 0 0 1 6 13.5C6 9.5 12 3 12 3z"/><path d="M9 14h6"/>',
};
BS.on('medConds', ({ list = [] }) => {
    const box = document.getElementById('hud-conds');
    if (!box) return;
    box.innerHTML = list.map((c) => `<span class="hud__cond" data-id="${c.id}" data-level="${Number(c.level) || 1}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${MED_ICONS[c.id] || MED_ICONS.bleed}</svg>
        <i>${String(c.label || '').replace(/[&<>"]/g, '')}</i></span>`).join('');
    box.classList.toggle('is-empty', list.length === 0);
});

// Throttle slider: slim vertical bar beside the dash. Zero is the middle; above = throttle, below = brake/reverse.
const thrEl = document.getElementById('throttle');
BS.on('throttle', (d) => {
    if (!thrEl) return;
    if (!d.show) { thrEl.classList.add('hidden'); return; }
    thrEl.classList.remove('hidden');
    const side = dashEl && dashEl.dataset.side === 'L' ? 'L' : 'R';
    const m = dashEl && /scale\(([\d.]+)\)/.exec(dashEl.style.transform || '');
    const sc = m ? Number(m[1]) : 1;
    thrEl.style.left = side === 'L' ? `calc(1.6vw / var(--ui-scale, 1) + ${Math.round(148 * sc + 8)}px)` : 'auto';
    thrEl.style.right = side === 'R' ? `calc(1.6vw / var(--ui-scale, 1) + ${Math.round(148 * sc + 8)}px)` : 'auto';
    const lv = Math.max(-100, Math.min(100, Number(d.level) || 0));
    const f = thrEl.firstElementChild;
    f.style.height = Math.abs(lv) / 2 + '%';
    f.style.top = lv >= 0 ? (50 - lv / 2) + '%' : '50%';
    f.classList.toggle('is-brake', lv < 0);
});

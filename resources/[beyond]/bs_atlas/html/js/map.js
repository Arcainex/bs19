// bs_atlas - map.js: canvas renderer for the atlas (one draw call per frame, no DOM)

'use strict';

// Translation lookup
function AT(key, fb, vars) {
    let s = (window.BSI18n && window.BSI18n.t) ? window.BSI18n.t(key, { fallback: fb }) : fb;
    if (vars) s = String(s).replace(/\{(\w+)\}/g, (mm, n) => (vars[n] !== undefined ? String(vars[n]) : mm));
    return s;
}

const AtlasMap = (function () {

// Palette duplicated from style.css: canvas cannot cheaply read CSS variables per dot

const COLOURS = {
    // Cell state. The density ramp carries 'how many'; state carries 'what kind of place'.
    cell: {
        locked:   '#b48cff',   // staff pinned it: regrowth and migration skip it
        cleared:  '#ff5f56',   // farmed out, inside its grace period
        thin:     '#ff9f43',   // below half baseline, healing
        promoted: '#4fd0ff',   // its zombies are live individuals right now
        full:     '#5ee08a',   // at or above baseline
        normal:   '#8fa6bd',
        empty:    '#33414f',
    },
    // Agent state: the decision ladder, made visible.
    agent: {
        wander:      '#8fa6bd',   // no target, drifting around its origin
        lurk:        '#5b6f84',   // standing still (lurking)
        investigate: '#ffd24a',   // heard something, walking to a point
        drawn:       '#ffa32f',   // pulled by a vehicle / sustained noise
        hunt:        '#ff5f56',   // has a PLAYER target
        feed:        '#c14ad6',   // occupied with a corpse
    },
    // Noise kind, from the sense ladder's board.
    noise: {
        gunshot: '#ff5f56', vehicle: '#ffa32f', explosion: '#ff2d55',
        footstep: '#5ee08a', shout: '#ffd24a', door: '#8fa6bd',
        melee: '#ff9f43', default: '#4fd0ff',
    },
    herd:   '#ff6ec7',
    player: '#ffffff',
    me:     '#4fd0ff',
    place:  '#5b7286',
};

// Density ramp: cell colour by head count, cold-empty to green-normal to amber-busy to red-packed
const RAMP = [
    [0,  [ 24,  36,  48]],
    [1,  [ 32,  66,  92]],
    [3,  [ 40, 110, 120]],
    [6,  [ 58, 158, 110]],
    [12, [140, 180,  70]],
    [20, [216, 160,  52]],
    [35, [226, 104,  56]],
    [60, [232,  58,  62]],
];

function rampColour(n) {
    if (n <= 0) return 'rgb(24,36,48)';
    let lo = RAMP[0], hi = RAMP[RAMP.length - 1];
    for (let i = 0; i < RAMP.length - 1; i++) {
        if (n >= RAMP[i][0] && n <= RAMP[i + 1][0]) { lo = RAMP[i]; hi = RAMP[i + 1]; break; }
        if (n > RAMP[RAMP.length - 1][0]) { lo = hi = RAMP[RAMP.length - 1]; }
    }
    const span = (hi[0] - lo[0]) || 1;
    const t = Math.max(0, Math.min(1, (n - lo[0]) / span));
    const c = [0, 1, 2].map(i => Math.round(lo[1][i] + (hi[1][i] - lo[1][i]) * t));
    return `rgb(${c[0]},${c[1]},${c[2]})`;
}

// state

const S = {
    cv: null, ctx: null, dpr: 1, w: 0, h: 0,

    world:  { minX: -4000, maxX: 5000, minY: -4000, maxY: 8000 },
    points: [],

    // The transform: one centre in world metres and one scale in pixels per metre
    view: { cx: 0, cy: 0, ppm: 0.2 },
    minSpan: 120, maxSpan: 16000,

    // Two snapshots and their arrival times (see the interpolation note in the header).
    cur: null, curAt: 0,
    prev: null, prevAt: 0,
    agentPrev: new Map(),   // id to {x,y} from the previous snapshot

    stale: false,
    me: null,
    observer: null,         // { x, y, radius } - what the server accepted
    selected: null,         // { cx, cy } - the inspected cell
    rect: null,             // { x1,y1,x2,y2 } - a completed selection
    dragRect: null,         // live during a right-drag
    rectArmed: false,       // SELECT AREA pressed: the next left-drag is a rectangle

    layers: {
        map: true,
        // Only real peds by default. NOT SPAWNED shows the simulated ones; cells are their head counts.
        cells: false, agents: true, virtual: false, herds: true, noise: true,
        players: true, places: true, grid: true, targets: true,
        heat: true, hordes: true, cars: false,
    },

    // The map image. state is one of
    map: { img: null, url: null, calib: null, state: 'none', note: '', opacity: 0.55 },

    hooks: {},              // onCellClick / onRect / onPick / onCursor / onView
    pickMode: false,
    running: false,
};

// transform

function w2sx(x) { return (x - S.view.cx) * S.view.ppm + S.w / 2; }
// world Y is north, screen Y is down
function w2sy(y) { return S.h / 2 - (y - S.view.cy) * S.view.ppm; }
function s2wx(px) { return (px - S.w / 2) / S.view.ppm + S.view.cx; }
function s2wy(py) { return (S.h / 2 - py) / S.view.ppm + S.view.cy; }

function viewRect() {
    return { x1: s2wx(0), y1: s2wy(S.h), x2: s2wx(S.w), y2: s2wy(0) };
}

function setSpan(metresAcross, anchorPx, anchorPy) {
    const clamped = Math.max(S.minSpan, Math.min(S.maxSpan, metresAcross));

    // Zoom about the cursor, not the centre.
    let ax = null, ay = null;
    if (anchorPx != null) { ax = s2wx(anchorPx); ay = s2wy(anchorPy); }

    S.view.ppm = S.w / clamped;

    if (ax != null) {
        S.view.cx += ax - s2wx(anchorPx);
        S.view.cy += ay - s2wy(anchorPy);
    }
    if (S.hooks.onView) S.hooks.onView();
}

// painting

function clear() {
    S.ctx.setTransform(S.dpr, 0, 0, S.dpr, 0, 0);
    S.ctx.clearRect(0, 0, S.w, S.h);
    S.ctx.fillStyle = '#07090c';
    S.ctx.fillRect(0, 0, S.w, S.h);
}

// The map image, cropped to what is on screen (see the header).
function drawMapImage(c) {
    const M = S.map;
    if (M.state !== 'ok' || !M.img || !M.calib) return;
    const K = M.calib;
    const iw = M.img.naturalWidth, ih = M.img.naturalHeight;
    if (!(iw > 0 && ih > 0)) return;

    // Where the whole image would land on screen. North (maxY) is the top edge.
    const dx = w2sx(K.minX), dy = w2sy(K.maxY);
    const dw = (K.maxX - K.minX) * S.view.ppm;
    const dh = (K.maxY - K.minY) * S.view.ppm;
    if (!(dw > 0 && dh > 0)) return;

    // The visible part of that rectangle.
    const vx1 = Math.max(0, dx), vy1 = Math.max(0, dy);
    const vx2 = Math.min(S.w, dx + dw), vy2 = Math.min(S.h, dy + dh);
    if (vx2 <= vx1 || vy2 <= vy1) return;

    // The same fraction of the source image.
    const sx = (vx1 - dx) / dw * iw, sy = (vy1 - dy) / dh * ih;
    const sw = (vx2 - vx1) / dw * iw, sh = (vy2 - vy1) / dh * ih;

    c.save();
    c.globalAlpha = Math.max(0, Math.min(1, M.opacity));
    // Always smooth: the source is low-res, blocky pixels at high zoom look worse than a soft image.
    c.imageSmoothingEnabled = true;
    c.imageSmoothingQuality = 'high';
    c.drawImage(M.img, sx, sy, sw, sh, vx1, vy1, vx2 - vx1, vy2 - vy1);
    c.restore();
}

// On-canvas note when the image is not drawn for a reason the user did not choose
function drawMapNote() {
    const M = S.map;
    let text = null;
    if (M.state === 'failed')        text = AT('atlas.m.c_failed', 'MAP IMAGE FAILED TO LOAD - showing the plain plane.') + ' ' + (M.note || '');
    else if (M.state === 'uncalibrated') text = AT('atlas.m.c_uncal', 'NO MAP CALIBRATION - image not drawn (it would be misaligned).') + ' ' + (M.note || '');
    else if (M.state === 'none')     text = AT('atlas.m.c_none', 'NO MAP IMAGE CONFIGURED - showing the plain plane.') + ' ' + (M.note || '');
    else if (M.state === 'ok' && M.note) text = M.note;
    if (!text || !S.layers.map) return;

    const c = S.ctx;
    c.save();
    c.font = '11px Consolas, monospace';
    c.textAlign = 'left';
    const w = Math.min(S.w - 24, c.measureText(text).width + 16);
    // Centred: the side panels cover both lower corners of the canvas.
    const x = Math.max(12, (S.w - w) / 2);
    c.globalAlpha = 0.85; c.fillStyle = '#1a0f0f';
    c.fillRect(x, S.h - 74, w, 22);
    c.globalAlpha = 1; c.fillStyle = M.state === 'ok' ? '#ffb648' : '#ff5f56';
    c.fillText(text, x + 8, S.h - 59);
    c.restore();
}

// The plane: world box and a 1km grid. Lets 'nothing here' be told apart from 'nothing answered'.
function drawPlane() {
    const c = S.ctx, W = S.world;

    const x1 = w2sx(W.minX), x2 = w2sx(W.maxX);
    const y1 = w2sy(W.maxY), y2 = w2sy(W.minY);

    c.fillStyle = '#0b1016';
    c.fillRect(x1, y1, x2 - x1, y2 - y1);

    // The real map, under the grid and every data layer.
    if (S.layers.map) drawMapImage(c);

    if (S.layers.grid) {
        // Grid step keeps lines at least ~60px apart.
        let step = 1000;
        while (step * S.view.ppm < 60) step *= 2;
        while (step * S.view.ppm > 300 && step > 50) step /= 2;

        c.strokeStyle = 'rgba(120,160,200,.07)';
        c.lineWidth = 1;
        c.beginPath();
        const sx = Math.ceil(W.minX / step) * step;
        for (let x = sx; x <= W.maxX; x += step) {
            const px = Math.round(w2sx(x)) + 0.5;
            if (px < -2 || px > S.w + 2) continue;
            c.moveTo(px, Math.max(y1, 0)); c.lineTo(px, Math.min(y2, S.h));
        }
        const sy = Math.ceil(W.minY / step) * step;
        for (let y = sy; y <= W.maxY; y += step) {
            const py = Math.round(w2sy(y)) + 0.5;
            if (py < -2 || py > S.h + 2) continue;
            c.moveTo(Math.max(x1, 0), py); c.lineTo(Math.min(x2, S.w), py);
        }
        c.stroke();

        // The origin.
        c.strokeStyle = 'rgba(120,160,200,.22)';
        c.beginPath();
        c.moveTo(w2sx(0), Math.max(y1, 0)); c.lineTo(w2sx(0), Math.min(y2, S.h));
        c.moveTo(Math.max(x1, 0), w2sy(0)); c.lineTo(Math.min(x2, S.w), w2sy(0));
        c.stroke();
    }

    c.strokeStyle = 'rgba(120,200,255,.28)';
    c.lineWidth = 1;
    c.strokeRect(x1 + .5, y1 + .5, x2 - x1, y2 - y1);
}

// Density cells
function drawCells(snap) {
    const c = S.ctx;
    const stride = Math.max(1, snap.stride || 1);
    const size = (snap.cellSize || 50) * stride;
    const px = Math.max(1.2, size * S.view.ppm);

    for (let i = 0; i < snap.cells.length; i++) {
        const cell = snap.cells[i];
        const wx = cell.cx * (snap.cellSize || 50);
        const wy = cell.cy * (snap.cellSize || 50);
        const sx = w2sx(wx), sy = w2sy(wy) - px;
        if (sx < -px || sx > S.w || sy < -px || sy > S.h) continue;

        c.fillStyle = rampColour(cell.n);
        c.globalAlpha = 0.82;
        c.fillRect(sx, sy, px, px);
        c.globalAlpha = 1;

        // State on top of density
        const st = cell.state;
        if (st === 'locked' || st === 'cleared' || st === 'thin' || st === 'promoted') {
            c.strokeStyle = COLOURS.cell[st];
            c.lineWidth = st === 'promoted' ? 1 : 1.4;
            c.globalAlpha = px < 4 ? 0.9 : 0.75;
            c.strokeRect(sx + .5, sy + .5, px - 1, px - 1);
            c.globalAlpha = 1;
        }
    }

    // The inspected cell, drawn last.
    if (S.selected) {
        const cs = snap.cellSize || 50;
        const sx = w2sx(S.selected.cx * cs);
        const sy = w2sy(S.selected.cy * cs) - cs * S.view.ppm;
        const p = Math.max(6, cs * S.view.ppm);
        c.strokeStyle = '#ffffff'; c.lineWidth = 2;
        c.strokeRect(sx - 1.5, sy - 1.5, p + 3, p + 3);
    }
}

// Noise, under the agents
function drawNoise(snap) {
    const c = S.ctx;
    for (let i = 0; i < snap.noise.length; i++) {
        const nz = snap.noise[i];
        const sx = w2sx(nz.x), sy = w2sy(nz.y);
        const r = Math.max(2, (nz.reach || 50) * S.view.ppm);

        // Ages beyond 60s are drawn at the floor instead of vanishing, since the board still holds them.
        const fade = Math.max(0.08, 1 - (nz.age || 0) / 60);
        const col = COLOURS.noise[nz.kind] || COLOURS.noise.default;

        c.strokeStyle = col;
        c.globalAlpha = 0.42 * fade;
        c.lineWidth = 1;
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.stroke();

        c.globalAlpha = 0.10 * fade;
        c.fillStyle = col;
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.fill();

        c.globalAlpha = Math.min(1, 0.5 + fade);
        c.fillStyle = col;
        c.beginPath(); c.arc(sx, sy, 2.5, 0, 6.2832); c.fill();

        if (r > 26) {
            c.globalAlpha = fade;
            c.font = '9px Consolas, monospace';
            c.textAlign = 'center';
            c.fillText(`${nz.kind || AT('atlas.cv.noise', 'noise')} ${Math.round(nz.age || 0)}s`, sx, sy - r - 4);
        }
        c.globalAlpha = 1;
    }
}

// Herds: an observation, not an object
function drawHerds(snap) {
    const c = S.ctx;
    for (let i = 0; i < snap.herds.length; i++) {
        const h = snap.herds[i];
        const sx = w2sx(h.x), sy = w2sy(h.y);
        const r = Math.max(6, (h.r || 40) * S.view.ppm);

        c.strokeStyle = COLOURS.herd;
        c.globalAlpha = 0.75; c.lineWidth = 1.5;
        c.setLineDash([4, 3]);
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.stroke();
        c.setLineDash([]);

        c.globalAlpha = 0.07; c.fillStyle = COLOURS.herd;
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.fill();

        c.globalAlpha = 1;
        c.fillStyle = COLOURS.herd;
        c.font = 'bold 11px Consolas, monospace';
        c.textAlign = 'center';
        c.fillText(String(h.n), sx, sy - r - 5);
    }
}

// Agents (individual zombies), interpolated. t is clamped to 0..1 so a slow poll does not extrapolate.
function drawAgents(snap, t) {
    const c = S.ctx;
    const dot = S.view.ppm > 0.6 ? 3 : (S.view.ppm > 0.18 ? 2 : 1.4);

    for (let i = 0; i < snap.agents.length; i++) {
        const a = snap.agents[i];
        if (!a.ped && !S.layers.virtual) continue;
        const p = S.agentPrev.get(a.id);

        let ax = a.x, ay = a.y, fade = 1;
        if (p) {
            // A jump over 120m in one interval is a demote/promote cycle reusing the id, not movement, so no line is drawn
            const dx = a.x - p.x, dy = a.y - p.y;
            if (dx * dx + dy * dy < 120 * 120) {
                ax = p.x + dx * t;
                ay = p.y + dy * t;
            }
        } else {
            fade = 0.35 + 0.65 * t;   // newly promoted: fade in where it is
        }

        const sx = w2sx(ax), sy = w2sy(ay);
        if (sx < -4 || sx > S.w + 4 || sy < -4 || sy > S.h + 4) continue;

        // The target line shows why a zombie is moving: to a point = it heard something, to a player = something above hearing fired
        if (S.layers.targets && a.target && S.view.ppm > 0.08) {
            c.strokeStyle = a.target.kind === 'player' ? COLOURS.agent.hunt : COLOURS.agent.investigate;
            c.globalAlpha = 0.28; c.lineWidth = 1;
            c.beginPath(); c.moveTo(sx, sy);
            c.lineTo(w2sx(a.target.x), w2sy(a.target.y)); c.stroke();
            c.globalAlpha = 1;
        }

        c.globalAlpha = fade;
        c.fillStyle = COLOURS.agent[a.state] || COLOURS.agent.wander;
        c.beginPath(); c.arc(sx, sy, dot, 0, 6.2832); c.fill();

        // A zombie turned into a real ped by the streaming pipeline gets a ring (the simulated/real boundary)
        if (a.ped && S.view.ppm > 0.12) {
            c.strokeStyle = '#ffffff'; c.globalAlpha = 0.55 * fade; c.lineWidth = 1;
            c.beginPath(); c.arc(sx, sy, dot + 2.2, 0, 6.2832); c.stroke();
        }
        c.globalAlpha = 1;
    }
}

const CAR_COLOURS = { system: '#f5c542', admin: '#3ddc84' };
function drawCars() {
    const c = S.ctx, list = S.cars || [];
    const labels = S.view.ppm > 0.12;
    for (let i = 0; i < list.length; i++) {
        const car = list[i];
        const sx = w2sx(car.x), sy = w2sy(car.y);
        if (sx < -20 || sy < -20 || sx > S.w + 20 || sy > S.h + 20) continue;
        c.fillStyle = CAR_COLOURS[car.origin] || CAR_COLOURS.system;
        c.fillRect(sx - 3, sy - 3, 6, 6);
        if (car.state === 'wrecked') {
            c.strokeStyle = '#ff5f56'; c.lineWidth = 1.5;
            c.strokeRect(sx - 4.5, sy - 4.5, 9, 9);
        }
        if (labels) {
            c.font = '10px Rajdhani, sans-serif';
            c.textAlign = 'left';
            c.fillText(car.model + ' ' + AT('atlas.cars.' + car.state, car.state), sx + 7, sy + 3);
        }
    }
}

function drawPlayers(snap) {
    const c = S.ctx;
    for (let i = 0; i < snap.players.length; i++) {
        const p = snap.players[i];
        drawActor(c, w2sx(p.x), w2sy(p.y), p.heading, COLOURS.player,
                  p.name, p.vehicle ? AT('atlas.cv.veh', 'VEH') : (p.prone ? AT('atlas.cv.prone', 'PRONE') : (p.crouched ? AT('atlas.cv.crouch', 'CROUCH') : null)));
    }
}

// One arrow per player; the heading arrow matters because sight depends on facing
function drawActor(c, sx, sy, headingDeg, colour, label, tag) {
    const a = (90 - (headingDeg || 0)) * Math.PI / 180;

    c.save();
    c.translate(sx, sy);
    c.rotate(-a + Math.PI / 2);
    c.fillStyle = colour;
    c.beginPath();
    c.moveTo(0, -7); c.lineTo(4.5, 5); c.lineTo(0, 2.5); c.lineTo(-4.5, 5);
    c.closePath(); c.fill();
    c.restore();

    if (S.view.ppm > 0.05) {
        c.fillStyle = colour;
        c.font = '10px Rajdhani, sans-serif';
        c.textAlign = 'left';
        c.fillText(label || '', sx + 8, sy + 3);
        if (tag) {
            c.fillStyle = '#ffd24a';
            c.font = '9px Consolas, monospace';
            c.fillText(tag, sx + 8, sy + 13);
        }
    }
}

// Place names from ZAtlas.points, sized by d (density weight)
function drawHeat(snap) {
    const d = snap.director; if (!d || !d.zones) return;
    const c = S.ctx;
    for (const z of d.zones) {
        const f = Math.max(0, Math.min(1, (z.heat || 0) / (z.heatMax || 100)));
        const sx = w2sx(z.x), sy = w2sy(z.y), r = Math.max(4, (z.radius || 100) * S.view.ppm);
        c.globalAlpha = 0.06 + 0.3 * f; c.fillStyle = '#ff5a3c';
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.fill();
        c.globalAlpha = 0.6; c.strokeStyle = '#ff5a3c'; c.lineWidth = 1;
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.stroke();
        c.globalAlpha = 0.95; c.fillStyle = '#ffb4a3'; c.textAlign = 'center';
        c.font = '10px Consolas, monospace';
        c.fillText(AT('atlas.cv.heat', '{id}  HEAT {h}/{m}', { id: String(z.id).toUpperCase(), h: Math.round(z.heat || 0), m: Math.round(z.heatMax || 100) }), sx, sy + r + 12);
        c.globalAlpha = 1;
    }
}

// Hordes: waves started from heat (solid ring) and crowds that converged on a sound (dashed).
function drawHordes(snap) {
    const d = snap.director; if (!d || !d.hordes) return;
    const c = S.ctx;
    for (const h of d.hordes) {
        const sx = w2sx(h.x), sy = w2sy(h.y);
        const r = Math.max(10, 60 * S.view.ppm);
        c.strokeStyle = '#ff2d55'; c.lineWidth = 2.5; c.globalAlpha = 0.9;
        if (h.source === 'converged') c.setLineDash([6, 4]);
        c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.stroke();
        c.setLineDash([]);
        c.fillStyle = '#ff2d55'; c.font = 'bold 11px Consolas, monospace'; c.textAlign = 'center';
        c.fillText(AT('atlas.cv.horde', 'HORDE ~{n}  {s}s', { n: h.size || '?', s: Math.max(0, h.secondsLeft || 0) }), sx, sy - r - 6);
        c.globalAlpha = 1;
    }
}

function drawPlaces() {
    const c = S.ctx;
    c.textAlign = 'center';
    for (let i = 0; i < S.points.length; i++) {
        const p = S.points[i];
        const sx = w2sx(p.x), sy = w2sy(p.y);
        if (sx < -80 || sx > S.w + 80 || sy < -20 || sy > S.h + 20) continue;

        c.fillStyle = COLOURS.place;
        c.globalAlpha = 0.85;
        c.beginPath(); c.arc(sx, sy, 2, 0, 6.2832); c.fill();

        const size = 9 + Math.min(4, (p.d || 1) / 3);
        c.font = `${size.toFixed(1)}px Rajdhani, sans-serif`;
        c.fillStyle = '#7f92a6';
        c.globalAlpha = 0.9;
        c.fillText(p.id.replace(/_/g, ' ').toUpperCase(), sx, sy - 6);
        c.globalAlpha = 1;
    }
}

// The observer ring
function drawObserver() {
    if (!S.observer) return;
    const c = S.ctx;
    const sx = w2sx(S.observer.x), sy = w2sy(S.observer.y);
    const r = Math.max(4, S.observer.radius * S.view.ppm);

    c.strokeStyle = '#4fd0ff'; c.lineWidth = 2; c.globalAlpha = 0.85;
    c.setLineDash([8, 5]);
    c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.stroke();
    c.setLineDash([]);

    c.globalAlpha = 0.05; c.fillStyle = '#4fd0ff';
    c.beginPath(); c.arc(sx, sy, r, 0, 6.2832); c.fill();

    c.globalAlpha = 1;
    c.fillStyle = '#4fd0ff';
    c.font = 'bold 10px Consolas, monospace';
    c.textAlign = 'center';
    c.fillText(AT('atlas.chip_obs', 'OBSERVING {r}m', { r: Math.round(S.observer.radius) }), sx, sy - r - 6);
}

function drawSelectionRect() {
    const r = S.dragRect || S.rect;
    if (!r) return;
    const c = S.ctx;
    const x = w2sx(Math.min(r.x1, r.x2)), y = w2sy(Math.max(r.y1, r.y2));
    const w = Math.abs(r.x2 - r.x1) * S.view.ppm;
    const h = Math.abs(r.y2 - r.y1) * S.view.ppm;

    c.strokeStyle = S.dragRect ? '#ffb648' : '#5ee08a';
    c.lineWidth = 1.5;
    c.setLineDash([6, 4]);
    c.strokeRect(x, y, w, h);
    c.setLineDash([]);
    c.globalAlpha = 0.07;
    c.fillStyle = S.dragRect ? '#ffb648' : '#5ee08a';
    c.fillRect(x, y, w, h);
    c.globalAlpha = 1;

    c.fillStyle = '#ffb648';
    c.font = '10px Consolas, monospace';
    c.textAlign = 'left';
    c.fillText(`${Math.round(Math.abs(r.x2 - r.x1))}m x ${Math.round(Math.abs(r.y2 - r.y1))}m`, x + 4, y - 4);
}

// The stale veil: a hatch rather than just dimming, so it reads as an overlay.
function drawStale() {
    const c = S.ctx;
    c.globalAlpha = 0.55; c.fillStyle = '#07090c';
    c.fillRect(0, 0, S.w, S.h);
    c.globalAlpha = 0.10; c.strokeStyle = '#ff5f56'; c.lineWidth = 2;
    c.beginPath();
    for (let x = -S.h; x < S.w; x += 26) { c.moveTo(x, S.h); c.lineTo(x + S.h, 0); }
    c.stroke();
    c.globalAlpha = 1;
}

// the frame

function frame() {
    if (!S.running) return;
    requestAnimationFrame(frame);
    if (!S.cv || S.cv.offsetParent === null) return;   // hidden: do not burn the GPU

    clear();
    drawPlane();

    const snap = S.cur;
    if (snap) {
        // t: progress through the interval after the current snapshot's arrival, using the previous interval's length
        let t = 0;
        if (!S.stale && S.prevAt) {
            const interval = Math.max(60, S.curAt - S.prevAt);
            t = Math.max(0, Math.min(1, (performance.now() - S.curAt) / interval));
        }

        if (S.layers.cells)   drawCells(snap);
        if (S.layers.heat)    drawHeat(snap);
        if (S.layers.places)  drawPlaces();
        if (S.layers.noise)   drawNoise(snap);
        if (S.layers.herds)   drawHerds(snap);
        if (S.layers.hordes)  drawHordes(snap);
        if (S.layers.agents)  drawAgents(snap, t);
        if (S.layers.players) drawPlayers(snap);
    } else {
        if (S.layers.places) drawPlaces();
    }

    drawObserver();
    drawSelectionRect();

    // You. Drawn from the pushed position, not the snapshot, so panning away does not lose you.
    if (S.me) drawActor(S.ctx, w2sx(S.me.x), w2sy(S.me.y), S.me.h, COLOURS.me, AT('atlas.cv.you', 'YOU'), null);

    if (S.layers.cars) drawCars();

    if (S.stale) drawStale();
    drawMapNote();   // after the veil: stays readable while stale
}

// pointer

function bindPointer() {
    let dragging = false, rectDrag = false;
    let lastX = 0, lastY = 0, downX = 0, downY = 0, moved = 0;

    S.cv.addEventListener('contextmenu', e => e.preventDefault());

    S.cv.addEventListener('mousedown', e => {
        downX = e.offsetX; downY = e.offsetY; moved = 0;

        // Right button (or left while SELECT AREA is armed) drags a rectangle; left drags the map.
        if (e.button === 2 || S.rectArmed) {
            rectDrag = true;
            S.dragRect = { x1: s2wx(e.offsetX), y1: s2wy(e.offsetY),
                           x2: s2wx(e.offsetX), y2: s2wy(e.offsetY) };
        } else {
            dragging = true;
            S.cv.classList.add('is-dragging');
        }
        lastX = e.offsetX; lastY = e.offsetY;
    });

    window.addEventListener('mousemove', e => {
        const r = S.cv.getBoundingClientRect();
        const px = e.clientX - r.left, py = e.clientY - r.top;

        if (S.hooks.onCursor) S.hooks.onCursor(s2wx(px), s2wy(py));

        if (rectDrag && S.dragRect) {
            S.dragRect.x2 = s2wx(px); S.dragRect.y2 = s2wy(py);
            return;
        }
        if (!dragging) return;

        const dx = px - lastX, dy = py - lastY;
        moved += Math.abs(dx) + Math.abs(dy);
        S.view.cx -= dx / S.view.ppm;
        S.view.cy += dy / S.view.ppm;
        lastX = px; lastY = py;
        if (S.hooks.onView) S.hooks.onView();
    });

    window.addEventListener('mouseup', e => {
        const r = S.cv.getBoundingClientRect();
        const px = e.clientX - r.left, py = e.clientY - r.top;

        if (rectDrag) {
            rectDrag = false;
            const d = S.dragRect; S.dragRect = null;
            S.rectArmed = false;
            if (d && Math.abs(d.x2 - d.x1) > 5 && Math.abs(d.y2 - d.y1) > 5) {
                S.rect = d;
                if (S.hooks.onRect) S.hooks.onRect(d);
            }
            return;
        }

        if (!dragging) return;
        dragging = false;
        S.cv.classList.remove('is-dragging');

        // A click is a drag that went nowhere: the threshold stops every pan from ending in an inspect call
        if (moved > 4) return;
        if (px < 0 || py < 0 || px > S.w || py > S.h) return;

        const wx = s2wx(px), wy = s2wy(py);

        if (S.pickMode) {
            S.pickMode = false;
            S.cv.classList.remove('is-picking');
            const kind = S.pickKind || 'observe';
            S.pickKind = null;
            if (S.hooks.onPick) S.hooks.onPick(wx, wy, kind);
            return;
        }

        const cs = (S.cur && S.cur.cellSize) || 50;
        if (S.hooks.onCellClick) S.hooks.onCellClick(Math.floor(wx / cs), Math.floor(wy / cs), wx, wy);
    });

    // passive:false so preventDefault works; otherwise CEF scrolls the page behind the canvas.
    S.cv.addEventListener('wheel', e => {
        e.preventDefault();
        const span = S.w / S.view.ppm;
        setSpan(span * (e.deltaY > 0 ? 1.18 : 1 / 1.18), e.offsetX, e.offsetY);
    }, { passive: false });
}

// Measuring a canvas that is not on screen yet
function resize() {
    if (!S.cv) return;

    const w = S.cv.clientWidth;
    const h = S.cv.clientHeight;

    // (A) Asked too early (display:none or layout not done): keep the last good size and let the ResizeObserver call again
    if (w <= 0 || h <= 0) {
        if (!S.warnedZeroSize) {
            S.warnedZeroSize = true;
            console.warn('[atlas] canvas measured 0x0 - not on screen yet; '
                + 'waiting for a real size rather than storing a zero scale.');
        }
        return;
    }
    S.warnedZeroSize = false;

    // (B) Read the current span before the width changes, and only if ppm is usable (on the first measurement it is still 0)
    const hadSpan = (S.w > 0 && S.view.ppm > 0) ? (S.w / S.view.ppm) : null;

    // devicePixelRatio matters: on a 4K screen a 1px line drawn into a CSS-sized backing store becomes a soft 2px smear
    S.dpr = window.devicePixelRatio || 1;
    S.w = w;
    S.h = h;
    S.cv.width = Math.round(S.w * S.dpr);
    S.cv.height = Math.round(S.h * S.dpr);
    S.ctx.setTransform(S.dpr, 0, 0, S.dpr, 0, 0);

    if (hadSpan) {
        S.view.ppm = S.w / hadSpan;
    } else if (!(S.view.ppm > 0)) {
        // First usable size and no view chosen yet: fit the whole world instead of leaving ppm at 0.
        API.fitWorld();
        return;   // fitWorld to setSpan already fired the onView hook
    }

    if (S.hooks.onView) S.hooks.onView();
}

// public shape

// Named (not anonymous) because resize() calls API.fitWorld() on the first usable measurement
const API = {
    COLOURS, RAMP, rampColour,

    init(canvas, hooks) {
        S.cv = canvas;
        S.ctx = canvas.getContext('2d', { alpha: false });
        S.hooks = hooks || {};
        bindPointer();
        window.addEventListener('resize', resize);

        // The ResizeObserver is the real fix (see the note on resize())
        if (typeof ResizeObserver === 'function') {
            try {
                new ResizeObserver(resize).observe(S.cv);
            } catch (e) {
                console.warn('[atlas] ResizeObserver failed:', e);
            }
        } else {
            console.warn('[atlas] no ResizeObserver - polling for a canvas size.');
            const poll = setInterval(function () {
                if (S.cv && S.cv.clientWidth > 0) { clearInterval(poll); resize(); }
            }, 200);
        }

        resize();
        S.running = true;
        requestAnimationFrame(frame);
    },

    setWorld(bounds, points, limits) {
        if (bounds) S.world = bounds;
        if (points) S.points = points;
        if (limits) { S.minSpan = limits.min || S.minSpan; S.maxSpan = limits.max || S.maxSpan; }
    },

    centreOn(x, y, spanMetres) {
        S.view.cx = x; S.view.cy = y;
        if (spanMetres) setSpan(spanMetres);
        else if (S.hooks.onView) S.hooks.onView();
    },

    fitWorld() {
        const W = S.world;
        S.view.cx = (W.minX + W.maxX) / 2;
        S.view.cy = (W.minY + W.maxY) / 2;
        // Fit the taller axis: San Andreas is 12km north-south and 9km across.
        const needX = (W.maxX - W.minX) * 1.06;
        const needY = (W.maxY - W.minY) * 1.06 * (S.w / Math.max(1, S.h));
        setSpan(Math.max(needX, needY));
    },

    // A new snapshot
    setSnapshot(snap) {
        S.agentPrev.clear();
        if (S.cur) {
            for (let i = 0; i < S.cur.agents.length; i++) {
                const a = S.cur.agents[i];
                S.agentPrev.set(a.id, { x: a.x, y: a.y });
            }
        }
        S.prev = S.cur; S.prevAt = S.curAt;
        S.cur = snap; S.curAt = performance.now();
        S.stale = false;
        // The server sends the live points (config + survey), so labels follow the survey instead of the copy the page opened with
        if (Array.isArray(snap.points)) S.points = snap.points.filter(p => !p.removed);
    },

    // The map image. url: where to load it
    setMapImage(url, calib, note) {
        const M = S.map;
        const K = calib && ['minX', 'maxX', 'minY', 'maxY'].every(k => Number.isFinite(Number(calib[k])))
            && Number(calib.maxX) > Number(calib.minX) && Number(calib.maxY) > Number(calib.minY)
            ? { minX: +calib.minX, maxX: +calib.maxX, minY: +calib.minY, maxY: +calib.maxY } : null;
        M.calib = K;
        M.note = note || '';
        const report = () => { if (S.hooks.onMapState) S.hooks.onMapState(M.state, M.note); };

        if (!url) { M.state = 'none'; M.img = null; M.url = null; report(); return; }

        if (url === M.url && M.img) {
            if (M.img.complete && M.img.naturalWidth > 0) M.state = K ? 'ok' : 'uncalibrated';
            report();
            return;
        }

        M.url = url;
        M.state = 'loading';
        report();
        const img = new Image();
        img.onload = () => {
            if (M.url !== url) return;       // superseded while loading
            M.img = img;
            M.state = M.calib ? 'ok' : 'uncalibrated';
            report();
        };
        img.onerror = () => {
            if (M.url !== url) return;
            M.img = null;
            M.state = 'failed';
            M.note = (M.note ? M.note + ' ' : '') + '(' + url.replace(/key=[^&]+/, 'key=...') + ')';
            report();
        };
        img.src = url;
    },
    setMapOpacity(v) { S.map.opacity = Math.max(0, Math.min(1, Number(v) || 0)); },
    mapState()       { return { state: S.map.state, note: S.map.note, calib: S.map.calib, opacity: S.map.opacity }; },

    setStale(v)      { S.stale = !!v; },
    setMe(m)         { S.me = m; },
    setCars(list)    { S.cars = Array.isArray(list) ? list : []; },
    setObserver(o)   { S.observer = o; },
    setSelected(c)   { S.selected = c; },
    setRect(r)       { S.rect = r; },
    armRect(v)       { S.rectArmed = !!v; },
    pick(v, kind)    { S.pickMode = !!v; S.pickKind = v ? (kind || 'observe') : null; S.cv.classList.toggle('is-picking', !!v); },
    CAR_COLOURS,

    layers: S.layers,
    view:   S.view,
    viewRect,
    centre() { return { x: S.view.cx, y: S.view.cy }; },
    spanMetres() { return S.w / S.view.ppm; },
    setSpan,
    snapshot() { return S.cur; },
};

return API;

})();

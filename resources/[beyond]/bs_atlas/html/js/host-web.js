// bs_atlas - web host for the node atlas, loaded only by the web panel (/nodes)

'use strict';

(function () {

const KEY = new URLSearchParams(location.search).get('key');

// Resource-relative base
let BASE = location.pathname;
if (/\.html?$/i.test(BASE)) BASE = BASE.replace(/[^/]*$/, '');
BASE = BASE.replace(/\/?$/, '/');

function url(p) {
    const u = new URL(String(p).replace(/^\//, ''), location.origin + BASE);
    if (KEY) u.searchParams.set('key', KEY);
    return u.toString();
}

const TIMEOUT_MS = 8000;   /* same as AtlasUI.callTimeoutMs in game */

// One HTTP call mapped to the three outcomes app.js distinguishes
async function http(path, body, method) {
    const ctl = (typeof AbortController === 'function') ? new AbortController() : null;
    const timer = ctl ? setTimeout(() => ctl.abort(), TIMEOUT_MS) : null;
    try {
        const r = await fetch(url(path), {
            method: method || 'POST',
            headers: body != null ? { 'Content-Type': 'application/json; charset=UTF-8' } : {},
            body: body != null ? JSON.stringify(body) : undefined,
            cache: 'no-store',
            signal: ctl ? ctl.signal : undefined,
        });
        if (r.status === 401 || r.status === 403) {
            return { ok: false, error: `panel key rejected (HTTP ${r.status}) - reopen the panel from the link printed in the server console` };
        }
        let data = null;
        try { data = await r.json(); } catch (_) { /* not JSON */ }
        if (!data || typeof data !== 'object') {
            return { ok: false, error: `HTTP ${r.status}: the server did not answer with JSON` };
        }
        return data;
    } catch (e) {
        return { ok: false, error: 'no answer from the server (' + (e && e.name === 'AbortError' ? 'timed out' : e) + ')', timedOut: true };
    } finally {
        if (timer) clearTimeout(timer);
    }
}

// The six operations the web API exposes - the same six the NUI bridge whitelists in cl_atlas.lua
const OPS = { snapshot: 1, inspect: 1, edit: 1, repopulate: 1, observe: 1, config: 1 };

let observer = null;       /* what the SERVER accepted: { x, y, radius } */
let obsTimer = null;
let refreshSeconds = 100;

function stopRefresh() { if (obsTimer) { clearInterval(obsTimer); obsTimer = null; } }

function startRefresh() {
    stopRefresh();
    obsTimer = setInterval(async () => {
        if (!observer) return stopRefresh();
        const res = await http('api/observe', { x: observer.x, y: observer.y, radius: observer.radius, on: true });
        // Report either way, like cl_atlas.lua: a silently failing refresh stops watching the region.
        window.postMessage({ action: 'observerState', ok: res.ok === true, res, observer }, '*');
    }, refreshSeconds * 1000);
}

async function post(endpoint, data) {
    data = data || {};
    switch (endpoint) {
        case 'call': {
            const op = String(data.name || '').replace(/^zombies:atlas:/, '');
            if (!OPS[op]) return { ok: false, error: 'refused locally: not an atlas operation' };
            return http('api/' + op, data.args || {}, 'POST');
        }
        case 'observer': {
            if (data.on === false) {
                const at = observer || { x: 0, y: 0, radius: 0 };
                observer = null;
                stopRefresh();
                // x/y are required by the server even to clear (it validates before it looks at on), so send the last point
                return http('api/observe', { x: at.x, y: at.y, radius: at.radius, on: false });
            }
            const res = await http('api/observe', { x: data.x, y: data.y, radius: data.radius, on: true });
            if (!res.ok) return res;     /* never keep a point the server refused */
            observer = { x: res.x, y: res.y, radius: res.radius };
            startRefresh();
            res.observer = observer;
            return res;
        }
        case 'close':    return { ok: true };
        case 'waypoint': return { ok: false, error: 'no player body on the web panel - waypoints are in-game only' };
    }
    return { ok: false, error: 'unknown endpoint ' + endpoint };
}

// Best-effort clear when the tab goes away
window.addEventListener('pagehide', () => {
    if (!observer || !navigator.sendBeacon) return;
    try {
        navigator.sendBeacon(url('api/observe'),
            JSON.stringify({ x: observer.x, y: observer.y, radius: observer.radius, on: false }));
    } catch (_) { /* nothing more we can do; the TTL will */ }
});

window.AtlasHost = {
    kind: 'web',
    caps: { me: false, waypoint: false, close: false, calibrate: true },
    post,
};

// boot

const $ = id => document.getElementById(id);
let mapPath = null;

function mapMessage(calib, note) {
    window.postMessage({ action: 'map', map: { url: mapPath ? url(mapPath) : null, calib, note } }, '*');
}

function readCalInputs() {
    const c = {
        minX: Number($('calMinX').value), maxX: Number($('calMaxX').value),
        minY: Number($('calMinY').value), maxY: Number($('calMaxY').value),
    };
    return Object.values(c).every(Number.isFinite) ? c : null;
}

function fillCalInputs(c) {
    if (!c) return;
    $('calMinX').value = c.minX; $('calMaxX').value = c.maxX;
    $('calMinY').value = c.minY; $('calMaxY').value = c.maxY;
}

// Map calibration: route /api/calibration, file nodes/calibration.json, validated on the server.
function wireCalibration() {
    $('btnCalPreview').addEventListener('click', () => {
        const c = readCalInputs();
        if (!c) { $('calState').textContent = 'All four numbers are required.'; return; }
        mapMessage(c, 'PREVIEW - not saved.');
        $('calState').textContent = 'Previewing. Nothing is saved until SAVE MAP BOUNDS.';
    });
    $('btnCalSave').addEventListener('click', async () => {
        const c = readCalInputs();
        if (!c) { $('calState').textContent = 'All four numbers are required.'; return; }
        if (!window.confirm('Save these map bounds to nodes/calibration.json?\n\n'
            + 'This realigns the map image on this panel AND on the in-game /atlas (next time it is opened).')) return;
        const res = await http('api/calibration', c, 'POST');
        if (!res.ok) { $('calState').textContent = 'SAVE FAILED: ' + (res.error || 'no answer'); return; }
        fillCalInputs(res.calib);
        mapMessage(res.calib, '');
        $('calState').textContent = 'Saved to calibration.json at ' + new Date().toLocaleTimeString('en-GB') + '.';
    });
}

async function boot() {
    const b = await http('api/boot', null, 'GET');
    if (!b.ok) {
        // Open anyway with a guessed world box
        window.postMessage({
            action: 'open',
            world: { minX: -4000, maxX: 5000, minY: -4000, maxY: 8000 },
            points: [], me: null, cfg: {},
            map: { error: 'boot failed: ' + (b.error || 'no answer') },
        }, '*');
        return;
    }

    const cfg = b.cfg || {};
    refreshSeconds = cfg.observerRefreshSeconds || 100;
    mapPath = b.map && b.map.path;
    fillCalInputs(b.map && b.map.calib);
    $('calState').textContent = (b.map && b.map.note) || 'Loaded from calibration.json.';
    wireCalibration();

    window.postMessage({
        action: 'open',
        world: b.world,
        points: b.points || [],
        me: null,
        cfg,
        map: mapPath
            ? { url: url(mapPath), calib: b.map.calib, note: b.map.note || '' }
            : { error: (b.map && b.map.error) || 'no map image on the server' },
    }, '*');
}

window.addEventListener('load', boot);

})();

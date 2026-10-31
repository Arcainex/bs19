// bs_atlas - web host for the node atlas, loaded only by the web panel (/nodes)

'use strict';

(function () {

const KEY = new URLSearchParams(location.search).get('key');
const W = (key, vars) => window.BSI18n.t('atlas.web.' + key, vars);
function useLocale(locale) {
    if (!locale || !locale.dict) return;
    window.dispatchEvent(new MessageEvent('message', {data: {action: 'bs_i18n', lang: locale.lang, dict: locale.dict}}));
}
function localTime() { return new Date().toLocaleTimeString(window.BSI18n.lang() || 'en'); }


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
            return { ok: false, error: W('auth', {status: r.status}) };
        }
        let data = null;
        try { data = await r.json(); } catch (_) { /* not JSON */ }
        if (!data || typeof data !== 'object') {
            return { ok: false, error: W('not_json', {status: r.status}) };
        }
        return data;
    } catch (e) {
        return { ok: false, error: W('no_answer', {error: e && e.name === 'AbortError' ? W('timeout') : String(e)}), timedOut: true };
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
            if (!OPS[op]) return { ok: false, error: W('invalid_op') };
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
        case 'waypoint': return { ok: false, error: W('no_waypoint') };
    }
    return { ok: false, error: W('unknown_endpoint', {endpoint}) };
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
        if (!c) { $('calState').textContent = W('four_numbers'); return; }
        mapMessage(c, W('preview_note'));
        $('calState').textContent = W('preview_state');
    });
    $('btnCalSave').addEventListener('click', async () => {
        const c = readCalInputs();
        if (!c) { $('calState').textContent = W('four_numbers'); return; }
        if (!window.confirm(W('save_confirm'))) return;
        const res = await http('api/calibration', c, 'POST');
        if (!res.ok) { $('calState').textContent = W('save_failed', {error: res.error || window.BSI18n.t('atlas.no_answer')}); return; }
        fillCalInputs(res.calib);
        mapMessage(res.calib, '');
        $('calState').textContent = W('saved', {time: localTime()});
    });
}

async function boot() {
    useLocale(window.__BS_ATLAS_LOCALE__);
    const b = await http('api/boot', null, 'GET');
    if (b.locale) useLocale(b.locale);
    if (!b.ok) {
        // Open anyway with a guessed world box
        window.postMessage({
            action: 'open',
            world: { minX: -4000, maxX: 5000, minY: -4000, maxY: 8000 },
            points: [], me: null, cfg: {},
            map: { error: W('boot_failed', {error: b.error || window.BSI18n.t('atlas.no_answer')}) },
        }, '*');
        return;
    }

    const cfg = b.cfg || {};
    refreshSeconds = cfg.observerRefreshSeconds || 100;
    mapPath = b.map && b.map.path;
    fillCalInputs(b.map && b.map.calib);
    $('calState').textContent = (b.map && b.map.note) || W('loaded');
    wireCalibration();

    window.postMessage({
        action: 'open',
        world: b.world,
        points: b.points || [],
        me: null,
        cfg,
        map: mapPath
            ? { url: url(mapPath), calib: b.map.calib, note: b.map.note || '' }
            : { error: (b.map && b.map.error) || W('no_map') },
    }, '*');
}

window.addEventListener('load', boot);

})();

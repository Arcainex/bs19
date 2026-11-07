// nui.js - message router and shared helpers. Panels register a handler per `action`.

const BS = {
    handlers: {},
    resource: (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'bs_ui',

    /** Registers a handler for an incoming NUI action. */
    on(action, fn) {
        (this.handlers[action] ||= []).push(fn);
    },

    /** POSTs to a RegisterNUICallback in cl_nui.lua. Returns the parsed body. */
    async post(endpoint, data = {}) {
        const res = await fetch(`https://${this.resource}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return res.json().catch(() => ({}));
    },

    /** Calls a bs_core server callback through the generic bridge. */
    callback(name, ...args) {
        return this.post('callback', { callback: name, args });
    },

    close(panel) {
        return this.post('close', { panel });
    },

    // Inline icon set, no external requests.
    icon(name, cls = '') {
        const paths = {
            heart:   'M12 20s-7-4.35-7-9a4 4 0 0 1 7-2.65A4 4 0 0 1 19 11c0 4.65-7 9-7 9z',
            shield:  'M12 3l7 3v5c0 4.4-3 8.3-7 10-4-1.7-7-5.6-7-10V6l7-3z',
            bolt:    'M13 2L4 14h6l-1 8 9-12h-6l1-8z',
            food:    'M7 3v8m0 0a3 3 0 0 0 3-3V3M7 11v10M17 3c-1.5 2-2 4-2 6s.5 3 2 3v9',
            drop:    'M12 3s6 6.5 6 10.5A6 6 0 0 1 6 13.5C6 9.5 12 3 12 3z',
            check:   'M4 12l5 5L20 6',
            warn:    'M12 4l9 16H3L12 4zm0 6v5m0 3v.5',
            error:   'M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM9 9l6 6m0-6l-6 6',
            info:    'M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zm0 4v.5M12 11v6',
            virus:   'M12 6a6 6 0 1 0 0 12 6 6 0 0 0 0-12zM12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5M17.5 17.5 19 19M19 5l-1.5 1.5M6.5 17.5 5 19',
            bag:     'M6 8h12l-1 12H7L6 8zm3 0V6a3 3 0 0 1 6 0v2',
        };
        const d = paths[name] || paths.info;
        return `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                 stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="${d}"/></svg>`;
    },

    money(value) {
        return '$' + Number(value || 0).toLocaleString('en-US');
    },
};

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const list = BS.handlers[payload.action];
    if (!list) return;
    for (const fn of list) {
        try { fn(payload); } catch (err) { console.error('[BS UI]', payload.action, err); }
    }
});

// Theme, layout and player settings arrive together in 'settings' and are handled in hud.js.

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') BS.close();
});

// /hidehud (bs_ui cl_hidehud.lua): hide the whole page for a clean screenshot.
window.addEventListener('message', (e) => { const d = e.data || {}; if (d.action === 'bsHideAll') document.documentElement.style.visibility = d.hidden ? 'hidden' : ''; });

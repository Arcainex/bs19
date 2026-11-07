// BeyondSurvival - menu palette shared by every NUI page. Polls bs_ui for the player's palette and writes the colour variables menus use. Loaded by scale.js, or directly by pages without scaling.
(function () {
    'use strict';
    if (window.BSPalette) return;
    var root = document.documentElement;
    var current = '';

    // palette key -> every custom property that page families use for that role
    var MAP = {
        accent: ['--bs-accent', '--amber', '--acc', '--accent', '--copper', '--rust', '--hx-rust'],
        hi:     ['--acc2', '--hx-rust-hi'],
        bg:     ['--soot', '--charcoal', '--hx-char', '--bs-bg'],
        text:   ['--bone', '--txt', '--bs-text', '--hx-bone'],
        muted:  ['--dust', '--ash', '--dim', '--bs-text-muted', '--hx-ash'],
        blood:  ['--blood', '--bs-blood', '--hx-blood']
    };

    function clear() {
        Object.keys(MAP).forEach(function (k) {
            MAP[k].forEach(function (v) { root.style.removeProperty(v); });
        });
        root.removeAttribute('data-bs-palette');
    }

    function apply(vars, id) {
        var sig = vars ? JSON.stringify(vars) : '';
        if (sig === current) return;
        current = sig;
        clear();
        if (!vars) return;
        Object.keys(MAP).forEach(function (k) {
            if (vars[k]) MAP[k].forEach(function (v) { root.style.setProperty(v, vars[k]); });
        });
        if (id) root.setAttribute('data-bs-palette', id);
    }

    function poll() {
        try {
            fetch('https://bs_ui/uiPaletteGet', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
                .then(function (r) { return r.json(); })
                .then(function (d) { if (d && d.ok) apply(d.vars || null, d.id); })
                .catch(function () { /* bs_ui not running: keep page colours */ });
        } catch (e) { /* no fetch */ }
    }

    window.BSPalette = { apply: apply, refresh: poll };
    poll();
    setInterval(poll, 4000);
})();

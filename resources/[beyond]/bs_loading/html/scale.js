// BeyondSurvival - resolution-adaptive NUI scaling shared by every [beyond] page. Pages are laid out for 1920x1080; the whole <body> is scaled with a transform (not CSS zoom, so client coordinates stay in one pixel space).
(function () {
    'use strict';
    if (window.BSScale) return;
    var BASE_W = 1920, BASE_H = 1080, AUTO_MIN = 0.6, AUTO_MAX = 1.25, OV_MIN = 0.6, OV_MAX = 1.4;
    var root = document.documentElement;
    var override = 0, scale = 0, listeners = [];

    var css = 'html.bs-scaled{overflow:hidden!important}' +
        'html.bs-scaled body{position:fixed!important;left:0!important;top:0!important;margin:0!important;' +
        'width:calc(100vw / var(--ui-scale,1))!important;height:calc(100vh / var(--ui-scale,1))!important;' +
        'min-width:0!important;min-height:0!important;max-width:none!important;max-height:none!important;' +
        'transform:scale(var(--ui-scale,1));transform-origin:0 0;overflow:hidden!important}';
    var st = document.createElement('style');
    st.id = 'bs-ui-scale';
    st.textContent = css;
    (document.head || root).appendChild(st);

    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
    function auto() {
        var w = window.innerWidth || BASE_W, h = window.innerHeight || BASE_H;
        return clamp(Math.min(w / BASE_W, h / BASE_H), AUTO_MIN, AUTO_MAX);
    }
    function apply() {
        if (root.hasAttribute('data-bs-noscale')) return;
        var n = override > 0 ? clamp(override, OV_MIN, OV_MAX) : auto();
        n = Math.round(n * 1000) / 1000;
        root.classList.add('bs-scaled');
        if (n === scale) return;
        scale = n;
        root.style.setProperty('--ui-scale', String(n));
        for (var i = 0; i < listeners.length; i++) { try { listeners[i](n); } catch (e) { /* page bug, ignore */ } }
    }
    function poll() {
        try {
            fetch('https://bs_ui/uiScaleGet', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
                .then(function (r) { return r.json(); })
                .then(function (d) {
                    var v = Number(d && d.scale) || 0;
                    if (v !== override) { override = v; apply(); }
                })
                .catch(function () { /* bs_ui not running: stay on auto */ });
        } catch (e) { /* no fetch */ }
    }

    window.BSScale = {
        get: function () { return scale || 1; },
        w: function () { return (window.innerWidth || BASE_W) / (scale || 1); },
        h: function () { return (window.innerHeight || BASE_H) / (scale || 1); },
        toLocal: function (px) { return px / (scale || 1); },
        onChange: function (fn) { if (typeof fn === 'function') listeners.push(fn); },
        set: function (v) { override = Number(v) || 0; apply(); },
        refresh: poll,
    };

    apply();
    window.addEventListener('resize', apply);
    window.addEventListener('message', function (e) {
        var d = e && e.data;
        if (d && d.action === 'bsUiScale') { override = Number(d.scale) || 0; apply(); }
    });
    poll();
    setInterval(poll, 4000);
})();

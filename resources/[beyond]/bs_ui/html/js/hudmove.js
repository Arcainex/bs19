// hudmove.js - drag HUD elements while move mode is on (CTRL, see cl_hudmove.lua).
(function () {
    'use strict';
    var IDS = ['xpbar', 'hud', 'hotbar', 'dashhud', 'throttle', 'partyhud'];
    var KEY = 'bs_hudpos';
    var pos = {};
    try { pos = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { pos = {}; }
    var haveLocal = Object.keys(pos).length > 0;

    function apply(id) {
        var el = document.getElementById(id);
        if (!el) return;
        var p = pos[id];
        el.style.translate = p ? p[0] + 'px ' + p[1] + 'px' : '';
    }
    function applyAll() { IDS.forEach(apply); }
    function save() {
        try { localStorage.setItem(KEY, JSON.stringify(pos)); } catch (e) { /* no storage */ }
        BS.post('hudPosSave', { pos: pos });
    }

    IDS.forEach(function (id) {
        var el = document.getElementById(id);
        if (!el) return;
        el.classList.add('hudmovable');
        var drag = null;
        el.addEventListener('mousedown', function (e) {
            if (!document.body.classList.contains('hudmove')) return;
            var p = pos[id] || [0, 0];
            drag = { x: e.clientX, y: e.clientY, ox: p[0], oy: p[1] };
            e.preventDefault();
        });
        window.addEventListener('mousemove', function (e) {
            if (!drag) return;
            pos[id] = [Math.round(drag.ox + e.clientX - drag.x), Math.round(drag.oy + e.clientY - drag.y)];
            apply(id);
        });
        window.addEventListener('mouseup', function () { if (drag) { drag = null; save(); } });
        el.addEventListener('dblclick', function () {
            if (!document.body.classList.contains('hudmove')) return;
            delete pos[id]; apply(id); save();
        });
    });
    applyAll();

    BS.on('hudMove', function (d) {
        document.body.classList.toggle('hudmove', !!d.on);
    });
    BS.on('hudPos', function (d) {
        if (haveLocal || !d.pos) return;
        pos = d.pos; haveLocal = Object.keys(pos).length > 0; applyAll();
    });
    document.addEventListener('keyup', function (e) {
        if (document.body.classList.contains('hudmove') && e.key === 'Escape') BS.post('hudMoveExit', {});
    });
})();

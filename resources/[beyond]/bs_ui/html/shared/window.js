// BeyondSurvival - draggable + resizable floating panels for NUI menus. Position/size is remembered per id in localStorage. Works with BSScale (shared/scale.js): all math is in scaled (layout) pixels.
(function () {
    'use strict';
    if (window.BSWindow) return;
    var PROPS = ['position', 'left', 'top', 'right', 'bottom', 'width', 'height', 'transform', 'margin', 'maxWidth', 'maxHeight', 'minWidth', 'minHeight', 'boxSizing'];
    var SKIP = 'button,input,select,textarea,a,label,[contenteditable],[data-nodrag]';
    var css = '.bsw-edge{position:absolute;z-index:5;touch-action:none}' +
        '.bsw-e{top:10px;right:-3px;width:6px;bottom:16px;cursor:ew-resize}' +
        '.bsw-s{left:10px;bottom:-3px;height:6px;right:16px;cursor:ns-resize}' +
        '.bsw-c{right:0;bottom:0;width:16px;height:16px;cursor:nwse-resize}';
    var st = document.createElement('style');
    st.textContent = css;
    (document.head || document.documentElement).appendChild(st);

    function scale() { return (window.BSScale && window.BSScale.get()) || 1; }
    function vw() { return (window.innerWidth || 1920) / scale(); }
    function vh() { return (window.innerHeight || 1080) / scale(); }
    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
    function resolve(x) { return typeof x === 'string' ? document.querySelector(x) : x; }

    function make(el, opts) {
        el = resolve(el);
        if (!el) return null;
        opts = opts || {};
        var key = 'bsw:' + (opts.id || el.id || 'win');
        var minW = opts.minW || 280, minH = opts.minH || 160;
        var handle = resolve(opts.handle) || el.querySelector('header') || el;
        var orig = {};
        for (var i = 0; i < PROPS.length; i++) orig[PROPS[i]] = el.style[PROPS[i]];
        var abs = false, box = null;

        function place(b) {
            b.w = clamp(b.w, Math.min(minW, vw()), vw());
            b.h = clamp(b.h, Math.min(minH, vh()), vh());
            b.x = clamp(b.x, 0, Math.max(0, vw() - b.w));
            b.y = clamp(b.y, 0, Math.max(0, vh() - b.h));
            var s = el.style;
            s.position = 'fixed'; s.boxSizing = 'border-box'; s.transform = 'none'; s.margin = '0';
            s.right = 'auto'; s.bottom = 'auto'; s.maxWidth = 'none'; s.maxHeight = 'none';
            s.minWidth = minW + 'px'; s.minHeight = minH + 'px';
            s.left = b.x + 'px'; s.top = b.y + 'px'; s.width = b.w + 'px'; s.height = b.h + 'px';
            abs = true; box = b;
        }
        function capture() {
            var r = el.getBoundingClientRect(), k = scale();
            if (!r.width) return null;
            return { x: r.left / k, y: r.top / k, w: r.width / k, h: r.height / k };
        }
        function save() {
            if (!box) return;
            try { localStorage.setItem(key, JSON.stringify(box)); } catch (e) { /* no storage */ }
        }
        function restore() {
            var b = null;
            try { b = JSON.parse(localStorage.getItem(key) || 'null'); } catch (e) { b = null; }
            if (b && isFinite(b.x) && isFinite(b.y) && b.w > 50 && b.h > 50) place(b);
        }
        function reset() {
            for (var i = 0; i < PROPS.length; i++) el.style[PROPS[i]] = orig[PROPS[i]];
            abs = false; box = null;
            try { localStorage.removeItem(key); } catch (e) { /* no storage */ }
        }
        function begin(e, mode) {
            if (e.button !== 0) return;
            if (mode === 'move' && e.target.closest && e.target.closest(SKIP)) return;
            var b = abs ? { x: box.x, y: box.y, w: box.w, h: box.h } : capture();
            if (!b) return;
            place(b);
            var sx = e.clientX, sy = e.clientY, k = scale(), o = { x: b.x, y: b.y, w: b.w, h: b.h };
            var src = e.currentTarget;
            try { src.setPointerCapture(e.pointerId); } catch (x) { /* ignore */ }
            function mv(ev) {
                var dx = (ev.clientX - sx) / k, dy = (ev.clientY - sy) / k;
                if (mode === 'move') {
                    place({ x: o.x + dx, y: o.y + dy, w: o.w, h: o.h });
                } else {
                    var w = mode.indexOf('e') >= 0 || mode === 'c' ? o.w + dx : o.w;
                    var h = mode.indexOf('s') >= 0 || mode === 'c' ? o.h + dy : o.h;
                    place({ x: o.x, y: o.y, w: Math.min(w, vw() - o.x), h: Math.min(h, vh() - o.y) });
                }
            }
            function up() {
                src.removeEventListener('pointermove', mv);
                src.removeEventListener('pointerup', up);
                src.removeEventListener('pointercancel', up);
                try { src.releasePointerCapture(e.pointerId); } catch (x) { /* ignore */ }
                save();
            }
            src.addEventListener('pointermove', mv);
            src.addEventListener('pointerup', up);
            src.addEventListener('pointercancel', up);
            e.preventDefault();
        }

        handle.style.cursor = 'move';
        handle.addEventListener('pointerdown', function (e) { begin(e, 'move'); });
        handle.addEventListener('dblclick', function (e) {
            if (e.target.closest && e.target.closest(SKIP)) return;
            reset();
        });
        var parts = [['bsw-c', 'c'], ['bsw-e', 'e'], ['bsw-s', 's']];
        var grips = [];
        for (var j = 0; j < parts.length; j++) {
            var g = (j === 0 && resolve(opts.grip)) || null;
            if (!g) { g = document.createElement('div'); g.className = 'bsw-edge ' + parts[j][0]; el.appendChild(g); }
            (function (node, mode) { node.addEventListener('pointerdown', function (e) { begin(e, mode); }); })(g, parts[j][1]);
            if (j === 0) g.addEventListener('dblclick', reset);
            grips.push(g);
        }
        function refit() { if (abs) { place({ x: box.x, y: box.y, w: box.w, h: box.h }); } }
        window.addEventListener('resize', refit);
        if (window.BSScale) window.BSScale.onChange(refit);

        restore();
        return { reset: reset, restore: restore, el: el };
    }

    window.BSWindow = { make: make };
})();

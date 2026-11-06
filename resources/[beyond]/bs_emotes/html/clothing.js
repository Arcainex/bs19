// Clothing wheel: one ring segment per slot, picked by cursor angle so the gaps never drop the hover.
// Clicking toggles that piece and the wheel stays open with the new states; Esc or right click closes it.
(function () {
    var RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_emotes';
    var NS = 'http://www.w3.org/2000/svg';
    var SIZE = 560, OUTER = 270, INNER = 118, GAP = 1.4;

    // Line icons, 24x24 grid, stroked in CSS.
    var ICONS = {
        hat: 'M3 17h18M6 17c0-6 2.5-10 6-10s6 4 6 10M9 11h6',
        glasses: 'M2 12h4m12 0h4M6 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0zm6 0a3 3 0 1 0 6 0 3 3 0 0 0-6 0z',
        mask: 'M4 8c5-2 11-2 16 0v4c0 4-4 7-8 7s-8-3-8-7V8zM8 12h2m4 0h2M2 9v3m20-3v3',
        jacket: 'M8 3l4 3 4-3 4 3-2 4v11H6V10L4 6l4-3zm4 3v15',
        vest: 'M8 3h2l2 3 2-3h2l1 4v14H7V7l1-4zM12 6v15M9 12h2m2 0h2',
        gloves: 'M8 21v-4l-2.5-4.5a1.5 1.5 0 0 1 2.5-1.6l1 1.6V6a3 3 0 0 1 6 0v.5a2 2 0 0 1 3 1.7V15c0 2-1 4-2 6H8zM8 18h8',
        pants: 'M7 3h10l1 18h-4l-2-11-2 11H6L7 3zM7 7h10',
        shoes: 'M3 16v-5h5l2 2 6 1c3 .5 5 1.5 5 3v1H3zM3 19h18',
        bag: 'M6 8h12l-1 12H7L6 8zm3 0V6a3 3 0 0 1 6 0v2M9 13h6',
        dot: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z'
    };
    var STATE_TEXT = { on: 'On', off: 'Off', none: 'None' };
    var ACT_TEXT = { on: 'Click to take off', off: 'Click to put on', none: 'Nothing to take off' };

    var S = { open: false, token: 0, slots: [], hover: -1, busy: false };
    var root, svg, segs = [], hub = {}, countEl, titleEl;

    function post(name, body) {
        return fetch('https://' + RES + '/' + name, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {})
        }).then(function (r) { return r.json(); }).catch(function () { return {}; });
    }

    function el(tag, cls, parent, ns) {
        var n = ns ? document.createElementNS(NS, tag) : document.createElement(tag);
        if (cls) n.setAttribute('class', cls);
        if (parent) parent.appendChild(n);
        return n;
    }

    function polar(r, deg) {
        var a = (deg - 90) * Math.PI / 180;
        return [r * Math.cos(a), r * Math.sin(a)];
    }

    function sector(r1, r2, a1, a2) {
        var large = (a2 - a1) > 180 ? 1 : 0;
        var p1 = polar(r2, a1), p2 = polar(r2, a2), p3 = polar(r1, a2), p4 = polar(r1, a1);
        return 'M' + p1 + 'A' + r2 + ',' + r2 + ' 0 ' + large + ' 1 ' + p2 + 'L' + p3 +
            'A' + r1 + ',' + r1 + ' 0 ' + large + ' 0 ' + p4 + 'Z';
    }

    function arc(r, a1, a2) {
        var p1 = polar(r, a1), p2 = polar(r, a2);
        return 'M' + p1 + 'A' + r + ',' + r + ' 0 ' + ((a2 - a1) > 180 ? 1 : 0) + ' 1 ' + p2;
    }

    function build() {
        root = el('div', null, document.body);
        root.id = 'cw';
        el('div', 'cw-veil', root);
        var stage = el('div', 'cw-stage', root);

        var plate = el('div', 'cw-plate', stage);
        el('div', 'cw-kicker', plate).textContent = 'Survivor file / Kit';
        var title = el('div', 'cw-title', plate);
        titleEl = el('h1', null, title);
        countEl = el('span', 'cw-count', title);

        var wheel = el('div', 'cw-wheel', stage);
        svg = el('svg', null, wheel, true);
        svg.setAttribute('viewBox', (-SIZE / 2) + ' ' + (-SIZE / 2) + ' ' + SIZE + ' ' + SIZE);

        var h = el('div', 'cw-hub', wheel);
        hub.kicker = el('div', 'cw-hub__kicker', h);
        hub.name = el('div', 'cw-hub__name', h);
        hub.stamp = el('span', 'cw-stamp', h);
        hub.act = el('div', 'cw-hub__act', h);

        var keys = el('div', 'cw-keys', stage);
        [['LMB', 'Toggle'], ['RMB', 'Close'], ['ESC', 'Close']].forEach(function (k) {
            var s = el('span', null, keys);
            el('kbd', null, s).textContent = k[0];
            s.appendChild(document.createTextNode(k[1]));
        });
    }

    function drawRing() {
        while (svg.firstChild) svg.removeChild(svg.firstChild);
        segs = [];
        var disc = el('circle', 'cw-disc', svg, true);
        disc.setAttribute('r', OUTER + 8);

        var n = S.slots.length, step = 360 / n;
        S.slots.forEach(function (slot, i) {
            var a1 = i * step - step / 2 + GAP / 2, a2 = (i + 1) * step - step / 2 - GAP / 2, mid = i * step;
            var g = el('g', 'cw-seg', svg, true);
            el('path', 'cw-face', g, true).setAttribute('d', sector(INNER, OUTER, a1, a2));
            el('path', 'cw-edge', g, true).setAttribute('d', arc(OUTER - 3, a1 + .6, a2 - .6));

            var c = polar(182, mid);
            var icon = el('g', null, g, true);
            icon.setAttribute('transform', 'translate(' + (c[0] - 19.2) + ',' + (c[1] - 19.2) + ') scale(1.6)');
            el('path', 'cw-icon', icon, true).setAttribute('d', ICONS[slot.icon] || ICONS.dot);
            var strike = el('line', 'cw-strike', icon, true);
            strike.setAttribute('x1', 3); strike.setAttribute('y1', 21); strike.setAttribute('x2', 21); strike.setAttribute('y2', 3);

            var t = polar(236, mid);
            var label = el('text', null, g, true);
            label.setAttribute('x', t[0]); label.setAttribute('y', t[1] + 5);
            label.textContent = slot.label;

            var p = polar(136, mid);
            var pip = el('circle', 'cw-pip', g, true);
            pip.setAttribute('cx', p[0]); pip.setAttribute('cy', p[1]); pip.setAttribute('r', 4);

            segs.push(g);
        });

        // small ticks at the segment borders on the outer rim
        for (var i = 0; i < n; i++) {
            var a = i * step - step / 2, o = polar(OUTER + 8, a), q = polar(OUTER + 16, a);
            var tk = el('line', 'cw-tick', svg, true);
            tk.setAttribute('x1', o[0]); tk.setAttribute('y1', o[1]); tk.setAttribute('x2', q[0]); tk.setAttribute('y2', q[1]);
        }
        paint();
    }

    function paint() {
        var worn = 0;
        S.slots.forEach(function (slot, i) {
            if (slot.state === 'on') worn++;
            var cls = 'cw-seg is-' + (STATE_TEXT[slot.state] ? slot.state : 'none') + (i === S.hover ? ' is-hover' : '');
            if (segs[i]) segs[i].setAttribute('class', cls);
        });
        countEl.textContent = '';
        el('b', null, countEl).textContent = String(worn);
        countEl.appendChild(document.createTextNode(' / ' + S.slots.length + ' worn'));

        var slot = S.slots[S.hover];
        if (!slot) {
            hub.kicker.textContent = 'Select a slot';
            hub.name.textContent = titleEl.textContent;
            hub.stamp.style.visibility = 'hidden';
            hub.act.textContent = '';
            return;
        }
        var st = STATE_TEXT[slot.state] ? slot.state : 'none';
        hub.kicker.textContent = 'Slot ' + (S.hover + 1) + ' / ' + S.slots.length;
        hub.name.textContent = slot.label;
        hub.stamp.style.visibility = 'visible';
        hub.stamp.className = 'cw-stamp is-' + st;
        hub.stamp.textContent = STATE_TEXT[st];
        hub.act.textContent = ACT_TEXT[st];
    }

    function hoverAt(x, y) {
        var box = svg.getBoundingClientRect();
        if (!box.width || !S.slots.length) return;
        var k = SIZE / box.width;
        var dx = (x - (box.left + box.width / 2)) * k, dy = (y - (box.top + box.height / 2)) * k;
        var next = -1;
        if (Math.sqrt(dx * dx + dy * dy) >= INNER) {
            var deg = (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 360) % 360;
            var step = 360 / S.slots.length;
            next = Math.floor(((deg + step / 2) % 360) / step);
        }
        if (next !== S.hover) { S.hover = next; paint(); }
    }

    function pick() {
        var slot = S.slots[S.hover];
        if (!S.open || S.busy || !slot || slot.state === 'none') return;
        S.busy = true;
        post('clothingPick', { id: slot.id, token: S.token }).then(function (r) {
            S.busy = false;
            if (r && r.slots && S.open) { S.slots = r.slots; paint(); }
        });
    }

    function shut(notify) {
        if (!S.open) return;
        S.open = false;
        root.classList.remove('show');
        if (notify) post('clothingClose', { token: S.token });
    }

    build();

    document.addEventListener('mousemove', function (e) { if (S.open) hoverAt(e.clientX, e.clientY); });
    document.addEventListener('mousedown', function (e) {
        if (!S.open) return;
        if (e.button === 2) { e.preventDefault(); shut(true); }
        else if (e.button === 0) { hoverAt(e.clientX, e.clientY); pick(); }
    });
    document.addEventListener('contextmenu', function (e) { if (S.open) e.preventDefault(); });
    document.addEventListener('keydown', function (e) {
        if (!S.open) return;
        var n = S.slots.length;
        if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); shut(true); }
        else if (e.key === 'ArrowRight' || e.key === 'ArrowDown') { S.hover = (S.hover + 1 + n) % n; paint(); e.preventDefault(); }
        else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') { S.hover = S.hover < 0 ? n - 1 : (S.hover - 1 + n) % n; paint(); e.preventDefault(); }
        else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(); }
    });

    window.addEventListener('message', function (e) {
        var m = e.data || {};
        if (m.action === 'clothingOpen') {
            S.token = m.token; S.slots = Array.isArray(m.slots) ? m.slots : []; S.hover = -1; S.busy = false; S.open = true;
            titleEl.textContent = m.title || 'Clothing';
            drawRing();
            root.classList.add('show');
        } else if (m.action === 'clothingClose') {
            shut(false);
        }
    });
})();

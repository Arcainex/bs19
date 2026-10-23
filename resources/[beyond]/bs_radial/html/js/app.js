// Radial wheel. Draws N slices as SVG arcs and picks the slice by cursor angle, not by hovering a DOM element.
// The middle is a dead zone: releasing there cancels.

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'bs_radial';

const $ = (id) => document.getElementById(id);
const SVG_NS = 'http://www.w3.org/2000/svg';

async function post(endpoint, data = {}) {
    try {
        const r = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await r.json();
    } catch (e) { return { ok: false }; }
}

function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// state

const S = {
    open: false,
    items: [],
    icons: {},
    stack: [],        // for submenus: [{ items, title }]
    title: '',
    hot: -1,
    hold: true,
    anchor: 'centre',
    geom: { outer: 21, inner: 7.4, dead: 6 },
};

// geometry

/* SVG arc for one slice, in the -50..50 viewBox. */
function slicePath(index, count, inner, outer) {
    // Start at 12 o'clock and go clockwise: that is where people expect slice 1.
    const step = (Math.PI * 2) / count;
    const start = -Math.PI / 2 + index * step - step / 2;
    const end = start + step;
    const gap = 0.012;                    // hairline between slices

    const a0 = start + gap, a1 = end - gap;
    const large = (a1 - a0) > Math.PI ? 1 : 0;

    const x = (r, a) => (r * Math.cos(a)).toFixed(3);
    const y = (r, a) => (r * Math.sin(a)).toFixed(3);

    return [
        `M ${x(inner, a0)} ${y(inner, a0)}`,
        `L ${x(outer, a0)} ${y(outer, a0)}`,
        `A ${outer} ${outer} 0 ${large} 1 ${x(outer, a1)} ${y(outer, a1)}`,
        `L ${x(inner, a1)} ${y(inner, a1)}`,
        `A ${inner} ${inner} 0 ${large} 0 ${x(inner, a0)} ${y(inner, a0)}`,
        'Z',
    ].join(' ');
}

function sliceCentre(index, count, radius) {
    const step = (Math.PI * 2) / count;
    const a = -Math.PI / 2 + index * step;
    return { x: radius * Math.cos(a), y: radius * Math.sin(a) };
}

/* Which slice is the cursor pointing at? By angle from the middle, so the whole
 * wedge counts - including well outside the ring, which is where people
 * actually flick to. */
function sliceAt(dx, dy, count) {
    const dist = Math.hypot(dx, dy);
    const deadPx = (S.geom.dead / S.geom.outer) * (wheelSize() / 2);
    if (dist < deadPx) return -1;

    let a = Math.atan2(dy, dx) + Math.PI / 2;      // 0 at 12 o'clock
    while (a < 0) a += Math.PI * 2;
    while (a >= Math.PI * 2) a -= Math.PI * 2;

    const step = (Math.PI * 2) / count;
    return Math.floor((a + step / 2) / step) % count;
}

function wheelSize() {
    return $('wheel').getBoundingClientRect().width;
}

// rendering

function render() {
    const svg = $('svg');
    svg.innerHTML = '';

    const n = S.items.length;
    const { outer, inner } = S.geom;

    // Scale the -50..50 viewBox to the configured vh radii.
    const oR = 46, iR = 46 * (inner / outer);

    // Cached once per render, so setHot() never needs a live DOM query - see
    // the comment on setHot below for why that matters.
    S.sliceEls = new Array(n);

    S.items.forEach((item, i) => {
        const g = document.createElementNS(SVG_NS, 'g');
        g.setAttribute('class', 'slice'
            + (item.disabled ? ' is-disabled' : '')
            + (item.active ? ' is-active' : '')
            + (item.danger ? ' is-danger' : ''));
        g.dataset.index = String(i);

        const path = document.createElementNS(SVG_NS, 'path');
        path.setAttribute('d', slicePath(i, n, iR, oR));
        g.appendChild(path);

        // Icon, centred in the ring.
        const c = sliceCentre(i, n, (iR + oR) / 2);
        const icon = document.createElementNS(SVG_NS, 'g');
        icon.setAttribute('class', 'slice__icon');
        icon.setAttribute('transform',
            `translate(${(c.x - 6).toFixed(2)} ${(c.y - 6).toFixed(2)}) scale(0.5)`);

        const p = document.createElementNS(SVG_NS, 'path');
        p.setAttribute('d', S.icons[item.icon] || S.icons.dot || '');
        icon.appendChild(p);
        g.appendChild(icon);

        // A submenu gets a tick on its outer edge so you can see it goes deeper.
        if (item.submenu) {
            const t = document.createElementNS(SVG_NS, 'path');
            const e = sliceCentre(i, n, oR + 2.5);
            t.setAttribute('class', 'slice__tick');
            t.setAttribute('d', `M ${(e.x - 1.6).toFixed(2)} ${e.y.toFixed(2)}
                                 L ${e.x.toFixed(2)} ${(e.y + 1.6).toFixed(2)}
                                 L ${(e.x + 1.6).toFixed(2)} ${e.y.toFixed(2)}`);
            g.appendChild(t);
        }

        svg.appendChild(g);
        S.sliceEls[i] = g;
    });

    $('title').textContent = S.title || t('ui.select', { fallback: 'SELECT' });
    setHot(-1);
    $('hint').textContent = S.stack.length
        ? 'RELEASE TO PICK · BACKSPACE TO GO BACK · ESC TO CLOSE'
        : (S.hold ? 'RELEASE TO PICK · ESC TO CLOSE' : 'CLICK TO PICK · ESC TO CLOSE');
}

// Perf: render() caches the slice elements (S.sliceEls), so a mousemove only touches the previously hot slice and the new one, and nothing on jitter within the same slice.
function setHot(index) {
    if (index === S.hot) return;

    const prev = S.sliceEls && S.sliceEls[S.hot];
    if (prev) prev.classList.remove('is-hot');

    S.hot = index;

    const next = S.sliceEls && S.sliceEls[index];
    if (next) next.classList.add('is-hot');

    const item = S.items[index];
    const label = $('label');
    const note = $('note');

    label.textContent = item ? item.label : '';
    label.classList.toggle('is-disabled', !!(item && item.disabled));
    label.classList.toggle('is-danger', !!(item && item.danger));
    note.textContent = item ? (item.note || (item.submenu ? 'more...' : '')) : '';
}

// picking

function pick(index) {
    const item = S.items[index];
    if (!item || item.disabled) return;

    if (item.submenu) {
        // Go deeper rather than answering.
        S.stack.push({ items: S.items, title: S.title });
        S.items = item.submenu;
        S.title = item.title || item.label;
        render();
        return;
    }

    close();
    post('pick', { id: item.id, token: S.token });
}

function back() {
    const previous = S.stack.pop();
    if (!previous) return false;
    S.items = previous.items;
    S.title = previous.title;
    render();
    return true;
}

function close() {
    S.open = false;
    $('root').classList.add('hidden');
}

// input

document.addEventListener('mousemove', (e) => {
    if (!S.open) return;

    const rect = $('wheel').getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;

    setHot(sliceAt(e.clientX - cx, e.clientY - cy, S.items.length));
});

document.addEventListener('mousedown', (e) => {
    if (!S.open || S.hold) return;
    if (e.button === 0 && S.hot >= 0) pick(S.hot);
    if (e.button === 2) { if (!back()) { close(); post('cancel', { token: S.token }); } }
});

/* Hold-to-pick: the key is released in Lua, which tells us to resolve. Clicking
 * also works, because not everyone holds. */
document.addEventListener('click', (e) => {
    if (!S.open || !S.hold) return;
    if (S.hot >= 0) pick(S.hot);
});

document.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (!S.open) return;
    if (!back()) { close(); post('cancel', { token: S.token }); }
});

document.addEventListener('keyup', (e) => {
    if (!S.open) return;

    if (e.key === 'Escape') { close(); post('cancel', { token: S.token }); }
    if (e.key === 'Backspace') { if (!back()) { close(); post('cancel', { token: S.token }); } }

    // 1-9 pick a slice directly, for people who would rather not aim.
    const n = Number(e.key);
    if (n >= 1 && n <= S.items.length) pick(n - 1);
});

// from client

window.addEventListener('message', (event) => {
    const d = event.data || {};

    if (d.action === 'open') {
        S.open = true;

        // The token identifies which wheel this is and goes back with the pick. Lua opens a new wheel on a new token, so a late pick from a replaced wheel is discarded.
        S.token = d.token;
        S.items = d.items || [];
        S.icons = d.icons || {};
        S.title = d.title || 'SELECT';
        S.hold = d.hold !== false;
        S.geom = d.geometry || S.geom;
        S.stack = [];

        // Wheel position is a CSS class (.is-right / .is-left in style.css). sliceAt() measures the wheel's bounding box on every mousemove, so the angles follow wherever CSS puts it.
        S.anchor = ['centre', 'right', 'left'].includes(d.anchor)
            ? d.anchor : 'centre';

        const root = $('root');
        root.classList.remove('is-right', 'is-left');
        if (S.anchor !== 'centre') root.classList.add(`is-${S.anchor}`);

        root.classList.remove('hidden');
        render();
    }

    if (d.action === 'close') close();

    /* The key that opened a hold-to-pick wheel was let go. */
    if (d.action === 'release') {
        if (!S.open || !S.hold) return;
        if (S.hot >= 0) pick(S.hot);
        else { close(); post('cancel', { token: S.token }); }
    }
});

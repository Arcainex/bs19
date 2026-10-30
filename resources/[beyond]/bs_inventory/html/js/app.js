// UI scale (bs_ui/html/shared/scale.js): body is transform-scaled, so screen px (clientX, getBoundingClientRect) must be divided by uiK() before being written to style.left/top. Hit-testing (elementFromPoint) stays in screen px.
const uiK = () => (window.BSScale ? window.BSScale.get() : 1);
const uiW = () => window.innerWidth / uiK();

// bs_inventory - NUI. Drag and drop between two grids. The client decides nothing: a drop posts a move and waits for the server's new state, so a rejected move never appears.

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'bs_inventory';

const $ = (id) => document.getElementById(id);

async function post(endpoint, data = {}) {
    try {
        const r = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await r.json();
    } catch (e) { return { ok: false, error: 'bridge failed' }; }
}

const S = { grid: { w: 8, h: 5 }, player: null, container: null, settings: {}, hotbar: {}, boosters: {}, gadgets: {}, filters: null, trade: null };
let pendingSplit = null;

// Items vs weapons are displayed separately, but the bag is still one pool of slots server-side and moves address slots by number.
let catFilter = 'all';

let invSearch = '';
function matchesFilter(entry) {
    if (!entry) return true;
    if (invSearch && !String(entry.label || entry.item || '').toLowerCase().includes(invSearch)
        && !String(entry.category || '').toLowerCase().includes(invSearch)) return false;
    if (catFilter === 'all') return true;
    const isWeapon = entry.category === 'weapon';
    return catFilter === 'weapon' ? isWeapon : !isWeapon;
}

// render

function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function slotCount() { return S.grid.w * S.grid.h; }

// Server flags each entry with `ongrid` (bag ids 1-40 and 101+). Older payloads fall back to the slot-number test.
function onGrid(entry, slot, limit) {
    if (entry && entry.ongrid !== undefined) return !!entry.ongrid;
    return slot <= limit;
}

// GRID. Items occupy real cells using their w/h from config_items (a rifle is 1x3, a toolbox 3x2).

function renderGrid(el, inv, which) {
    const W = (inv && inv.grid && inv.grid.w) || S.grid.w;
    let H = (inv && inv.grid && inv.grid.h) || S.grid.h;

    // Compact panels (mailbox) show the used rows plus one spare, min 2, and scroll past the max height.
    const compact = !!(inv && inv.compact);
    if (compact) {
        let bottom = 0;
        Object.keys(inv.slots || {}).forEach((k) => {
            const e = inv.slots[k];
            if (!e || !e.y) return;
            const eh = e.rot ? (e.w || 1) : (e.h || 1);
            bottom = Math.max(bottom, e.y + eh - 1);
        });
        H = Math.min(H, Math.max(2, bottom + 1));
    }
    el.classList.toggle('grid--scroll', compact);

    el.style.setProperty('--cols', W);
    el.style.setProperty('--rows', H);
    el.innerHTML = '';

    // Layer 1: the cells.
    for (let y = 1; y <= H; y++) {
        for (let x = 1; x <= W; x++) {
            const cell = document.createElement('div');
            cell.className = 'cell';
            cell.style.gridColumn = x;
            cell.style.gridRow = y;
            cell.dataset.inv = which;
            cell.dataset.x = x;
            cell.dataset.y = y;
            el.appendChild(cell);
        }
    }

    if (!inv || !inv.slots) return;

    // Layer 2: the items.
    const limit = inv.gridSlots || inv.size || (W * H);

    Object.keys(inv.slots).forEach((key) => {
        const entry = inv.slots[key];
        const slot = Number(key);

        // The last slots are the hotbar, the same inventory drawn elsewhere. Skip them here so bound items are not shown twice.
        if (!onGrid(entry, slot, limit)) return;

        // No coordinates means the server could not place it. It still has its row and slot, so it is drawn in the overflow strip.
        if (!entry.x || !entry.y) { renderOverflow(el, entry, which, slot); return; }

        // Rotation swaps the footprint. Same rule as Grid.Footprint on the server.
        const w = entry.rot ? (entry.h || 1) : (entry.w || 1);
        const h = entry.rot ? (entry.w || 1) : (entry.h || 1);

        const node = document.createElement('div');
        node.className = 'slot has-item'
            + (which === 'player' && !matchesFilter(entry) ? ' is-filtered' : '')
            + (entry.rot ? ' is-rot' : '')
            + (w === 4 && h === 4 ? ' is-4x4' : '');
        node.dataset.slot = slot;
        node.dataset.inv = which;
        node.dataset.cat = entry.category || 'misc';
        if (entry.rarity) node.dataset.rarity = entry.rarity;
        node.style.gridColumn = `${entry.x} / span ${w}`;
        node.style.gridRow = `${entry.y} / span ${h}`;

        const icon = (typeof BSIcons !== 'undefined')
            ? BSIcons.get(entry.item, entry.category) : '';

        node.innerHTML = `
            <span class="slot__icon">${icon}</span>
            <span class="slot__name">${esc(entry.label)}</span>
            <span class="slot__foot">${slotBadge(entry)}</span>${fillBar(entry)}`;

        wireSlot(node, entry, which, slot);
        el.appendChild(node);
    });
}

// Anything the grid could not seat. Rare, and visible on purpose so the player does not think it is lost.
function renderOverflow(gridEl, entry, which, slot) {
    let strip = gridEl.parentElement.querySelector('.overflow');
    if (!strip) {
        strip = document.createElement('div');
        strip.className = 'overflow';
        strip.innerHTML = `<span class="overflow__label">${t('inv.no_room_grid')}</span>`;
        gridEl.parentElement.appendChild(strip);
    }

    const icon = (typeof BSIcons !== 'undefined')
        ? BSIcons.get(entry.item, entry.category) : '';
    const node = document.createElement('div');
    node.className = 'slot has-item slot--loose';
    node.dataset.slot = slot;
    node.dataset.inv = which;
    node.innerHTML = `<span class="slot__icon">${icon}</span>
        <span class="slot__name">${esc(entry.label)}</span>`;
    wireSlot(node, entry, which, slot);
    strip.appendChild(node);
}

// Corner badge. A count gets the `x` prefix that `.slot__amount` paints; a fill level must not ("x87%" is meaningless).
function slotBadge(entry) {
    if (entry.capacity || entry.battery != null) return `<span>${slotCountLabel(entry)}</span>`;
    return `<span class="slot__amount">${slotCountLabel(entry)}</span>`;
}

// A measured container (jerrycan) shows its level, not its count. The server sends `fill` and `capacity`, turned into a percentage here.
function slotCountLabel(entry) {
    if (entry.battery != null) return `${Math.round(entry.battery)}%`;
    if (!entry.capacity) return entry.amount;
    return `${Math.round(((entry.fill || 0) / entry.capacity) * 100)}%`;
}

// Plus a bar across the bottom, easier to read than a number.
function fillBar(entry) {
    if (!entry.capacity) return '';
    const pct = Math.max(0, Math.min(100,
        Math.round(((entry.fill || 0) / entry.capacity) * 100)));
    return `<span class="slot__fill"><i style="width:${pct}%"></i></span>`;
}

function wireSlot(node, entry, which, index) {
    // All dragging goes through the pointer-driven carry system below. Native HTML5 drag-and-drop is not used: in FiveM's embedded browser dragend/drop often never arrives for elements inside a re-rendering grid.
    if (entry) {
        // Right-click opens Use / Give / Drop.
        node.addEventListener('contextmenu', (e) => {
            e.preventDefault();
            openContext(e.clientX, e.clientY, which, index, entry);
        });

        node.addEventListener('mouseenter', (e) => { node.dataset.hover = '1'; showTip(entry, e); });
        node.addEventListener('mousemove', moveTip);
        node.addEventListener('mouseleave', () => { delete node.dataset.hover; hideTip(); });
        node.addEventListener('click', () => {
            if (Date.now() - lastDragEnd < 250) return;
            // Own 400 ms double-click: the grid re-renders on select, which eats the browser's dblclick.
            const key = `${which}:${index}`, now = Date.now();
            if (lastClick.key === key && now - lastClick.t < 400) {
                lastClick = { key: '', t: 0 };
                quickToggle(which, index, entry, node);
                return;
            }
            lastClick = { key, t: now };
            selectItem(which, index);
        });
        if (sel && sel.inv === which && sel.slot === index) node.classList.add('is-selected');

        // Double-click to wear / take off. A shortcut for the drag: it works out the destination and sends the same move a drag would.
        node.addEventListener('dblclick', (e) => {
            // handled by the click window above
            e.preventDefault();
            e.stopPropagation();
        });
    }
}

let lastClick = { key: '', t: 0 };

// Gadget/booster into the first free matching loadout slot (slot 1 if all full).
function equipLoadout(entry, node) {
    const gad = entry.category === 'gadget';
    const n = gad ? 2 : 3, cur = gad ? S.gadgets : S.boosters;
    let idx = 1;
    for (let i = 1; i <= n; i++) { if (!cur || !cur[String(i)]) { idx = i; break; } }
    return post(gad ? 'gadgetSet' : 'boosterSet', { index: idx, item: entry.item }).then((r) => {
        if (r && r.ok === false && r.error && node) flashBar(node, r.error);
        return r;
    });
}
function isLoadoutItem(entry) { return !!entry && (entry.category === 'gadget' || entry.category === 'booster'); }

// Double-click a booster in the bag: put it in the first free booster slot.
async function quickToggle(which, index, entry, node) {
    // Double-click in the pack or vest: into the pockets.
    if (which === 'pack' || which === 'vest') {
        const free = firstFreeGridSlot();
        if (free === null) { flashBar(node, t('inv.no_room')); return; }
        const r = await post('move', { from: { inv: which, slot: index }, to: { inv: 'player', slot: free }, amount: entry.amount });
        if (r && !r.ok && r.error) flashBar(node, r.error);
        return;
    }
    const gear = which === 'player' ? gearSlotFor(entry) : null;
    if (gear && index !== gear) {
        const r = await post('move', { from: { inv: 'player', slot: index }, to: { inv: 'player', slot: gear }, amount: entry.amount });
        if (r && !r.ok && r.error) flashBar(node, r.error);
        return;
    }
    if (which !== 'player' || !isLoadoutItem(entry)) { return; }
    await equipLoadout(entry, node);
}

function renderWeight(inv, labelEl, fillEl) {
    if (!inv) { labelEl.textContent = ''; fillEl.style.width = '0%'; return; }
    const pct = inv.maxWeight ? Math.min(100, (inv.weight / inv.maxWeight) * 100) : 0;
    labelEl.textContent = `${inv.weight.toFixed(1)} / ${inv.maxWeight.toFixed(1)} KG`;
    fillEl.style.width = `${pct}%`;
    fillEl.classList.toggle('is-heavy', pct > 90);
}

function renderAll() {
    renderGrid($('playerGrid'), S.player, 'player');
    renderList();
    renderWeight(S.player, $('weight'), $('weightFill'));
    renderWeightBreak();
    refreshQuick();

    const hasContainer = !!S.container;
    $('containerHollow').classList.toggle('hidden', hasContainer);
    $('containerGrid').classList.toggle('hidden', !hasContainer);
    const containerColumn = $('containerGrid').closest('.col--bags');
    if (containerColumn) containerColumn.classList.toggle('is-open', hasContainer);

    if (hasContainer) {
        renderGrid($('containerGrid'), S.container, 'container');
        renderWeight(S.container, $('containerWeight'), $('containerFill'));

        // Anchor the opened storage to the right edge of the player inventory.
        // Fixed viewport coordinates make the 10x14 personal storage visible even
        // though the inventory column itself is deliberately compact.
        if (containerColumn) {
            const playerBoard = $('playerGrid').closest('.board');
            if (playerBoard) {
                const r = playerBoard.getBoundingClientRect();
                const gap = Math.max(10, window.innerWidth * 0.014 / (Number(getComputedStyle(document.documentElement).getPropertyValue('--ui-scale')) || 1));
                const k = uiK();
                // Lift the storage a few screen pixels so its top border lines up exactly
                // with the carried-inventory board.
                containerColumn.style.setProperty('--container-top', `${(r.top - 6) / k}px`);
                containerColumn.style.setProperty('--container-left', `${r.right / k + gap}px`);
            }
        }
    } else {
        $('containerWeight').textContent = '';
        $('containerFill').style.width = '0%';
        if (containerColumn) {
            containerColumn.style.removeProperty('--container-top');
            containerColumn.style.removeProperty('--container-left');
        }
    }

    renderHotbar();
    renderGear();
    renderBoosters();
    renderBags();
}

// Worn vest pockets and backpack, each its own grid under the pockets. The server sends them as player.vest / player.pack.
function renderBags() {
    const p = S.player || {};
    const wrap = $('bagBoxes');
    if (!wrap) return;   // older cached page
    wrap.classList.toggle('hidden', !p.pack && !p.vest);
    [['vest', 'vestBox', 'vestGrid', 'vestWeight', 'vestTitle'], ['pack', 'packBox', 'packGrid', 'packWeight', 'packTitle']].forEach(([k, box, grid, w, title]) => {
        const b = p[k];
        $(box).classList.toggle('hidden', !b);
        if (!b) { $(grid).innerHTML = ''; return; }
        renderGrid($(grid), b, k);
        $(w).textContent = `${(b.weight || 0).toFixed(1)} / ${(b.maxWeight || 0).toFixed(1)} KG`;
        $(title).textContent = String(b.label || '').toUpperCase();
    });
    const pack = p.pack;
    if (!pack) return;
    const sel = $('packLook');
    const want = (pack.looks || []).map((l) => `${l.i}`).join(',');
    if (sel.dataset.opts !== want) {
        sel.dataset.opts = want;
        sel.innerHTML = (pack.looks || []).map((l) => `<option value="${l.i}">${esc(t('look.' + l.id))}</option>`).join('');
    }
    sel.value = String(pack.look || '');
    $('packHide').classList.toggle('is-on', !!pack.hidden);
    $('packHide').textContent = pack.hidden ? t('ui.pack_show') : t('ui.pack_hide');
}

(function wirePackControls() {
    const sel = $('packLook'), hide = $('packHide');
    if (sel) sel.addEventListener('change', () => post('packLook', { look: Number(sel.value) }));
    if (hide) hide.addEventListener('click', () => {
        const pack = S.player && S.player.pack;
        if (pack) post('packLook', { hidden: !pack.hidden });
    });
})();

// One plate for gear, booster and gadget slots: icon centred, key top-left, count bottom-right, small name along the bottom.
function loadoutPlate(item, category, label, key, count) {
    const icon = (typeof BSIcons !== 'undefined') ? BSIcons.get(item, category) : '';
    return `<span class="lslot__icon">${icon}</span>
        ${key ? `<span class="lslot__key">${esc(key)}</span>` : ''}
        ${count !== '' && count !== undefined ? `<span class="lslot__count">x${esc(count)}</span>` : ''}
        <span class="lslot__name">${esc(label || item)}</span>`;
}

// Gear: armour + backpack. They are real inventory slots (the server's equip frames), so dragging in/out is an ordinary move and the server decides.
const GEAR_IDS = ['armour', 'backpack'];

function renderGear() {
    const box = $('gearSlots');
    if (!box) return;
    box.innerHTML = '';
    const equip = (S.player && S.player.equip) || [];
    GEAR_IDS.forEach((id) => {
        const def = equip.find((e) => e.id === id);
        if (!def) return;
        const abs = Number(def.slot);
        const entry = S.player.slots ? S.player.slots[String(abs)] : null;
        const node = document.createElement('div');
        node.className = 'slot gear__slot' + (entry ? ' has-item' : '');
        node.dataset.inv = 'player';
        node.dataset.slot = abs;
        node.dataset.gear = id;
        if (entry) node.dataset.cat = entry.category || 'misc';
        node.innerHTML = entry
            ? loadoutPlate(entry.item, entry.category, entry.label, '', entry.amount > 1 ? entry.amount : '')
            : `<span class="lslot__empty">${esc(def.label || id).toUpperCase()}</span>`;
        node.title = entry ? t('inv.take_off') : t('inv.drag_here', { name: def.label || id });
        // Right-click takes it off, into the first free bag square.
        node.addEventListener('contextmenu', async (e) => {
            e.preventDefault();
            e.stopImmediatePropagation();
            if (!entry) return;
            const r = await unbind(abs, entry);
            if (r && !r.ok && r.error) flashBar(node, r.error);
        });
        box.appendChild(node);
    });
}

// The gear frame an item belongs in, or null.
function gearSlotFor(entry) {
    if (!entry || !S.player || !S.player.equip) return null;
    const id = entry.equipSlot;
    if (!GEAR_IDS.includes(id)) return null;
    const def = S.player.equip.find((e) => e.id === id);
    return def ? Number(def.slot) : null;
}

// The bar: five quick slots, drawn inside the bag as well as on the HUD, so you can drag items onto them. A binding is by item name, not grid position.

// The bar is five more slots of the bag. A bar slot is a real inventory slot (41-45) with data-inv="player" and its absolute slot number, so drags in, out and between bar slots are ordinary moves.

function barSlotOf(index) {
    const grid = (S.player && S.player.gridSlots) || slotCount();
    return grid + index;
}

function renderHotbar() {
    const strip = $('hotbarStrip');
    if (!strip) return;

    strip.innerHTML = '';

    for (let i = 1; i <= 5; i++) {
        const abs = barSlotOf(i);
        const entry = (S.player && S.player.slots) ? S.player.slots[String(abs)] : null;

        const node = document.createElement('div');
        node.className = 'slot bar__slot' + (entry ? ' has-item is-bound' : '');
        node.dataset.bind = i;
        node.dataset.inv = 'player';
        node.dataset.slot = abs;
        if (entry) node.dataset.cat = entry.category || 'misc';

        const icon = (entry && typeof BSIcons !== 'undefined')
            ? BSIcons.get(entry.item, entry.category) : '';

        // The bar draws the same parts as a bag plate, with the same class names, so the stylesheet rules apply (otherwise the 512px icons render at full size).
        node.innerHTML = `
            <span class="bar__key">${i}</span>
            ${entry ? `<span class="slot__icon">${icon}</span>` : ''}
            ${entry ? `<span class="slot__name">${esc(entry.label || entry.item)}</span>` : ''}
            ${entry ? `<span class="slot__foot">${slotBadge(entry)}</span>` : ''}
            ${entry ? fillBar(entry) : ''}`;

        // Right-click takes it off the bar and back to the first free grid square.
        node.addEventListener('contextmenu', async (e) => {
            e.preventDefault();
            if (!entry) return;

            // Attached before wireSlot's handler and stops it, because right-click on the bar means take off, not the Use/Give/Drop menu.
            e.stopImmediatePropagation();
            await unbind(abs, entry);
        });

        node.addEventListener('click', () => {
            if (carry) return;                          // finishing a drag
            if (Date.now() - barDragged < 250) return;  // just finished one
            if (!entry) openBarPicker(i, node);
        });

        wireSlot(node, entry, 'player', abs);
        strip.appendChild(node);
    }
}

// A drag that ends on the bar is followed by a click on the same element, which would open the picker. `carry` is already null by then, so a timestamp is the guard.
let barDragged = 0;

// The first empty square in the carried grid, or null if the bag is full.
function firstFreeGridSlot() {
    if (S.player && S.player.freeSlot !== undefined) return S.player.freeSlot || null;
    const slots = (S.player && S.player.slots) || {};
    const grid = (S.player && S.player.gridSlots) || slotCount();

    for (let i = 1; i <= grid; i++) {
        if (!slots[String(i)]) return i;
    }
    return null;
}

async function unbind(abs, entry) {
    const free = firstFreeGridSlot();
    if (free === null) return;      // nowhere to put it; leave it on the bar

    return post('move', {
        from: { inv: 'player', slot: abs },
        to:   { inv: 'player', slot: free },
        amount: entry.amount,
    });
}

// Bar picker: click a slot and choose from what you carry. Dragging is faster; this one is more discoverable.

function openBarPicker(index, node) {
    closeBarPicker();

    // Listed by slot, not item name: stacks of the same item can differ in durability or fill.
    const usable = [];
    const slots = (S.player && S.player.slots) || {};
    const grid = (S.player && S.player.gridSlots) || slotCount();

    for (let i = 1; i <= grid; i++) {
        const e = slots[String(i)];
        if (e && e.usable) usable.push({ slot: i, entry: e });
    }

    const box = document.createElement('div');
    box.className = 'barpick';
    box.id = 'barpick';

    if (!usable.length) {
        box.innerHTML = `<p class="barpick__empty">${t('inv.bar_empty')}</p>`;
    } else {
        box.innerHTML = `<p class="barpick__head">SLOT ${index}</p>` + usable.map(({ slot, entry }) => {
            const icon = (typeof BSIcons !== 'undefined')
                ? BSIcons.get(entry.item, entry.category) : '';
            return `<button class="barpick__row" data-slot="${slot}">
                        <span class="barpick__icon">${icon}</span>
                        <span>${esc(entry.label)}</span>
                        <span class="barpick__count">${slotCountLabel(entry)}</span>
                    </button>`;
        }).join('');
    }

    document.body.appendChild(box);

    const r = node.getBoundingClientRect();
    // rects are screen px, body is ui-scaled: convert to local (offsetWidth is already local)
    const k = uiK();
    box.style.left = `${Math.min(r.left / k, uiW() - box.offsetWidth - 8)}px`;
    box.style.top  = `${Math.max(8, r.top / k - box.offsetHeight - 6)}px`;

    box.querySelectorAll('.barpick__row').forEach((b) => {
        b.addEventListener('click', async (ev) => {
            ev.stopPropagation();
            const from = Number(b.dataset.slot || 0);
            closeBarPicker();

            // Moves the actual stack onto the bar. There is no separate bind step.
            if (from > 0) {
                const entry = entryAt('player', from);
                if (entry) {
                    await post('move', {
                        from: { inv: 'player', slot: from },
                        to:   { inv: 'player', slot: barSlotOf(index) },
                        amount: entry.amount,
                    });
                }
            }
        });
    });
}

function closeBarPicker() {
    const old = document.getElementById('barpick');
    if (old) old.remove();
}

document.addEventListener('mousedown', (e) => {
    if (!e.target.closest('#barpick') && !e.target.closest('.bar__slot')) closeBarPicker();
});

// The carry: one pointer-driven drag for everything (grid, container incl. trunk, hotbar). Used because the browser's own drag-and-drop is unreliable in FiveM's embedded browser.

let carry = null;       // { from: {inv, slot}, entry, ghost, shift }
let lastDragEnd = 0;

// Finds the element a carry started from, so every place that un-highlights it uses one lookup.
function sourceNodeFor(from) {
    return document.querySelector(
        `.slot[data-inv="${from.inv}"][data-slot="${from.slot}"]`);
}

function entryAt(which, slot) {
    const source = which === 'player' ? S.player : which === 'container' ? S.container
        : (which === 'pack' || which === 'vest') ? (S.player && S.player[which]) : null;
    return source && source.slots ? source.slots[String(slot)] : null;
}

document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;

    // A bar slot is a normal slot (data-inv="player" plus its absolute slot number), so dragging uses the same code path as the grid.
    const node = e.target.closest('.slot.has-item');
    if (!node) return;

    const which = node.dataset.inv;
    const slot = Number(node.dataset.slot);
    const entry = entryAt(which, slot);
    if (!entry) return;

    // Armed, not carrying: a click that never moves is still a click.
    carry = { from: { inv: which, slot }, entry, ghost: null,
              start: { x: e.clientX, y: e.clientY }, shift: e.shiftKey };
});

document.addEventListener('mousemove', (e) => {
    if (!carry) return;

    if (!carry.ghost) {
        const moved = Math.abs(e.clientX - carry.start.x) + Math.abs(e.clientY - carry.start.y);
        if (moved < 6) return;

        const sourceNode = sourceNodeFor(carry.from);
        if (sourceNode) sourceNode.classList.add('is-dragging');

        const ghost = document.createElement('div');
        ghost.className = 'ghost';
        const icon = (typeof BSIcons !== 'undefined')
            ? BSIcons.get(carry.entry.item, carry.entry.category) : '';
        ghost.innerHTML = `<span class="ghost__icon">${icon}</span>
                           <span class="ghost__name">${esc(carry.entry.label)}</span>`;
        document.body.appendChild(ghost);
        carry.ghost = ghost;
        document.body.classList.add('is-carrying');
    }

    carry.ghost.style.left = `${e.clientX / uiK() + 12}px`;
    carry.ghost.style.top  = `${e.clientY / uiK() + 12}px`;

    const over = document.elementFromPoint(e.clientX, e.clientY);
    const target = over && (over.closest('.bar__slot') || over.closest('.booster[data-bidx]')
        || over.closest('.booster[data-gidx]') || over.closest('.slot'));

    document.querySelectorAll('.is-over').forEach((n) => n.classList.remove('is-over'));
    if (target) target.classList.add('is-over');
});

document.addEventListener('mouseup', (e) => {
    if (!carry) return;

    const had = carry.ghost;
    const sourceNode = sourceNodeFor(carry.from);
    if (sourceNode) sourceNode.classList.remove('is-dragging');
    if (carry.ghost) carry.ghost.remove();
    document.body.classList.remove('is-carrying');
    document.querySelectorAll('.is-over').forEach((n) => n.classList.remove('is-over'));

    const { from, entry, shift } = carry;
    carry = null;

    if (!had) return;   // a click, not a drag
    lastDragEnd = Date.now();

    const over = document.elementFromPoint(e.clientX, e.clientY);

    // Dropping on the bar is dropping on a slot; it only needs the guard against the click that follows a drag.
    if (over && over.closest('.bar__slot')) barDragged = Date.now();

    // A drop lands on a cell, not a slot number. The server needs the x/y of the cell the item's top-left should occupy. Dropping onto another item still resolves to that item's slot.
    const cellTarget = over && over.closest('.cell');
    const slotTarget = over && over.closest('.slot');

    // Booster/gadget slots take the stack out of the bag (server moves it).
    const gadgetTarget = over ? over.closest('.booster[data-gidx]') : null;
    if (gadgetTarget) {
        if (!entry || entry.category !== 'gadget') { flashBar(gadgetTarget, t('inv.only_gadgets')); return; }
        post('gadgetSet', { index: Number(gadgetTarget.dataset.gidx), item: entry.item });
        return;
    }
    const boosterTarget = over ? over.closest('.booster[data-bidx]') : null;
    if (boosterTarget) {
        if (!entry || entry.category !== 'booster') { flashBar(boosterTarget, t('inv.only_boosters')); return; }
        post('boosterSet', { index: Number(boosterTarget.dataset.bidx), item: entry.item });
        return;
    }

    if (!cellTarget && !slotTarget) return;

    const to = slotTarget
        ? { inv: slotTarget.dataset.inv, slot: Number(slotTarget.dataset.slot) }
        : { inv: cellTarget.dataset.inv,
            slot: from.slot,                       // keeps its identity
            x: Number(cellTarget.dataset.x),
            y: Number(cellTarget.dataset.y),
            rot: !!(entry && entry.rot) };

    // Coming off a gear frame onto a bag cell: it needs a grid slot id to land in.
    if (!slotTarget && from.inv === 'player' && to.inv === 'player'
        && !onGrid(entry, from.slot, (S.player && S.player.gridSlots) || slotCount())) {
        const free = firstFreeGridSlot();
        if (free === null) { flashBar(cellTarget, t('inv.no_room')); return; }
        to.slot = free;
    }

    if (from.inv === to.inv && from.slot === to.slot && to.x === undefined) return;

    if (shift && entry.amount > 1) {
        pendingSplit = { from, to, max: entry.amount };
        $('splitInput').max = entry.amount;
        $('splitInput').value = Math.max(1, Math.floor(entry.amount / 2));
        $('split').classList.remove('hidden');
        $('splitInput').focus();
        return;
    }

    // Refused grid/bar moves (no room, bad placement) flash a reason, so a drop never undoes itself silently.
    const flashOn = cellTarget || slotTarget;
    post('move', { from, to, amount: entry.amount }).then((r) => {
        if (r && !r.ok && r.error && flashOn) flashBar(flashOn, r.error);
    });
});

// A short red flash with a reason, for a drop that was refused.
function flashBar(node, why) {
    node.classList.add('is-refused');
    node.setAttribute('data-why', why);
    setTimeout(() => {
        node.classList.remove('is-refused');
        node.removeAttribute('data-why');
    }, 1400);
}

// context menu

let ctxTarget = null;

function openContext(x, y, which, slot, entry) {
    ctxTarget = { inv: which, slot, entry };

    const ctx = $('ctx');
    $('ctxHead').textContent = `${entry.label} ×${entry.amount}`.toUpperCase();

    // Only your own bag can be used from, given from or dropped from.
    const mine = which === 'player';
    // Only usable items can go on the bar - a plank in slot 3 does nothing.
    const bind = $('ctxBind');
    if (bind) bind.classList.toggle('hidden', !mine || !entry.usable);

    ctx.querySelector('[data-act="use"]').disabled  = !mine || !entry.usable;
    ctx.querySelector('[data-act="give"]').disabled = !mine;
    ctx.querySelector('[data-act="offer"]').disabled = !mine || !S.trade || S.trade.phase !== 'offering';
    ctx.querySelector('[data-act="drop"]').disabled = !mine;
    const sp = ctx.querySelector('[data-act="split"]');
    if (sp) sp.classList.toggle('hidden', !mine || !(entry.amount > 1));
    const eq = ctx.querySelector('[data-act="equipslot"]');
    if (eq) {
        eq.classList.toggle('hidden', !mine || !isLoadoutItem(entry));
        eq.textContent = entry.category === 'gadget' ? t('inv.equip_gadget') : t('inv.equip_booster');
    }

    ctx.classList.remove('hidden');

    // Keep it on screen near the cursor.
    const rect = ctx.getBoundingClientRect();
    const k = uiK();
    ctx.style.left = `${Math.min(x, window.innerWidth - rect.width - 8) / k}px`;
    ctx.style.top  = `${Math.min(y, window.innerHeight - rect.height - 8) / k}px`;
}

function closeContext() {
    $('ctx').classList.add('hidden');
    ctxTarget = null;
}

document.addEventListener('click', (e) => {
    if (!e.target.closest('#ctx')) closeContext();
});

$('ctx').querySelectorAll('.ctx__item').forEach((btn) => {
    btn.addEventListener('click', async () => {
        if (!ctxTarget) return;
        const { slot, entry } = ctxTarget;
        const act = btn.dataset.act;
        closeContext();

        if (act === 'equipslot') return void await equipLoadout(entry, null);
        if (act === 'use')  return void await post('use', { slot });
        if (act === 'drop') return void await post('drop', { slot, amount: entry.amount });
        if (act === 'split') return void openSplitPrompt(slot, entry, null);
        if (act === 'offer') {
            const result = await post('tradeOffer', { slot, add: true });
            if (!result.ok) tradeNotice(result.error || t('trade.offer_fail'));
            return;
        }

        if (act === 'give') {
            const res = await post('nearbyPlayers');
            const list = $('whoList');
            $('who').querySelector('h3').textContent = t('inv.give_to', { fallback: 'GIVE TO' });
            list.innerHTML = '';

            if (!res.players || !res.players.length) {
                list.innerHTML = `<p class="setting__note">${t('trade.nobody')}</p>`;
            } else {
                res.players.forEach((p) => {
                    const b = document.createElement('button');
                    b.className = 'who__btn';
                    b.textContent = `${p.name}  (#${p.source})`;
                    b.addEventListener('click', async () => {
                        $('who').classList.add('hidden');
                        await post('give', { slot, amount: entry.amount, target: p.source });
                    });
                    list.appendChild(b);
                });
            }
            $('who').classList.remove('hidden');
        }
    });
});

$('whoCancel').addEventListener('click', () => $('who').classList.add('hidden'));

let noticeTimer;
function tradeNotice(message) {
    const el = $('tradeNotice');
    el.textContent = message;
    el.classList.remove('hidden');
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => el.classList.add('hidden'), 3500);
}

function renderTrade(trade) {
    if (!trade || trade.phase === 'closed') {
        S.trade = null;
        $('root').classList.remove('trade-active');
        $('tradePanel').classList.add('hidden');
        if (trade && trade.reason) tradeNotice(trade.reason);
        return;
    }
    S.trade = trade;
    $('root').classList.add('trade-active');
    $('tradePanel').classList.remove('hidden');
    $('tradeTitle').textContent = t('trade.with', { name: trade.peerName || t('trade.survivor') }).toUpperCase();
    $('tradeOffers').classList.toggle('hidden', trade.phase !== 'offering');
    $('tradeBagSection').classList.toggle('hidden', trade.phase !== 'offering');
    $('tradeAccept').classList.toggle('hidden', trade.phase !== 'invited' || !trade.invitedToYou);
    $('tradeConfirm').classList.toggle('hidden', trade.phase !== 'offering');
    $('tradeConfirm').disabled = !!trade.confirmed;
    $('tradeConfirm').textContent = trade.confirmed ? t('trade.confirmed') : t('trade.confirm');
    $('tradeStatus').textContent = trade.phase === 'invited'
        ? (trade.invitedToYou ? t('trade.review') : t('trade.waiting'))
        : (trade.peerConfirmed ? t('trade.peer_confirmed') : t('trade.both_confirm'));
    $('tradeCash').value = String(trade.myCash || 0);
    $('tradePeerCash').textContent = '$' + Number(trade.peerCash || 0).toLocaleString();
    $('tradeCashAvailable').textContent = t('trade.available') + ' $' + Number(trade.availableCash || 0).toLocaleString();
    renderTradeBag();
    for (const [id, offers, removable] of [
        ['tradeMine', trade.mine || [], true], ['tradeTheirs', trade.theirs || [], false],
    ]) {
        const host = $(id);
        host.innerHTML = '';
        if (!offers.length) host.textContent = t('trade.no_items');
        for (const offer of offers) {
            const row = document.createElement('div');
            row.className = 'trade-panel__item';
            const name = document.createElement('span');
            const detail = offer.capacity
                ? ` · ${Math.round(Number(offer.durability) || 0)}/${offer.capacity}`
                : offer.durability != null
                    ? ` · condition ${Math.round(Number(offer.durability))}`
                    : '';
            name.innerHTML = `<span class="trade-panel__icon">${typeof BSIcons !== 'undefined'
                ? BSIcons.get(offer.item, offer.category) : ''}</span>`;
            name.appendChild(document.createTextNode(`${offer.label} ×${offer.amount}${detail}`));
            row.appendChild(name);
            if (removable) {
                const remove = document.createElement('button');
                remove.textContent = t('trade.remove');
                remove.addEventListener('click', async () => {
                    const result = await post('tradeOffer', { slot: offer.slot, add: false });
                    if (!result.ok) tradeNotice(result.error || t('trade.remove_fail'));
                });
                row.appendChild(remove);
            }
            host.appendChild(row);
        }
    }
}

function renderTradeBag() {
    const host = $('tradeBag');
    if (!host) return; // An older cached HTML page may lack the new trade bag.
    host.innerHTML = '';
    if (!S.trade || S.trade.phase !== 'offering') return;
    const offered = new Set((S.trade.mine || []).map((entry) => Number(entry.slot)));
    const slots = (S.player && S.player.slots) || {};
    const entries = Object.entries(slots).filter(([, entry]) => entry && entry.item);
    entries.sort((a, b) => Number(a[0]) - Number(b[0]));
    if (!entries.length) host.textContent = t('trade.bag_empty');
    for (const [key, entry] of entries) {
        const slot = Number(key);
        const button = document.createElement('button');
        button.className = 'trade-panel__bag-item';
        button.type = 'button';
        button.draggable = !offered.has(slot);
        button.disabled = offered.has(slot);
        button.title = offered.has(slot) ? t('trade.already_offered') : t('trade.drag_offer');
        button.innerHTML = `<span class="trade-panel__icon">${typeof BSIcons !== 'undefined' ? BSIcons.get(entry.item, entry.category) : ''}</span><span>${esc(entry.label || entry.item)} ×${Number(entry.amount || 1)}</span>`;
        button.addEventListener('dragstart', (event) => {
            event.dataTransfer.setData('text/plain', String(slot));
            event.dataTransfer.effectAllowed = 'move';
        });
        button.addEventListener('click', async () => {
            const result = await post('tradeOffer', { slot, add: true });
            if (!result.ok) tradeNotice(result.error || t('trade.offer_fail2'));
        });
        host.appendChild(button);
    }
}

const tradeDrop = $('tradeMineZone');
tradeDrop?.addEventListener('dragover', (event) => {
    if (!S.trade || S.trade.phase !== 'offering') return;
    event.preventDefault();
    tradeDrop.classList.add('is-over');
});
tradeDrop?.addEventListener('dragleave', () => tradeDrop.classList.remove('is-over'));
tradeDrop?.addEventListener('drop', async (event) => {
    event.preventDefault();
    tradeDrop.classList.remove('is-over');
    const slot = Number(event.dataTransfer.getData('text/plain'));
    if (!Number.isInteger(slot) || slot < 1) return;
    const result = await post('tradeOffer', { slot, add: true });
    if (!result.ok) tradeNotice(result.error || t('trade.offer_fail2'));
});
$('tradeCashSet')?.addEventListener('click', async () => {
    const raw = $('tradeCash').value.trim();
    const amount = Number(raw);
    if (!/^\d+$/.test(raw) || !Number.isSafeInteger(amount)) {
        tradeNotice(t('trade.whole_dollar'));
        return;
    }
    const result = await post('tradeMoney', { amount });
    if (!result.ok) tradeNotice(result.error || t('trade.cash_fail'));
});

$('btnTrade').addEventListener('click', async () => {
    if (S.trade) return;
    const res = await post('nearbyPlayers');
    const list = $('whoList');
    $('who').querySelector('h3').textContent = t('inv.trade_with', { fallback: 'TRADE WITH' });
    list.innerHTML = '';
    if (!res.players || !res.players.length) {
        list.textContent = t('trade.nobody');
    } else {
        for (const player of res.players) {
            const button = document.createElement('button');
            button.className = 'who__btn';
            button.textContent = `${player.name} (#${player.source})`;
            button.addEventListener('click', async () => {
                $('who').classList.add('hidden');
                const result = await post('tradeRequest', { target: player.source });
                if (!result.ok) tradeNotice(result.error || t('trade.invite_fail'));
            });
            list.appendChild(button);
        }
    }
    $('who').classList.remove('hidden');
});

$('tradeAccept').addEventListener('click', async () => {
    const result = await post('tradeRespond', { accept: true });
    if (!result.ok) tradeNotice(result.error || t('trade.expired'));
});
$('tradeConfirm').addEventListener('click', async () => {
    const result = await post('tradeConfirm');
    if (!result.ok) tradeNotice(result.error || t('trade.failed'));
});
$('tradeCancel').addEventListener('click', () => post('tradeCancel'));

// split

$('splitOk').addEventListener('click', async () => {
    if (!pendingSplit) return;
    const amount = Math.max(1, Math.min(Number($('splitInput').value) || 1, pendingSplit.max));
    const { from, to } = pendingSplit;
    pendingSplit = null;
    $('split').classList.add('hidden');
    await post('move', { from, to, amount });
});

$('splitCancel').addEventListener('click', () => {
    pendingSplit = null;
    $('split').classList.add('hidden');
});

// settings

// Filter picker is built from data: the filter list lives in bs_ui's config, so the buttons are generated into the same .seg container and use the generic data-value handler.

// Filter names and notes come from bs_ui's config in English; locale keys win.
function filterText(preset, field) {
    const fb = field === 'note' ? (preset.note || '') : String(preset.label || preset.id);
    return t('inv.filter_' + preset.id + (field === 'note' ? '_note' : ''), { fallback: fb });
}

function buildFilterSeg() {
    const seg = $('filterSeg');
    if (!seg || !S.filters) { return; }
    if (seg.dataset.built === '1') { return; }   // the list never changes mid-session

    seg.innerHTML = '';
    S.filters.forEach((preset) => {
        const b = document.createElement('button');
        b.dataset.value = preset.id;
        b.textContent = filterText(preset, 'label').toUpperCase();
        if (preset.note) { b.title = filterText(preset, 'note'); }
        seg.appendChild(b);
    });

    seg.dataset.built = '1';
    wireSeg(seg);
}

// The note under the picker follows the selected filter.
function paintFilterNote() {
    const note = $('filterNote');
    if (!note || !S.filters) { return; }
    const preset = S.filters.filter((f) => f.id === S.settings.filter)[0];
    note.textContent = (preset && preset.note && filterText(preset, 'note'))
        || t('inv.filter_note');
}

// Sliders show 0.00 by default, or a percent when the input says data-unit="pct".
function rangeText(input, value) {
    return input.dataset.unit === 'pct' ? `${Math.round(Number(value))}%` : Number(value).toFixed(2);
}

// HUD style and menu palette pickers: built from the lists bs_ui sends, so a new entry needs no markup here.
function lockedChoice(def) { return !!(def && def.vip) && S.settings.hudVip !== true; }

function buildChoiceSegs() {
    const ch = S.choices;
    if (!ch) return;
    const lang = (window.BSI18n && BSI18n.lang && BSI18n.lang()) || 'en';
    const stamp = lang + ':' + (ch.vip ? 1 : 0);

    [['hudStyleSeg', ch.styles, 'hs_'], ['paletteSeg', ch.palettes, 'pal_']].forEach(([id, list, pre]) => {
        const seg = $(id);
        if (!seg || !list || seg.dataset.built === stamp) return;
        seg.innerHTML = '';
        list.forEach((d) => {
            const b = document.createElement('button');
            b.dataset.value = d.id;
            if (d.vip) b.dataset.vip = '1';
            if (d.sw) {
                const dots = document.createElement('span');
                dots.className = 'swatch';
                d.sw.forEach((c) => { const i = document.createElement('i'); i.style.background = c; dots.appendChild(i); });
                b.appendChild(dots);
            }
            b.appendChild(document.createTextNode(String(t('st.' + pre + d.id, { fallback: d.label })).toUpperCase()));
            seg.appendChild(b);
        });
        seg.dataset.built = stamp;
        wireSeg(seg);
    });

    // Hover previews a style without selecting it.
    const prev = $('hudPrev');
    const seg = $('hudStyleSeg');
    if (prev && seg && !seg.dataset.hover) {
        seg.dataset.hover = '1';
        seg.addEventListener('mouseover', (e) => {
            const b = e.target.closest('button[data-value]');
            if (b) prev.dataset.style = b.dataset.value;
        });
        seg.addEventListener('mouseleave', paintPreview);
    }
}

function activeChoice(key, list) {
    const def = (list || []).filter((d) => d.id === S.settings[key])[0];
    return def && !lockedChoice(def) ? def.id : (key === 'hudStyle' ? 'classic' : 'default');
}

function paintPreview() {
    const prev = $('hudPrev');
    if (prev) prev.dataset.style = activeChoice('hudStyle', S.choices && S.choices.styles);
}

function paintSettings() {
    buildChoiceSegs();
    buildFilterSeg();
    paintFilterNote();
    document.querySelectorAll('.seg[data-setting]').forEach((seg) => {
        const key = seg.dataset.setting;
        const current = String(S.settings[key]);
        seg.querySelectorAll('button').forEach((b) =>
            b.classList.toggle('is-active', b.dataset.value === current));
    });

    document.querySelectorAll('input[type=range][data-setting]').forEach((input) => {
        const key = input.dataset.setting;
        const value = S.settings[key];
        if (value !== undefined) {
            input.value = value;
            const out = $(`val-${key}`);
            if (out) out.textContent = rangeText(input, value);
        }
    });

    // VIP HUD styles and palettes: locked unless the player is VIP (or the VIP system is off)
    [['hudStyleSeg', 'hudStyle', 'styles'], ['paletteSeg', 'menuPalette', 'palettes']].forEach(([id, key, list]) => {
        const seg = $(id);
        if (!seg || !S.choices) return;
        const cur = activeChoice(key, S.choices[list]);
        seg.querySelectorAll('button').forEach((b) => {
            b.classList.toggle('is-locked', b.dataset.vip === '1' && S.settings.hudVip !== true);
            b.classList.toggle('is-active', b.dataset.value === cur);
        });
    });
    paintPreview();

    // VIP dash styles: locked with a VIP tag for non-VIP players
    document.querySelectorAll('.seg[data-setting="carHudStyle"] button[data-vip]').forEach((b) => {
        b.classList.toggle('is-locked', S.settings.carHudVip !== true);
    });

    // Chat background opacity means nothing while the background is off.
    const bgOpacity = document.querySelector('input[data-setting="chatBgOpacity"]');
    if (bgOpacity) {
        const off = S.settings.chatBackdrop === false;
        bgOpacity.disabled = off;
        bgOpacity.closest('.setting').classList.toggle('is-disabled', off);
    }
}

// Pulled out of the loop so buildFilterSeg can call it on buttons created after page load.
function wireSeg(seg) {
    seg.querySelectorAll('button').forEach((b) => {
        b.addEventListener('click', () => {
            if (b.classList.contains('is-locked')) return;
            const key = seg.dataset.setting;
            let value = b.dataset.value;
            if (value === 'true') value = true;
            else if (value === 'false') value = false;
            S.settings[key] = value;
            // Palette shows at once; bs_ui confirms it a moment later.
            if (key === 'menuPalette' && window.BSPalette && S.choices) {
                BSPalette.apply(paletteVars(value), value);
            }
            paintSettings();
            post('settings', { patch: { [key]: value } });
            if (key === 'menuPalette' && window.BSPalette) setTimeout(() => BSPalette.refresh(), 400);
        });
    });
}

// Colours of a palette for the instant preview, as sent by bs_ui.
function paletteVars(id) {
    const d = ((S.choices && S.choices.palettes) || []).filter((p) => p.id === id)[0];
    return (d && d.vars) || null;
}

// Settings search: hides rows and empty groups that do not match.
(function () {
    const box = document.getElementById('settingsSearch');
    if (!box) return;
    box.addEventListener('input', () => {
        const q = box.value.trim().toLowerCase();
        let shown = 0;
        document.querySelectorAll('.sgroup').forEach((g) => {
            let any = 0;
            g.querySelectorAll('.setting').forEach((row) => {
                const hit = !q || row.textContent.toLowerCase().indexOf(q) !== -1;
                row.classList.toggle('hidden', !hit);
                if (hit) any++;
            });
            g.classList.toggle('hidden', any === 0);
            shown += any;
        });
        const none = document.getElementById('settingsNone');
        if (none) none.classList.toggle('hidden', shown > 0);
    });
})();

document.querySelectorAll('.seg[data-setting]').forEach(wireSeg);

// Language picker reflects the account language when it changes (also from another screen).
if (window.BSI18n) {
    window.BSI18n.onChange((lang) => {
        S.settings.language = lang;
        // rebuild the filter buttons so their names follow the language
        const seg = $('filterSeg');
        if (seg) seg.dataset.built = '';
        paintSettings();
    });
}

// Troubleshooting buttons. The Lua side runs the matching chat command.
document.querySelectorAll('button[data-action]').forEach((b) => {
    b.addEventListener('click', () => post('settingsAction', { action: b.dataset.action }));
});

document.querySelectorAll('input[type=range][data-setting]').forEach((input) => {
    input.addEventListener('input', () => {
        const key = input.dataset.setting;
        const value = Number(input.value);
        S.settings[key] = value;
        const out = $(`val-${key}`);
        if (out) out.textContent = rangeText(input, value);
        post('settings', { patch: { [key]: value } });
    });
});

// cat filter

const catFilterEl = $('catFilter');
if (catFilterEl) {
    catFilterEl.querySelectorAll('button[data-filter]').forEach((b) => {
        b.addEventListener('click', () => {
            catFilter = b.dataset.filter;
            catFilterEl.querySelectorAll('button').forEach((x) =>
                x.classList.toggle('is-active', x === b));
            renderGrid($('playerGrid'), S.player, 'player');
            renderList();
        });
    });
}

// tabs

document.querySelectorAll('.tab[data-tab]').forEach((t) => {
    t.addEventListener('click', () => {
        document.querySelectorAll('.tab[data-tab]').forEach((x) => x.classList.remove('is-active'));
        document.querySelectorAll('.pane').forEach((x) => x.classList.remove('is-active'));
        t.classList.add('is-active');
        document.querySelector(`.pane[data-pane="${t.dataset.tab}"]`).classList.add('is-active');
    });
});

$('btnClose').addEventListener('click', () => post('close'));

// ESC only. Listening for the open key here would close the window right away, because the keyup of the opening press arrives while the NUI has focus.
document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') post('close');
});

document.addEventListener('keydown', async (e) => {
    if (e.key !== 'x' && e.key !== 'X') return;
    const hovered = document.querySelector('.slot[data-hover="1"][data-inv="player"]');
    if (!hovered) return;
    await post('drop', { slot: Number(hovered.dataset.slot) });
});

// from client

// Item names follow the player's language: locale key item.<name>, the server label as fallback.
function localizeItems(o, depth = 0) {
    if (!o || typeof o !== 'object' || depth > 6) return;
    if (Array.isArray(o)) { o.forEach((v) => localizeItems(v, depth + 1)); return; }
    if (typeof o.item === 'string' && typeof o.label === 'string') o.label = t('item.' + o.item, { fallback: o.label });
    for (const k in o) {
        const v = o[k];
        if (v && typeof v === 'object') localizeItems(v, depth + 1);
    }
}

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action !== 'bs_i18n') localizeItems(d);

    if (d.action === 'tradeOpen') {
        try {
            S.player = d.player || null;
            $('root').classList.remove('hidden');
            renderTrade(d.trade);
            post('inventoryReady', {});
        } catch (error) {
            console.error('[bs_inventory] trade window failed', error);
            post('close');
        }
        return;
    }

    if (d.action === 'open') {
        // Reveal the shell first so a bad item or stale cached asset never leaves the game camera active behind an invisible page.
        $('root').classList.remove('hidden');
        try {
        renderTrade(d.trade);
        if (d.grid) S.grid = { w: d.grid.w, h: d.grid.h };
        S.player = d.player || null;
        // A normal TAB-open must never reuse the container from the previous session.
        // Containers (including the personal storage) are only restored by an explicit
        // server 'update' after the player actually opens one at its world interaction point.
        S.container = null;
        $('containerTitle').textContent = t('inv.nothing_open');
        renderStats(d.stats);
        renderMedical(d.stats, d.levels, S.player && S.player.equipStats);
        renderSheet(d.levels, d.effects, d.trees);
        if (d.hotbar) S.hotbar = d.hotbar;
        // Must run before paintSettings: buildFilterSeg reads it on first paint and never rebuilds.
        if (d.filters) S.filters = d.filters;
        if (d.choices) S.choices = d.choices;
        if (d.settings) { S.settings = d.settings; paintSettings(); }

        // The hub can ask for a specific tab (Settings).
        const wanted = d.tab || 'carry';
        document.querySelectorAll('.tab[data-tab]').forEach((t) =>
            t.classList.toggle('is-active', t.dataset.tab === wanted));
        document.querySelectorAll('.pane').forEach((p) =>
            p.classList.toggle('is-active', p.dataset.pane === wanted));

        renderAll();
        renderTradeBag();
        // rect only after layout, or the camera has nothing to fit to
        requestAnimationFrame(() => requestAnimationFrame(() =>
            post('inventoryReady', {})));
        } catch (error) {
            console.error('[bs_inventory] inventory open failed', error);
            post('close');
        }
    }

    if (d.action === 'boosters') {
        S.boosters = d.loadout || {};
        if (d.keys) S.boosterKeys = d.keys;
        Object.values(S.boosters).forEach((b) => {
            if (b) b.cooldownEnd = b.cooldown > 0 ? Date.now() + b.cooldown * 1000 : 0;
        });
        renderBoosters();
        return;
    }

    if (d.action === 'gadgets') {
        S.gadgets = d.loadout || {};
        if (d.keys) S.gadgetKeys = d.keys;
        Object.values(S.gadgets).forEach((b) => {
            if (b) b.cooldownEnd = b.cooldown > 0 ? Date.now() + b.cooldown * 1000 : 0;
        });
        renderGadgets();
        return;
    }

    if (d.action === 'hotbar') {
        // The HUD still pushes its copy here; a push triggers a redraw.
        renderHotbar();
        return;
    }

    if (d.action === 'update') {
        if (d.player) S.player = d.player;
        if (d.container !== undefined) S.container = d.container || null;
        if (d.containerLabel) $('containerTitle').textContent = String(d.containerLabel).toUpperCase();
        if (!S.container) $('containerTitle').textContent = t('inv.nothing_open');
        renderAll();
        renderTradeBag();
    }

    if (d.action === 'trade') renderTrade(d.trade);

    if (d.action === 'close') {
        renderTrade(null);
        hideTip();
        sel = null;
        $('root').classList.add('hidden');
        $('split').classList.add('hidden');
        $('who').classList.add('hidden');
        closeContext();
        if (carry) {
            if (carry.ghost) carry.ghost.remove();
            document.body.classList.remove('is-carrying');
            document.querySelectorAll('.is-over, .is-dragging').forEach((n) => {
                n.classList.remove('is-over');
                n.classList.remove('is-dragging');
            });
            carry = null;
        }
        pendingSplit = null;
    }
});


// hotbar
// Moves the stack onto one of the five bar slots from the context menu, which frees the source square.

document.querySelectorAll('.ctx__slot').forEach((b) => {
    b.addEventListener('click', async () => {
        if (!ctxTarget || !ctxTarget.entry) return;

        const index = Number(b.dataset.bind);
        const from = ctxTarget.slot;
        const entry = ctxTarget.entry;

        closeContext();

        await post('move', {
            from: { inv: ctxTarget.inv || 'player', slot: from },
            to:   { inv: 'player', slot: barSlotOf(index) },
            amount: entry.amount,
        });
    });
});

// stats
// Snapshot from bs_core GetData() taken when the panel opens, not a live feed (see cl_main.lua).

function renderMedical(d, levels, gear) {
    const state = document.getElementById('medicalState');
    const readout = document.getElementById('medicalReadout');
    if (!readout) return;
    const needs = (d && d.needs) || {};
    const num = (v, fallback = 0) => Number.isFinite(Number(v)) ? Math.max(0, Math.min(100, Number(v))) : fallback;
    const health = num(d && d.health, 100), infection = num(needs.infection, 0), hunger = num(needs.hunger, 100), thirst = num(needs.thirst, 100), armour = num(d && d.armour, 0), vest = Math.max(0, Number(gear && gear.armour) || 0);
    const critical = health <= 25 || infection >= 75, watch = !critical && (health <= 55 || infection >= 45 || hunger <= 20 || thirst <= 20);
    const condition = critical ? t('fm.critical') : (watch ? t('fm.watch') : t('fm.stable')), skill = Number(levels && levels.medical) || 0;
    Body.sex = d && d.bodySex;
    if (state) { state.textContent = condition; state.className = `fieldmed__state ${critical ? 'is-critical' : (watch ? 'is-watch' : '')}`; }
    const row = (label, value, mood = '') => `<div class="medrow ${mood}"><span class="medrow__label">${label}</span><span class="medrow__value">${value}</span></div>`;
    readout.innerHTML = [
        row(t('fm.vital'), `${Math.round(health)}%`, health <= 25 ? 'is-critical' : (health <= 55 ? 'is-watch' : '')),
        row(t('fm.infection'), `${Math.round(infection)}%`, infection >= 75 ? 'is-critical' : (infection >= 45 ? 'is-watch' : '')),
        row(t('fm.food'), `${Math.round(hunger)}%`, hunger <= 20 ? 'is-watch' : ''),
        row(t('fm.water'), `${Math.round(thirst)}%`, thirst <= 20 ? 'is-watch' : ''),
        row(t('fm.vest'), armour > 0 ? `${Math.round(armour)}%` : t('fm.none')),
        `<div class="fieldmed__note">${t('fm.skill', { n: skill })}</div>`,
        `<button type="button" class="fieldmed__refresh" id="bodyRefresh">${t('fm.refresh')}</button>`,
    ].join('');
    syncRefreshBtn();
}

// Body snapshot refresh: recapture on demand, 10 s cooldown.
const BodyRefresh = { busy: false, until: 0, timer: null };
function syncRefreshBtn() {
    const b = document.getElementById('bodyRefresh');
    if (!b) return;
    const left = Math.ceil((BodyRefresh.until - Date.now()) / 1000);
    b.disabled = BodyRefresh.busy || left > 0;
    b.textContent = BodyRefresh.busy ? t('fm.capturing') : (left > 0 ? `${t('fm.refresh')} (${left})` : t('fm.refresh'));
}
document.addEventListener('click', async (e) => {
    const b = e.target.closest && e.target.closest('#bodyRefresh');
    if (!b || b.disabled) return;
    BodyRefresh.busy = true; syncRefreshBtn();
    const r = await post('bodyRefresh');
    if (!r || !r.ok) {
        BodyRefresh.busy = false;
        BodyRefresh.until = Date.now() + ((r && r.wait) || 0);
    } else {
        BodyRefresh.until = Date.now() + (r.cooldown || 10000);
        setTimeout(() => { if (BodyRefresh.busy) { BodyRefresh.busy = false; syncRefreshBtn(); } }, 6000);   // never stuck
    }
    clearInterval(BodyRefresh.timer);
    BodyRefresh.timer = setInterval(() => { syncRefreshBtn(); if (Date.now() > BodyRefresh.until && !BodyRefresh.busy) clearInterval(BodyRefresh.timer); }, 1000);
    syncRefreshBtn();
});
function renderStats(d) {
    const fieldmedTitle = document.getElementById('fieldmedTitle');
    const name = document.getElementById('statName');
    const klass = document.getElementById('statClass');
    const rows = document.getElementById('statRows');
    if (!rows) return;

    if (!d) {
        if (fieldmedTitle) fieldmedTitle.textContent = 'CHARAKTER';
        rows.innerHTML = '';
        return;
    }

    if (fieldmedTitle) fieldmedTitle.textContent = d.name || 'CHARAKTER';
    if (name) name.textContent = d.name || '-';
    if (klass) klass.textContent = d.className || d.classId || '';

    const needs = d.needs || {};

    // `low` is the threshold under which the bar turns red. Infection is inverted: high is bad.
    const spec = [
        { k: 'health', label: 'Health', v: d.health,        max: 100, low: 30 },
        { k: 'armour', label: 'Armour', v: d.armour,        max: 100, low: -1 },
        { k: 'hunger', label: 'Food',   v: needs.hunger,    max: 100, low: 25 },
        { k: 'thirst', label: 'Water',  v: needs.thirst,    max: 100, low: 25 },
        { k: 'infect', label: 'Infect', v: needs.infection, max: 100, low: -1, invert: true },
    ];

    let html = '';

    spec.forEach((s) => {
        if (s.v === undefined || s.v === null) return;   // a stat we do not track
        const val = Math.max(0, Math.min(s.max, Math.round(s.v)));
        const pct = (val / s.max) * 100;
        const bad = s.invert ? (val >= 60) : (s.low >= 0 && val <= s.low);

        html += `<div class="stat stat--${s.k}${bad ? ' is-low' : ''}">
            <span class="stat__label">${esc(t('stat.' + s.k, { fallback: s.label }))}</span>
            <span class="stat__track"><span class="stat__fill" style="width:${pct}%"></span></span>
            <span class="stat__val">${val}</span>
        </div>`;
    });

    // Level and XP last, since it is progress rather than condition.
    if (d.level !== undefined) {
        const toNext = d.xpToNext || 0;
        const pct = toNext > 0 ? Math.max(0, Math.min(100, ((d.xp || 0) / toNext) * 100)) : 100;
        html += `<div class="stat stat--xp">
            <span class="stat__label">${esc(t('stat.lv', { n: d.level }))}</span>
            <span class="stat__track"><span class="stat__fill" style="width:${pct}%"></span></span>
            <span class="stat__val">${isFinite(toNext) && toNext > 0
                ? Math.round(pct) + '%' : t('stat.max')}</span>
        </div>`;
    }

    rows.innerHTML = html;
}

// character sheet
// Each modifier declares its own polarity (good/bad), because a negative hunger rate is a buff and the sign alone cannot tell.

const MOD_SPEC = [
    { k: 'carryWeight',  label: 'Carry weight', pct: false, unit: 'kg', good: 'up' },
    { k: 'weaponDamage', label: 'Gun damage',   pct: true,  good: 'up' },
    { k: 'meleeDamage',  label: 'Melee damage', pct: true,  good: 'up' },
    { k: 'stealth',      label: 'Seen later',   pct: true,  good: 'up' },
    { k: 'xpBonus',      label: 'XP gain',      pct: true,  good: 'up' },
    { k: 'hungerRate',   label: 'Hunger rate',  pct: true,  good: 'down', flip: true },
    { k: 'thirstRate',   label: 'Thirst rate',  pct: true,  good: 'down', flip: true },
];

function renderSheet(levels, effects, trees) {
    const treeBox = document.getElementById('sheetTrees');
    const modBox = document.getElementById('sheetMods');
    const pts = document.getElementById('sheetPoints');
    if (!treeBox || !modBox) return;

    levels = levels || {};
    effects = effects || {};
    trees = trees || {};

    if (pts) {
        const p = effects.points;
        pts.textContent = (p && p > 0) ? `${p} POINT${p === 1 ? '' : 'S'} TO SPEND` : '';
    }

    // Trees follow the config order so the panel and the skills menu agree.
    let th = '';
    Object.keys(trees).forEach((id) => {
        const t = trees[id] || {};
        const lvl = levels[id] || 0;
        const max = t.maxLevel || 20;
        th += `<div class="tree">
            <span class="tree__name">${esc(t.label || id)}</span>
            <span class="tree__track"><span class="tree__fill"
                style="width:${Math.min(100, (lvl / max) * 100)}%"></span></span>
            <span class="tree__lvl">${lvl}</span>
        </div>`;
    });
    treeBox.innerHTML = th || `<span class="mod__none">${t('mod.no_skills')}</span>`;

    // Only modifiers that are actually active; zero rows are noise.
    let mh = '';
    MOD_SPEC.forEach((m) => {
        const raw = effects[m.k];
        if (raw === undefined || raw === null || Math.abs(raw) < 0.0001) return;

        const shown = m.flip ? -raw : raw;
        const helping = (m.good === 'up') ? (raw > 0) : (raw > 0);
        const text = m.pct
            ? `${shown > 0 ? '+' : ''}${Math.round(shown * 100)}%`
            : `${shown > 0 ? '+' : ''}${shown.toFixed(1)}${m.unit || ''}`;

        mh += `<div class="mod ${helping ? 'mod--good' : 'mod--bad'}">
            <span class="mod__label">${esc(t('mod.' + m.k, { fallback: m.label }))}</span>
            <span class="mod__val">${text}</span>
        </div>`;
    });

    modBox.innerHTML = mh || `<span class="mod__none">${t('mod.spend')}</span>`;
}




// boosters
// Three slots fed by bs_boosters: name, count left, cooldown.
let boosterTick = null;
function renderBoosters() {
    const keys = S.boosterKeys || ['6', '7', '8'];
    document.querySelectorAll('.booster[data-bidx]').forEach((node) => {
        const idx = node.dataset.bidx;
        const b = S.boosters && S.boosters[idx];
        node.classList.toggle('has-booster', !!b);
        node.classList.toggle('is-out', !!b && !(b.count > 0));
        const key = `<span class="booster__key">${esc(keys[Number(idx) - 1] || idx)}</span>`;
        if (!b) {
            node.innerHTML = `${key}<span class="lslot__empty">${esc(t('inv.slot_empty', { fallback: 'EMPTY' }))}</span>`;
            node.title = t('inv.drag_booster');
            return;
        }
        const cd = b.cooldownEnd ? Math.ceil((b.cooldownEnd - Date.now()) / 1000) : 0;
        node.innerHTML = loadoutPlate(b.item, node.dataset.gidx ? 'gadget' : 'booster', b.label,
            keys[Number(idx) - 1] || idx, Number(b.count) || 0)
            + (cd > 0 ? `<span class="booster__cd">${cd}s</span>` : '');
        node.title = t('inv.rclick_clear', { name: b.label, fallback: `${b.label} - right-click to clear` });
    });
    const anyCd = Object.values(S.boosters || {}).some((b) => b && b.cooldownEnd && b.cooldownEnd > Date.now());
    if (anyCd && !boosterTick) {
        boosterTick = setInterval(() => {
            renderBoosters();
        }, 1000);
    } else if (!anyCd && boosterTick) {
        clearInterval(boosterTick);
        boosterTick = null;
    }
}

document.querySelectorAll('.booster[data-bidx]').forEach((node) => {
    node.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        if (S.boosters && S.boosters[node.dataset.bidx]) {
            post('boosterSet', { index: Number(node.dataset.bidx), item: null });
        }
    });
});

// gadgets
// Two deployable slots fed by bs_gadgets. Same look as boosters.
let gadgetTick = null;
function renderGadgets() {
    const keys = S.gadgetKeys || ['9', '0'];
    document.querySelectorAll('.booster[data-gidx]').forEach((node) => {
        const idx = node.dataset.gidx;
        const b = S.gadgets && S.gadgets[idx];
        node.classList.toggle('has-booster', !!b);
        node.classList.toggle('is-out', !!b && !(b.count > 0));
        const key = `<span class="booster__key">${esc(keys[Number(idx) - 1] || idx)}</span>`;
        if (!b) {
            node.innerHTML = `${key}<span class="lslot__empty">${esc(t('inv.slot_empty', { fallback: 'EMPTY' }))}</span>`;
            node.title = t('inv.drag_gadget');
            return;
        }
        const cd = b.cooldownEnd ? Math.ceil((b.cooldownEnd - Date.now()) / 1000) : 0;
        node.innerHTML = loadoutPlate(b.item, node.dataset.gidx ? 'gadget' : 'booster', b.label,
            keys[Number(idx) - 1] || idx, Number(b.count) || 0)
            + (cd > 0 ? `<span class="booster__cd">${cd}s</span>` : '')
            + (b.battery != null ? `<span class="booster__cd">${Math.round(b.battery)}%</span>` : '');
        node.title = b.battery != null ? `${b.label} - battery ${Math.round(b.battery)}% - right-click to clear` : `${b.label} - right-click to clear`;
    });
    const anyCd = Object.values(S.gadgets || {}).some((b) => b && b.cooldownEnd && b.cooldownEnd > Date.now());
    if (anyCd && !gadgetTick) {
        gadgetTick = setInterval(renderGadgets, 1000);
    } else if (!anyCd && gadgetTick) {
        clearInterval(gadgetTick);
        gadgetTick = null;
    }
}

document.querySelectorAll('.booster[data-gidx]').forEach((node) => {
    node.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        if (S.gadgets && S.gadgets[node.dataset.gidx]) {
            post('gadgetSet', { index: Number(node.dataset.gidx), item: null });
        }
    });
});

// body status
// Four snapshots (front/right/back/left) cut from one game-view grab (see grabGameView): the flat backdrop is keyed out and all four are trimmed and scaled the same. If the grab fails the silhouette stays.

const Body = { shots: null, angle: 0, sex: null, injuries: {}, front: 'A' };
const ANGLE_NAMES = ['FRONT', 'RIGHT SIDE', 'BACK', 'LEFT SIDE'];
const SHOT_W = 300, SHOT_H = 600;

// Game-view grab in plain WebGL. FiveM's NUI swaps in the live game frame when WRAP_T goes CLAMP -> MIRRORED -> REPEAT right after upload. The frame has no NUI in it.
const GameView = { gl: null, fb: null, rt: null, w: 0, h: 0 };

function gameViewInit() {
    if (GameView.gl) return GameView.gl;
    const cv = document.createElement('canvas');
    const gl = cv.getContext('webgl', { preserveDrawingBuffer: true, antialias: false });
    if (!gl) return null;
    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; };
    const prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER,
        'attribute vec2 p; varying vec2 uv; void main(){ uv = vec2((p.x+1.0)*0.5, 1.0-(p.y+1.0)*0.5); gl_Position = vec4(p,0.0,1.0); }'));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER,
        'precision mediump float; varying vec2 uv; uniform sampler2D t; void main(){ gl_FragColor = texture2D(t, uv); }'));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return null;
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'p');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    // the game texture (magic sequence, do not reorder)
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, new Uint8Array(3));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.uniform1i(gl.getUniformLocation(prog, 't'), 0);
    GameView.gl = gl;
    return gl;
}

// offscreen target sized to the window
function gameViewTarget(gl, w, h) {
    if (GameView.fb && GameView.w === w && GameView.h === h) return;
    if (GameView.fb) { gl.deleteFramebuffer(GameView.fb); gl.deleteTexture(GameView.rt); }
    const rt = gl.createTexture();
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, rt);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.activeTexture(gl.TEXTURE0);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, rt, 0);
    Object.assign(GameView, { fb, rt, w, h });
}

// current game frame as a canvas (no NUI), or null
function grabGameView() {
    try {
        const gl = gameViewInit();
        if (!gl) return null;
        const w = window.innerWidth, h = window.innerHeight;
        gameViewTarget(gl, w, h);
        gl.bindFramebuffer(gl.FRAMEBUFFER, GameView.fb);
        gl.viewport(0, 0, w, h);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
        const px = new Uint8Array(w * h * 4);
        gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
        // shader already flipped v, readPixels flips back: rows come out top-down
        for (let i = 3; i < px.length; i += 4) px[i] = 255;
        const c = document.createElement('canvas');
        c.width = w; c.height = h;
        c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(px.buffer), w, h), 0, 0);
        return c;
    } catch (err) {
        console.warn('[bs_inventory] game view grab failed', err);
        return null;
    }
}

// keys out the backdrop in place and returns the 4 figure boxes (or null)
function keyPixels(d, w, h, marks) {

            // backdrop colour = average of the four corners (survives filters/fog)
            let kr = 0, kg = 0, kb = 0, n = 0;
            [[0, 0], [w - 8, 0], [0, h - 8], [w - 8, h - 8]].forEach(([x0, y0]) => {
                for (let y = y0; y < y0 + 8; y++) for (let x = x0; x < x0 + 8; x++) {
                    const i = (y * w + x) * 4; kr += d[i]; kg += d[i + 1]; kb += d[i + 2]; n++;
                }
            });
            kr /= n; kg /= n; kb /= n;

            for (let i = 0; i < d.length; i += 4) {
                const dr = d[i] - kr, dg = d[i + 1] - kg, db = d[i + 2] - kb;
                const dist = Math.sqrt(dr * dr + dg * dg + db * db);
                const a = Math.max(0, Math.min(1, (dist - 45) / 70));
                if (a <= 0) { d[i + 3] = 0; continue; }
                if (a < 1) {   // pull the backdrop tint out of the edge
                    d[i] = Math.max(0, Math.min(255, (d[i] - (1 - a) * kr) / a));
                    d[i + 1] = Math.max(0, Math.min(255, (d[i + 1] - (1 - a) * kg) / a));
                    d[i + 2] = Math.max(0, Math.min(255, (d[i + 2] - (1 - a) * kb) / a));
                }
                d[i + 3] = Math.round(a * 255);
            }

            // bounding box of each figure inside its quarter
            const boxes = [];
            for (let k = 0; k < 4; k++) {
                const m = marks && marks[k];
                const cx = Math.round(((m && m.x > 0 && m.x < 1) ? m.x : (k + 0.5) / 4) * w);
                const half = Math.round(w / 8);
                const x0 = Math.max(0, cx - half), x1 = Math.min(w - 1, cx + half);
                let bx0 = w, by0 = h, bx1 = -1, by1 = -1;
                for (let y = 0; y < h; y += 2) {
                    for (let x = x0; x <= x1; x += 2) {
                        if (d[(y * w + x) * 4 + 3] > 90) {
                            if (x < bx0) bx0 = x; if (x > bx1) bx1 = x;
                            if (y < by0) by0 = y; if (y > by1) by1 = y;
                        }
                    }
                }
                if (bx1 < 0 || (by1 - by0) < h * 0.15) return null;   // nothing usable
                boxes.push({ x: bx0, y: by0, w: bx1 - bx0 + 2, h: by1 - by0 + 2 });
            }
            return boxes;
}

// canvas in, four trimmed PNG data URLs out (or null)
function keyCanvas(src, marks) {
            const w = src.width, h = src.height;
            if (!w || !h) return null;
            const sx = src.getContext('2d', { willReadFrequently: true });
            const px = sx.getImageData(0, 0, w, h);
            const boxes = keyPixels(px.data, w, h, marks);
            if (!boxes) return null;
            sx.putImageData(px, 0, 0);

            const tallest = Math.max(...boxes.map((b) => b.h));
            const scale = Math.min((SHOT_H * 0.95) / tallest, (SHOT_W * 0.96) / Math.max(...boxes.map((b) => b.w)));
            const out = boxes.map((b) => {
                const c = document.createElement('canvas');
                c.width = SHOT_W; c.height = SHOT_H;
                const cx = c.getContext('2d');
                const dw = b.w * scale, dh = b.h * scale;
                cx.drawImage(src, b.x, b.y, b.w, b.h, (SHOT_W - dw) / 2, SHOT_H - dh - SHOT_H * 0.025, dw, dh);
                return c.toDataURL('image/png');
            });
            return out;
}

// fallback: a screenshot data URL
function keyShots(dataUrl, marks) {
    return new Promise((resolve) => {
        const img = new Image();
        img.onload = () => {
            const c = document.createElement('canvas');
            c.width = img.naturalWidth; c.height = img.naturalHeight;
            c.getContext('2d').drawImage(img, 0, 0);
            resolve(keyCanvas(c, marks));
        };
        img.onerror = () => resolve(null);
        img.src = dataUrl;
    });
}

function showAngle(i, instant) {
    Body.angle = ((i % 4) + 4) % 4;
    const stage = $('bodyStage');
    if (!stage) return;
    const sil = $('bodySil');
    if (Body.shots) {
        const next = Body.front === 'A' ? 'B' : 'A';
        const inImg = $(`bodyImg${next}`), outImg = $(`bodyImg${Body.front}`);
        inImg.src = Body.shots[Body.angle];
        inImg.classList.toggle('is-instant', !!instant);
        inImg.classList.add('is-on');
        outImg.classList.remove('is-on');
        Body.front = next;
        stage.classList.add('has-shots');
    } else {
        stage.classList.remove('has-shots');
        $('bodyImgA').classList.remove('is-on');
        $('bodyImgB').classList.remove('is-on');
        if (sil) sil.dataset.angle = String(Body.angle);
    }
    $('bodyAngle').textContent = t('body.angle' + Body.angle, { fallback: ANGLE_NAMES[Body.angle] });
    document.querySelectorAll('#bodyDots b').forEach((b, k) => b.classList.toggle('is-on', k === Body.angle));
    renderMarks();
}

// Marker spots in % of the image, per angle. Side views only show the limbs on that side.
const MARKS = {
    head:  [[50, 8], [50, 8], [50, 8], [50, 8]],
    torso: [[50, 30], [50, 30], [50, 30], [50, 30]],
    rarm:  [[25, 46], [50, 44], [75, 46], null],
    larm:  [[75, 46], null, [25, 46], [50, 44]],
    rleg:  [[42, 78], [50, 78], [58, 78], null],
    lleg:  [[58, 78], null, [42, 78], [50, 78]],
};
const zoneName = (z) => t('zone.' + z, { fallback: ZONE_NAMES[z] || z });
const ZONE_NAMES = { head: 'HEAD', torso: 'TORSO', rarm: 'RIGHT ARM', larm: 'LEFT ARM', rleg: 'RIGHT LEG', lleg: 'LEFT LEG' };

function renderMarks() {
    const box = $('bodyMarks');
    if (!box) return;
    box.innerHTML = Object.entries(Body.injuries || {}).map(([zone, lvl]) => {
        const at = MARKS[zone] && MARKS[zone][Body.angle];
        if (!at || !lvl) return '';
        return `<span class="bmark bmark--${Math.min(3, lvl)}" style="left:${at[0]}%;top:${at[1]}%" title="${esc(t('body.injured', { zone: zoneName(zone) }))}"><i></i></span>`;
    }).join('');
}

function renderChips(list) {
    const box = $('fxChips');
    if (!box) return;
    const injured = Object.keys(Body.injuries || {}).filter((z) => Body.injuries[z] > 0);
    const chips = injured.map((z) => `<span class="fxchip fxchip--hurt">${esc(zoneName(z))}</span>`);
    (list || Body.fx || []).forEach((f) => {
        const m = Math.floor((f.left || 0) / 60), sec = (f.left || 0) % 60;
        chips.push(`<span class="fxchip fxchip--${f.kind === 'drug' ? 'drug' : 'boost'}">${esc(f.label)}<small>${m}:${String(sec).padStart(2, '0')}</small></span>`);
    });
    box.innerHTML = chips.join('') || `<span class="fxchip fxchip--none">${t('body.no_effects')}</span>`;
}

// drag on the picture switches angle every ~60px
(function wireBodyTurn() {
    const stage = $('bodyStage');
    if (!stage) return;
    let down = false, lastX = 0, acc = 0;
    stage.addEventListener('mousedown', (e) => { down = true; lastX = e.clientX; acc = 0; e.preventDefault(); });
    window.addEventListener('mousemove', (e) => {
        if (!down) return;
        acc += e.clientX - lastX; lastX = e.clientX;
        if (Math.abs(acc) >= 60) { showAngle(Body.angle + (acc > 0 ? 1 : -1)); acc = 0; }
    });
    window.addEventListener('mouseup', () => { down = false; });
})();

let coverTimer = null;
window.addEventListener('message', async (e) => {
    const d = e.data || {};
    if (d.action === 'captureCover') {
        const c = $('captureCover');
        c.classList.toggle('hidden', !d.on);
        c.querySelector('span').textContent = d.soft ? t('inv.updating_gear', { fallback: 'UPDATING GEAR...' }) : t('inv.preparing', { fallback: 'PREPARING SURVIVOR...' });
        clearTimeout(coverTimer);
        if (d.on) coverTimer = setTimeout(() => c.classList.add('hidden'), 5000);   // never stuck
    } else if (d.action === 'bodyShots') {
        const shots = await keyShots(d.image, d.marks);
        if (shots) { Body.shots = shots; showAngle(Body.angle, true); }
        else console.warn('[bs_inventory] body snapshot could not be keyed; keeping silhouette');
    } else if (d.action === 'bodyGrab') {
        // The game-view texture is occasionally not ready on slower clients even
        // though the NUI has already painted. Retry a few frames before giving up.
        let shots = null;
        let frame = null;
        for (let attempt = 0; attempt < 5 && !shots; attempt++) {
            await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
            frame = grabGameView();
            if (frame) shots = keyCanvas(frame, d.marks);
            if (!shots && attempt < 4) await new Promise((r) => setTimeout(r, 75));
        }

        // ACK only after keying succeeded. Previously Lua received ok=true as soon
        // as a raw frame existed and immediately destroyed the capture set, even
        // when keyCanvas() had failed. That made the intermittent failure permanent.
        post('bodyGrabbed', { ok: !!shots });

        if (shots) {
            Body.shots = shots;
            showAngle(Body.angle, true);
        } else {
            console.warn('[bs_inventory] game view grab/key failed after retries; keeping silhouette');
        }
    } else if (d.action === 'bodyRefreshDone') {
        BodyRefresh.busy = false; syncRefreshBtn();
    } else if (d.action === 'bodyMode') {
        $('bodyCard').classList.toggle('is-fallback', !d.available);
        if (!Body.shots) showAngle(Body.angle, true);
    } else if (d.action === 'injuries') {
        Body.injuries = d.zones || {};
        renderMarks(); renderChips();
    } else if (d.action === 'activeEffects') {
        Body.fx = d.list || [];
        renderChips();
    }
});

// active effect timers tick down while the bag is open
setInterval(() => {
    if (!Body.fx || !Body.fx.length || $('root').classList.contains('hidden')) return;
    Body.fx.forEach((f) => { f.left = Math.max(0, (f.left || 0) - 1); });
    Body.fx = Body.fx.filter((f) => f.left > 0);
    renderChips();
}, 1000);

// tooltips

const CAT_NAMES = { weapon: 'WEAPON', ammo: 'AMMUNITION', food: 'FOOD', drink: 'DRINK', medical: 'MEDICAL', gear: 'GEAR', booster: 'BOOSTER', gadget: 'GADGET', tool: 'TOOL', material: 'MATERIAL', clothing: 'CLOTHING', misc: 'MISC' };
const CAT_BLURB = {
    weapon: 'Equip it from the bar or drag it to a quick slot.',
    ammo: 'Loaded automatically into the matching weapon.',
    food: 'Restores food. Eat before you are starving.',
    drink: 'Restores water.',
    medical: 'Treats wounds and restores health.',
    booster: 'Single-use buff. Drag into a booster slot, use with 5/6/7.',
    gadget: 'Deployable. Drag into a gadget slot, use with G/H.',
    gear: 'Worn in a gear frame.',
    material: 'Used for crafting and building.',
    tool: 'Wears down with use.',
};
const catName = (c) => t('cat.' + c, { fallback: CAT_NAMES[c] || String(c || 'misc').toUpperCase() });

let tipOn = false;
function showTip(entry, e) {
    if (carry || !entry) return;
    const tip = $('tip');
    const weight = (Number(entry.weight) || 0) * (Number(entry.amount) || 1);
    const rows = [
        `<div class="tip__row"><span>${t('tip.weight')}</span><b>${weight.toFixed(2)} KG${entry.amount > 1 ? ` <small>(${t('tip.each', { n: Number(entry.weight || 0).toFixed(2) })})</small>` : ''}</b></div>`,
        entry.amount > 1 || entry.stack > 1 ? `<div class="tip__row"><span>${t('tip.stack')}</span><b>${entry.amount} / ${entry.stack || 1}</b></div>` : '',
        entry.capacity ? `<div class="tip__row"><span>${t('tip.fill')}</span><b>${slotCountLabel(entry)}</b></div>` : '',
        (!entry.capacity && entry.durability != null) ? `<div class="tip__row"><span>${t('tip.durability')}</span><b>${Math.round(entry.durability)}</b></div>` : '',
        entry.battery != null ? `<div class="tip__row"><span>${t('tip.battery')}</span><b>${Math.round(entry.battery)}% <small>(${esc(entry.batteryCap || 'small')})</small></b></div>` : '',
    ].join('');
    const itemDesc = entry.item ? t('item.' + entry.item + '.desc', { fallback: '' }) : '';
    const desc = itemDesc || entry.description || t('blurb.' + entry.category, { fallback: CAT_BLURB[entry.category] || '' });
    tip.innerHTML = `<div class="tip__head"><span class="tip__name">${esc(entry.label)}</span><span class="tip__cat" data-cat="${esc(entry.category || 'misc')}">${esc(catName(entry.category))}</span></div>
        ${rows}${desc ? `<p class="tip__desc">${esc(desc)}</p>` : ''}
        <div class="tip__keys">${entry.usable ? t('tip.dbl_use') : t('tip.click_select')} &middot; ${t('tip.right_more')}</div>`;
    tip.classList.remove('hidden');
    tipOn = true;
    moveTip(e);
}
function moveTip(e) {
    if (!tipOn || !e) return;
    const tip = $('tip');
    const r = tip.getBoundingClientRect();
    let x = e.clientX + 16, y = e.clientY + 14;
    if (x + r.width > window.innerWidth * 0.66) x = e.clientX - r.width - 12;   // keep out of the right third
    if (y + r.height > window.innerHeight - 8) y = window.innerHeight - r.height - 8;
    tip.style.left = `${Math.max(8, x) / uiK()}px`; tip.style.top = `${Math.max(8, y) / uiK()}px`;
}
function hideTip() { tipOn = false; const t = $('tip'); if (t) t.classList.add('hidden'); }
document.addEventListener('mousedown', hideTip);

// selection + actions

let sel = null;   // { inv, slot }
function selectItem(which, slot) {
    sel = (sel && sel.inv === which && sel.slot === slot) ? null : { inv: which, slot };
    document.querySelectorAll('.is-selected').forEach((n) => n.classList.remove('is-selected'));
    if (sel) document.querySelectorAll(`[data-inv="${which}"][data-slot="${slot}"]`).forEach((n) => n.classList.add('is-selected'));
    refreshQuick();
}
function refreshQuick() {
    const entry = sel && entryAt(sel.inv, sel.slot);
    if (sel && !entry) sel = null;
    const mine = !!entry && sel.inv === 'player';
    $('quickName').textContent = entry ? `${entry.label} ×${entry.amount}`.toUpperCase() : t('inv.select_item');
    $('quickBar').classList.toggle('has-sel', !!entry);
    const btn = (k) => document.querySelector(`[data-quick="${k}"]`);
    btn('use').disabled = !mine || !(entry.usable || isLoadoutItem(entry));
    btn('split').disabled = !mine || !(entry.amount > 1);
    btn('drop').disabled = !mine;
}

// first free spot for a w x h item in the carried grid
// Split from the SPLIT button or the right-click menu: the new half goes to the first free spot. The server gives it its own slot id.
function openSplitPrompt(slot, entry, flashOn) {
    if (!entry || !(entry.amount > 1)) return;
    const spot = freeSpot(entry.w || 1, entry.h || 1);
    if (!spot) { if (flashOn) flashBar(flashOn, t('inv.no_room')); return; }
    pendingSplit = { from: { inv: 'player', slot }, to: { inv: 'player', slot, x: spot.x, y: spot.y, rot: false }, max: entry.amount };
    $('splitInput').max = entry.amount;
    $('splitInput').value = Math.max(1, Math.floor(entry.amount / 2));
    $('split').classList.remove('hidden');
    $('splitInput').focus();
}

function freeSpot(w, h) {
    const W = (S.player && S.player.grid && S.player.grid.w) || S.grid.w;
    const H = (S.player && S.player.grid && S.player.grid.h) || S.grid.h;
    const used = new Set();
    const limit = (S.player && (S.player.gridSlots || S.player.size)) || W * H;
    Object.entries((S.player && S.player.slots) || {}).forEach(([k, e]) => {
        if (!onGrid(e, Number(k), limit) || !e.x || !e.y) return;
        const ew = e.rot ? (e.h || 1) : (e.w || 1), eh = e.rot ? (e.w || 1) : (e.h || 1);
        for (let y = e.y; y < e.y + eh; y++) for (let x = e.x; x < e.x + ew; x++) used.add(`${x},${y}`);
    });
    for (let y = 1; y <= H - h + 1; y++) for (let x = 1; x <= W - w + 1; x++) {
        let ok = true;
        for (let yy = y; yy < y + h && ok; yy++) for (let xx = x; xx < x + w; xx++) if (used.has(`${xx},${yy}`)) { ok = false; break; }
        if (ok) return { x, y };
    }
    return null;
}

document.querySelectorAll('[data-quick]').forEach((b) => {
    b.addEventListener('click', async () => {
        const entry = sel && entryAt(sel.inv, sel.slot);
        if (!entry || sel.inv !== 'player') return;
        const slot = sel.slot, act = b.dataset.quick;
        // Gadgets (and boosters with no use action) go to their slot.
        if (act === 'use' && isLoadoutItem(entry) && !entry.usable) { await equipLoadout(entry, b); return; }
        if (act === 'use') { await post('use', { slot }); return; }
        if (act === 'drop') { sel = null; await post('drop', { slot, amount: entry.amount }); return; }
        if (act === 'split') openSplitPrompt(slot, entry, b);
    });
});

// search, sort, weights

const searchEl = $('invSearch');
if (searchEl) {
    searchEl.addEventListener('input', () => {
        invSearch = searchEl.value.trim().toLowerCase();
        renderGrid($('playerGrid'), S.player, 'player');
        renderList();
    });
    // typing must not trigger the X-to-drop shortcut or ESC-close twice
    searchEl.addEventListener('keydown', (e) => e.stopPropagation());
    searchEl.addEventListener('keyup', (e) => { if (e.key !== 'Escape') e.stopPropagation(); });
}
const sortEl = $('invSort');
if (sortEl) sortEl.addEventListener('change', () => { renderGrid($('playerGrid'), S.player, 'player'); renderList(); });

// sorted view: a list over the same slots, nothing moves on the server
function renderList() {
    const list = $('playerList'), grid = $('playerGrid');
    const mode = sortEl ? sortEl.value : 'grid';
    if (!list || !grid) return;
    list.classList.toggle('hidden', mode === 'grid');
    grid.classList.toggle('hidden', mode !== 'grid');
    if (mode === 'grid') { list.innerHTML = ''; return; }
    const limit = (S.player && (S.player.gridSlots || S.player.size)) || slotCount();
    const rows = Object.entries((S.player && S.player.slots) || {})
        .filter(([k, e]) => onGrid(e, Number(k), limit) && matchesFilter(e))
        .map(([k, e]) => ({ slot: Number(k), e }));
    const byName = (a, b) => String(a.e.label).localeCompare(String(b.e.label));
    rows.sort(mode === 'weight'
        ? (a, b) => (b.e.weight * b.e.amount) - (a.e.weight * a.e.amount) || byName(a, b)
        : mode === 'type' ? (a, b) => String(a.e.category).localeCompare(String(b.e.category)) || byName(a, b)
        : byName);
    list.innerHTML = '';
    if (!rows.length) { list.innerHTML = `<p class="invlist__empty">${esc(t('inv.nothing_matches', { fallback: 'NOTHING MATCHES' }))}</p>`; return; }
    rows.forEach(({ slot, e }) => {
        const icon = (typeof BSIcons !== 'undefined') ? BSIcons.get(e.item, e.category) : '';
        const row = document.createElement('div');
        row.className = 'invrow';
        row.dataset.inv = 'player'; row.dataset.slot = slot; row.dataset.cat = e.category || 'misc';
        row.innerHTML = `<span class="invrow__icon">${icon}</span><span class="invrow__name">${esc(e.label)}</span>
            <span class="invrow__cat">${esc(catName(e.category))}</span><span class="invrow__amt">×${esc(slotCountLabel(e))}</span>
            <span class="invrow__kg">${((e.weight || 0) * (e.amount || 1)).toFixed(1)} KG</span>`;
        wireSlot(row, e, 'player', slot);
        list.appendChild(row);
    });
}

function renderWeightBreak() {
    const box = $('weightBreak');
    if (!box) return;
    const inv = S.player;
    if (!inv || !inv.slots) { box.innerHTML = ''; return; }
    const per = {};
    Object.values(inv.slots).forEach((e) => {
        const k = e.category || 'misc';
        per[k] = (per[k] || 0) + (Number(e.weight) || 0) * (Number(e.amount) || 1);
    });
    const total = Object.values(per).reduce((a, b) => a + b, 0) || 1;
    const over = inv.maxWeight && inv.weight > inv.maxWeight;
    const near = inv.maxWeight && !over && inv.weight / inv.maxWeight > 0.9;
    const parts = Object.entries(per).filter(([, v]) => v > 0.001).sort((a, b) => b[1] - a[1]);
    box.innerHTML = `<div class="wbreak__bar">${parts.map(([k, v]) =>
        `<i data-cat="${esc(k)}" style="width:${(v / total) * 100}%" title="${esc(catName(k))} ${v.toFixed(1)} KG"></i>`).join('')}</div>
        <div class="wbreak__legend">${parts.slice(0, 6).map(([k, v]) =>
        `<span data-cat="${esc(k)}"><b></b>${esc(catName(k))} ${v.toFixed(1)}</span>`).join('')}</div>
        ${over ? `<div class="wbreak__warn">${esc(t('inv.over_capacity', { fallback: 'OVER CAPACITY' }))}</div>` : near ? `<div class="wbreak__warn is-near">${esc(t('inv.nearly_full', { fallback: 'NEARLY FULL' }))}</div>` : ''}`;
}

showAngle(0, true);
renderChips([]);

// /hidehud (bs_ui cl_hidehud.lua): hide the whole page for a clean screenshot.
window.addEventListener('message', (e) => { const d = e.data || {}; if (d.action === 'bsHideAll') document.documentElement.style.visibility = d.hidden ? 'hidden' : ''; });

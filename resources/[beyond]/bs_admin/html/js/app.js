// bs_admin - staff menu UI

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'bs_admin';

const $ = (id) => document.getElementById(id);

async function post(endpoint, data = {}) {
    try {
        const r = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await r.json();
    } catch (e) {
        return { ok: false, error: 'bridge failed' };
    }
}

function msg(text, bad) {
    const m = $('msg');
    m.textContent = String(text || '').toUpperCase();
    m.classList.toggle('bad', !!bad);
    clearTimeout(msg._t);
    msg._t = setTimeout(() => { m.textContent = ''; }, 3500);
}

function report(res, okText) {
    if (res && res.ok) msg(okText || 'done');
    else msg((res && res.error) || 'failed', true);
    return res;
}

function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Tabs

document.querySelectorAll('.mtab').forEach((t) => {
    t.addEventListener('click', () => {
        document.querySelectorAll('.mtab').forEach((x) => x.classList.remove('is-active'));
        document.querySelectorAll('.mpane').forEach((x) => x.classList.remove('is-active'));
        t.classList.add('is-active');
        document.querySelector(`.mpane[data-pane="${t.dataset.tab}"]`).classList.add('is-active');
    });
});

// Actions

document.querySelectorAll('[data-local]').forEach((b) => {
    b.addEventListener('click', async () => {
        // Fixed value baked into the button (data-radius style), for the one local action (failVehicle) that needs an argument
        const payload = { action: b.dataset.local };
        if (b.dataset.seconds) payload.seconds = Number(b.dataset.seconds);
        if (b.dataset.radiusFrom) payload.radius = Number($(b.dataset.radiusFrom).value) || 0;

        const res = await post('local', payload);
        if (res.error) return msg(res.error, true);

        // Some actions need the menu out of the way (teleport, spectate). data-close on the button says so instead of a hardcoded list.
        if (b.dataset.close) {
            $('root').classList.add('hidden');
            post('close');
        }

        if ('godmode' in res)   setToggle('godmode', res.godmode);
        if ('zombieGodmode' in res) setToggle('zombiegodmode', res.zombieGodmode);
        if ('guardAlerts' in res) setToggle('guardalerts', res.guardAlerts);
        if ('noclip' in res)    setToggle('noclip', res.noclip);
        if ('invisible' in res) setToggle('invisible', res.invisible);
        if ('coords' in res)    setToggle('coords', res.coords);
        if ('propid' in res)    setToggle('propid', res.propid);
        if ('zombiehp' in res)  setToggle('zombiehp', res.zombiehp);
        if (res.text) $('debugOut').textContent = res.text;
        msg(res.note || 'done');
    });
});

document.querySelectorAll('[data-server]').forEach((b) => {
    b.addEventListener('click', async () => {
        const args = withTarget({});
        if (b.dataset.radius) args.radius = Number(b.dataset.radius);
        // Fixed value on the button (like data-radius), used by the zombie spawn-mode rows
        if (b.dataset.mode) args.mode = b.dataset.mode;

        const res = await post('server', { action: b.dataset.server, args });
        report(res, res && res.note);

        // Diagnostics has something to show rather than just succeeding.
        if (b.dataset.server === 'diagnostics' && res && res.info) {
            $('debugOut').textContent = JSON.stringify(res.info, null, 2);
        }
        if (b.dataset.server === 'respec' && res && res.ok) {
            msg(`wiped - ${res.refunded} points back`);
            loadSkills();
        }
    });
});

const GIVE_FIELDS = {
    givexp:      'xpAmount',
    givemoney:   'moneyAmount',
    setlevel:    'levelAmount',
    givepoints:  'pointsAmount',
};

document.querySelectorAll('[data-vip]').forEach((b) => {
    b.addEventListener('click', async () => {
        if (b.dataset.vip === 'ticket') {
            report(await post('server', { action: 'grantappearance', args: withTarget({ count: 1 }) }));
            return;
        }
        const action = b.dataset.vip === 'grant' ? 'grantvip' : 'revokevip';
        const args = withTarget({
            tier: $('vipTier').value,
            days: Number($('vipDays').value) || 0,
        });
        report(await post('server', { action, args }));
    });
});

document.querySelectorAll('[data-give]').forEach((b) => {
    b.addEventListener('click', async () => {
        const action = b.dataset.give;
        const value = Number($(GIVE_FIELDS[action]).value);
        if (!value && action !== 'givepoints') return msg('bad amount', true);

        const args = withTarget(action === 'setlevel' ? { level: value } : { amount: value });
        report(await post('server', { action, args }));

        if (action === 'givepoints' || action === 'setlevel') loadSkills();
    });
});

// Debug: change class (yourself, or whoever the target selector names)
async function loadClasses() {
    const res = await post('server', { action: 'classes', args: {} });
    const sel = $('classSelect');
    if (!sel || !res || !res.ok) return;
    const list = (res.classes || []).slice().sort((a, b) => (a.order || 99) - (b.order || 99));
    sel.innerHTML = list.map((c) => `<option value="${esc(c.id)}">${esc(c.label || c.id)}</option>`).join('');
}

$('setClassBtn').addEventListener('click', async () => {
    const cls = $('classSelect').value;
    if (!cls) return msg('no class', true);
    const res = report(await post('server', { action: 'setclass', args: withTarget({ class: cls }) }),
        'class changed');
    if (res && res.ok) renderPlayers(await post('refreshPlayers'));
});

// Server-side actions take a target. The selector at the top picks who and defaults to yourself.
function target() {
    const v = $('targetSelect').value;
    return v ? Number(v) : undefined;
}

function withTarget(args = {}) {
    const t = target();
    if (t !== undefined) args.target = t;
    return args;
}

function setToggle(name, on) {
    const el = $('st-' + name);
    if (!el) return;
    el.textContent = on ? 'ON' : 'OFF';
    el.classList.toggle('on', !!on);
}

// Players

function renderTargets(list) {
    const sel = $('targetSelect');
    const keep = sel.value;
    sel.innerHTML = '<option value="">MYSELF</option>' + (list || []).map((p) =>
        `<option value="${p.source}">#${p.source} ${esc(p.character || p.name)}</option>`).join('');
    sel.value = keep;
}

function renderPlayers(list) {
    renderTargets(list);

    const box = $('players');
    box.innerHTML = '';

    if (!list || !list.length) {
        box.innerHTML = '<p class="mpane__label">NOBODY ONLINE</p>';
        return;
    }

    list.forEach((p) => {
        const node = document.createElement('div');
        node.className = 'player';
        node.innerHTML = `
            <div class="player__top">
                <span>${esc(p.character || p.name)}</span>
                <span class="player__id">#${p.source}</span>
            </div>
            <div class="player__sub">
                ${esc(p.name)} · ${p.class ? esc(p.class).toUpperCase() : 'NO CHARACTER'}
                ${p.level ? ' · LVL ' + p.level : ''} · ${p.ping}MS
            </div>
            <div class="player__acts">
                <button data-act="goto">GOTO</button>
                <button data-act="bring">BRING</button>
                <button data-act="heal">HEAL</button>
                <button data-act="toggleTester" title="Tester menu access (F4), saved per account">${p.tester ? 'TESTER: ON' : 'TESTER: OFF'}</button>
                <button data-act="kick" class="danger">KICK</button>
            </div>`;

        node.querySelectorAll('button').forEach((b) => {
            b.addEventListener('click', async () => {
                const args = { target: p.source };
                if (b.dataset.act === 'kick') {
                    const reason = window.prompt(`Kick ${p.name}? Reason:`);
                    if (reason === null) return;
                    args.reason = reason;
                }
                report(await post('server', { action: b.dataset.act, args }));
                if (b.dataset.act === 'toggleTester') renderPlayers(await post('refreshPlayers'));
            });
        });

        box.appendChild(node);
    });
}

$('targetSelect').addEventListener('change', () => loadSkills());

$('refreshPlayers').addEventListener('click', async () => {
    renderPlayers(await post('refreshPlayers'));
    msg('list refreshed');
});

// World / vehicles

function chips(containerId, items, onPick) {
    const box = $(containerId);
    box.innerHTML = '';
    items.forEach((it) => {
        const b = document.createElement('button');
        b.className = 'chip';

        // Item chips use the same icon as the bag.
        if (it.item && typeof BSIcons !== 'undefined') {
            b.classList.add('chip--icon');
            b.innerHTML = `<span class="chip__icon">${BSIcons.get(it.item, it.category)}</span>`;
            b.appendChild(document.createTextNode(it.label));
        } else {
            b.textContent = it.label;
        }

        b.addEventListener('click', () => onPick(it));
        box.appendChild(b);
    });
}

// Vehicles arrive as labelled groups ({ label, items }), same shape as the weapons tab, each with its own .chips strip
function renderVehicleGroups(groups) {
    const box = $('vehicles');
    box.innerHTML = '';

    (groups || []).forEach((g, i) => {
        const label = document.createElement('p');
        label.className = 'mpane__label';
        label.textContent = String(g.label || '').toUpperCase();
        box.appendChild(label);

        // chips() addresses its container by id, so each strip needs one.
        const strip = document.createElement('div');
        strip.className = 'chips';
        strip.id = `vehicles__g${i}`;
        box.appendChild(strip);

        chips(strip.id, (g.items || []).map((v) => ({
                label: String(v.label).toUpperCase(), model: v.model,
            })),
            async (v) => report(await post('spawnVehicle', { model: v.model }), 'spawned'));
    });
}

// Skills

let PERKS = [];

async function loadSkills() {
    const res = await post('server', { action: 'skills', args: withTarget({}) });
    const box = $('skills');

    if (!res || !res.ok) {
        box.innerHTML = `<p class="mpane__label">${esc((res && res.error) || 'NO DATA')}</p>`;
        return;
    }

    const skills = res.skills || {};
    box.innerHTML = `<p class="mpane__label">${res.points ?? 0} SKILL POINTS UNSPENT</p>` +
        Object.keys(skills).sort().map((k) => {
            const s = skills[k];
            return `<div class="skill">
                <div class="skill__top">
                    <span>${esc(s.label || k)}</span>
                    <span class="skill__lvl">LVL ${s.level}</span>
                </div>
                <div class="skill__acts">
                    <button data-skill="${esc(k)}" data-xp="250">+250 XP</button>
                    <button data-skill="${esc(k)}" data-xp="2000">+2000 XP</button>
                    <button data-skill="${esc(k)}" data-set="5">SET 5</button>
                    <button data-skill="${esc(k)}" data-set="12">SET 12</button>
                    <button data-skill="${esc(k)}" data-set="20">SET 20</button>
                    <button data-skill="${esc(k)}" data-set="0" class="danger">RESET</button>
                </div>
            </div>`;
        }).join('');

    box.querySelectorAll('button').forEach((b) => {
        b.addEventListener('click', async () => {
            const args = withTarget({ skill: b.dataset.skill });
            let action;
            if (b.dataset.xp) { action = 'skillxp'; args.amount = Number(b.dataset.xp); }
            else { action = 'setskill'; args.level = Number(b.dataset.set); }

            report(await post('server', { action, args }));
            loadSkills();
        });
    });

    renderPerks(skills);
}

function renderPerks(skills) {
    const owned = new Set();
    Object.values(skills || {}).forEach((s) =>
        (s.perks || []).forEach((p) => { if (p.owned) owned.add(p.id); }));

    const box = $('perks');
    box.innerHTML = PERKS.map((p) => `
        <div class="perkrow ${owned.has(p.id) ? 'is-owned' : ''}">
            <span class="perkrow__name">${esc(p.label)}
                <em>${esc(p.tree)} ${p.requires}${p.pending ? ' · inactive' : ''}</em></span>
            <button data-perk="${esc(p.id)}" data-remove="${owned.has(p.id) ? 1 : 0}"
                class="${owned.has(p.id) ? 'danger' : ''}">
                ${owned.has(p.id) ? 'REMOVE' : 'GRANT'}</button>
        </div>`).join('');

    box.querySelectorAll('button').forEach((b) => {
        b.addEventListener('click', async () => {
            const args = withTarget({ perk: b.dataset.perk, remove: b.dataset.remove === '1' });
            report(await post('server', { action: 'perk', args }));
            loadSkills();
        });
    });
}

$('refreshSkills').addEventListener('click', loadSkills);

// Items

let ITEMS = [];

// Category tabs come from the item list itself, so new categories show up on their own.
let ITEM_CAT = 'all';
const tt = (k, fb) => (typeof t === 'function' ? t(k, { fallback: fb }) : fb);

function renderItemTabs() {
    const cats = [...new Set(ITEMS.map((i) => i.category || 'misc'))].sort();
    if (ITEM_CAT !== 'all' && !cats.includes(ITEM_CAT)) ITEM_CAT = 'all';
    $('itemTabs').innerHTML = ['all', ...cats].map((c) => {
        const n = c === 'all' ? ITEMS.length : ITEMS.filter((i) => (i.category || 'misc') === c).length;
        const label = c === 'all' ? tt('admin.all', 'ALL') : c.toUpperCase();
        return `<button class="itab${c === ITEM_CAT ? ' is-on' : ''}" data-icat="${esc(c)}">${esc(label)} <small>${n}</small></button>`;
    }).join('');
    $('itemTabs').querySelectorAll('[data-icat]').forEach((b) => b.addEventListener('click', () => {
        ITEM_CAT = b.dataset.icat;
        renderItemTabs();
        renderItems();
    }));
}

function renderItems() {
    const filter = ($('itemFilter').value || '').toLowerCase();
    const list = ITEMS.filter((i) => (ITEM_CAT === 'all' || (i.category || 'misc') === ITEM_CAT) &&
        (!filter || i.label.toLowerCase().includes(filter) || i.item.includes(filter)));
    if (!list.length) { $('items').innerHTML = '<p class="hint">No items here.</p>'; return; }

    chips('items', list.map((i) => ({
            label: i.label.toUpperCase(), item: i.item, category: i.category,
        })),
        async (i) => {
            const amount = Math.max(1, Number($('itemAmount').value) || 1);
            report(await post('server',
                { action: 'giveitem', args: withTarget({ item: i.item, amount }) }),
                `gave ${amount}x ${i.label}`);
        });
}

$('itemFilter').addEventListener('input', renderItems);
document.querySelectorAll('[data-amt]').forEach((b) => b.addEventListener('click', () => { $('itemAmount').value = b.dataset.amt; }));

// Build tab

function fillPick(sel, list, costEl) {
    sel.innerHTML = list.map((x) => `<option value="${esc(x.id)}">${esc(x.label)}${x.station ? ' [' + esc(x.station) + ']' : ''}</option>`).join('');
    const show = () => { const x = list.find((y) => y.id === sel.value); costEl.textContent = x ? x.cost : ''; };
    sel.onchange = show;
    show();
}

async function loadBuild() {
    const r = await post('server', { action: 'buildData', args: {} });
    if (!r || !r.ok) return;
    fillPick($('abPiece'), r.pieces || [], $('abPieceCost'));
    fillPick($('abRecipe'), r.recipes || [], $('abRecipeCost'));
    setToggle('freebuild', r.freeBuild);
    setToggle('raidalways', r.raidAlways);
}

async function giveFor(kind, id, times) {
    if (!id) return msg(tt('admin.pick_first', 'pick one first'), true);
    const res = await post('server', { action: 'giveFor', args: withTarget({ kind, id, times }) });
    if (res && res.ok) msg(res.note || 'done'); else report(res);
}
$('abPieceGive').addEventListener('click', () => giveFor('piece', $('abPiece').value, Number($('abPieceN').value) || 1));
$('abRecipeGive').addEventListener('click', () => giveFor('recipe', $('abRecipe').value, Number($('abRecipeN').value) || 1));
$('abFree').addEventListener('click', async () => {
    const res = await post('server', { action: 'freeBuild', args: {} });
    if (res && res.ok) { setToggle('freebuild', res.on); msg(res.note); } else report(res);
});
$('abRaid').addEventListener('click', async () => {
    const res = await post('server', { action: 'raidAlways', args: {} });
    if (res && res.ok) { setToggle('raidalways', res.on); msg(res.note); } else report(res);
});
$('abFinish').addEventListener('click', async () => {
    const res = await post('server', { action: 'finishFrames', args: { radius: Number($('abRadius').value) || 25 } });
    if (res && res.ok) msg(res.note); else report(res);
});
document.querySelector('.mtab[data-tab="build"]').addEventListener('click', loadBuild);


// Clothing
// Appearance tuner

let CLOTH = null;

// Slot ids in Clothing.Slots order, so groups read top-down like a body.
const CLOTH_SLOT_ORDER = ['top', 'undershirt', 'legs', 'shoes', 'armour',
    'backpack', 'mask', 'accessories', 'glasses', 'hat', 'watch', 'bracelet', 'earrings'];

function renderClothing() {
    const box = $('clothGroups');
    if (!box) { return; }

    const filter = ($('clothFilter').value || '').toLowerCase();
    const garments = ITEMS.filter((i) => i.category === 'clothing'
        && (!filter || i.label.toLowerCase().includes(filter) || i.item.includes(filter)));

    box.innerHTML = '';

    if (!garments.length) {
        const p = document.createElement('p');
        p.className = 'row__hint';
        p.textContent = ITEMS.length
            ? 'No clothing items matched.'
            : 'Item list not loaded yet - reopen the menu.';
        box.appendChild(p);
        return;
    }

    // Grouped by equipSlot, or 'other' when none was sent
    const groups = {};
    garments.forEach((g) => {
        const key = g.equipSlot || 'other';
        (groups[key] = groups[key] || []).push(g);
    });

    const keys = Object.keys(groups).sort((a, b) => {
        const ai = CLOTH_SLOT_ORDER.indexOf(a), bi = CLOTH_SLOT_ORDER.indexOf(b);
        return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
    });

    keys.forEach((key) => {
        const head = document.createElement('p');
        head.className = 'mpane__label mpane__label--sub';
        head.textContent = key.toUpperCase();
        box.appendChild(head);

        const strip = document.createElement('div');
        strip.className = 'chips';
        strip.id = 'cloth_' + key;
        box.appendChild(strip);

        chips(strip.id, groups[key].map((i) => ({ label: i.label.toUpperCase(), item: i.item })),
            async (i) => {
                report(await post('server',
                    { action: 'giveitem', args: withTarget({ item: i.item, amount: 1 }) }),
                    `gave ${i.label}`);
            });
    });
}

// One stepper row per component, rebuilt from the values read off the ped (the ped is the authority)
function renderTuner(state) {
    CLOTH = state;
    const box = $('clothTuner');
    if (!box || !state || !state.components) { return; }

    box.innerHTML = '';

    state.components.forEach((c) => {
        const row = document.createElement('div');
        row.className = 'tunerow';

        const name = document.createElement('span');
        name.className = 'tunerow__name';
        name.textContent = c.label;

        const mk = (text, cls, fn) => {
            const b = document.createElement('button');
            b.className = 'tunebtn ' + (cls || '');
            b.textContent = text;
            b.addEventListener('click', fn);
            return b;
        };

        const val = document.createElement('span');
        val.className = 'tunerow__val';
        val.textContent = `${c.drawable} / ${c.max}`;

        const tex = document.createElement('span');
        val.title = 'drawable / highest available';
        tex.className = 'tunerow__tex';
        tex.textContent = `tex ${c.texture} / ${c.textureMax}`;

        const set = async (drawable, texture) => {
            const r = await post('clothSet',
                { index: c.index, drawable, texture: texture === undefined ? c.texture : texture });
            if (r && r.ok) { renderTuner(r); }
        };

        row.appendChild(name);
        row.appendChild(mk('−', 'tunebtn--d', () => set(c.drawable - 1, 0)));
        row.appendChild(val);
        row.appendChild(mk('+', 'tunebtn--d', () => set(c.drawable + 1, 0)));
        row.appendChild(tex);
        row.appendChild(mk('−', 'tunebtn--t', () => set(c.drawable, c.texture - 1)));
        row.appendChild(mk('+', 'tunebtn--t', () => set(c.drawable, c.texture + 1)));

        box.appendChild(row);
    });

    // The line to paste. arms is emitted even when it is the bare index, so a top never inherits the fallback.
    const by = {};
    state.components.forEach((c) => { by[c.id] = c; });
    const top = by.top || {}, arms = by.arms || {};
    const g = state.gender || 'male';

    $('clothConfig').textContent =
        `${g} = { d = ${top.drawable ?? 0}, t = ${top.texture ?? 0}, arms = ${arms.drawable ?? 15} }`;
}

async function loadTuner() {
    const r = await post('clothRead');
    if (r && r.ok) { renderTuner(r); }
}

if ($('clothFilter')) {
    $('clothFilter').addEventListener('input', renderClothing);

    $('clothStrip').addEventListener('click', async () => {
        const r = await post('clothStrip');
        if (r && r.ok) { renderTuner(r); report({ ok: true }, 'stripped to bare'); }
        else { report(r, ''); }
    });

    $('clothScanArms').addEventListener('click', async () => {
        const r = await post('clothScan', { index: 3 });
        if (!r || !r.ok) { report(r, ''); return; }
        // Written into the config readout rather than a toast, since it is a list to read through.
        $('clothConfig').textContent =
            `component 3 - ${r.valid.length} valid of ${r.total}: ${r.valid.join(', ')}`;
    });

    $('clothRestore').addEventListener('click', async () => {
        const r = await post('server', { action: 'clothRestore', args: {} });
        report(r, 'restored');
        setTimeout(async () => {
            const s = await post('clothPoll');
            if (s && s.ok) { renderTuner(s); }
        }, 500);
    });
}

// Weapons

// Each weapon on its own row with the parts that fit it, plus a KIT button that hands over the lot
function renderWeapons(groups) {
    const box = $('weapons');
    box.innerHTML = '';

    (groups || []).forEach((g) => {
        const label = document.createElement('p');
        label.className = 'mpane__label';
        label.textContent = String(g.label || '').toUpperCase();
        box.appendChild(label);

        g.items.forEach((w) => {
            const row = document.createElement('div');
            row.className = 'wpn';

            const parts = (w.attachments || []);

            row.innerHTML = `
                <div class="wpn__row">
                    <span class="wpn__name">${esc(w.label).toUpperCase()}</span>
                    <button class="chip" data-give="1">GIVE</button>
                    ${parts.length ? '<button class="btn--kit" data-kit="1">+ KIT</button>' : ''}
                </div>
                <div class="wpn__parts">
                    ${parts.length
                        ? parts.map((p) => `<button class="wpn__part" data-item="${esc(p.item)}">
                                ${esc(p.slot).toUpperCase()} · ${esc(p.label)}</button>`).join('')
                        : '<span class="wpn__part wpn__part--none">nothing fits this</span>'}
                </div>`;

            row.querySelector('[data-give]').addEventListener('click', async () => {
                report(await post('giveWeapon', { model: w.model, ammo: w.ammo || 0 }),
                    `gave ${w.label}`);
            });

            const kit = row.querySelector('[data-kit]');
            if (kit) {
                kit.addEventListener('click', async () => {
                    // One call only: the weaponkit already gives the weapon, so posting giveWeapon first handed it over twice
                    const r = await post('server',
                        { action: 'weaponkit', args: withTarget({ model: w.model }) });
                    report(r, `${w.label} + ${(r && r.count) || 0} parts`);
                });
            }

            // One part on its own, for testing a single slot.
            row.querySelectorAll('.wpn__part[data-item]').forEach((b) => {
                b.addEventListener('click', async () => {
                    report(await post('server', {
                        action: 'giveitem',
                        args: withTarget({ item: b.dataset.item, amount: 1 }),
                    }), `gave ${b.textContent.trim()}`);
                });
            });

            box.appendChild(row);
        });
    });
}

// Spawn a specific zombie

// One row per zombie archetype, built from the list bs_zombies sends when the menu opens
function renderZombieTypes(list) {
    const box = $('zombieTypes');
    if (!box) return;

    box.innerHTML = '';

    if (!list || !list.length) {
        box.innerHTML = '<p class="mpane__label">BS_ZOMBIES IS NOT RUNNING</p>';
        return;
    }

    list.forEach((t) => {
        const b = document.createElement('button');
        b.className = 'row';

        // The hint says what the button gives, e.g. that the world never spawns a crawler on its own.
        const hint = t.crawls
            ? 'crawls - admin spawn only, not in the world yet'
            : `${t.health ?? '?'} hp`;

        b.innerHTML = `SPAWN A ${esc(String(t.label || t.id)).toUpperCase()}`
            + `<span class="row__hint">${esc(hint)}</span>`;

        // Closes the menu like the other spawn buttons
        b.addEventListener('click', async () => {
            const res = await post('local', { action: 'forceZombieType', type: t.id });
            if (res && res.error) return msg(res.error, true);
            $('root').classList.add('hidden');
            post('close');
        });

        box.appendChild(b);
    });
}

// Debug

document.querySelectorAll('#debugOut').forEach(() => {});

// From client

window.addEventListener('message', (e) => {
    const d = e.data || {};

    if (d.action === 'open') {
        $('root').classList.remove('hidden');
        renderPlayers(d.players);
        if (!$('classSelect').options.length) loadClasses();
        renderZombieTypes(d.zombieTypes);

        chips('times', (d.times || []).map((t) => ({ label: t.label.toUpperCase(), hour: t.hour })),
            async (t) => report(await post('server', { action: 'setTime', args: { hour: t.hour } }), 'time set'));

        chips('weather', (d.weather || []).map((w) => ({ label: w })),
            async (w) => report(await post('server', { action: 'setWeather', args: { weather: w.label } }), 'weather set'));

        // The freeze buttons follow bs_world's real state, so /freezetime and /weather in chat and this menu agree
        const world = { timeFrozen: false, weatherFrozen: false };
        const paintWorld = () => {
            $('freezeTime').firstChild.nodeValue = world.timeFrozen ? 'UNFREEZE THE CLOCK' : 'FREEZE THE CLOCK';
            $('freezeWeather').firstChild.nodeValue = world.weatherFrozen ? 'UNFREEZE WEATHER' : 'FREEZE WEATHER';
        };
        const readWorld = async () => {
            const r = await post('server', { action: 'worldState', args: {} });
            if (r && r.ok && r.world) {
                world.timeFrozen = !!r.world.timeFrozen;
                world.weatherFrozen = !!r.world.weatherFrozen;
                setToggle('blackout2', r.world.blackout);
                paintWorld();
            }
        };
        readWorld();

        // Events: one row per kind in the bs_events registry.
        const loadEvents = async () => {
            const r = await post('server', { action: 'eventList', args: {} });
            const box = $('evList');
            if (!r || !r.ok) { box.textContent = (r && r.error) || ''; return; }
            box.innerHTML = r.kinds.map((k) => `
                <div class="split">
                    <div class="row" style="cursor:default"><span>${esc(t('admin.ev.k_' + k.kind, { fallback: k.kind.toUpperCase() }))}</span>
                        <span class="row__hint">${k.enabled ? (k.running ? '#' + k.running : '') : esc(t('admin.ev.off'))}</span></div>
                    <button class="row" data-ev="${esc(k.kind)}" data-here="0"><span>${esc(t('admin.ev.start'))}</span></button>
                    ${k.atOk ? `<button class="row" data-ev="${esc(k.kind)}" data-here="1"><span>${esc(t('admin.ev.here'))}</span></button>` : ''}
                </div>`).join('');
            box.querySelectorAll('[data-ev]').forEach((b) => {
                b.onclick = async () => {
                    report(await post('server', { action: 'eventStart', args: { kind: b.dataset.ev, here: b.dataset.here === '1' } }),
                        t('admin.ev.started'));
                    loadEvents();
                };
            });
        };
        loadEvents();
        if (window.BSI18n && BSI18n.onChange) BSI18n.onChange(loadEvents);
        $('evStop').onclick = async () => {
            const r = await post('server', { action: 'eventStop', args: {} });
            report(r, t('admin.ev.stopped'));
            loadEvents();
        };
        $('freezeTime').onclick = async () => {
            report(await post('server', { action: 'freezeTime', args: { on: !world.timeFrozen } }));
            readWorld();
        };
        $('freezeWeather').onclick = async () => {
            report(await post('server', { action: 'freezeWeather', args: { on: !world.weatherFrozen } }));
            readWorld();
        };
        $('wBlackout').onclick = async () => {
            report(await post('server', { action: 'blackout', args: {} }));
            readWorld();
        };
        $('weather').onclick = () => setTimeout(readWorld, 400);

        renderVehicleGroups(d.vehicles);

        renderWeapons(d.weapons);

        chips('condition', [
            { label: 'STARVE', hunger: 3, thirst: 3 },
            { label: 'FEED', hunger: 100, thirst: 100 },
            { label: '+25 INFECTION', infect: 25 },
            { label: 'CURE', infect: -100 },
            { label: 'MED: HEAL ALL', med: 'clear' },
            { label: 'MED: BLEED', med: 'bleed' },
            { label: 'MED: HEAVY BLEED', med: 'bleed_heavy' },
            { label: 'MED: BREAK LEG', med: 'fracture_leg' },
            { label: 'MED: BREAK ARM', med: 'fracture_arm' },
            { label: 'MED: BULLET', med: 'bullet' },
            { label: 'MED: INFECT', med: 'infect' },
            { label: 'MED: FOOD POISON', med: 'food' },
            { label: 'MED: COLD', med: 'cold' },
            { label: 'MED: LOW BLOOD', med: 'lowblood' },
            { label: 'MED: PAIN', med: 'pain' },
        ], async (c) => {
            if (c.med !== undefined) {
                report(await post('server',
                    { action: 'medical', args: withTarget({ op: c.med }) }), 'done');
            } else if (c.infect !== undefined) {
                report(await post('server',
                    { action: 'infect', args: withTarget({ amount: c.infect }) }), 'done');
            } else {
                report(await post('server',
                    { action: 'setneeds', args: withTarget({ hunger: c.hunger, thirst: c.thirst }) }), 'done');
            }
        });

        if (d.state) {
            setToggle('godmode', d.state.godmode);
            setToggle('zombiegodmode', d.state.zombieGodmode);
            setToggle('noclip', d.state.noclip);
            setToggle('invisible', d.state.invisible);
            setToggle('coords', d.state.coords);
            setToggle('propid', d.state.propid);
            setToggle('guardalerts', d.state.guardAlerts);
        }

        // Catalogues are fetched once the menu is actually up.
        post('server', { action: 'items', args: {} }).then((r) => {
            if (r && r.ok) { ITEMS = r.items || []; renderItemTabs(); renderItems(); renderClothing(); }
        });
        post('server', { action: 'perks', args: {} }).then((r) => {
            if (r && r.ok) { PERKS = r.perks || []; }
        });
        loadSkills();
    }

    if (d.action === 'close') $('root').classList.add('hidden');

    if (d.action === 'rights') {
        $('tier').textContent = d.superadmin ? 'SUPERADMIN' : (d.admin ? 'ADMIN' : 'NONE');
    }
});

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') {
        // the Guard logs viewer takes ESC first (drawer, then overlay), the menu closes on the next press
        if (typeof glOpen === 'function' && glOpen()) { glClose(); return; }
        post('close');
    }
});

// Sanctions
// Proxied through the 'sanctions' NUI callback to bs_faction_bases' server callbacks (sanctions:* / jail:*)

const sx = (cb, args) => post('sanctions', { cb, args: args || {} });
let sxTemplates = [];

async function sxLoadTemplates() {
    const res = await sx('sanctions:templates');
    if (!res || !res.ok) return;
    sxTemplates = res.templates || [];
    const sel = $('sxTemplate');
    sel.innerHTML = '';
    (res.tiers || []).forEach((tier) => {
        const g = document.createElement('optgroup');
        g.label = tier.label.toUpperCase();
        sxTemplates.filter((t) => t.tier === tier.id).forEach((t) => {
            const o = document.createElement('option');
            o.value = t.id;
            o.textContent = `${t.label} (${t.min}-${t.max} min)`;
            g.appendChild(o);
        });
        sel.appendChild(g);
    });
    sxTemplateChanged();
}
function sxTemplateChanged() {
    const t = sxTemplates.find((v) => v.id === $('sxTemplate').value);
    if (t) $('sxMinutes').value = t.default;
}
$('sxTemplate').addEventListener('change', sxTemplateChanged);

function sxEffects(e) {
    return Object.keys(e || {}).map((k) => (e[k] === true ? k : `${k} ${e[k]}`)).join(', ');
}
function sxTime(s) { s = Math.max(0, s | 0); return s >= 3600 ? `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m` : `${Math.floor(s / 60)}m${s % 60}s`; }

async function sxRefresh() {
    const res = await sx('sanctions:list', { factionId: $('sxFaction').value.trim() || undefined, activeOnly: true });
    const box = $('sxList');
    box.innerHTML = '';
    if (!res || !res.ok) return report(res);
    if (!res.sanctions.length) { box.innerHTML = '<p class="hint">none active</p>'; return; }
    res.sanctions.forEach((s) => {
        const b = document.createElement('button');
        b.className = 'row row--danger';
        b.innerHTML = `#${s.id} ${esc(s.name || (s.charId ? 'char ' + s.charId : 'FACTION ' + s.factionId))} - ${esc(s.label)}`
            + `<span class="row__hint">${esc(sxEffects(s.effects))} · ${sxTime(s.remaining)} left · LIFT</span>`;
        b.addEventListener('click', async () => { report(await sx('sanctions:lift', { id: s.id }), 'lifted'); sxRefresh(); });
        box.appendChild(b);
    });
}

async function sxIssue(factionWide) {
    const args = {
        template: $('sxTemplate').value,
        minutes: Number($('sxMinutes').value) || undefined,
        reason: $('sxReason').value,
        jailScope: $('sxJailScope').value.trim() || 'global',
    };
    if (factionWide) {
        args.targetFactionId = $('sxFaction').value.trim();
        if (!args.targetFactionId) return msg('enter a faction id', true);
    } else {
        const cid = Number($('sxChar').value);
        if (cid > 0) args.targetCharId = cid;
        else args.targetSrc = target();
        if (!args.targetCharId && !args.targetSrc) return msg('pick a target or char id', true);
    }
    report(await sx('sanctions:issue', args), 'sanction issued');
    sxRefresh();
}
$('sxIssue').addEventListener('click', () => sxIssue(false));
$('sxIssueFaction').addEventListener('click', () => sxIssue(true));
$('sxRefresh').addEventListener('click', sxRefresh);

function sxRenderJail(res) {
    const box = $('sxJail');
    box.innerHTML = '';
    if (!res || !res.ok) return report(res);
    const j = res.jail || (res.jail === undefined ? null : res.jail);
    if (!j) { box.innerHTML = '<p class="hint">no jail here yet - set an origin</p>'; return; }
    const head = document.createElement('p');
    head.className = 'hint';
    head.textContent = `ORIGIN ${j.origin.x.toFixed(1)}, ${j.origin.y.toFixed(1)} · RADIUS ${Math.round(j.radius)}M · RELEASE ${j.exit ? 'SET' : 'ORIGIN'} · ${j.cells.length} CELLS`;
    box.appendChild(head);
    j.cells.forEach((c) => {
        const b = document.createElement('button');
        b.className = 'row';
        b.innerHTML = `CELL ${c.n}<span class="row__hint">${c.occupied ? c.occupied + ' inmate(s)' : 'free'} · REMOVE</span>`;
        b.addEventListener('click', async () => sxRenderJail(await sx('jail:removeCell', { n: c.n, scope: $('sxScope').value.trim() })));
        box.appendChild(b);
    });
    (res.inmates || []).forEach((i) => {
        const b = document.createElement('button');
        b.className = 'row row--danger';
        b.innerHTML = `${esc(i.name)} · CELL ${i.cell}<span class="row__hint">${sxTime(i.remaining)} left${i.online ? '' : ' (offline)'} · RELEASE</span>`;
        b.addEventListener('click', async () => { report(await sx('jail:release', { charId: i.charId }), 'released'); sxJailLoad(); });
        box.appendChild(b);
    });
}
async function sxJailLoad() { sxRenderJail(await sx('jail:get', { scope: $('sxScope').value.trim() })); }
async function sxJailThen(cb, extra) {
    const res = await sx(cb, Object.assign({ scope: $('sxScope').value.trim() }, extra || {}));
    report(res, 'saved');
    if (res && res.ok) sxJailLoad();
}
$('sxJailLoad').addEventListener('click', sxJailLoad);
$('sxOrigin').addEventListener('click', () => sxJailThen('jail:setOrigin', { radius: Number($('sxRadius').value) || 25 }));
$('sxExit').addEventListener('click', () => sxJailThen('jail:setExit'));
$('sxCell').addEventListener('click', () => sxJailThen('jail:addCell'));
document.querySelector('.mtab[data-tab="sanctions"]').addEventListener('click', () => {
    if (!sxTemplates.length) sxLoadTemplates();
    sxRefresh();
    sxJailLoad();
});

// Guard logs viewer
// Full-screen overlay over bs_guard_log

const gd = (cb, args) => post('guard', { cb, args: args || {} });
const GL = { page: 1, sort: 'time', dir: 'desc', rows: [], total: 0, sel: null, busy: false, timer: null };
const glOpen = () => !$('gl').classList.contains('hidden');
const glDrawerOpen = () => !$('glDrawer').classList.contains('hidden');

function gdTime(t) {
    const d = new Date((Number(t) || 0) * 1000);
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
function gdCopy(text) {
    const ta = document.createElement('textarea');
    ta.value = text; document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); msg('copied'); } catch (e) { msg('copy failed', true); }
    ta.remove();
}
const glCoords = (r) => [r.x, r.y, r.z].map((v) => Number(v || 0).toFixed(1)).join(', ');
const glDay = (id, end) => {
    const v = $(id).value;
    if (!v) return undefined;
    const d = new Date(v + (end ? 'T23:59:59' : 'T00:00:00'));
    return isNaN(d) ? undefined : Math.floor(d.getTime() / 1000);
};

async function glLoad() {
    if (GL.busy) return;
    GL.busy = true;
    const res = await gd('guard:page', {
        page: GL.page, per: Number($('glPer').value) || 25, sort: GL.sort, dir: GL.dir,
        kind: $('glKind').value || undefined, q: $('glQ').value.trim() || undefined,
        minConf: Number($('glMin').value) || undefined, from: glDay('glFrom', false), to: glDay('glTo', true),
    });
    GL.busy = false;
    if (!res || !res.ok) { report(res); return; }
    GL.rows = res.rows || []; GL.total = Number(res.total) || 0;
    const per = Number(res.per) || 25;
    const pages = Math.max(1, Math.ceil(GL.total / per));
    if (GL.page > pages) { GL.page = pages; return glLoad(); }
    glRender(pages);
}

function glRender(pages) {
    const body = $('glBody');
    body.innerHTML = '';
    GL.rows.forEach((r, i) => {
        const conf = Number(r.confidence) || 0;
        const tr = document.createElement('tr');
        if (conf >= 80) tr.className = 'hi';
        if (GL.sel && GL.sel.id === r.id) tr.classList.add('is-sel');
        tr.innerHTML = `<td>${gdTime(r.time)}</td><td>${esc(r.name)} [${esc(r.src)}]${r.online ? '<span class="gl__on">&#9679;</span>' : ''}</td>`
            + `<td>${esc(r.charId == null ? '-' : r.charId)}</td><td>${esc(r.kind)}</td>`
            + `<td><span class="gl__conf ${conf >= 80 ? 'hi' : conf >= 50 ? 'mid' : ''}">${conf}%</span></td>`
            + `<td class="det" title="${esc(r.details)}">${esc(r.details)}</td><td>${esc(glCoords(r))}</td>`;
        tr.addEventListener('click', () => glSelect(r));
        body.appendChild(tr);
    });
    $('glEmpty').classList.toggle('hidden', GL.rows.length > 0);
    $('glTotal').textContent = tt('admin.gl.total', '{n} entries').replace('{n}', GL.total);
    $('glPage').textContent = tt('admin.gl.page', 'Page {p} / {n}').replace('{p}', GL.page).replace('{n}', pages);
    $('glPrev').disabled = GL.page <= 1;
    $('glNext').disabled = GL.page >= pages;
    document.querySelectorAll('.gl__table th[data-sort]').forEach((th) => {
        const on = th.dataset.sort === GL.sort;
        th.classList.toggle('is-sorted', on);
        th.classList.toggle('asc', on && GL.dir === 'asc');
    });
}

function glSelect(r) {
    GL.sel = r;
    const rows = [
        ['admin.gl.c_time', 'Time', gdTime(r.time)],
        ['admin.gl.c_player', 'Player', `${r.name} [${r.src}] ${r.online ? tt('admin.gl.online', 'online') : tt('admin.gl.offline', 'offline')}`],
        ['admin.gl.license', 'License', r.license || '-'],
        ['admin.gl.c_char', 'Char', r.charId == null ? '-' : r.charId],
        ['admin.gl.c_kind', 'Kind', r.kind],
        ['admin.gl.c_conf', 'Confidence', `${r.confidence}%`],
        ['admin.gl.c_details', 'Details', r.details || '-'],
        ['admin.gl.c_coords', 'Coords', glCoords(r)],
    ];
    $('glDBody').innerHTML = rows.map((x) => `<dt>${esc(tt(x[0], x[1]))}</dt><dd>${esc(x[2])}</dd>`).join('');
    $('glSpec').disabled = !r.online;
    $('glDrawer').classList.remove('hidden');
    document.querySelectorAll('#glBody tr').forEach((tr, i) => tr.classList.toggle('is-sel', GL.rows[i] === r));
}

function glTarget(r) { return { src: r.src, license: r.license, x: r.x, y: r.y, z: r.z }; }
function glClose() {
    if (glDrawerOpen()) { $('glDrawer').classList.add('hidden'); GL.sel = null; glRender(Math.max(1, Math.ceil(GL.total / (Number($('glPer').value) || 25)))); return; }
    $('gl').classList.add('hidden');
}
function glReload(resetPage) { if (resetPage) GL.page = 1; glLoad(); }

$('gdOpen').addEventListener('click', () => { $('gl').classList.remove('hidden'); glReload(true); });
$('glClose').addEventListener('click', () => { $('glDrawer').classList.add('hidden'); $('gl').classList.add('hidden'); });
$('glDClose').addEventListener('click', glClose);
$('glPrev').addEventListener('click', () => { if (GL.page > 1) { GL.page--; glLoad(); } });
$('glNext').addEventListener('click', () => { GL.page++; glLoad(); });
['glKind', 'glFrom', 'glTo', 'glPer'].forEach((id) => $(id).addEventListener('change', () => glReload(true)));
['glQ', 'glMin'].forEach((id) => $(id).addEventListener('input', () => { clearTimeout(GL.timer); GL.timer = setTimeout(() => glReload(true), 300); }));
$('glReset').addEventListener('click', () => {
    $('glKind').value = ''; $('glQ').value = ''; $('glFrom').value = ''; $('glTo').value = ''; $('glMin').value = 0;
    GL.sort = 'time'; GL.dir = 'desc'; glReload(true);
});
document.querySelectorAll('.gl__table th[data-sort]').forEach((th) => th.addEventListener('click', () => {
    if (GL.sort === th.dataset.sort) GL.dir = GL.dir === 'desc' ? 'asc' : 'desc';
    else { GL.sort = th.dataset.sort; GL.dir = th.dataset.sort === 'player' || th.dataset.sort === 'kind' ? 'asc' : 'desc'; }
    glReload(true);
}));
$('glTp').addEventListener('click', async () => { if (GL.sel) report(await gd('guard:goto', glTarget(GL.sel)), GL.sel.online ? 'teleported' : 'teleported to log position'); });
$('glSpec').addEventListener('click', async () => {
    if (!GL.sel) return;
    const res = await gd('guard:spectate', glTarget(GL.sel));
    if (res && res.ok) { $('glDrawer').classList.add('hidden'); $('gl').classList.add('hidden'); }
    report(res, 'spectating');
});
$('glCopy').addEventListener('click', () => {
    const r = GL.sel;
    if (r) gdCopy(`[${gdTime(r.time)}] ${r.kind} ${r.confidence}% ${r.name} [${r.src}] ${r.license || ''} char ${r.charId == null ? '-' : r.charId} @ ${glCoords(r)} - ${r.details}`);
});
$('glStop').addEventListener('click', async () => report(await post('guardStop'), 'stopped'));
window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'close') { $('gl').classList.add('hidden'); $('glDrawer').classList.add('hidden'); }
    // a new detection while the viewer is open: refresh the current page
    if (d.action === 'guardDetection' && glOpen() && GL.page === 1) glLoad();
});

// Sectors tab removed: that pane belongs to bs_zombies



// Power tab: bs_world generator zones
async function loadPower() {
    const r = await post('server', { action: 'powerList', args: {} });
    if (!r || !r.ok) return report(r);
    setToggle('blackout3', r.blackout);
    const box = $('powerList');
    box.innerHTML = (r.zones || []).map((z) => `
        <div class="pzone${z.powered ? ' is-lit' : ''}">
            <div class="pzone__head"><b>${esc(z.label)}</b><span>${esc(z.postal || '')}</span>
                <span class="pzone__st">${z.powered ? tt('admin.p_powered', 'POWERED') : tt('admin.p_dark', 'DARK')}</span></div>
            <div class="pzone__meta">${tt('admin.p_fuel', 'FUEL')} ${z.fuel}% · ${tt('admin.p_health', 'CONDITION')} ${z.health}% · ${tt('admin.p_owner', 'OWNER')} ${esc(z.owner || tt('admin.p_none', 'none'))}</div>
            <div class="split">
                <button class="row row--inline" data-pz="powerToggle" data-zone="${esc(z.id)}">${z.on ? tt('admin.p_off', 'TURN OFF') : tt('admin.p_on', 'TURN ON')}</button>
                <button class="row row--inline" data-pz="powerRefuel" data-zone="${esc(z.id)}">${tt('admin.p_refuel', 'REFUEL')}</button>
                <button class="row row--inline" data-pz="powerRepair" data-zone="${esc(z.id)}">${tt('admin.p_repair', 'REPAIR')}</button>
                <button class="row row--inline" data-pz="powerTp" data-zone="${esc(z.id)}">${tt('admin.p_tp', 'TP')}</button>
            </div>
        </div>`).join('') || `<p class="hint">${tt('admin.p_empty', 'No generator zones configured.')}</p>`;
    box.querySelectorAll('[data-pz]').forEach((b) => b.addEventListener('click', async () => {
        const res = await post('server', { action: b.dataset.pz, args: { zone: b.dataset.zone } });
        if (res && res.ok) msg(res.note || 'done'); else report(res);
        if (b.dataset.pz === 'powerTp' && res && res.ok) { $('root').classList.add('hidden'); post('close'); return; }
        loadPower();
    }));
}
document.querySelector('.mtab[data-tab="power"]').addEventListener('click', loadPower);
document.querySelector('.mtab[data-tab="power"]').addEventListener('click', loadPumps);
$('pRefresh').addEventListener('click', loadPumps);
$('pRefresh').addEventListener('click', loadPower);
$('pRestore').addEventListener('click', async () => {
    const res = await post('server', { action: 'powerRestore', args: {} });
    if (res && res.ok) msg(res.note || 'done'); else report(res);
    loadPower();
});
$('pBlackout').addEventListener('click', async () => {
    const res = await post('server', { action: 'blackout', args: {} });
    if (res && res.ok) msg(res.note || 'done'); else report(res);
    loadPower();
});

// Gas station fuel: one row per station, type a litre value and SET.
async function loadPumps() {
    const r = await post('server', { action: 'pumpList', args: {} });
    const box = $('pumpList');
    if (!r || !r.ok) { box.innerHTML = ''; return; }
    box.innerHTML = (r.stations || []).map((s) => `
        <div class="pzone${s.grid || s.jumped ? ' is-lit' : ''}">
            <div class="pzone__head"><b>${esc(s.label)}</b><span>${esc(s.id)}</span>
                <span class="pzone__st">${s.grid ? tt('admin.p_grid_on', 'GRID') : s.jumped ? tt('admin.p_jumped', 'BATTERY') : tt('admin.p_dark', 'DARK')}</span></div>
            <div class="pzone__meta">${tt('admin.p_fuel', 'FUEL')} ${s.fuel} / ${s.cap} L</div>
            <div class="split">
                <input class="pz-in" type="number" min="0" max="${s.cap}" value="${s.fuel}" data-st="${esc(s.id)}">
                <button class="row row--inline" data-pset="${esc(s.id)}">${tt('admin.p_set', 'SET')}</button>
            </div>
        </div>`).join('') || `<p class="hint">${tt('admin.p_no_stations', 'No stations.')}</p>`;
    box.querySelectorAll('[data-pset]').forEach((b) => b.addEventListener('click', async () => {
        const input = box.querySelector(`input[data-st="${CSS.escape(b.dataset.pset)}"]`);
        const res = await post('server', { action: 'pumpSet', args: { station: b.dataset.pset, liters: Number(input && input.value) } });
        if (res && res.ok) msg(res.note || 'done'); else report(res);
        loadPumps();
    }));
}

// Drag / resize the panel (shared helper, remembered per id).
if (window.BSWindow) BSWindow.make(document.querySelector('.menu'), { id: 'bs_admin', handle: '.menu__head', minW: 480, minH: 320 });

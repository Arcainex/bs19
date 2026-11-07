// bs_multichar - character select and creator.
// The 3D ped lives in the game; this file decides what to show and posts it to Lua via post(), which restyles the preview ped.
// Every choice is only a request: the server re-validates identity, kit, outfit and faction against its own config.

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'bs_multichar';

const $  = (id) => document.getElementById(id);
const el = (tag, cls, html) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html !== undefined) n.innerHTML = html;
    return n;
};

async function post(endpoint, data = {}) {
    try {
        const res = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await res.json();
    } catch (err) {
        console.error('[multichar]', endpoint, err);
        return { ok: false, error: 'bridge failed' };
    }
}

// Translation helper: key, {vars}, English fallback text. Output is plain text, escape before innerHTML.
const tr = (key, vars, fb) => t(key, Object.assign({ fallback: fb === undefined ? key : fb }, vars || {}));
const lang = () => (window.BSI18n && BSI18n.lang && BSI18n.lang()) || 'en';
const up = (s) => String(s).toLocaleUpperCase(lang());
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const r2 = (v) => Math.round(v * 100) / 100;
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const rnd = (lo, hi) => lo + Math.random() * (hi - lo);

// state

const S = {
    characters: [],
    classes: [],
    appearance: [],      // slider schema from bs_core's Config.Appearance
    maxSlots: 3,
    selected: 0,         // index into characters
    draft: null,         // the character being created
    cfg: null,           // creator lists from the server (multichar:creatorData)
    steps: [],
    step: 'identity',
    counts: {},          // per sex: drawable counts reported by the preview ped
    tex: {},             // texture counts of the pieces currently worn
    catalog: {},         // valid and enabled addon clothing, per gender
    catalogLoading: false,
    wardrobeGroup: 'wear',
    hands: false,
    busy: false,
};

// select view

function playtime(seconds) {
    const h = Math.floor((seconds || 0) / 3600);
    if (h < 1) return tr('ui.new_tag', null, 'NEW');
    if (h < 24) return tr('ui.hours_survived', { n: h }, `${h}H SURVIVED`);
    const d = Math.floor(h / 24);
    return tr('ui.days_survived', { n: d }, `${d}D SURVIVED`);
}

function slotCountText() {
    return tr('ui.slots_used', { n: S.characters.length, max: S.maxSlots },
        `${S.characters.length} / ${S.maxSlots} SLOTS USED`);
}

function renderSlots() {
    const list = $('slots');
    list.innerHTML = '';

    $('slotCount').textContent = slotCountText();

    S.characters.forEach((c, i) => {
        const node = el('div', 'slot' + (i === S.selected ? ' is-active' : ''));
        node.innerHTML = `
            <div class="slot__name">${escape(c.first_name)} ${escape(c.last_name)}</div>
            <div class="slot__meta">
                <span><em>${escape(c.classLabel || c.class)}</em></span>
                <span>${escape(playtime(c.playtime))}</span>
            </div>`;
        node.addEventListener('click', () => selectSlot(i));
        list.appendChild(node);
    });

    // Empty slots are shown so a fresh account does not look broken.
    for (let i = S.characters.length; i < S.maxSlots; i++) {
        const node = el('div', 'slot slot--empty', escape(tr('ui.empty_slot', null, 'EMPTY SLOT')));
        node.addEventListener('click', openCreator);
        list.appendChild(node);
    }

    const has = S.characters.length > 0;
    $('btnPlay').disabled = !has;
    $('btnDelete').disabled = !has;
    $('btnNew').disabled = S.characters.length >= S.maxSlots;
}

function selectSlot(i) {
    S.selected = i;
    renderSlots();
    post('preview', { index: i + 1 });
}

function escape(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// creator: draft

const CLOTH_CATS = ['top', 'undershirt', 'arms', 'legs', 'shoes', 'mask', 'hat', 'glasses', 'ears', 'accessory', 'watch', 'bracelet'];
// Small, consistent stroke icons. No external library or font dependency.
const AZ_ICONS = {
    shirt: '<path d="M16 4h-8L5 7 2 9l2 5 3-1v8h10v-8l3 1 2-5-3-2-3-3z"/><path d="M8 4c0 2 2 3 4 3s4-1 4-3"/>',
    layers:'<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 9h16M4 14h16"/>',
    hand:'<path d="M8 13V6a1.5 1.5 0 0 1 3 0v5-7a1.5 1.5 0 0 1 3 0v7-5a1.5 1.5 0 0 1 3 0v6-3a1.5 1.5 0 0 1 3 0v5c0 5-3 8-8 8h-1c-3 0-4-2-6-5l-2-2a1.5 1.5 0 0 1 2-2l3 2"/>',
    pants:'<path d="M6 3h12l1 18h-5l-2-11-2 11H5L6 3z"/><path d="M6 7h12"/>',
    shoe:'<path d="M4 12c2 0 3 2 6 2l3-3 4 3 4 2v4H3v-4l1-4z"/><path d="M5 17h15"/>',
    mask:'<path d="M4 9c5-3 11-3 16 0v5c0 5-3 7-8 9-5-2-8-4-8-9V9z"/><path d="M7 13h3M14 13h3"/>',
    hat:'<path d="M5 14l2-9 5-2 5 2 2 9M2 15c6 4 14 4 20 0v3c-6 4-14 4-20 0v-3z"/>',
    glasses:'<circle cx="6.7" cy="13" r="3.5"/><circle cx="17.3" cy="13" r="3.5"/><path d="M10.2 12c1-1 2.6-1 3.6 0M3 10L1 9M21 10l2-1"/>',
    ear:'<path d="M8 17c-4-4-2-11 4-12 5-1 9 3 8 8-.5 3-3 4-5 5-1 1-1 4-4 4-2 0-3-2-3-5z"/><path d="M11 12c0-3 5-4 6-1 1 2-2 3-3 5"/>',
    gem:'<path d="M6 4h12l4 6-10 11L2 10l4-6z"/><path d="M2 10h20M8 4l4 6 4-6M12 10v11"/>',
    watch:'<rect x="7" y="7" width="10" height="10" rx="5"/><path d="M9 7 8 2h8l-1 5M9 17l-1 5h8l-1-5M12 10v3l2 1"/>',
    bracelet:'<circle cx="12" cy="12" r="8"/><path d="M8 4 9 8M16 4l-1 4M4 12h4M16 12h4M8 20l1-4m7 4-1-4"/>',
    head:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-2c0-4 3-6 8-6s8 2 8 6v2"/>',
};
function azIcon(name) {
    return `<svg viewBox="0 0 24 24" width="21" height="21" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${AZ_ICONS[name] || AZ_ICONS.gem}</svg>`;
}
const WGROUPS = [
    { id:'wear', icon:'shirt', name:'Kleidung', cats:['top','undershirt','arms','legs','shoes'] },
    { id:'head', icon:'head', name:'Kopf', cats:['mask','hat','glasses','ears'] },
    { id:'details', icon:'gem', name:'Accessoires', cats:['accessory','watch','bracelet'] },
];
const WCAT = {
    mask:['mask','Maske'], top:['shirt','Oberteil'], undershirt:['layers','Unterhemd'], arms:['hand','Arme'],
    legs:['pants','Hose'], shoes:['shoe','Schuhe'], accessory:['gem','Kette / Schmuck'],
    hat:['hat','Kopfbedeckung'], glasses:['glasses','Brille'], ears:['ear','Ohrschmuck'],
    watch:['watch','Uhr'], bracelet:['bracelet','Armband'],
};
const STEP_LABEL = {
    identity: ['ui.identity', 'IDENTITY'], origin: ['ui.origin', 'ORIGIN'], faction: ['ui.faction', 'FACTION'],
    look: ['ui.look', 'LOOK'], clothing: ['ui.clothing', 'CLOTHING'], kit: ['ui.kit', 'STARTING KIT'], review: ['ui.review', 'REVIEW'],
};

/* Schema defaults overlaid with the starting look of that sex (parents, hair and brows that read as male / female). */
function seedAppearance(gender) {
    const ap = {};
    for (const f of S.appearance) ap[f.key] = f.default;
    const d = (S.cfg && S.cfg.defaults && S.cfg.defaults[gender]) || {};
    for (const k of Object.keys(d)) ap[k] = d[k];
    return ap;
}

function clothDef(cat) { return S.cfg.clothes[cat]; }
function clothKey(cat) { const d = clothDef(cat); return d.c !== undefined ? 'c' + d.c : 'p' + d.p; }
function catList(cat, gender = S.draft?.gender) { return ((S.catalog[gender] || {})[cat] || []); }
function currentEntry(cat) { return catList(cat).find(e => e.d === S.draft.clothes[cat]?.d); }

function defaultClothes(gender) {
    const out = {};
    const preset = S.cfg?.defaultOutfits?.[gender] || {};
    for (const cat of CLOTH_CATS) {
        const d = clothDef(cat);
        const list = catList(cat, gender);
        const saved = preset[cat];
        // Stored IDs are only used if still present and enabled in the live catalog.
        let entry = list.find(x => x.d === saved?.d && x.k === (saved?.k || ''));
        if (!entry) entry = list.find(x => x.d === d.default) || (d.p !== undefined ? list.find(x => x.d === -1) : null) || list[0];
        const tex = entry?.ts?.includes(saved?.t) ? saved.t : entry?.ts?.[0] ?? 0;
        out[cat] = { d: entry?.d ?? d.default ?? (d.p !== undefined ? -1 : 0), t: tex };
    }
    return out;
}

function normalizeClothes() {
    if (!S.draft || !S.catalog[S.draft.gender]) return false;
    let changed = false;
    for (const cat of CLOTH_CATS) {
        const all = catList(cat);
        const current = S.draft.clothes[cat];
        const entry = all.find(x => x.d === current?.d);
        const chosen = entry || (clothDef(cat).p !== undefined ? all.find(x => x.d === -1) : null) || all[0];
        if (!chosen) continue;
        const texture = chosen.ts.includes(current?.t) ? current.t : chosen.ts[0];
        if (chosen.d !== current?.d || texture !== current?.t) changed = true;
        S.draft.clothes[cat] = { d: chosen.d, t: texture };
    }
    return changed;
}

function draftOutfit() {
    const comps = {}, props = {};
    if (!S.draft) return { components: comps, props };
    for (const cat of CLOTH_CATS) {
        const def = clothDef(cat), c = S.draft.clothes[cat];
        if (!c) continue;
        if (def.c !== undefined) comps[def.c] = { drawable: c.d, texture: c.t, palette: 2 };
        else props[def.p] = { drawable: c.d, texture: c.d < 0 ? -1 : c.t };
    }
    // No backpack in creator. Keep the component empty even when switching genders.
    comps[5] = { drawable: 0, texture: 0, palette: 2 };
    return { components: comps, props };
}

function outfitChoices() {
    const out = {};
    for (const cat of CLOTH_CATS) {
        const c = S.draft.clothes[cat], entry = currentEntry(cat);
        out[cat] = { d: c.d, t: c.t, k: entry?.k || '' };
    }
    return out;
}

async function loadWardrobe() {
    if (!S.draft || !S.cfg || S.catalogLoading || S.catalog[S.draft.gender]) return;
    const gender = S.draft.gender;
    S.catalogLoading = true;
    renderWardrobe();
    let r = null;
    for (let attempt = 0; attempt < 5; attempt++) {
        r = await post('wardrobeCatalog', { gender, rules: S.cfg.clothingRules || {} });
        if (r?.ok) break;
        await new Promise(resolve => setTimeout(resolve, 220));
    }
    S.catalogLoading = false;
    if (!S.draft || S.draft.gender !== gender) return;
    if (r?.ok) {
        S.catalog[gender] = r.catalog;
        S.draft.clothes = defaultClothes(gender);
        if (normalizeClothes()) pushDraft(false);
        else pushDraft(false);
    } else {
        S.catalogError = 'Kleidung konnte nicht eingelesen werden. Bitte erneut versuchen.';
    }
    renderWardrobe();
}

function blankDraft() {
    const I = S.cfg.identity;
    return {
        firstName: '', lastName: '', nickname: '',
        dobDay: 1, dobMonth: 1, dobYear: new Date().getFullYear() - 30,
        gender: 'male',
        height: I.heightDefault, bloodType: I.bloodTypes[0], occupation: I.occupations[0], backstory: '',
        class: S.classes[0]?.id || 'survivor',
        faction: 'civilians', // canonical bs_factions id; server enforces this as well
        kit: { melee: null, goodies: [] },
        appearance: seedAppearance('male'),
        clothes: defaultClothes('male'),
    };
}

async function openCreator() {
    if (S.busy || S.characters.length >= S.maxSlots) return;
    S.busy = true;
    // Open framed. Zoom and rotation persist while browsing survivors, but should not carry into a new character.
    post('resetView', {});

    const cfg = await post('creatorData', {});
    S.busy = false;
    if (!cfg || !cfg.ok) { alertLine(tr('ui.could_not_create', null, 'Could not create the character.')); return; }

    S.cfg = cfg;
    S.counts = {}; S.tex = {}; S.hands = false; S.catalog = {}; S.catalogLoading = false; S.catalogError = ''; S.wardrobeGroup = 'wear';
    S.draft = blankDraft();
    ensureKit();
    S.steps = buildSteps();
    S.edit = false;

    $('select').classList.add('hidden');
    $('creator').classList.remove('hidden');
    $('createError').textContent = '';
    $('btnHands').classList.remove('hidden');
    syncHands();

    buildLangPicker();
    buildDobPickers();
    buildIdentityLists();
    syncIdentityInputs();
    setStep('identity');
    pushDraft(true);
}

function closeCreator() {
    $('creator').classList.add('hidden');
    $('select').classList.remove('hidden');
    $('btnHands').classList.add('hidden');
    S.draft = null;
    S.hands = false;
    // The list opens framed; otherwise zoom and rotation from the creator carry over after cancelling.
    post('resetView', {});
    post('preview', { index: S.selected + 1 });
}

function buildSteps() {
    const s = ['identity'];
    s.push('look');
    if (S.cfg.clothingStep) s.push('clothing');
    if (S.cfg.kit && S.cfg.kit.enabled !== false) s.push('kit');
    s.push('review');
    return s;
}

// date of birth

function monthNames() {
    const out = [];
    for (let m = 0; m < 12; m++) {
        try { out.push(new Date(2000, m, 1).toLocaleString(lang(), { month: 'long' })); }
        catch (e) { out.push(String(m + 1)); }
    }
    return out;
}

// Days in a month, leap years included.
function daysInMonth(month, year) {
    return new Date(year, month, 0).getDate();
}

// The creator can be opened many times: option lists are rebuilt each time but listeners are bound once, otherwise handlers stack up.
let dobBound = false;

function buildDobPickers() {
    const thisYear = new Date().getFullYear();
    const I = S.cfg ? S.cfg.identity : {};

    const monthSel = $('dobMonth');
    monthSel.innerHTML = monthNames()
        .map((m, i) => `<option value="${i + 1}">${escape(up(m))}</option>`).join('');

    const yearSel = $('dobYear');
    // Config allows 18-90; offer exactly that range, newest first.
    const years = [];
    for (let y = thisYear - 18; y >= thisYear - 90; y--) years.push(y);
    yearSel.innerHTML = years.map((y) => `<option value="${y}">${y}</option>`).join('');

    rebuildDays();
    monthSel.value = String(S.draft.dobMonth);
    yearSel.value = String(S.draft.dobYear);

    if (dobBound) return;
    dobBound = true;

    [monthSel, yearSel].forEach((sel) => sel.addEventListener('change', () => {
        if (!S.draft) return;
        S.draft.dobMonth = Number(monthSel.value);
        S.draft.dobYear = Number(yearSel.value);
        rebuildDays();
        updateAgeHint();
    }));

    $('dobDay').addEventListener('change', () => {
        if (!S.draft) return;
        S.draft.dobDay = Number($('dobDay').value);
        updateAgeHint();
    });
}

function rebuildDays() {
    const daySel = $('dobDay');
    const max = daysInMonth(S.draft.dobMonth, S.draft.dobYear);
    const keep = Math.min(S.draft.dobDay, max);

    let html = '';
    for (let d = 1; d <= max; d++) html += `<option value="${d}">${String(d).padStart(2, '0')}</option>`;
    daySel.innerHTML = html;

    S.draft.dobDay = keep;
    daySel.value = String(keep);
}

function draftAge() {
    const today = new Date();
    let age = today.getFullYear() - S.draft.dobYear;
    const beforeBirthday =
        today.getMonth() + 1 < S.draft.dobMonth ||
        (today.getMonth() + 1 === S.draft.dobMonth && today.getDate() < S.draft.dobDay);
    if (beforeBirthday) age--;
    return age;
}

function updateAgeHint() {
    const age = draftAge();
    const hint = $('ageHint');
    const bad = age < 18 || age > 90;
    hint.textContent = bad
        ? tr('ui.age_bad', { n: age, min: 18, max: 90 }, `AGE ${age} - MUST BE 18 TO 90`)
        : tr('ui.age', { n: age }, `AGE ${age}`);
    hint.classList.toggle('bad', bad);
}

/** The wire format bs_core validates is still YYYY-MM-DD. */
function draftDobString() {
    const p = (n) => String(n).padStart(2, '0');
    return `${S.draft.dobYear}-${p(S.draft.dobMonth)}-${p(S.draft.dobDay)}`;
}

// creator: identity

function feetInches(cm) {
    const inches = Math.round(cm / 2.54);
    return `${Math.floor(inches / 12)}'${inches % 12}"`;
}

function showHeight() {
    $('heightVal').textContent = `${S.draft.height} cm · ${feetInches(S.draft.height)}`;
}

function buildIdentityLists() {
    const I = S.cfg.identity;

    const h = $('height');
    h.min = I.heightMin; h.max = I.heightMax; h.step = 1; h.value = S.draft.height;

    const box = $('bloodChoice');
    box.innerHTML = '';
    I.bloodTypes.forEach((b) => {
        const btn = el('button', 'chip' + (b === S.draft.bloodType ? ' is-active' : ''), escape(b));
        btn.type = 'button';
        btn.addEventListener('click', () => {
            S.draft.bloodType = b;
            box.querySelectorAll('.chip').forEach((c) => c.classList.toggle('is-active', c === btn));
        });
        box.appendChild(btn);
    });

    $('occupation').innerHTML = I.occupations
        .map((o) => `<option value="${escape(o)}">${escape(tr('occ.' + o, null, o))}</option>`).join('');
    $('occupation').value = S.draft.occupation;

    $('backstory').maxLength = I.backstoryMax;
    $('nickname').maxLength = I.nicknameMax;
}

function syncIdentityInputs() {
    $('firstName').value = S.draft.firstName;
    $('lastName').value  = S.draft.lastName;
    $('nickname').value  = S.draft.nickname;
    $('backstory').value = S.draft.backstory;
    $('height').value    = S.draft.height;
    $('occupation').value = S.draft.occupation;
    $('dobDay').value    = String(S.draft.dobDay);
    $('dobMonth').value  = String(S.draft.dobMonth);
    $('dobYear').value   = String(S.draft.dobYear);
    updateAgeHint();
    showHeight();
    showStoryCount();
    document.querySelectorAll('#genderChoice .choice__btn').forEach((b) =>
        b.classList.toggle('is-active', b.dataset.gender === S.draft.gender));
}

function showStoryCount() {
    const max = S.cfg ? S.cfg.identity.backstoryMax : 200;
    $('storyCount').textContent = `${[...$('backstory').value].length} / ${max}`;
}

// creator: origin

const STATS = [
    { k: 'maxHealth',       l: 'ui.stat_hp',      fb: 'HEALTH',       fmt: (v) => `${v}` },
    { k: 'armorCap',        l: 'ui.stat_armor',   fb: 'ARMOUR CAP',   fmt: (v) => `${v}` },
    { k: 'carryWeight',     l: 'ui.stat_carry',   fb: 'CARRY',        fmt: (v) => `${v} KG` },
    { k: 'staminaMult',     l: 'ui.stat_stamina', fb: 'STAMINA',      fmt: (v) => `×${Number(v).toFixed(2)}` },
    { k: 'meleeDamageMult', l: 'ui.stat_melee',   fb: 'MELEE DAMAGE', fmt: (v) => `×${Number(v).toFixed(2)}` },
    { k: 'hungerRate',      l: 'ui.stat_hunger',  fb: 'HUNGER RATE',  fmt: (v) => `×${Number(v).toFixed(2)}`, low: true },
    { k: 'thirstRate',      l: 'ui.stat_thirst',  fb: 'THIRST RATE',  fmt: (v) => `×${Number(v).toFixed(2)}`, low: true },
    { k: 'tempFixBonus',    l: 'ui.stat_fix',     fb: 'TEMP FIX BONUS', fmt: (v) => `+${Math.round(v * 100)}%`, optional: true },
];

function pretty(id) { return String(id).replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()); }
function itemName(item) { return tr('item.' + item, null, pretty(item)); }
function className(c) { return tr('class.' + c.id + '.n', null, c.label); }
function classDesc(c) { return tr('class.' + c.id + '.d', null, c.description || ''); }

function statMax(key) {
    let m = 0;
    for (const c of S.classes) m = Math.max(m, Number((c.stats || {})[key]) || 0);
    return m || 1;
}

function renderClasses() {
    const box = $('classes');
    box.innerHTML = '';
    S.classes.forEach((c) => {
        const stats = c.stats || {};
        const on = c.id === S.draft.class;
        const node = el('div', 'card' + (on ? ' is-active' : ''));
        let html = `<div class="card__title">${escape(className(c))}</div>
            <div class="card__blurb">${escape(classDesc(c))}</div>`;

        if (on) {
            for (const s of STATS) {
                const v = stats[s.k];
                if (v === undefined || v === null) { if (s.optional) continue; }
                const val = Number(v) || 0;
                const pct = clamp((val / statMax(s.k)) * 100, 3, 100);
                html += `<div class="card__row"><span>${escape(tr(s.l, null, s.fb))}</span>
                    <div class="card__bar${s.low ? ' is-low' : ''}"><i style="width:${pct}%"></i></div>
                    <span class="card__val">${escape(s.fmt(val))}</span></div>`;
            }
            const skills = Object.entries(c.skills || {})
                .map(([k, v]) => `${escape(tr('skill.' + k, null, pretty(k)))} <b>${v}</b>`).join(' · ');
            const items = (c.items || [])
                .map((i) => `${escape(itemName(i.item))} <b>×${i.amount || 1}</b>`).join(' · ');
            if (skills) html += `<div class="card__sub">${escape(tr('ui.skills', null, 'STARTING SKILLS'))}: ${skills}</div>`;
            if (items) html += `<div class="card__sub">${escape(tr('ui.starts_with', null, 'STARTS WITH'))}: ${items}</div>`;
            html += `<div class="card__note">${escape(tr('ui.stat_note', null, ''))} (${escape(tr('ui.lower_better', null, 'lower is better'))}: ${escape(tr('ui.stat_hunger', null, 'HUNGER RATE'))}, ${escape(tr('ui.stat_thirst', null, 'THIRST RATE'))})</div>`;
        } else {
            html += `<div class="card__stats">
                <span>${escape(tr('ui.stat_hp', null, 'HEALTH'))} ${stats.maxHealth ?? '-'}</span>
                <span>${escape(tr('ui.stat_carry', null, 'CARRY'))} ${stats.carryWeight ?? '-'} KG</span>
                <span>${escape(tr('ui.stat_melee', null, 'MELEE'))} ×${stats.meleeDamageMult ?? 1}</span>
            </div>`;
        }
        node.innerHTML = html;
        node.addEventListener('click', () => {
            S.draft.class = c.id;
            ensureKit();
            renderClasses();
        });
        box.appendChild(node);
    });
}

// creator: faction

function renderFactions() {
    const box = $('factions');
    box.innerHTML = '';
    for (const f of (S.cfg.factions || [])) {
        const on = f.id === S.draft.faction;
        const node = el('div', 'card card--fac' + (on ? ' is-active' : ''));
        node.style.setProperty('--fc', f.colour || '');
        const name = tr('fac.' + f.id + '.n', null, f.id);
        let html = '';
        if (f.bonus) html += `<span class="card__tag">${escape(tr('ui.smallest_bonus', { cash: S.cfg.bonusCash || 0, xp: S.cfg.bonusXp || 0 }, 'SMALLEST'))}</span>`;
        html += `<div class="card__title">${escape(name)}</div>
            <div class="card__blurb">${escape(tr('fac.' + f.id + '.d', null, ''))}</div>`;
        if (on) {
            const perks = [1, 2, 3].map((n) => tr('fac.' + f.id + '.p' + n, null, '')).filter(Boolean);
            html += `<ul>${perks.map((p) => `<li>${escape(p)}</li>`).join('')}</ul>
                <div class="card__sub"><b>${escape(tr('ui.jobs', null, 'JOBS'))}</b> ${escape(tr('fac.' + f.id + '.jobs', null, ''))}</div>
                <div class="card__sub">${escape(tr('ui.spawn_safezone', null, ''))}</div>`;
        }
        html += `<div class="card__sub">${escape(tr('ui.members', null, 'MEMBERS'))} <b>${Number(f.members) || 0}</b></div>`;
        node.innerHTML = html;
        node.addEventListener('click', () => { S.draft.faction = f.id; renderFactions(); });
        box.appendChild(node);
    }
}

// creator: look

const GROUPS = [
    ['heritage', 'HERITAGE', ['motherIndex', 'fatherIndex', 'shapeMix', 'skinMix']],
    ['hair', 'HAIR', ['hairStyle', 'hairColor', 'hairHighlight']],
    ['face', 'FACE DETAILS', ['eyeColor']],
    ['hairy', 'BEARD & BROWS', ['eyebrowStyle', 'eyebrowColor', 'beardStyle', 'beardColor', 'beardOpacity']],
    ['skin', 'SKIN', ['blemishStyle', 'ageingStyle', 'complexion', 'sunDamage', 'freckles', 'bodyBlemish']],
    ['makeup', 'MAKEUP', ['makeupStyle', 'lipstickStyle', 'lipstickColor', 'blushStyle', 'blushColor']],
];
const BEARD_KEYS = ['beardStyle', 'beardColor', 'beardOpacity'];

function groupOf(f) {
    for (const g of GROUPS) if (g[2].includes(f.key)) return g[0];
    return 'face';   // face feature sliders and anything added to the schema later
}

function renderSliders() {
    const box = $('sliders');
    box.innerHTML = '';
    const female = S.draft.gender === 'female';

    for (const [gid, fb] of GROUPS.map((g) => [g[0], g[1]])) {
        const fields = S.appearance.filter((f) => groupOf(f) === gid && !(female && BEARD_KEYS.includes(f.key)));
        if (!fields.length) continue;
        box.appendChild(el('div', 'group__title', escape(up(tr('grp.' + gid, null, fb)))));

        fields.forEach((f) => {
            const row = el('div', 'slider');
            const isFloat = f.type === 'float';
            const step = isFloat ? 0.05 : 1;
            const value = S.draft.appearance[f.key] ?? f.default;
            const shown = (v) => (!isFloat && v < 0) ? up(tr('cl.none', null, 'NONE')) : (isFloat ? Number(v).toFixed(2) : v);

            row.innerHTML = `
                <span class="slider__label">${escape(up(tr('ap.' + f.key, null, f.label)))}</span>
                <input type="range" min="${f.min}" max="${f.max}" step="${step}" value="${value}" />
                <span class="slider__value">${escape(shown(value))}</span>`;

            const input = row.querySelector('input');
            const out = row.querySelector('.slider__value');

            input.addEventListener('input', () => {
                const v = isFloat ? parseFloat(input.value) : parseInt(input.value, 10);
                S.draft.appearance[f.key] = v;
                out.textContent = shown(v);
                pushDraft(false);
            });

            box.appendChild(row);
        });
    }
}

/* ROLL A FACE: everything comes from the server's Multichar.Roll lists - curated parent pairs, shape/skin ranges
   that follow the dominant parent, natural hair and eye colours, small face details. Female never gets a beard. */
function randomiseLook() {
    if (!S.draft || !S.cfg || !S.cfg.roll) return;
    const g = S.draft.gender;
    const R = S.cfg.roll, G = R[g] || R.male;
    const ap = seedAppearance(g);

    const [mother, father] = pick(G.pairs);
    const shape = r2(rnd(G.shape[0], G.shape[1]));
    ap.motherIndex = mother;
    ap.fatherIndex = father;
    ap.shapeMix = shape;
    ap.skinMix = r2(clamp(shape + rnd(-G.skinSpread, G.skinSpread), G.skinMin, G.skinMax));

    const hairColor = pick(G.hairColors);
    ap.hairStyle = pick(G.hair);
    ap.hairColor = hairColor;
    ap.hairHighlight = Math.random() < 0.75 ? hairColor : pick(G.hairColors);
    ap.eyebrowStyle = pick(G.browStyles);
    ap.eyebrowColor = hairColor;
    ap.eyeColor = pick(G.eyeColors);

    if (g === 'female' || !G.beard || Math.random() >= (G.beard.chance || 0)) {
        ap.beardStyle = -1;
    } else {
        ap.beardStyle = pick(G.beard.styles);
        ap.beardColor = hairColor;
        ap.beardOpacity = r2(rnd(G.beard.opacity[0], G.beard.opacity[1]));
    }

    // Face details: centre-weighted, never past +-featureRange.
    const fr = R.featureRange || 0.35;
    for (const f of S.appearance) {
        if (f.feature !== undefined) ap[f.key] = r2(clamp(((rnd(-1, 1) + rnd(-1, 1)) / 2) * fr, -fr, fr));
    }

    // Older characters get a little ageing, nobody gets blemishes from a roll.
    ap.ageingStyle = (draftAge() >= 55 && Math.random() < 0.6) ? pick([1, 2, 3]) : -1;

    const L = G.lipstick;
    if (L && Math.random() < (L.chance || 0)) {
        ap.lipstickStyle = pick(L.styles || [0]);
        ap.lipstickColor = pick(L.colors || [0]);
    }

    S.draft.appearance = ap;
    renderSliders();
    pushDraft(false);
}

/* Debounced so dragging a slider does not spam the client every frame. The answer carries what the preview ped has (drawable and texture counts). */
let draftTimer = null;
function pushDraft(rebuild) {
    clearTimeout(draftTimer);
    draftTimer = setTimeout(async () => {
        if (!S.draft) return;
        const draft = { gender: S.draft.gender, appearance: S.draft.appearance };
        if (S.cfg && S.cfg.clothingStep && S.draft.clothes) draft.outfit = draftOutfit();
        const r = await post('draft', { rebuild: !!rebuild, draft });
        if (r && r.counts && S.draft) {
            S.counts[draft.gender] = r.counts;
            S.tex = r.tex || {};
            if (S.step === 'clothing') renderWardrobe();
        }
    }, rebuild ? 0 : 60);
}

// creator: clothing, enabled collections only, without dead model slots

function wardrobeRow(cat) {
    const C = S.draft.clothes[cat];
    const list = catList(cat);
    const entry = list.find(e => e.d === C?.d);
    const pos = Math.max(0, list.findIndex(e => e.d === C?.d));
    const noItem = entry?.d === -1;
    const texList = entry?.ts || [];
    const texPos = Math.max(0, texList.indexOf(C?.t));
    const [symbol,label] = WCAT[cat] || ['◇',cat];
    const val = noItem ? 'Keine' : (entry ? `${pos+1} / ${list.length}` : 'Nicht verfügbar');
    return `<div class="az-wardrobe-card">
      <div class="az-wardrobe-header"><span class="az-garment-icon" aria-hidden="true">${azIcon(symbol)}</span>
        <div class="az-garment-name"><b>${escape(label)}</b><small>${list.length ? `${list.length} freigegebene Modelle` : 'Keine freigegebenen Modelle'}</small></div>
        <span class="az-wardrobe-tag">${clothDef(cat).p !== undefined ? 'Zubehör' : 'Kleidung'}</span>
      </div>
      <div class="az-selectors"><div class="az-selector">
        <span>Modell</span><div class="az-selector-control">
          <button class="arrow" type="button" data-cat="${cat}" data-act="prev" ${!list.length?'disabled':''} aria-label="Vorheriges Modell">&#8249;</button>
          <strong>${escape(val)}</strong>
          <button class="arrow" type="button" data-cat="${cat}" data-act="next" ${!list.length?'disabled':''} aria-label="Nächstes Modell">&#8250;</button>
        </div></div><div class="az-selector">
        <span>Textur</span><div class="az-selector-control">
          <button class="arrow" type="button" data-cat="${cat}" data-act="tprev" ${noItem||texList.length<2?'disabled':''} aria-label="Vorherige Textur">&#8249;</button>
          <strong>${noItem||!texList.length ? '–' : `${texPos+1} / ${texList.length}`}</strong>
          <button class="arrow" type="button" data-cat="${cat}" data-act="tnext" ${noItem||texList.length<2?'disabled':''} aria-label="Nächste Textur">&#8250;</button>
        </div></div></div>
    </div>`;
}

function renderWardrobe() {
    if (!S.draft || !S.cfg || !S.cfg.clothingStep) return;
    const box = $('wardrobe');
    if (!S.catalog[S.draft.gender]) {
        box.innerHTML = `<div class="az-loading"><span class="az-loading-symbol">◈</span><b>Kleidung wird erfasst</b><small>${escape(S.catalogError || 'Verfügbare Modelle und Texturen werden überprüft …')}</small></div>`;
        return;
    }
    const group = WGROUPS.find(g => g.id === S.wardrobeGroup) || WGROUPS[0];
    box.innerHTML = `<nav class="az-wardrobe-tabs" aria-label="Kleidungskategorien">${WGROUPS.map(g =>
        `<button class="az-wardrobe-tab ${g.id===group.id?'is-active':''}" data-group="${g.id}" type="button"><span>${azIcon(g.icon)}</span>${g.name}</button>`).join('')}</nav>
        ${S.cfg.canSaveDefaultOutfit ? '<button type="button" class="az-save-default" id="azSaveDefault">Als Standard-Outfit speichern</button>' : ''}
        <p class="az-wardrobe-guide">Nur freigegebene Kleidung · Rucksäcke nicht verfügbar</p>
        <div class="az-wardrobe-list">${group.cats.map(wardrobeRow).join('')}</div>`;
}

function stepCloth(cat, act) {
    const list = catList(cat);
    const current = S.draft?.clothes[cat];
    if (!current || !list.length) return;
    if (act === 'prev' || act === 'next') {
        const index = list.findIndex(x => x.d === current.d);
        const next = list[(index + (act === 'next' ? 1 : -1) + list.length) % list.length];
        S.draft.clothes[cat] = { d: next.d, t: next.ts[0] };
        // Follow the operator's mapped arm/torso variant when the top changes.
        if (cat === 'top') {
            const map = S.cfg.clothingRules?.torsoMappings?.[next.k];
            const fallback = S.cfg.clothes.armsFor?.[S.draft.gender]?.[next.d];
            const armId = Number(map?.drawable ?? fallback);
            const arm = catList('arms').find(x => x.d === armId);
            if (arm) S.draft.clothes.arms = { d: arm.d, t: arm.ts.includes(map?.texture) ? map.texture : arm.ts[0] };
        }
    } else {
        const entry = list.find(x => x.d === current.d);
        const arr = entry?.ts || [];
        if (!arr.length) return;
        const index = arr.indexOf(current.t);
        current.t = arr[(index + (act === 'tnext' ? 1 : -1) + arr.length) % arr.length];
    }
    renderWardrobe();
    pushDraft(false);
}

// creator: kit

function classItemSet() {
    const c = S.classes.find((x) => x.id === S.draft.class);
    const set = new Set();
    for (const i of ((c && c.items) || [])) set.add(i.item);
    return set;
}

// language picker (first creator step)
const LANGS = [['en', 'English'], ['pt', 'Português'], ['de', 'Deutsch'], ['pl', 'Polski'], ['tr', 'Türkçe'],
               ['es', 'Español'], ['fr', 'Français'], ['it', 'Italiano'], ['ru', 'Русский']];

function buildLangPicker() {
    const sel = $('langSel');
    if (!sel) return;
    if (!sel.options.length) {
        LANGS.forEach(([id, name]) => { const o = el('option'); o.value = id; o.textContent = name; sel.appendChild(o); });
        sel.addEventListener('change', () => { post('setLang', { lang: sel.value }); });
    }
    sel.value = lang();
}

function meleeOptions() {
    return ((S.cfg.kit && S.cfg.kit.melee) || []);
}

/* Keep the kit choice valid after the origin changes. Creator choices are always available. */
function ensureKit() {
    if (!S.draft || !S.cfg || !S.cfg.kit || S.cfg.kit.enabled === false) return;
    const opts = meleeOptions();
    if (!opts.some((m) => m.id === S.draft.kit.melee)) S.draft.kit.melee = opts.length ? opts[0].id : null;
    S.draft.kit.goodies = S.draft.kit.goodies.filter((id) =>
        (S.cfg.kit.goodies || []).some((g) => g.id === id));
}

function renderKit() {
    const K = S.cfg.kit;
    const max = K.maxGoodies || 2;
    const have = S.draft.kit.goodies.length;
    $('kitCount').textContent = tr('kit.goodies_hint', { n: max, have }, `${have} / ${max}`);
    const box = $('kitGoodies');
    box.innerHTML = '';
    K.goodies.forEach((g) => {
        const on = S.draft.kit.goodies.includes(g.id);
        const b = el('button', 'opt-card' + (on ? ' is-active' : ''),
            `${escape(g.label || itemName(g.item))}<em>×${g.amount || 1}</em>`);
        b.type = 'button';
        b.disabled = !on && have >= max;
        b.addEventListener('click', () => {
            const list = S.draft.kit.goodies;
            const at = list.indexOf(g.id);
            if (at >= 0) list.splice(at, 1);
            else if (list.length < max) list.push(g.id);
            renderKit();
        });
        box.appendChild(b);
    });
}

// creator: review

function factionName(id) { return tr('fac.' + id + '.n', null, id); }

function renderReview() {
    const D = S.draft, I = S.cfg;
    const cls = S.classes.find((c) => c.id === D.class) || {};
    const st = cls.stats || {};
    const rows = [];
    const add = (step, key, fb, value, sub) => rows.push({ step, key, fb, value, sub });

    add('identity', 'rv.name', 'NAME', `${D.firstName.trim()} ${D.lastName.trim()}`, D.nickname.trim() ? `"${D.nickname.trim()}"` : '');
    add('identity', 'ui.age', 'AGE', `${draftAge()} · ${up(tr(D.gender === 'female' ? 'ui.female' : 'ui.male', null, D.gender))}`,
        `${D.height} cm · ${feetInches(D.height)} · ${D.bloodType} · ${tr('occ.' + D.occupation, null, D.occupation)}`);
    if (D.backstory.trim()) add('identity', 'ui.backstory', 'BACKSTORY', D.backstory.trim());
    add('origin', 'ui.origin', 'ORIGIN', className(cls),
        `${tr('ui.stat_hp', null, 'HEALTH')} ${st.maxHealth ?? '-'} · ${tr('ui.stat_carry', null, 'CARRY')} ${st.carryWeight ?? '-'} KG · ${tr('ui.stat_melee', null, 'MELEE')} ×${st.meleeDamageMult ?? 1}`);
    if (S.steps.includes('faction')) {
        add('faction', 'ui.faction', 'FACTION', D.faction ? factionName(D.faction) : '-', tr('ui.spawn_safezone', null, ''));
    } else {
        add('origin', 'rv.spawn', 'FIRST SPAWN', tr('rv.camp', null, 'The camp'));
    }
    if (S.steps.includes('clothing')) add('clothing', 'rv.outfit', 'OUTFIT', tr('rv.custom_outfit', null, 'Custom outfit'));
    else add('look', 'rv.outfit', 'OUTFIT', tr('rv.default_outfit', null, 'Default outfit'));
    if (S.steps.includes('kit')) {
        const K = S.cfg.kit;
        const goods = D.kit.goodies.map((id) => K.goodies.find((g) => g.id === id)).filter(Boolean)
            .map((g) => `${itemName(g.item)} ×${g.amount || 1}`);
        add('kit', 'rv.kit', 'KIT', 'Jagdmesser ×1', goods.join(' · '));
    }

    $('review').innerHTML = rows.map((r) => `<div class="rv">
        <span class="rv__k">${escape(up(tr(r.key, null, r.fb)))}</span>
        <span class="rv__v">${escape(r.value)}${r.sub ? `<small>${escape(r.sub)}</small>` : ''}</span>
        <button class="rv__edit" data-go="${r.step}">${escape(up(tr('ui.edit', null, 'EDIT')))}</button></div>`).join('');
}

// creator: steps

function renderSteps() {
    const nav = $('steps');
    nav.innerHTML = '';
    const at = S.steps.indexOf(S.step);
    S.steps.forEach((id, i) => {
        const b = el('button', 'step' + (i === at ? ' is-active' : (i < at ? ' is-done' : '')), String(i + 1));
        b.type = 'button';
        b.title = tr(STEP_LABEL[id][0], null, STEP_LABEL[id][1]);
        b.addEventListener('click', () => setStep(id));
        nav.appendChild(b);
    });
    const label = tr(STEP_LABEL[S.step][0], null, STEP_LABEL[S.step][1]);
    $('stepName').innerHTML = `${escape(tr('ui.step_n', { n: at + 1, total: S.steps.length }, `STEP ${at + 1} / ${S.steps.length}`))}<b>${escape(up(label))}</b>`;
    $('btnCreate').textContent = S.step === 'review'
        ? tr('ui.begin', null, 'BEGIN') : tr('ui.next', null, 'NEXT');
    $('btnCancel').textContent = tr('ui.back', null, 'BACK');
}

function setStep(id) {
    if (!S.steps.includes(id)) return;
    S.step = id;
    document.querySelectorAll('.pane').forEach((p) => p.classList.toggle('is-active', p.dataset.pane === id));
    $('createError').textContent = '';
    if (id === 'origin') renderClasses();
    if (id === 'faction') renderFactions();
    if (id === 'look') renderSliders();
    if (id === 'clothing') { renderWardrobe(); loadWardrobe(); }
    if (id === 'kit') { ensureKit(); renderKit(); }
    if (id === 'review') renderReview();
    renderSteps();
    // Faces are easier to judge close up.
    const mode = id === 'look' ? 'face' : 'full';
    post('focus', { mode });
    document.querySelectorAll('.cam__btn[data-focus]').forEach((x) =>
        x.classList.toggle('is-active', x.dataset.focus === mode));
    updateCameraLabel(mode);
}

// validation

function problem(id) {
    const D = S.draft;
    if (id === 'identity') {
        const nameRe = /^[A-Za-z][A-Za-z\s'-]{1,23}$/;
        if (!nameRe.test(D.firstName.trim())) return tr('ui.bad_first', null, 'First name looks wrong.');
        if (!nameRe.test(D.lastName.trim()))  return tr('ui.bad_last', null, 'Last name looks wrong.');
        if (D.nickname.trim() && [...D.nickname.trim()].length < 2) return tr('ui.bad_nick', null, 'Nickname is too short.');
        const age = draftAge();
        if (age < 18 || age > 90) return tr('ui.bad_age', { min: 18, max: 90 }, 'Age must be between 18 and 90.');
        if (!D.bloodType) return tr('ui.pick_blood', null, 'Choose a blood type.');
        if (!D.occupation) return tr('ui.pick_occ', null, 'Choose a previous occupation.');
    }
    if (id === 'origin' && !D.class) return tr('ui.pick_origin', null, 'Choose an origin.');
    if (id === 'faction' && !D.faction) return tr('ui.pick_faction', null, 'Choose a faction.');
    if (id === 'clothing' && !S.catalog[D.gender]) return 'Die Kleidungsmodelle werden noch geprüft.';

    return null;
}

function firstProblem() {
    for (const id of S.steps) {
        const p = problem(id);
        if (p) return { id, text: p };
    }
    return null;
}

function syncHands() {
    const b = $('btnHands');
    b.innerHTML = `<span class="az-hands-icon" aria-hidden="true">⌃</span>${S.hands ? 'Hände runter' : 'Hände hoch'}`;
    b.classList.toggle('is-active', S.hands);
}

// wiring

$('btnPlay').addEventListener('click', async () => {
    const c = S.characters[S.selected];
    if (!c) return;
    $('btnPlay').disabled = true;

    // The old safe-spawn option was removed from character selection.
    const res = await post('play', { id: c.id, safeSpawn: false });
    if (!res.ok) {
        $('btnPlay').disabled = false;
        alertLine(res.error || tr('ui.could_not_enter', null, 'Could not enter the world.'));
    }
});

$('btnNew').addEventListener('click', openCreator);
if ($('btnRandom')) $('btnRandom').addEventListener('click', randomiseLook);

$('btnCancel').addEventListener('click', () => {
    if (S.edit) { post('editCancel', {}); leaveEdit(); return; }
    const at = S.steps.indexOf(S.step);
    if (at <= 0) closeCreator(); else setStep(S.steps[at - 1]);
});

$('btnHands').addEventListener('click', () => {
    S.hands = !S.hands;
    syncHands();
    post('handsUp', { on: S.hands });
});

$('btnOutfitReset').addEventListener('click', () => {
    if (!S.draft) return;
    S.draft.clothes = defaultClothes(S.draft.gender);
    normalizeClothes();
    renderWardrobe();
    pushDraft(false);
});

$('wardrobe').addEventListener('click', (e) => {
    const group = e.target.closest('[data-group]');
    if (group) { S.wardrobeGroup = group.dataset.group; renderWardrobe(); return; }
    const b = e.target.closest('[data-act]');
    if (b && S.draft) stepCloth(b.dataset.cat, b.dataset.act);
});

$('review').addEventListener('click', (e) => {
    const b = e.target.closest('[data-go]');
    if (b) setStep(b.dataset.go);
});

// appearance edit mode
// Opened in-game by bs_vip. Only the LOOK pane, on the live character.
function setEditChrome(on) {
    $('steps').style.display = on ? 'none' : '';
    $('stepName').style.display = on ? 'none' : '';
    const cam = document.querySelector('.cam'); if (cam) cam.style.display = on ? 'none' : '';
    const title = document.querySelector('#creator .panel__title');
    const sub = document.querySelector('#creator .panel__sub');
    if (on) {
        title.textContent = tr('ui.edit_appearance', null, 'EDIT APPEARANCE');
        sub.textContent = tr('ui.edit_appearance_sub', null, 'Face and hair. Clothes stay as they are.');
        $('btnCreate').textContent = tr('ui.save_look', null, 'SAVE LOOK');
        $('btnCancel').textContent = tr('ui.cancel', null, 'CANCEL');
    } else {
        title.textContent = tr('ui.new_survivor', null, 'NEW SURVIVOR');
        sub.textContent = tr('ui.everyone_out_here_was_someone_before', null, 'Everyone out here was someone before.');
    }
}

async function enterEdit(d) {
    S.edit = true;
    S.appearance = d.appearance || S.appearance;
    const appearance = {};
    for (const f of S.appearance) appearance[f.key] = (d.current && d.current[f.key] !== undefined) ? d.current[f.key] : f.default;
    S.draft = { gender: d.gender || 'male', appearance, firstName: '', lastName: '', class: '', dobYear: 2000, dobMonth: 1, dobDay: 1 };
    $('root').classList.remove('hidden');
    $('select').classList.add('hidden');
    $('confirm').classList.add('hidden');
    $('creator').classList.remove('hidden');
    $('btnHands').classList.add('hidden');
    $('createError').textContent = '';
    setEditChrome(true);
    document.querySelectorAll('.pane').forEach((x) => x.classList.toggle('is-active', x.dataset.pane === 'look'));
    // Roll tables come from the server; without them the roll button is hidden.
    S.cfg = null;
    $('btnRandom').style.display = 'none';
    renderSliders();
    const cfg = await post('creatorData', {});
    if (S.edit && cfg && cfg.ok) { S.cfg = cfg; $('btnRandom').style.display = ''; }
}

function leaveEdit() {
    S.edit = false; S.draft = null;
    setEditChrome(false);
    $('btnRandom').style.display = '';
    $('creator').classList.add('hidden');
    $('root').classList.add('hidden');
}

async function submitCreate() {
    const bad = firstProblem();
    if (bad) { setStep(bad.id); $('createError').textContent = bad.text; return; }

    const D = S.draft;
    const character = {
        firstName: D.firstName.trim(),
        lastName:  D.lastName.trim(),
        dob:       draftDobString(),
        gender:    D.gender,
        class:     D.class,
        appearance: D.appearance,
        identity: {
            nickname: D.nickname.trim(), height: D.height, bloodType: D.bloodType,
            occupation: D.occupation, backstory: D.backstory.trim(),
        },
    };
    if (S.steps.includes('faction')) character.faction = D.faction;
    if (S.steps.includes('kit')) character.kit = { goodies: D.kit.goodies };
    if (S.steps.includes('clothing')) character.outfit = outfitChoices();

    $('createError').textContent = '';
    $('btnCreate').disabled = true;
    $('btnCreate').textContent = tr('ui.creating', null, 'CREATING...');

    const res = await post('create', { character });

    $('btnCreate').disabled = false;
    renderSteps();

    if (!res.ok) { $('createError').textContent = res.error || tr('ui.could_not_create', null, 'Could not create the character.'); return; }

    // Use the list the client handed back. Reading S.characters here raced the setData broadcast and could select the slot before the new one existed.
    if (res.characters) S.characters = res.characters;

    S.selected = Math.max(0, S.characters.length - 1);
    closeCreator();
    renderSlots();
    selectSlot(S.selected);
}

$('btnCreate').addEventListener('click', async () => {
    if (S.edit) {
        $('btnCreate').disabled = true;
        const r = await post('editSave', { appearance: S.draft.appearance });
        $('btnCreate').disabled = false;
        if (!r.ok) { $('createError').textContent = r.error || tr('ui.could_not_save', null, 'Could not save.'); return; }
        leaveEdit();
        return;
    }
    if (!S.draft) return;
    if (S.step === 'review') return submitCreate();

    const p = problem(S.step);
    if (p) { $('createError').textContent = p; return; }
    const at = S.steps.indexOf(S.step);
    setStep(S.steps[at + 1]);
});

['firstName', 'lastName', 'nickname'].forEach((id) => {
    $(id).addEventListener('input', (e) => { if (S.draft) S.draft[id] = e.target.value; });
});
$('backstory').addEventListener('input', (e) => {
    if (!S.draft) return;
    S.draft.backstory = e.target.value;
    showStoryCount();
});
$('height').addEventListener('input', (e) => {
    if (!S.draft) return;
    S.draft.height = Number(e.target.value);
    showHeight();
});
$('occupation').addEventListener('change', (e) => { if (S.draft) S.draft.occupation = e.target.value; });

/* Switching sex swaps the model AND resets the face, hair, brows, beard, makeup and outfit to that sex's starting look,
   otherwise the male head blend stays on the female model. */
document.querySelectorAll('#genderChoice .choice__btn').forEach((b) => {
    b.addEventListener('click', () => {
        if (!S.draft) return;
        if (S.draft.gender === b.dataset.gender) return;

        S.draft.gender = b.dataset.gender;
        S.draft.appearance = seedAppearance(S.draft.gender);
        S.draft.clothes = defaultClothes(S.draft.gender);

        syncIdentityInputs();
        pushDraft(true);           // different model - the ped must respawn
        if (S.catalog[S.draft.gender]) normalizeClothes();
    });
});

function updateCameraLabel(mode) {
    const count = { full:'01', face:'02', body:'03', legs:'04' }[mode] || '01';
    const indicator = document.querySelector('.az-cam-label em');
    if (indicator) indicator.textContent = `${count} / 04`;
}

// [data-focus] only. The turn arrows share the .cam__btn class and would post focus:undefined, snapping the camera back to FULL.
document.querySelectorAll('.cam__btn[data-focus]').forEach((b) => {
    b.addEventListener('click', () => {
        document.querySelectorAll('.cam__btn[data-focus]')
            .forEach((x) => x.classList.remove('is-active'));
        b.classList.add('is-active');
        post('focus', { mode: b.dataset.focus });
        updateCameraLabel(b.dataset.focus);
    });
});

/* delete flow */

$('btnDelete').addEventListener('click', () => {
    const c = S.characters[S.selected];
    if (!c) return;
    $('confirmBody').textContent = tr('ui.abandon_body',
        { name: `${c.first_name} ${c.last_name}`, time: playtime(c.playtime).toLowerCase() },
        `${c.first_name} ${c.last_name}`);
    $('confirmInput').value = '';
    $('confirmYes').disabled = true;
    $('confirm').classList.remove('hidden');
    $('confirmInput').focus();
});

$('confirmInput').addEventListener('input', (e) => {
    const c = S.characters[S.selected];
    $('confirmYes').disabled =
        !c || e.target.value.trim().toLowerCase() !== String(c.first_name).toLowerCase();
});

$('confirmNo').addEventListener('click', () => $('confirm').classList.add('hidden'));

$('confirmYes').addEventListener('click', async () => {
    const c = S.characters[S.selected];
    $('confirm').classList.add('hidden');
    const res = await post('delete', { id: c.id });
    if (res && res.ok) {
        S.characters = res.characters || [];
        S.selected = 0;
        renderSlots();
        selectSlot(0);
    }
});

let alertTimer = null;
function alertLine(text) {
    $('slotCount').textContent = String(text).toUpperCase();
    // Restore the slot counter so one failed attempt does not leave the screen looking broken.
    clearTimeout(alertTimer);
    alertTimer = setTimeout(() => {
        $('slotCount').textContent = slotCountText();
    }, 4000);
}

// Language change: relabel what is on screen.
if (window.BSI18n && BSI18n.onChange) {
    BSI18n.onChange(() => {
        renderSlots();
        if (!S.draft) return;
        if (S.edit) { setEditChrome(true); renderSliders(); return; }
        buildLangPicker();
        buildDobPickers();
        buildIdentityLists();
        syncIdentityInputs();
        setStep(S.step);
        syncHands();
    });
}
// from the client

window.addEventListener('message', (event) => {
    const d = event.data || {};

    switch (d.action) {
        case 'setData':
            if (d.characters) S.characters = d.characters;
            if (d.classes)    S.classes = d.classes;
            if (d.appearance) S.appearance = d.appearance;
            if (d.maxSlots)   S.maxSlots = d.maxSlots;
            renderSlots();
            break;

        case 'open':
            $('root').classList.remove('hidden');
            $('creator').classList.add('hidden');
            $('btnHands').classList.add('hidden');
            $('select').classList.remove('hidden');
            $('confirm').classList.add('hidden');
            renderSlots();
            // Wait until the selection UI has actually been painted.
            requestAnimationFrame(() => requestAnimationFrame(() => {
                fetch(`https://${GetParentResourceName()}/selectionReady`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: '{}'
                }).catch(() => {});
            }));
            break;

        case 'close':
            if (S.edit) leaveEdit();
            $('root').classList.add('hidden');
            break;

        case 'editAppearance':
            enterEdit(d);
            break;
    }
});


// turning

// While the NUI has the cursor the game never sees the mouse, so rotation originates here and is posted to Lua.

const ROTATE_STEP = 18;

function rotate(delta) { post('rotate', { delta }); }

$('turnLeft').addEventListener('click',  () => rotate(-ROTATE_STEP));
$('turnRight').addEventListener('click', () => rotate(ROTATE_STEP));

/* Drag anywhere that is not a panel. */
let dragging = false;
let lastX = 0;

function overPanel(target) {
    return !!target.closest('.panel, .cam, .modal');
}

document.addEventListener('mousedown', (e) => {
    if (overPanel(e.target)) return;
    dragging = true;
    lastX = e.clientX;
    document.body.classList.add('is-turning');
});

document.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    const dx = e.clientX - lastX;
    if (Math.abs(dx) < 2) return;
    lastX = e.clientX;
    rotate(dx * 0.4);
});

['mouseup', 'mouseleave'].forEach((ev) => document.addEventListener(ev, () => {
    dragging = false;
    document.body.classList.remove('is-turning');
}));

document.addEventListener('wheel', (e) => {
    if (overPanel(e.target)) return;
    post('zoom', { delta: e.deltaY > 0 ? 0.18 : -0.18 });
}, { passive: true });

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        if (!e.repeat) post('azOpenPauseMenu');
        return;
    }
    // Never steal keys while someone is typing a name.
    if (['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
    if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft')  rotate(-ROTATE_STEP);
    if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') rotate(ROTATE_STEP);
});

// Admin-only preset action: server validates the catalog and ACE permission again.
document.addEventListener('click', async (ev) => {
    if (!ev.target.closest('#azSaveDefault') || !S.draft || !S.cfg?.canSaveDefaultOutfit) return;
    const button = ev.target.closest('#azSaveDefault');
    button.disabled = true;
    const r = await post('saveDefaultOutfit', { gender: S.draft.gender, outfit: outfitChoices() });
    if (r?.ok) {
        S.cfg.defaultOutfits = S.cfg.defaultOutfits || {};
        S.cfg.defaultOutfits[S.draft.gender] = outfitChoices();
        button.textContent = 'Standard-Outfit gespeichert';
    } else {
        button.textContent = r?.error || 'Speichern fehlgeschlagen';
        button.disabled = false;
    }
});

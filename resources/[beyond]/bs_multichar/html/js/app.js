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
                <span>${escape(tr('ui.lvl', null, 'LVL'))} ${c.level ?? 1}</span>
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

const CLOTH_CATS = ['top', 'legs', 'shoes'];
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
function noneOf(cat) { const d = clothDef(cat); return d.none !== undefined ? d.none : null; }

/* Listed drawables of a category for the current sex, minus any the preview ped reported as missing. */
function catList(cat) {
    const list = (clothDef(cat)[S.draft.gender] || []).slice();
    const n = (S.counts[S.draft.gender] || {})[clothKey(cat)];
    return n ? list.filter((d) => d < 0 || d < n) : list;
}

function defaultClothes(gender) {
    const out = {};
    for (const cat of CLOTH_CATS) {
        const list = clothDef(cat)[gender] || [];
        const none = noneOf(cat);
        out[cat] = { d: none !== null && list.includes(none) ? none : (list[0] ?? 0), t: 0 };
    }
    out.arms = { auto: true, d: 0 };
    return out;
}

function armsDrawable() {
    const C = S.draft.clothes;
    if (!C.arms.auto) return C.arms.d;
    const map = (S.cfg.clothes.armsFor || {})[S.draft.gender] || {};
    return map[C.top.d] ?? C.top.d;
}

/* The outfit as the preview ped (and later the saved metadata.outfit) wears it. */
function draftOutfit() {
    const C = S.draft.clothes;
    const comps = {}, props = {};
    for (const cat of CLOTH_CATS) {
        comps[clothDef(cat).c] = { drawable: C[cat].d, texture: C[cat].t, palette: 2 };
    }
    comps[8] = { drawable: 15, texture: 0, palette: 2 };   // bare undershirt, no slot
    comps[3] = { drawable: armsDrawable(), texture: 0, palette: 2 };
    return { components: comps, props };
}

/* Choices only (ids), the server rebuilds the real outfit from them. */
function outfitChoices() {
    const C = S.draft.clothes;
    const o = {};
    for (const cat of CLOTH_CATS) o[cat] = { d: C[cat].d, t: C[cat].t };
    if (!C.arms.auto) o.arms = C.arms.d;
    return o;
}

function blankDraft() {
    const I = S.cfg.identity;
    return {
        firstName: '', lastName: '', nickname: '',
        dobDay: 1, dobMonth: 1, dobYear: new Date().getFullYear() - 30,
        gender: 'male',
        height: I.heightDefault, bloodType: I.bloodTypes[0], occupation: I.occupations[0], backstory: '',
        class: S.classes[0]?.id || 'survivor',
        faction: null,
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
    S.counts = {}; S.tex = {}; S.hands = false;
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
    const s = ['identity', 'origin'];
    if ((S.cfg.factions || []).length) s.push('faction');
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

// creator: clothing

function wardrobeRow(cat) {
    const C = S.draft.clothes[cat];
    const list = catList(cat);
    const none = noneOf(cat);
    const pos = Math.max(0, list.indexOf(C.d));
    const isNone = none !== null && C.d === none;
    const val = isNone ? up(tr('cl.none', null, 'NONE')) : `${pos + 1} / ${list.length}`;
    const texN = Math.max(1, Math.min((S.tex[clothKey(cat)] || (S.cfg.clothes.maxTexture + 1)), S.cfg.clothes.maxTexture + 1));
    const showTex = !isNone;
    return `<div class="wrow"><span class="wrow__label">${escape(tr('cl.' + cat, null, cat.toUpperCase()))}</span>
        <div class="wrow__pick">
            <button class="arrow" data-cat="${cat}" data-act="prev">&#8249;</button>
            <span class="wrow__val">${escape(val)}</span>
            <button class="arrow" data-cat="${cat}" data-act="next">&#8250;</button>
        </div>
        <div class="wrow__col">
            <button class="arrow" data-cat="${cat}" data-act="tprev" ${showTex ? '' : 'disabled'}>&#8249;</button>
            <span class="wrow__val" style="min-width:2.2rem">${showTex ? (C.t + 1) + '/' + texN : '-'}</span>
            <button class="arrow" data-cat="${cat}" data-act="tnext" ${showTex ? '' : 'disabled'}>&#8250;</button>
        </div></div>`;
}

function armsRow() {
    const A = S.draft.clothes.arms;
    const d = armsDrawable();
    return `<div class="wrow"><span class="wrow__label">${escape(tr('cl.arms_gloves', null, 'GLOVES / ARMS'))}</span>
        <div class="wrow__pick">
            <button class="arrow" data-cat="arms" data-act="prev" ${A.auto ? 'disabled' : ''}>&#8249;</button>
            <span class="wrow__val">${d}</span>
            <button class="arrow" data-cat="arms" data-act="next" ${A.auto ? 'disabled' : ''}>&#8250;</button>
        </div>
        <div class="wrow__col"><button class="mini${A.auto ? ' is-active' : ''}" data-cat="arms" data-act="auto">${escape(tr('cl.auto', null, 'AUTO'))}</button></div></div>`;
}

function renderWardrobe() {
    if (!S.draft || !S.cfg || !S.cfg.clothingStep) return;
    $('wardrobe').innerHTML = wardrobeRow('top') + armsRow() +
        ['legs', 'shoes'].map(wardrobeRow).join('');
}

function stepCloth(cat, act) {
    const C = S.draft.clothes;
    if (cat === 'arms') {
        const A = C.arms;
        if (act === 'auto') { A.auto = !A.auto; if (!A.auto) A.d = armsDrawable(); }
        else if (!A.auto) {
            const [lo, hi] = S.cfg.clothes.armsRange;
            const n = (S.counts[S.draft.gender] || {}).c3;
            const top = Math.min(hi, n ? n - 1 : hi);
            A.d = act === 'next' ? (A.d >= top ? lo : A.d + 1) : (A.d <= lo ? top : A.d - 1);
        }
    } else if (act === 'prev' || act === 'next') {
        const list = catList(cat);
        if (!list.length) return;
        let i = list.indexOf(C[cat].d);
        i = act === 'next' ? (i + 1) % list.length : (i - 1 + list.length) % list.length;
        C[cat] = { d: list[i], t: 0 };
    } else {
        const texN = Math.max(1, Math.min((S.tex[clothKey(cat)] || (S.cfg.clothes.maxTexture + 1)), S.cfg.clothes.maxTexture + 1));
        C[cat].t = act === 'tnext' ? (C[cat].t + 1) % texN : (C[cat].t - 1 + texN) % texN;
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
    const own = classItemSet();
    return ((S.cfg.kit && S.cfg.kit.melee) || []).filter((m) => !own.has(m.item));
}

/* Keep the kit choice valid after the origin changes: a weapon the origin already carries is not offered twice. */
function ensureKit() {
    if (!S.draft || !S.cfg || !S.cfg.kit || S.cfg.kit.enabled === false) return;
    const opts = meleeOptions();
    if (!opts.some((m) => m.id === S.draft.kit.melee)) S.draft.kit.melee = opts.length ? opts[0].id : null;
    // Goodies the origin already carries are not offered (and not kept) a second time.
    const own = classItemSet();
    S.draft.kit.goodies = S.draft.kit.goodies.filter((id) => {
        const g = (S.cfg.kit.goodies || []).find((x) => x.id === id);
        return g && !own.has(g.item);
    });
}

function renderKit() {
    const K = S.cfg.kit;
    const melee = $('kitMelee');
    melee.innerHTML = '';
    meleeOptions().forEach((m) => {
        const b = el('button', 'opt-card' + (m.id === S.draft.kit.melee ? ' is-active' : ''), escape(itemName(m.item)));
        b.type = 'button';
        b.addEventListener('click', () => { S.draft.kit.melee = m.id; renderKit(); });
        melee.appendChild(b);
    });
    const own = [...classItemSet()].filter((i) => (K.melee || []).some((m) => m.item === i));
    if (own.length) {
        melee.appendChild(el('p', 'card__note', escape(tr('kit.origin_has', { items: own.map(itemName).join(', ') }, ''))));
    }

    const max = K.maxGoodies || 2;
    const have = S.draft.kit.goodies.length;
    $('kitCount').textContent = tr('kit.goodies_hint', { n: max, have }, `${have} / ${max}`);
    const box = $('kitGoodies');
    box.innerHTML = '';
    const ownSet = classItemSet();
    K.goodies.forEach((g) => {
        if (ownSet.has(g.item)) return;
        const on = S.draft.kit.goodies.includes(g.id);
        const b = el('button', 'opt-card' + (on ? ' is-active' : ''),
            `${escape(itemName(g.item))}<em>×${g.amount || 1}</em>`);
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
        const m = (K.melee || []).find((x) => x.id === D.kit.melee);
        const goods = D.kit.goodies.map((id) => K.goodies.find((g) => g.id === id)).filter(Boolean)
            .map((g) => `${itemName(g.item)} ×${g.amount || 1}`);
        add('kit', 'rv.kit', 'KIT', m ? itemName(m.item) : '-', goods.join(' · '));
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
    if (id === 'clothing') renderWardrobe();
    if (id === 'kit') { ensureKit(); renderKit(); }
    if (id === 'review') renderReview();
    renderSteps();
    // Faces are easier to judge close up.
    const mode = id === 'look' ? 'face' : 'full';
    post('focus', { mode });
    document.querySelectorAll('.cam__btn[data-focus]').forEach((x) =>
        x.classList.toggle('is-active', x.dataset.focus === mode));
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
    if (id === 'kit' && !D.kit.melee) return tr('ui.pick_melee', null, 'Choose a melee weapon.');
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
    b.textContent = up(tr(S.hands ? 'ui.hands_down' : 'ui.hands_up', null, S.hands ? 'HANDS DOWN' : 'HANDS UP'));
    b.classList.toggle('is-active', S.hands);
}

// wiring

$('btnPlay').addEventListener('click', async () => {
    const c = S.characters[S.selected];
    if (!c) return;
    $('btnPlay').disabled = true;

    // Read at the moment of pressing, sent with the selection and never stored, so a rescue cannot silently cost anyone their logout position.
    const safe = !!($('safeSpawn') && $('safeSpawn').checked);

    const res = await post('play', { id: c.id, safeSpawn: safe });
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
    renderWardrobe();
    pushDraft(false);
});

$('wardrobe').addEventListener('click', (e) => {
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
    if (S.steps.includes('kit')) character.kit = { melee: D.kit.melee, goodies: D.kit.goodies };
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
    });
});

// [data-focus] only. The turn arrows share the .cam__btn class and would post focus:undefined, snapping the camera back to FULL.
document.querySelectorAll('.cam__btn[data-focus]').forEach((b) => {
    b.addEventListener('click', () => {
        document.querySelectorAll('.cam__btn[data-focus]')
            .forEach((x) => x.classList.remove('is-active'));
        b.classList.add('is-active');
        post('focus', { mode: b.dataset.focus });
    });
});

/* delete flow */

$('btnDelete').addEventListener('click', () => {
    const c = S.characters[S.selected];
    if (!c) return;
    $('confirmBody').textContent = tr('ui.abandon_body',
        { name: `${c.first_name} ${c.last_name}`, level: c.level ?? 1, time: playtime(c.playtime).toLowerCase() },
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
    // Never steal keys while someone is typing a name.
    if (['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
    if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft')  rotate(-ROTATE_STEP);
    if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') rotate(ROTATE_STEP);
});

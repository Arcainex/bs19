// Faction emblems in the hub: crest helper and the emblem workshop tab. Loaded after app.js and uses its helpers.
// Drawing comes from nui://bs_ui/html/shared/emblem.js (window.BSEmblem); the server validates every save.

const EB_COLOURS = [
    '#1b1a17', '#2c2a24', '#4a4741', '#8f8c83', '#e8e2d4', '#efe4cc',
    '#4b5531', '#323a20', '#2d3b2b', '#7c8f52', '#c6d36b', '#8fbf7a',
    '#7e221b', '#a8453a', '#e46a5c', '#5a1d10', '#3b1f3d', '#d7b7e0',
    '#c9a24d', '#e2bd63', '#e08c46', '#f08a2a', '#8f6f2a', '#5b4630',
    '#27303c', '#3c4b5f', '#5a6f8a', '#1f3140', '#c9d1d6', '#d9d4c7',
];
const EB_SECTIONS = [['presets', 'PRESETS'], ['shape', 'SHAPE'], ['pattern', 'PATTERN'], ['symbol', 'SYMBOL'], ['colours', 'COLOURS'], ['finish', 'FINISH']];

// i18n only fills {vars} for keys it has, so the English fallback is filled here too
const ebT = (k, fb, v) => String(tr('eb.' + k, Object.assign({ fallback: fb }, v || {}))).replace(/\{(\w+)\}/g, (m, n) => (v && v[n] !== undefined ? String(v[n]) : m));
const ebLabel = (id) => ebT('o.' + id, window.BSEmblem ? BSEmblem.catalog.label(id) : id);

// The spec to draw for a faction entry: its emblem, the old logo, or a stable default from the id.
function emblemSpec(entry) {
    const E = window.BSEmblem;
    if (!E || !entry) return null;
    if (entry.emblem) return E.normalize(entry.emblem);
    return E.fromLegacy(entry.logo, entry.id || entry.label || '');
}

function factionCrest(entry, small) {
    const spec = emblemSpec(entry && typeof entry === 'object' ? entry : { logo: entry });
    const name = entry && entry.label ? esc(entry.label) : '';
    if (!spec) return `<span class="hx-crest${small ? ' hx-crest--sm' : ''}"></span>`;
    return `<span class="hx-crest${small ? ' hx-crest--sm' : ''}" title="${name}">${BSEmblem.render(spec)}</span>`;
}

// Hero colour comes from the emblem so every faction page feels like its own.
function factionTint(entry) {
    const s = emblemSpec(entry);
    if (!s) return '';
    const lum = (h) => { const n = parseInt(h.slice(1), 16); return (0.3 * (n >> 16) + 0.59 * ((n >> 8) & 255) + 0.11 * (n & 255)) / 255; };
    const tint = lum(s.primary) > 0.12 && lum(s.primary) < 0.8 ? s.primary : s.accent;
    // text needs to stand out on dark panels
    const text = [s.accent, s.primary, s.secondary].sort((a, b) => lum(b) - lum(a))[0];
    return `--fc:${tint};--fa:${lum(text) > 0.35 ? text : '#e9e2d0'}`;
}

/* workshop state */
S.eb = null;

function ebOpen(ctx) {
    const spec = ctx.spec ? BSEmblem.normalize(ctx.spec) : BSEmblem.normalize(BSEmblem.presets[0].spec);
    S.eb = { fid: ctx.fid, admin: !!ctx.admin, label: ctx.label || '', canEdit: ctx.canEdit !== false, custom: !!ctx.custom, isConfig: !!ctx.isConfig,
        spec, saved: JSON.stringify(spec), sec: S.eb && S.eb.fid === ctx.fid ? S.eb.sec : 'presets' };
}

function ebDirty() { return S.eb && JSON.stringify(S.eb.spec) !== S.eb.saved; }

function ebThumb(over) {
    const s = Object.assign({}, S.eb.spec, over, { wear: 'none' });
    return BSEmblem.render(s);
}

const ebBtn = (label, act, cls) => `<button class="hx-btn hx-btn--sm ${cls || ''}" data-eb="${act}">${label}</button>`;

function ebOptions(key, list) {
    return `<div class="eb__grid">${list.map((id) => {
        const on = S.eb.spec[key] === id;
        return `<button class="eb__opt${on ? ' is-on' : ''}" data-eb="set" data-k="${key}" data-v="${esc(id)}" aria-pressed="${on}">${ebThumb({ [key]: id, tag: key === 'symbol' ? '' : S.eb.spec.tag })}<span>${esc(ebLabel(id))}</span></button>`;
    }).join('')}</div>`;
}

function ebColourRow(key, label, note) {
    const cur = S.eb.spec[key];
    const sw = EB_COLOURS.map((c) => `<button style="--sw:${c}" class="${c === cur ? 'is-on' : ''}" data-eb="set" data-k="${key}" data-v="${c}" title="${c}"></button>`).join('');
    return `<div class="eb__colour"><span>${label}<small>${note}</small></span><div class="eb__sw">${sw}<input type="color" value="${cur}" data-ebin="${key}" aria-label="${label}"><input class="hx-in" maxlength="7" value="${cur}" data-ebhex="${key}" aria-label="${label}"></div></div>`;
}

function ebPanel() {
    const C = BSEmblem.catalog, sec = S.eb.sec;
    let body = '';
    if (sec === 'presets') {
        body = `<div class="eb__grid eb__grid--presets">${BSEmblem.presets.map((p) => `<button class="eb__opt" data-eb="preset" data-id="${esc(p.id)}">${BSEmblem.render(Object.assign({}, p.spec, { tag: S.eb.spec.tag || p.spec.tag }))}<span>${esc(p.name)}</span></button>`).join('')}</div>`;
    } else if (sec === 'shape') body = ebOptions('shape', C.shapes);
    else if (sec === 'pattern') body = ebOptions('pattern', C.patterns);
    else if (sec === 'symbol') body = ebOptions('symbol', C.symbols);
    else if (sec === 'colours') {
        body = ebColourRow('primary', ebT('primary', 'FIELD'), ebT('primary_n', 'Main colour of the emblem.'))
            + ebColourRow('secondary', ebT('secondary', 'PATTERN'), ebT('secondary_n', 'Stripes, bands and split fields.'))
            + ebColourRow('accent', ebT('accent', 'SYMBOL'), ebT('accent_n', 'Symbol, rim and tag plate.'))
            + `<div class="hx-form">${ebBtn(ebT('swap', 'SWAP FIELD / PATTERN'), 'swap')}${ebBtn(ebT('invert', 'SWAP FIELD / SYMBOL'), 'invert')}</div>`;
    } else {
        const chips = (key, list) => list.map((id) => `<button class="hx-btn hx-btn--sm${S.eb.spec[key] === id ? ' is-sel' : ''}" data-eb="set" data-k="${key}" data-v="${id}">${esc(ebLabel(id))}</button>`).join('');
        body = `<div class="eb__row"><span>${ebT('border', 'BORDER')}</span><div class="eb__chips">${chips('border', C.borders)}</div></div>`
            + `<div class="eb__row"><span>${ebT('wear', 'WEAR')}</span><div class="eb__chips">${chips('wear', C.wear)}</div></div>`
            + `<div class="eb__row"><span>${ebT('tag', 'TAG')}</span><div class="eb__chips"><input class="hx-in eb__tagin" maxlength="${C.tagMax}" value="${esc(S.eb.spec.tag)}" data-ebtag placeholder="----">${ebBtn(ebT('tag_faction', 'USE FACTION TAG'), 'tagFaction')}${ebBtn(ebT('tag_none', 'NO TAG'), 'tagNone')}<p class="hx-muted" style="flex-basis:100%;margin:4px 0 0">${ebT('tag_n', 'Up to {n} letters or numbers, stamped on a plate under the symbol.', { n: C.tagMax })}</p></div></div>`;
    }
    const secs = EB_SECTIONS.map(([id, fb]) => `<button class="eb__sec${id === sec ? ' is-on' : ''}" data-eb="sec" data-id="${id}">${ebT('s_' + id, fb)}</button>`).join('');
    return `<div class="eb__secs" role="tablist">${secs}</div><div id="ebOpts">${body}</div>`;
}

function ebFlag(spec) {
    return `<div class="eb__flag"><span style="background:linear-gradient(90deg,${spec.secondary} 0 18%,${spec.primary} 18%)"></span><i>${BSEmblem.render(Object.assign({}, spec, { tag: '' }))}</i></div>`;
}

function ebBench() {
    const s = S.eb.spec, dirty = ebDirty();
    return `<p class="eb__title">${esc(S.eb.label)}</p>
        <div class="eb__big" id="ebBig">${BSEmblem.render(s)}</div>
        <div class="eb__minis" id="ebMinis"><div>${BSEmblem.render(s, { size: 64 })}${ebT('m_hub', 'Hub')}</div><div>${BSEmblem.render(s, { size: 32 })}${ebT('m_tag', 'Name tag')}</div><div>${ebFlag(s)}${ebT('m_flag', 'Banner')}</div></div>
        ${S.eb.canEdit ? `<div class="eb__acts">
            <button class="hx-btn hx-btn--go" data-eb="save"${dirty ? '' : ' disabled'}>${ebT('save', 'SAVE EMBLEM')}</button>
            <button class="hx-btn" data-eb="revert"${dirty ? '' : ' disabled'}>${ebT('revert', 'UNDO CHANGES')}</button>
            <button class="hx-btn hx-btn--bad" data-eb="reset"${S.eb.custom ? '' : ' disabled'}>${ebT(S.eb.isConfig ? 'reset_cfg' : 'reset', S.eb.isConfig ? 'BACK TO DEFAULT' : 'REMOVE')}</button>
        </div>` : ''}
        <p class="eb__note">${S.eb.canEdit ? (dirty ? ebT('unsaved', 'Unsaved changes.') : ebT('saved_n', 'Everyone sees this on the hub, name tags and banners.')) : ebT('view_only', 'Only the leader or ranks with the Emblem permission can change this.')}</p>`;
}

function ebMarkup() {
    if (!window.BSEmblem) return empty(ebT('missing', 'Emblems are not loaded (bs_ui).'));
    return `<div class="eb" id="ebRoot"><aside class="eb__bench" id="ebBench">${ebBench()}</aside><section class="eb__panel" id="ebPanel">${ebPanel()}</section></div>`;
}

function ebRefresh(panelToo) {
    const b = document.getElementById('ebBench'); if (b) b.innerHTML = ebBench();
    if (panelToo) { const p = document.getElementById('ebPanel'); if (p) p.innerHTML = ebPanel(); }
}

function ebSet(k, v) {
    S.eb.spec = BSEmblem.normalize(Object.assign({}, S.eb.spec, { [k]: v }));
    ebRefresh(true);
}

// Own faction tab.
HUB_RENDER.emblem = (f) => {
    const fac = f.faction;
    if (!fac) return empty(tr('m.you_are_not_in_a_faction', { fallback: 'You are not in a faction.' }));
    if (!S.eb || S.eb.admin || S.eb.fid !== fac.id) ebOpen({ fid: fac.id, label: fac.label, spec: emblemSpec(fac), canEdit: !!fac.canEditEmblem, custom: !!fac.emblemCustom, isConfig: !!fac.lore });
    return card(ebT('title', 'EMBLEM WORKSHOP'), ebMarkup(), 'hx-wide');
};

async function ebSave(reset) {
    const E = S.eb;
    const r = E.admin
        ? await fx('factions:admin:emblem', reset ? { id: E.fid, reset: true } : { id: E.fid, spec: E.spec })
        : await fx('factions:emblem:set', reset ? { reset: true } : { spec: E.spec });
    if (!r || !r.ok) return;
    toast(reset ? ebT('t_reset', 'Emblem reset.') : ebT('t_saved', 'Emblem saved.'));
    const spec = BSEmblem.normalize(r.emblem || E.spec);
    E.spec = spec; E.saved = JSON.stringify(spec); E.custom = !!r.custom;
    const apply = (x) => { if (x && x.id === E.fid) { x.emblem = r.emblem || null; x.emblemCustom = !!r.custom; } };
    if (S.faction) { apply(S.faction.faction); (S.faction.directory || []).forEach(apply); (S.faction.adminFactions || []).forEach(apply); }
    if (S.adm && S.adm.detail) { apply(S.adm.detail); S.adm.overview = null; }
    renderStage();
}

(function wireEmblemWorkshop() {
    const stage = $('stage');
    if (!stage) return;
    stage.addEventListener('click', (e) => {
        const b = e.target.closest('[data-eb]');
        if (!b || !S.eb || b.disabled) return;
        const a = b.dataset.eb;
        if (a === 'sec') { S.eb.sec = b.dataset.id; return ebRefresh(true); }
        if (!S.eb.canEdit) return;
        if (a === 'set') return ebSet(b.dataset.k, b.dataset.v);
        if (a === 'preset') {
            const p = BSEmblem.presets.find((x) => x.id === b.dataset.id);
            if (p) { S.eb.spec = BSEmblem.normalize(Object.assign({}, p.spec, { tag: S.eb.spec.tag || p.spec.tag })); ebRefresh(true); }
            return;
        }
        if (a === 'swap') { const s = S.eb.spec; S.eb.spec = BSEmblem.normalize(Object.assign({}, s, { primary: s.secondary, secondary: s.primary })); return ebRefresh(true); }
        if (a === 'invert') { const s = S.eb.spec; S.eb.spec = BSEmblem.normalize(Object.assign({}, s, { primary: s.accent, accent: s.primary })); return ebRefresh(true); }
        if (a === 'tagFaction') {
            const tag = BSEmblem.cleanTag(S.eb.admin ? ((S.adm.detail || {}).short || '') : (((S.faction || {}).faction || {}).short || ''));
            return ebSet('tag', tag);
        }
        if (a === 'tagNone') return ebSet('tag', '');
        if (a === 'revert') { S.eb.spec = BSEmblem.normalize(JSON.parse(S.eb.saved)); return ebRefresh(true); }
        if (a === 'save') return once(() => ebSave(false));
        if (a === 'reset') { if (!armed(b)) return; return once(() => ebSave(true)); }
        if (a === 'close') { S.adm.emblem = false; return renderStage(); }
    });
    stage.addEventListener('input', (e) => {
        const el = e.target;
        if (!S.eb || !el.dataset) return;
        if (el.dataset.ebin) { S.eb.spec = BSEmblem.normalize(Object.assign({}, S.eb.spec, { [el.dataset.ebin]: el.value })); ebRefresh(false); const hx = document.querySelector(`[data-ebhex="${el.dataset.ebin}"]`); if (hx) hx.value = el.value; }
        else if (el.dataset.ebhex && /^#[0-9a-f]{6}$/i.test(el.value)) { S.eb.spec = BSEmblem.normalize(Object.assign({}, S.eb.spec, { [el.dataset.ebhex]: el.value })); ebRefresh(false); }
        else if (el.dataset.ebtag !== undefined) {
            const v = BSEmblem.cleanTag(el.value);
            if (v !== el.value) el.value = v;
            S.eb.spec = BSEmblem.normalize(Object.assign({}, S.eb.spec, { tag: v }));
            ebRefresh(false);
        }
    });
    // colour pickers settle on change: redraw the swatch rows too
    stage.addEventListener('change', (e) => { if (S.eb && e.target.dataset && (e.target.dataset.ebin || e.target.dataset.ebhex)) ebRefresh(true); });
})();

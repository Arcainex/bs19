// bs_vip panel (F7). Tabs: overview, customise, appearance, vehicles, settings. Changes go back through Lua and the server validates them.
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// Translations from nui://bs_ui/html/js/i18n.js (t is a common local name in here).
const tr = (k, v) => (window.BSI18n ? window.BSI18n.t(k, v) : k);
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'bs_vip';
function post(action, data) {
    return fetch(`https://${RES}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) })
        .then((r) => r.json()).catch(() => null);
}

const S = { tab: 'overview', cfg: null, data: null };
const st = () => (S.data && S.data.status) || {};
const lvl = () => Number(st().level) || 0;
const prefs = () => st().prefs || {};
const perk = (id) => (S.cfg.perks || []).find((p) => p.id === id) || { minTier: 9 };
const has = (id) => lvl() >= perk(id).minTier;
const tierByLevel = (n) => (S.cfg.tiers || []).find((t) => t.level === n);
const tierColour = () => st().colour || '#e08c46';

let toastT;
function toast(msg, bad) {
    const t = $('toast'); t.textContent = msg; t.classList.toggle('bad', !!bad); t.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 2400);
}

// Colours this player may pick: palette + tier colours up to their tier.
function colours() {
    const out = (S.cfg.palette || []).map((c) => ({ hex: c.hex.toLowerCase(), label: c.label }));
    (S.cfg.tiers || []).forEach((t) => { if (t.level <= lvl()) out.push({ hex: t.colour.toLowerCase(), label: t.label }); });
    return out;
}
function swatches(key, current, kind) {
    const cur = (current || '').toLowerCase();
    return `<div class="chips"><button class="sw sw--none${cur ? '' : ' on'}" title="${tr('vip.default')}" data-${kind}="${key}" data-v=""></button>` +
        colours().map((c) => `<button class="sw${cur === c.hex ? ' on' : ''}" style="--c:${c.hex}" title="${esc(c.label)}" data-${kind}="${key}" data-v="${c.hex}"></button>`).join('') + '</div>';
}
function chips(key, list, current, kind = 'pref') {
    return '<div class="chips">' + (list || []).map((x) =>
        `<button class="chip${String(current) === String(x.id) ? ' on' : ''}" data-${kind}="${key}" data-v="${esc(x.id)}" data-num="${typeof x.id === 'number' ? 1 : 0}">${esc(x.label)}</button>`).join('') + '</div>';
}
function card(title, perkId, inner, i, wide) {
    const locked = perkId && !has(perkId);
    const t = locked ? tierByLevel(perk(perkId).minTier) : null;
    return `<div class="card${wide ? ' card--wide' : ''}${locked ? ' locked' : ''}" style="--i:${i || 0}"${locked ? ` data-lock="${esc((t ? t.label : 'VIP').toUpperCase())} ${tr('vip.tier')}"` : ''}><h3>${esc(title)}</h3>${inner}</div>`;
}

// overview
function renderOverview() {
    const s = st(), t = tierByLevel(lvl());
    const exp = s.expiresAt ? new Date(s.expiresAt).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : null;
    if (s.open) {
        // VIP switched off by the server owner: no tiers, everything open
        const heroOpen = `<div class="hero"><div class="hero__badge">*</div><div><h2>${tr('vip.open_title')}</h2><p class="muted">${tr('vip.open_note')}</p></div></div>`;
        const list = (S.cfg.perks || []).map((p) => `<div class="perk"><b>${esc(tr('vip.perk_' + p.id, { fallback: p.label }))}</b><small>${tr('vip.active')}</small></div>`).join('');
        return heroOpen + `<div class="grid">${card(tr('vip.perks'), null, list, 0, true)}</div>`;
    }
    const hero = `<div class="hero"><div class="hero__badge">${t ? ['', 'I', 'II', 'III'][t.level] : '-'}</div><div>
        <h2>${t ? esc(t.label.toUpperCase()) : tr('vip.no_tier')}</h2>
        <p class="muted">${t ? (exp ? tr('vip.active_until', { d: esc(exp) }) : tr('vip.no_expiry')) + (s.title ? ' · ' + tr('vip.title_is', { t: esc(s.title) }) : '') : tr('vip.cosmetic_only')}</p>
        <div class="tiers">${(S.cfg.tiers || []).map((x) => `<span style="--c:${x.colour}" class="${x.level <= lvl() ? 'have' : ''}">${esc(x.label.toUpperCase())}</span>`).join('')}</div></div></div>`;
    const perks = (S.cfg.perks || []).map((p) => {
        const on = lvl() >= p.minTier, tt = tierByLevel(p.minTier);
        const extra = p.bonus ? ` +${p.bonus}` : (p.pct ? ` ${p.pct}%` : '');
        return `<div class="perk${on ? '' : ' off'}"><b>${esc(tr('vip.perk_' + p.id, { fallback: p.label }))}${esc(extra)}</b><small style="color:${on ? tt.colour : ''}">${on ? tr('vip.active') : esc(tt.label.toUpperCase())}</small></div>`;
    }).join('');
    return hero + `<div class="grid">${card(tr('vip.perks'), null, perks, 0, true)}</div>`;
}

// customise
function tagPreview() {
    const p = prefs(), style = has('tagStyle') && p.tagStyle && p.tagStyle !== 'default' ? p.tagStyle : 'plainbr';
    const c = (has('tagStyle') && p.tagHex) || '#e08c46';
    return `<div class="prev"><div class="tag tag--${esc(style)}" style="--c:${esc(c)}"><div class="tag__g"><span class="tag__br tag__br--l"></span>${tr('vip.squad')}<span class="tag__br tag__br--r"></span></div><div class="tag__rule"></div><div class="tag__n">${esc((S.data.name || tr('vip.survivor')).toUpperCase())}</div></div></div>`;
}
function chatPreview() {
    const p = prefs(), t = tierByLevel(lvl());
    const badge = t && p.chatBadge !== false ? `<span class="bdg" style="color:${t.colour};border-color:${t.colour}">${esc(t.label.toUpperCase())}</span>` : '';
    return `<div class="prev chatl">${badge}<span class="nm" style="color:${esc(p.chatHex || '#e08c46')}">${esc(S.data.name || tr('vip.survivor'))}</span><span>${tr('vip.chat_sample')}</span></div>`;
}
function combatPreview() {
    const f = S.data.fx || {};
    const hi = f.hbHigh || '#c8763a', mid = f.hbMid || '#b05424', lo = f.hbLow || '#963428', hm = f.hmHex || '#e6dcc6';
    return `<div class="prev"><div class="hb">${[hi, hi, hi, hi, hi, mid, mid, lo, lo, lo].map((c, i) => `<i style="--c:${c};opacity:${i < 7 ? 1 : .25}"></i>`).join('')}</div><div class="hm" style="--c:${hm}"><i></i><i></i><i></i><i></i></div></div>`;
}
function renderCustom() {
    const p = prefs(), f = S.data.fx || {};
    const stashes = (S.data.stashes || []).map((s) => `<div class="row"><input type="text" maxlength="40" value="${esc(s.label)}" data-stashinput="${s.id}"><button class="btn" data-stash="${s.id}">${tr('vip.rename')}</button></div>`).join('') || `<p class="muted">${tr('vip.nothing_buried')}</p>`;
    return '<div class="grid">' + [
        card(tr('vip.name_tag'), 'tagStyle', tagPreview() + '<div class="lbl">' + tr('vip.style') + '</div>' + chips('tagStyle', S.cfg.tagStyles, p.tagStyle || 'default') + '<div class="lbl">' + tr('vip.colour') + '</div>' + swatches('tagHex', p.tagHex, 'pref'), 0),
        card(tr('vip.chat'), 'chatBadge', chatPreview() + `<div class="row"><span>${tr('vip.show_badge')}</span><button class="sw-tg${p.chatBadge !== false ? ' on' : ''}" data-bool="chatBadge"></button></div><div class="lbl">${tr('vip.name_colour')}</div>` + swatches('chatHex', p.chatHex, 'pref'), 1),
        card(tr('vip.blip'), 'blipColour', '<p>' + tr('vip.blip_note') + '</p>' + chips('blipColour', S.cfg.blipColours, p.blipColour ?? 2), 2),
        card(tr('vip.squad_hud'), 'hudColour', `<div class="prev"><span style="color:${esc(p.hudHex || '#e6dcc6')};font-weight:700;letter-spacing:.06em">${esc((S.data.name || tr('vip.survivor')).toUpperCase())}</span></div><div class="lbl">${tr('vip.hud_colour')}</div>` + swatches('hudHex', p.hudHex, 'pref'), 3),
        card(tr('vip.combat_colours'), 'combatColours', combatPreview() +
            '<div class="lbl">' + tr('vip.bar_full') + '</div>' + swatches('hbHigh', f.hbHigh, 'fx') + '<div class="lbl">' + tr('vip.bar_hurt') + '</div>' + swatches('hbMid', f.hbMid, 'fx') +
            '<div class="lbl">' + tr('vip.bar_low') + '</div>' + swatches('hbLow', f.hbLow, 'fx') + '<div class="lbl">' + tr('vip.hit_marker') + '</div>' + swatches('hmHex', f.hmHex, 'fx'), 4),
        card(tr('vip.stash'), 'stashSkin', '<p>' + tr('vip.stash_note') + '</p>' + chips('stashSkin', S.cfg.stashSkins, p.stashSkin || 'none'), 5),
        card(tr('vip.stash_names'), 'stashName', stashes, 6),
        card(tr('vip.boosters'), 'boosterSkins', '<div class="lbl">' + tr('vip.drone_marks') + '</div>' + chips('droneSkin', S.cfg.droneSkins, p.droneSkin || 'default') + '<div class="lbl">' + tr('vip.turret_finish') + '</div>' + chips('turretSkin', S.cfg.turretSkins, p.turretSkin || 'default'), 7),
        card(tr('vip.killfeed_death'), 'killfeedStyle', '<div class="lbl">' + tr('vip.killfeed') + '</div>' + chips('killfeed', S.cfg.killfeed, p.killfeed || 'default') + '<div class="lbl">' + tr('vip.death_screen') + '</div>' + chips('deathscreen', S.cfg.deathscreen, p.deathscreen || 'default'), 8),
        card(tr('vip.banner'), 'profileBanner', chips('banner', S.cfg.banners, p.banner || 'none'), 9),
        card(tr('vip.emotes'), 'emoteFavourites', `<p>${has('emoteFavourites') ? tr('vip.fav_active', { n: perk('emoteFavourites').bonus }) : tr('vip.fav_extra')} ${has('exclusiveEmotes') ? tr('vip.exclusive') : ''}</p><br><button class="btn" data-act="openEmotes">${tr('vip.open_emotes')}</button>`, 10),
    ].join('') + '</div>';
}

// appearance
function renderAppearance() {
    const a = st().appearance || {};
    const can = a.free || (a.tickets || 0) > 0;
    const monthly = a.perk
        ? (a.free ? tr('vip.free_ready') : tr('vip.free_used'))
        : tr('vip.free_with', { tier: esc((tierByLevel(perk('appearanceChange').minTier) || {}).label || 'VIP') });
    return '<div class="grid">' +
        card(tr('vip.monthly'), null, `<p>${monthly}</p><br><div class="big">${a.free ? tr('vip.ready') : '-'}</div>`, 0) +
        card(tr('vip.tickets'), null, `<p>${tr('vip.tickets_note')}</p><br><div class="big">${a.tickets || 0}</div>`, 1) +
        card(tr('vip.edit_face'), null, `<p>${tr('vip.edit_face_note')}</p><br><button class="btn" data-act="appearance"${can ? '' : ' disabled'}>${can ? tr('vip.open_creator') : tr('vip.nothing_available')}</button>`, 2, true) +
        '</div>';
}

// vehicles
function plateCheck(t) {
    t = (t || '').toUpperCase().trim();
    const P = S.cfg.plate || { min: 1, max: 8 };
    if (t.length < P.min || t.length > P.max) return tr('vip.plate_len', { min: P.min, max: P.max });
    if (!/^[A-Z0-9 ]+$/.test(t)) return tr('vip.plate_chars');
    return '';
}
function renderVehicles() {
    const v = S.data.vehicle;
    const body = v
        ? `<p>${tr('vip.driving', { model: '<b>' + esc(v.model) + '</b>' })}</p><br>
           <div class="prev"><span class="plate" id="platePrev">${esc(v.plate)}</span></div>
           <div class="row"><input type="text" id="plateIn" maxlength="${(S.cfg.plate || {}).max || 8}" placeholder="${tr('vip.new_plate')}" value=""><button class="btn" data-act="plate">${tr('vip.apply')}</button></div><div class="err" id="plateErr"></div>`
        : `<p>${tr('vip.sit_driver')}</p>`;
    return '<div class="grid">' + card(tr('vip.plate_text'), 'plateText', body, 0, true) + '</div>';
}

// settings
function tg(key, on, label, note, kind = 'fxbool') {
    return `<div class="row"><span>${esc(label)}<small>${esc(note)}</small></span><button class="sw-tg${on ? ' on' : ''}" data-${kind}="${key}"></button></div>`;
}
function renderSettings() {
    const f = S.data.fx;
    const fx = f ? tg('zombieHealthBars', f.zombieHealthBars, tr('vip.s_hb'), tr('vip.s_hb_n')) +
        `<div class="row"><span>${tr('vip.s_linger')}<small>${tr('vip.s_linger_n')}</small></span><span><input type="range" min="1" max="15" value="${f.healthBarLinger || 5}" data-fxrange="healthBarLinger"> <b id="lingerV">${f.healthBarLinger || 5}s</b></span></div>` +
        tg('hitMarker', f.hitMarker, tr('vip.s_hm'), tr('vip.s_hm_n')) + tg('hitMarkerVisual', f.hitMarkerVisual, tr('vip.s_hmx'), tr('vip.s_hmx_n')) +
        tg('hitMarkerHead', f.hitMarkerHead, tr('vip.s_head'), tr('vip.s_head_n')) + tg('hitMarkerKill', f.hitMarkerKill, tr('vip.s_kill'), tr('vip.s_kill_n')) +
        tg('hitMarkerHeadOnly', f.hitMarkerHeadOnly, tr('vip.s_headonly'), tr('vip.s_headonly_n'))
        : `<p class="muted">${tr('vip.no_zombies')}</p>`;
    const chat = S.data.chatView === null || S.data.chatView === undefined ? `<p class="muted">${tr('vip.no_chat')}</p>`
        : tg('chat', S.data.chatView, tr('vip.s_chat'), tr('vip.s_chat_n'), 'chatview');
    return '<div class="grid">' + card(tr('vip.combat_all'), null, fx, 0) + card(tr('vip.chat'), null, chat, 1) + '</div>';
}

// render
const VIEWS = { overview: renderOverview, custom: renderCustom, appearance: renderAppearance, vehicles: renderVehicles, settings: renderSettings };
function render() {
    document.documentElement.style.setProperty('--tier', tierColour());
    const t = tierByLevel(lvl());
    $('tierLine').innerHTML = t ? `${tr('vip.tier')} <b>${esc(t.label.toUpperCase())}</b>` : tr('vip.no_tier');
    document.querySelectorAll('#tabs button').forEach((b) => b.classList.toggle('on', b.dataset.tab === S.tab));
    const y = $('body').scrollTop;
    $('body').innerHTML = VIEWS[S.tab]();
    $('body').scrollTop = y;
}

async function setPref(key, value) {
    const r = await post('setPref', { key, value });
    if (!r || !r.ok) return toast((r && r.error) || tr('vip.cant_save'), true);
    st().prefs = r.prefs; render();
}
async function setFx(key, value) {
    const r = await post('setFx', { key, value });
    if (!r || !r.ok) return toast((r && r.error) || tr('vip.cant_change'), true);
    S.data.fx = r.options; render();
}

$('tabs').addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; S.tab = b.dataset.tab; $('body').scrollTop = 0; render(); });
$('btnClose').addEventListener('click', () => post('close'));

$('body').addEventListener('click', async (e) => {
    const el = e.target.closest('button'); if (!el || el.disabled) return;
    const d = el.dataset;
    if (d.pref !== undefined) return setPref(d.pref, d.num === '1' ? Number(d.v) : d.v);
    if (d.fx !== undefined) return setFx(d.fx, d.v);
    if (d.bool !== undefined) return setPref(d.bool, !el.classList.contains('on'));
    if (d.fxbool !== undefined) return setFx(d.fxbool, !el.classList.contains('on'));
    if (d.chatview !== undefined) { const r = await post('setChatView', { on: !el.classList.contains('on') }); if (r && r.ok) { S.data.chatView = r.on; render(); } return; }
    if (d.stash !== undefined) {
        const inp = document.querySelector(`[data-stashinput="${d.stash}"]`);
        const r = await post('renameStash', { id: Number(d.stash), label: inp ? inp.value : '' });
        return toast(r && r.ok ? tr('vip.stash_renamed') : ((r && r.error) || tr('vip.cant_rename')), !(r && r.ok));
    }
    if (d.act === 'appearance') return post('appearance');
    if (d.act === 'openEmotes') return post('openEmotes');
    if (d.act === 'plate') {
        const v = $('plateIn').value, bad = plateCheck(v);
        if (bad) { $('plateErr').textContent = bad; return; }
        el.disabled = true;
        const r = await post('setPlate', { text: v });
        el.disabled = false;
        if (!r || !r.ok) { $('plateErr').textContent = (r && r.error) || tr('vip.cant_plate'); return; }
        S.data.vehicle.plate = r.plate; toast(tr('vip.plate_changed', { plate: r.plate })); render();
    }
});
$('body').addEventListener('input', (e) => {
    if (e.target.id === 'plateIn') {
        e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9 ]/g, '');
        $('platePrev').textContent = e.target.value || (S.data.vehicle || {}).plate || '';
        $('plateErr').textContent = e.target.value ? plateCheck(e.target.value) : '';
    }
    if (e.target.dataset.fxrange) $('lingerV').textContent = e.target.value + 's';
});
$('body').addEventListener('change', (e) => { if (e.target.dataset.fxrange) setFx(e.target.dataset.fxrange, Number(e.target.value)); });

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.cfg = m.config || {}; S.data = m.data || {};
        if (!S.data.status) S.data.status = { level: 0, prefs: {} };
        $('keyHint').textContent = tr('vip.key_hint', { key: S.cfg.key || 'F7' });
        $('root').classList.remove('hidden');
        render();
    } else if (m.action === 'close') {
        $('root').classList.add('hidden');
    }
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close'); });
if (window.BSI18n) BSI18n.onChange(() => { if (S.cfg && S.data) render(); });

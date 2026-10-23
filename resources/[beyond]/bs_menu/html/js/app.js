// BeyondSurvival hub - entries either render here or hand off to another resource. Renders a server snapshot and decides nothing itself.

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'bs_menu';

const $ = (id) => document.getElementById(id);
// Translations from nui://bs_ui/html/js/i18n.js; t is a common local name in here, so use tr.
const tr = (k, v) => (window.BSI18n ? window.BSI18n.t(k, v) : k);

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

const ICONS = {
    bag:   'M6 8h12l-1 12H7L6 8zm3 0V6a3 3 0 0 1 6 0v2',
    heart: 'M12 20s-7-4.35-7-9a4 4 0 0 1 7-2.65A4 4 0 0 1 19 11c0 4.65-7 9-7 9z',
    star:  'M12 3l2.6 5.6 6 .8-4.4 4.2 1.1 6.1L12 16.9 6.7 19.7l1.1-6.1L3.4 9.4l6-.8L12 3z',
    gear:  'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2',
    hand:  'M8 13V5.5a1.5 1.5 0 0 1 3 0V12m0-1.5a1.5 1.5 0 0 1 3 0V12m0-1a1.5 1.5 0 0 1 3 0v5a5 5 0 0 1-5 5h-1a5 5 0 0 1-4.3-2.5L5 15.5a1.6 1.6 0 0 1 2.6-1.8L8 14',
    shirt: 'M8 3l4 2 4-2 4 3-2.5 3L17 21H7l-.5-12L4 6l4-3z',
    anvil: 'M4 8h9l3 3h4v3a4 4 0 0 1-4 4H9l-5-5V8zm3 13h10',
    wall:  'M3 6h18v12H3V6zm0 6h18M9 6v6m6-6v6m-3 6v-6',
};

function icon(name, cls) {
    return `<svg class="${cls || ''}" viewBox="0 0 24 24" fill="none" stroke="currentColor"
             stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="${ICONS[name] || ICONS.star}"/></svg>`;
}

const S = { entries: [], data: null, current: null, emotes: [], clothing: [], recipes: [], build: null, faction: null };

// Pulls a fresh server snapshot and re-renders the open panel, so the hub is never stale.
async function loadSkillPanel() {
    const r = await post('refresh');
    if (r && r.ok && r.data) { S.data = r.data; renderStage(); }
}

async function refresh() {
    const r = await post('refresh');
    if (r && r.ok && r.data) { S.data = r.data; renderStage(); }
}

// One request at a time: every skill action rebuilds the panel when it returns, so parallel clicks left dead handlers and a stuck hub. Extra clicks while one is in flight are ignored.
let actionBusy = false;

async function once(fn) {
    if (actionBusy) return null;
    actionBusy = true;
    try {
        return await fn();
    } catch (e) {
        // Never leave the flag stuck: a thrown request must not wedge the hub.
        return null;
    } finally {
        actionBusy = false;
    }
}

function num(n) {
  return Math.floor(Number(n) || 0).toLocaleString('en-GB');
}
function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function playtime(seconds) {
    const h = Math.floor((seconds || 0) / 3600);
    const m = Math.floor(((seconds || 0) % 3600) / 60);
    if (h < 1) return `${m}m`;
    return `${h}h ${m}m`;
}

// rail

function renderRail() {
    const rail = $('rail');
    rail.innerHTML = '';

    S.entries.forEach((e) => {
        const b = document.createElement('button');
        b.className = 'rail__item' + (S.current === e.id ? ' is-active' : '');
        b.innerHTML = `
            ${icon(e.icon, 'rail__icon')}
            <span>${esc(e.label).toUpperCase()}
                <span class="rail__blurb">${esc(e.blurb || '')}</span>
            </span>`;
        b.addEventListener('click', () => choose(e));
        rail.appendChild(b);
    });
}

function choose(entry) {
    if (entry.kind === 'panel') {
        S.current = entry.id;
        renderRail();
        renderStage();
    }
    post('pick', { id: entry.id });
}

// stage

// Stats rows stack label above value so long values (e.g. XP pair) cannot overlap a neighbour. `wide` spans the whole grid for long values.
function row(k, v, cls, wide) {
    return `<div class="row ${wide ? 'row--wide' : ''}">
              <span class="row__k">${esc(k).toUpperCase()}</span>
              <span class="row__v ${cls || ''}">${esc(v)}</span>
            </div>`;
}

// A throwing render would leave the hub half-drawn with no handlers; the guard shows a visible message instead.
function renderStage() {
    try {
        renderStageInner();
    } catch (e) {
        const stage = $('stage');
        if (stage) {
            stage.innerHTML = `<p class="hollow">${tr('m.render_error')}</p>`;
        }
    }
}

function renderStageInner() {
    const stage = $('stage');
    const d = S.data;

    if (!d) { stage.innerHTML = `<p class="hollow">${tr('m.no_char')}</p>`; return; }

    if (S.current === 'faction') {
        stage.innerHTML = renderFaction();
        wireFaction(stage);
        return;
    }

    if (S.current === 'stats') {
        const needs = d.needs || {};
        const stats = d.stats || {};
        const xpPct = d.xpToNext ? Math.min(100, (d.xp / d.xpToNext) * 100) : 0;

        stage.innerHTML = `
            <div class="block">
                <div class="block__title">${tr('m.condition')}</div>
                <div class="rows">
                    ${row(tr('m.hunger'), `${Math.round(needs.hunger ?? 0)}%`)}
                    ${row(tr('m.thirst'), `${Math.round(needs.thirst ?? 0)}%`)}
                    ${row(tr('m.infection'), `${Math.round(needs.infection ?? 0)}%`,
                          (needs.infection ?? 0) > 35 ? 'row__v--amber' : 'row__v--good')}
                </div>
            </div>

            <div class="block">
                <div class="block__title">${tr('m.progress')}</div>
                <div class="rows">
                    ${row(tr('m.level'), d.level ?? 1, 'row__v--amber')}
                    ${row(tr('m.skill_points'), d.skillPoints ?? 0, (d.skillPoints > 0) ? 'row__v--good' : '')}
                    ${row(tr('m.survived'), playtime(d.playtime))}
                    ${row(tr('m.experience'), `${(d.xp ?? 0).toLocaleString()} / ${(d.xpToNext ?? 0).toLocaleString()}`, '', true)}
                </div>
                <div class="meter"><div class="meter__fill" style="width:${xpPct}%"></div></div>
            </div>

            <div class="block">
                <div class="block__title">${tr('m.origin')} - ${esc(d.class || '').toUpperCase()}</div>
                <div class="rows">
                    ${row(tr('m.max_health'), stats.maxHealth ?? '-')}
                    ${row(tr('m.carry_weight'), stats.carryWeight ? `${stats.carryWeight} kg` : '-')}
                    ${row(tr('m.melee'), stats.melee ? `×${stats.melee}` : '-')}
                    ${row(tr('m.stamina'), stats.stamina ? `×${stats.stamina}` : '-')}
                </div>
            </div>

            <div class="block">
                <!-- NO BANK ROW. "Bank system should not exist" - and a bank
                     balance on a survivor sheet is worse than redundant, it
                     tells the player there is a banking system to go and find.
                     Cash is the only money in this world; what you are
                     carrying is what you have. -->
                <div class="block__title">${tr('m.holdings')}</div>
                <div class="rows">
                    ${row(tr('m.cash'), `$${(d.accounts?.cash ?? 0).toLocaleString()}`)}
                </div>
            </div>`;
        return;
    }

    if (S.current === 'skills') {
        if (!d.skillsReady) {
            stage.innerHTML = `
                <p class="hollow">${tr('m.no_skills_res')}</p>`;
            return;
        }

        const skills = d.skills || {};
        const keys = Object.keys(skills);
        if (!keys.length) { stage.innerHTML = `<p class="hollow">${tr('m.no_skills')}</p>`; return; }

        const points = d.skillPoints ?? 0;

        const head = `
            <div class="points">
                <span class="points__n ${points > 0 ? 'points__n--good' : ''}">${points}</span>
                <span class="points__l">${tr('m.points_unspent', { n: points })}</span>
                <button class="btn btn--ghost" id="respec">${tr('m.unlearn_all')}</button>
            </div>`;

        const trees = keys.sort().map((k) => {
            const s = skills[k];
            const pct = s.xpToNext && isFinite(s.xpToNext)
                ? Math.min(100, (s.xp / s.xpToNext) * 100) : 100;

            const perks = (s.perks || []).map((p) => {
                let state = 'perk--locked';
                let action = `<span class="perk__req">${tr('m.level_n', { n: p.requires })}</span>`;

                if (p.owned) {
                    state = 'perk--owned';
                    action = `<span class="perk__req perk__req--owned">${p.pending ? tr('m.inactive') : tr('m.learned')}</span>`;
                } else if (p.available && points >= p.cost) {
                    state = 'perk--ready';
                    action = `<button class="btn btn--buy" data-tree="${esc(k)}" data-perk="${esc(p.id)}">
                                ${tr('m.learn_pts', { n: p.cost })}</button>`;
                } else if (p.available) {
                    action = `<span class="perk__req">${tr('m.pts', { n: p.cost })}</span>`;
                }

                return `<div class="perk ${state}">
                    <div class="perk__body">
                        <div class="perk__name">${esc(p.label)}${p.pending
                            ? ` <em class="perk__pending">${tr('m.not_impl')}</em>` : ''}</div>
                        <div class="perk__desc">${esc(p.description || '')}</div>
                    </div>
                    <div class="perk__action">${action}</div>
                </div>`;
            }).join('');

            const canTrain = points > 0 && s.level < (s.maxLevel ?? 20);

            return `<div class="block">
                <div class="block__title">${esc(s.label || k).toUpperCase()} - ${tr('m.level_n', { n: s.level ?? 0 })}
                    <span class="block__sub">${esc(s.blurb || '')}</span></div>
                <div class="meter"><div class="meter__fill" style="width:${pct}%"></div></div>
                <div class="meter__caption">${(s.xp ?? 0).toLocaleString()} /
                    ${isFinite(s.xpToNext) ? (s.xpToNext ?? 0).toLocaleString() : '-'} XP</div>

                <div class="trainrow">
                    <span class="trainrow__hint">${tr('m.train_hint')}</span>
                    ${canTrain
                        ? `<button class="btn" data-train="${esc(k)}">${tr('m.train_1')}</button>`
                        : `<span class="perk__req">${points > 0 ? tr('m.at_cap') : tr('m.no_points')}</span>`}
                </div>

                <div class="perks">${perks || `<p class="hollow">${tr('m.no_perks')}</p>`}</div>
            </div>`;
        }).join('');

        stage.innerHTML = head + trees;

        stage.querySelectorAll('.btn[data-train]').forEach((b) => {
            b.addEventListener('click', () => once(async () => {
                b.disabled = true;
                const r = await post('skillTrain', { tree: b.dataset.train });
                // Single refresh per action (loadSkillPanel and refresh used to do the same thing).
                if (r && r.ok) { await refresh(); } else { b.disabled = false; }
            }));
        });

        stage.querySelectorAll('.btn--buy').forEach((b) => {
            b.addEventListener('click', () => once(async () => {
                b.disabled = true;
                const r = await post('skillUnlock', {
                    tree: b.dataset.tree, perk: b.dataset.perk,
                });
                if (r && r.ok) { await refresh(); } else { b.disabled = false; }
            }));
        });

        const respec = $('respec');
        if (respec) {
            respec.addEventListener('click', () => once(async () => {
                respec.disabled = true;
                const r = await post('skillRespec');
                if (r && r.ok) { await refresh(); } else { respec.disabled = false; }
            }));
        }
        return;
    }

    if (S.current === 'emotes') {
        if (!S.emotes.length) {
            stage.innerHTML = `<p class="hollow">${tr('m.no_emotes_res')}</p>`;
            return;
        }

        stage.innerHTML = `
            <p class="hollow hollow--tight">${tr('m.emotes_hint')}</p>` + S.emotes.map((cat) => `
            <div class="block">
                <div class="block__title">${esc(cat.label).toUpperCase()}</div>
                <div class="chips">
                    ${cat.items.map((i) => `
                        <button class="chip" data-emote="${esc(i.id)}">
                            ${esc(i.label)}${i.upper ? `<span class="chip__tag">${tr('m.walkable')}</span>` : ''}
                        </button>`).join('')}
                </div>
            </div>`).join('');

        stage.querySelectorAll('.chip[data-emote]').forEach((b) => {
            b.addEventListener('click', () => post('emote', { id: b.dataset.emote }));
        });
        return;
    }

    if (S.current === 'craft') {
        if (!S.recipes.length) {
            stage.innerHTML = `<p class="hollow">${tr('m.no_recipes')}</p>`;
            return;
        }

        stage.innerHTML = S.recipes.map((r) => {
            const costs = r.costs.map((c) =>
                `<span class="cost ${c.have >= c.need ? '' : 'cost--short'}">
                    ${esc(c.label)} ${c.have}/${c.need}</span>`).join('');

            const gates = (r.requires || []).map((q) =>
                `<span class="cost">${esc(q.skill)} ${q.level}</span>`).join('');

            const station = r.station
                ? `<span class="cost">${tr('m.needs', { what: esc(r.station) })}</span>` : '';

            // Same line-art set as the bag. Recipes carry a category (see sv_crafting.lua) so the icon falls back to it.
            const icon = (typeof BSIcons !== 'undefined')
                ? BSIcons.get(r.result.item, r.result.category) : '';

            return `<div class="perk ${r.canMake ? 'perk--ready' : 'perk--locked'}">
                <div class="perk__icon">${icon}</div>
                <div class="perk__body">
                    <div class="perk__name">${esc(r.label)}
                        ${r.result.amount > 1 ? `<em class="perk__pending">×${r.result.amount}</em>` : ''}</div>
                    <div class="costs">${costs}${gates}${station}</div>
                    ${r.blocked ? `<div class="perk__desc">${esc(r.blocked)}</div>` : ''}
                </div>
                <div class="perk__action">
                    ${r.canMake
                        ? `<button class="btn" data-craft="${esc(r.id)}"
                             data-time="${r.time}">${tr('m.make')}</button>`
                        : '<span class="perk__req">-</span>'}
                </div>
            </div>`;
        }).join('');

        stage.querySelectorAll('.btn[data-craft]').forEach((b) => {
            b.addEventListener('click', async () => {
                const time = Number(b.dataset.time) || 4000;
                b.disabled = true;
                b.textContent = tr('m.working');

                // The bar is the wait. The server re-checks everything when it lands.
                b.style.setProperty('--fill-ms', `${time}ms`);
                b.classList.add('btn--working');
                await new Promise((res) => setTimeout(res, time));

                const r = await post('craft', { id: b.dataset.craft });
                if (r && r.recipes) { S.recipes = r.recipes; }
                renderStage();
            });
        });
        return;
    }

    if (S.current === 'build') {
        if (!S.build) {
            stage.innerHTML = `<p class="hollow">${tr('m.no_build_res')}</p>`;
            return;
        }

        const rows = (S.build.pieces || []).map((p) => {
            const costs = p.costs.map((c) =>
                `<span class="cost ${c.have >= c.need ? '' : 'cost--short'}">
                    ${esc(c.label)} ${c.have}/${c.need}</span>`).join('');

            const tags = [
                p.station ? `<span class="cost">${esc(p.station)}</span>` : '',
                p.respawn ? `<span class="cost">${tr('m.respawn_point')}</span>` : '',
            ].join('');

            return `<div class="perk ${p.canBuild ? 'perk--ready' : 'perk--locked'}">
                <div class="perk__body">
                    <div class="perk__name">${esc(p.label)}${p.pending
                        ? ` <em class="perk__pending">${tr('m.not_impl')}</em>` : ''}</div>
                    <div class="perk__desc">${esc(p.blurb || '')}</div>
                    <div class="costs">${costs}${tags}</div>
                    ${p.blocked ? `<div class="perk__desc">${esc(p.blocked)}</div>` : ''}
                </div>
                <div class="perk__action">
                    ${p.canBuild
                        ? `<button class="btn" data-build="${esc(p.id)}">${tr('m.place')}</button>`
                        : '<span class="perk__req">-</span>'}
                </div>
            </div>`;
        }).join('');

        stage.innerHTML = `
            <div class="points">
                <span class="points__n ${S.build.built >= S.build.max ? '' : 'points__n--good'}">
                    ${S.build.built}</span>
                <span class="points__l">${tr('m.of_standing', { n: S.build.max })}</span>
            </div>
            <p class="hollow hollow--tight">${tr('m.build_hint')}</p>
            <div class="block"><div class="perks">${rows}</div></div>`;

        stage.querySelectorAll('.btn[data-build]').forEach((b) => {
            b.addEventListener('click', () => post('build', { id: b.dataset.build }));
        });
        return;
    }

    stage.innerHTML = `<p class="hollow">${tr('m.choose_left')}</p>`;
}

// faction

// Faction hub. Each tab loads its data from the server on first open and after changes, never on a timer.
S.hub = {}; S.hubBusy = {}; S.hubTab = 'overview'; S.hubLastTab = null; S.rankDraft = null;

async function factionPost(endpoint, data) {
    const r = await post(endpoint, data || {});
    if (r && r.faction) S.faction = r.faction;
    delete S.hub.roster; delete S.hub.treasury;
    renderStage();
}

async function fx(name, args) {
    const r = await post('fx', { name, args: args || {} });
    if (!r || r.ok === false) toast((r && r.error) || tr('m.request_failed'), 'bad');
    return r || { ok: false };
}

function toast(msg, kind) {
    let t = $('hubToast');
    if (!t) { t = document.createElement('div'); t.id = 'hubToast'; document.body.appendChild(t); }
    t.className = 'hub-toast is-' + (kind || 'ok');
    t.textContent = msg;
    void t.offsetWidth;
    t.classList.add('is-on');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.classList.remove('is-on'), 2800);
}

// Looked up through tr so labels follow the player's language; the English stays as fallback.
const labelProxy = (prefix, base) => new Proxy(base, { get: (o, k) => (typeof k === 'string' && k in o ? tr(prefix + k, { fallback: o[k] }) : o[k]) });
const RANK_LABEL = labelProxy('m.rank_', { owner: 'Leader', officer: 'Vice Leader', member: 'Member' });
const RANK_IDX = { owner: 0, officer: 1, member: 2 };
// Ranks are per faction now (custom names); the server sends the label, the fixed three are only a fallback.
const rankName = (m) => (m && (m.rankLabel || RANK_LABEL[m.rank] || m.rank)) || '';
const PERM_LABEL = labelProxy('m.perm_', { deposit: 'Deposit', withdraw: 'Withdraw', invite: 'Invite', kick: 'Kick', promote: 'Promote', sanction: 'Sanction', build: 'Build', demolish: 'Demolish', storage: 'Base storage', jail: 'Jail', squad_manage: 'Squads', skills: 'Skills', raid: 'Declare raids', jobs: 'Jobs' });

function dur(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    if (h) return `${h}h ${m}m`;
    if (m) return `${m}m ${s}s`;
    return `${s}s`;
}
function when(ts) {
    if (!ts) return '-';
    const d = new Date(ts * 1000);
    return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' }) + ' ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}
function card(kicker, inner, cls) {
    return `<article class="hx-card ${cls || ''}"><span class="hx-card__kicker">${kicker}</span>${inner}</article>`;
}
function btn(label, hx, extra, cls) {
    return `<button class="hx-btn ${cls || ''}" data-hx="${hx}" ${extra || ''}>${label}</button>`;
}
function loading() {
    return `<div class="hx-loading"><span></span>${tr('m.syncing')}</div>`;
}
function empty(msg) { return `<p class="hx-empty">${esc(msg)}</p>`; }

const FACTION_MARKS = { wolf:'◆', skull:'☠', claw:'✦', shield:'⬟', eye:'◉', bolt:'ϟ', crown:'♛', serpent:'☯' };
function factionLogo(raw) {
    let logo = raw;
    if (typeof raw === 'string') { try { logo = JSON.parse(raw); } catch (_) { logo = {}; } }
    logo = logo || {};
    const mark = FACTION_MARKS[logo.mark] ? logo.mark : 'shield';
    const color = /^#[0-9a-f]{6}$/i.test(logo.color || '') ? logo.color : '#e08c46';
    return { mark, color };
}
function factionCrest(raw, small = false) {
    const logo = factionLogo(raw);
    return `<span class="faction-crest${small ? ' faction-crest--small' : ''}" style="--crest:${logo.color}" title="${esc(logo.mark)}">${FACTION_MARKS[logo.mark]}</span>`;
}
function memberMetrics(m) {
    return `<span class="faction-member__metrics">${tr('m.lv')} ${num(m.level || 1)} · ${num(m.zombieKills || 0)} ${tr('m.walkers')} · ${num(m.survivorKills || 0)} ${tr('m.survivors')} · ${num(m.xp || 0)} XP · <b>${num(m.score || 0)} ${tr('m.score')}</b></span>`;
}
function factionEmblemEditor(faction, prefix, action) {
    const logo = factionLogo(faction.logo), marks = Object.keys(FACTION_MARKS);
    return `<div class="emblem-workshop"><div id="${prefix}EmblemPreview" class="faction-crest faction-crest--preview" style="--crest:${logo.color}">${FACTION_MARKS[logo.mark]}</div><div class="emblem-workshop__controls"><label>${tr('m.symbol')}<select id="${prefix}LogoMark">${marks.map(k => `<option value="${k}"${logo.mark === k ? ' selected' : ''}>${k.toUpperCase()}</option>`).join('')}</select></label><label>${tr('m.colour')}<input id="${prefix}LogoColor" type="color" value="${logo.color}"></label><div class="emblem-workshop__marks">${marks.map(k => `<button class="${logo.mark === k ? 'is-selected' : ''}" data-emblem-select="${prefix}" data-mark="${k}" title="${k}">${FACTION_MARKS[k]}</button>`).join('')}</div><button class="hx-btn hx-btn--go" data-act="${action}">${tr('m.save_emblem')}</button></div></div>`;
}

/* ---- data loaders, one per tab */
const HUB_LOAD = {
    roster: async () => {
        const [roster, squad] = await Promise.all([fx('factions:roster'), post('fx', { name: 'squad:get' })]);
        return { ok: true, roster, squad };
    },
    squad: () => fx('squad:get'),
    treasury: () => fx('factions:bank:info'),
    ranks: () => fx('factions:perms:get'),
    sanctions: async () => {
        const [templates, list] = await Promise.all([post('fx', { name: 'sanctions:templates' }), fx('sanctions:list')]);
        return { ok: true, templates, list };
    },
    jail: () => fx('jail:get'),
    raids: () => fx('raids:get'),
    progress: async () => {
        const [prog, missions, skills] = await Promise.all([fx('factions:progress:get'), post('fx', { name: 'factions:missions:get' }), post('fx', { name: 'factions:skills:get' })]);
        return { ok: !!(prog && prog.ok), error: prog && prog.error, prog, missions: missions || {}, skills: skills || {} };
    },
    settings: () => post('hubPrefs'),
};

function hubLoad(tab, force) {
    if (!HUB_LOAD[tab]) return;
    if (!force && (S.hub[tab] || S.hubBusy[tab])) return;
    S.hubBusy[tab] = true;
    Promise.resolve(HUB_LOAD[tab]())
        .then((r) => { S.hub[tab] = r || { ok: false }; })
        .catch(() => { S.hub[tab] = { ok: false, error: tr('m.tab_failed') }; })
        .finally(() => {
            S.hubBusy[tab] = false;
            if (S.current === 'faction' && S.hubTab === tab) renderStage();
        });
}
async function reload(tab) {
    const r = await HUB_LOAD[tab]();
    S.hub[tab] = r || { ok: false };
    renderStage();
}

function hubTabs(f) {
    if (!f.faction) {
        const t = [['overview', tr('m.tab_overview')], ['intel', tr('m.tab_factions')], ['settings', tr('m.tab_settings')]];
        if (f.admin) t.push(['admin', tr('m.tab_admin')]);
        return t;
    }
    const t = [['overview', tr('m.tab_overview')], ['roster', tr('m.tab_roster')], ['squad', tr('m.tab_squad')], ['progress', tr('m.tab_progression')], ['treasury', tr('m.tab_treasury')], ['raids', tr('m.tab_raids')], ['jobs', tr('m.tab_jobs')], ['board', tr('m.tab_board')], ['jobscore', tr('m.tab_jobscore')], ['ranks', tr('m.tab_ranks')], ['sanctions', tr('m.tab_sanctions')]];
    if (f.rank === 'owner' || (f.myPerms || {}).jail || f.admin) t.push(['jail', tr('m.tab_jail')]);
    t.push(['settings', tr('m.tab_settings')], ['intel', tr('m.tab_factions')]);
    if (f.admin) t.push(['admin', tr('m.tab_admin')]);
    return t;
}

function renderFaction() {
    const f = S.faction;
    if (!f || !f.ok) return `<div class="hub-x"><p class="hx-empty">${esc((f && f.error) || tr('m.registry_starting'))}</p></div>`;
    const tabs = hubTabs(f);
    if (!tabs.some((t) => t[0] === S.hubTab)) S.hubTab = 'overview';
    const tab = S.hubTab;

    let body;
    if (HUB_LOAD[tab] && !S.hub[tab]) { hubLoad(tab); body = loading(); }
    else body = (HUB_RENDER[tab] || HUB_RENDER.overview)(f, S.hub[tab] || {});

    const fresh = S.hubLastTab !== tab;
    S.hubLastTab = tab;

    const fac = f.faction;
    const hero = fac
        ? `<header class="hx-hero">${factionCrest(fac.logo)}<div class="hx-hero__id"><span class="hx-eyebrow">[${esc(fac.short || tr('m.tag'))}] · ${esc(f.rankLabel || RANK_LABEL[f.rank] || f.rank || RANK_LABEL.member).toUpperCase()}</span><h2>${esc(fac.label)}</h2></div><div class="hx-hero__stats"><span><b>${num(fac.reputation)}</b>${tr('m.score')}</span><span><b>$${num((fac.bank || {}).balance)}</b>${tr('m.treasury_word')}</span><span><b>${(f.members || []).filter((m) => m.src).length}/${(f.members || []).length}</b>${tr('m.online')}</span></div></header>`
        : `<header class="hx-hero hx-hero--solo"><div class="hx-hero__id"><span class="hx-eyebrow">${tr('m.unaffiliated')}</span><h2>${tr('m.no_faction')}</h2></div></header>`;

    return `<div class="hub-x${fresh ? ' is-fresh' : ''}"><div class="hub-x__scan"></div>${hero}<nav class="hx-tabs">${tabs.map(([id, l], i) => `<button class="hx-tab${id === tab ? ' is-active' : ''}" data-hubtab="${id}" style="--i:${i}">${l}</button>`).join('')}</nav><section class="hx-body" data-tab="${tab}">${body}</section></div>`;
}

/* ---- tabs */
const HUB_RENDER = {};

HUB_RENDER.overview = (f) => {
    if (!f.faction) {
        return `<div class="hx-grid">${card(tr('m.find_crew'), `<p>${tr('m.find_crew_text')}</p>${(f.vanilla || []).length ? `<div class="hx-form">${f.vanilla.map(v => `<button class="hx-btn hx-btn--go" data-act="joinVanilla" data-id="${esc(v.id)}">${tr('m.join_x', { name: esc(v.label) })}</button>`).join('')}</div>` : ''}${f.joinCooldown > 0 ? `<p>${tr('m.join_again', { h: Math.ceil(f.joinCooldown / 3600) })}</p>` : ''}${f.invite ? `<button class="hx-btn hx-btn--go" data-act="accept">${tr('m.accept_x', { name: esc(f.invite.label) })}</button>` : ''}`, 'hx-row')}${f.canCreate ? card(tr('m.found'), `<div class="hx-form"><input id="facTag" class="hx-in hx-in--tag" maxlength="8" placeholder="${tr('m.tag')}"><input id="facName" class="hx-in" maxlength="48" placeholder="${tr('m.fac_name')}"><button class="hx-btn hx-btn--go" data-act="create">${tr('m.create')}</button></div>`, 'hx-row') : ''}</div>`;
    }
    const fac = f.faction, owner = f.rank === 'owner', st = fac.scoreboard || {};
    let i = 0;
    const brief = owner
        ? `<textarea id="factionDescription" class="hx-in hx-area" maxlength="360" placeholder="${tr('m.brief_ph')}">${esc(fac.description || '')}</textarea><button class="hx-btn hx-btn--go" data-act="description">${tr('m.save_brief')}</button>`
        : `<p>${esc(fac.blurb || '')}</p>`;
    return `<div class="hx-grid">
        ${card(tr('m.briefing'), brief, 'hx-row hx-span2" style="--i:' + (i++))}
        ${card(tr('m.field_report'), `<div class="hx-stats"><span><b>${num(st.members || 0)}</b>${tr('m.members')}</span><span><b>${num(st.zombieKills || 0)}</b>${tr('m.walkers')}</span><span><b>${num(st.survivorKills || 0)}</b>${tr('m.survivors')}</span><span><b>${num(st.xp || 0)}</b>XP</span></div>`, 'hx-row hx-span2" style="--i:' + (i++))}
        ${owner ? card(tr('m.emblem'), factionEmblemEditor(fac, 'faction', 'logo'), 'hx-row hx-span2" style="--i:' + (i++)) : ''}
        ${f.nearby && f.nearby.length ? card(tr('m.recruit'), f.nearby.map((p) => `<div class="hx-line"><span>${esc(p.name)}</span><button class="hx-btn hx-btn--sm" data-act="invite" data-target="${p.src}">${tr('m.invite')}</button></div>`).join(''), 'hx-row" style="--i:' + (i++)) : ''}
        ${card(tr('m.membership'), `<p>${tr('m.leave_note')}</p><div class="hx-form"><button class="hx-btn" data-act="leave">${tr('m.leave_fac')}</button>${owner ? `<button class="hx-btn hx-btn--bad" data-act="disband">${tr('m.disband')}</button>` : ''}</div>`, 'hx-row" style="--i:' + (i++))}
    </div>`;
};

HUB_RENDER.roster = (f, d) => {
    const online = {};
    ((d.roster && d.roster.members) || []).forEach((m) => { if (m.charId) online[m.charId] = m; });
    const sq = d.squad && d.squad.squad;
    const iLead = sq && sq.isLeader;
    const owner = f.rank === 'owner', perms = f.myPerms || {}, ranks = f.ranks || [];
    const idx = (r) => { const i = ranks.findIndex((x) => x.id === r); return i < 0 ? ranks.length : i + 1; };
    const my = owner ? 1 : idx(f.rank);
    const list = (f.members || []).slice().sort((a, b) => ((b.src ? 1 : 0) - (a.src ? 1 : 0)) || (idx(a.rank) - idx(b.rank)));
    const rows = list.map((m, i) => {
        const o = online[m.charId];
        const status = o && o.downed ? 'down' : (m.src ? 'on' : 'off');
        const squadTxt = o && o.squadId ? `${sq && o.squadId === sq.id ? tr('m.x_my_squad') : tr('m.squad')}${o.squadRankLabel ? ' · ' + esc(o.squadRankLabel).toUpperCase() : ''}` : '-';
        const acts = [
            iLead && m.src && !m.you && o && !o.squadId ? `<button class="hx-btn hx-btn--sm" data-hx="squadInvite" data-target="${m.src}">${tr('m.squad_invite')}</button>` : '',
            !m.you && m.rank !== 'owner' && (owner || (perms.promote && idx(m.rank) > my)) ? `<select class="hx-in hx-in--sm" data-hxchange="facRank" data-char="${m.charId}">${ranks.filter((r) => r.id !== 'owner' && (owner || idx(r.id) > my)).map((r) => `<option value="${esc(r.id)}"${r.id === m.rank ? ' selected' : ''}>${esc(r.label).toUpperCase()}</option>`).join('')}</select>` : '',
            !m.you && m.rank !== 'owner' && perms.kick && (owner || idx(m.rank) > my) ? `<button class="hx-btn hx-btn--sm hx-btn--bad" data-act="kick" data-char="${m.charId}">${tr('m.remove')}</button>` : '',
        ].join('');
        return `<div class="hx-roster hx-row${m.you ? ' is-you' : ''}" style="--i:${i}"><i class="hx-dot hx-dot--${status}"></i><span class="hx-roster__name"><b>${esc(m.name)}${m.you ? ` <em>${tr('m.you')}</em>` : ''}</b>${memberMetrics(m)}</span><span class="hx-tag">${esc(rankName(m)).toUpperCase()}</span><span class="hx-roster__sq">${squadTxt}</span><span class="hx-roster__st">${status === 'down' ? tr('m.x_down') : status === 'on' ? tr('m.x_online') : tr('m.x_offline')}</span><span class="hx-roster__acts">${acts}</span></div>`;
    }).join('') || empty(tr('m.e_no_members_on_record'));
    return card(`ROSTER · ${list.filter((m) => m.src).length} ONLINE / ${list.length}`, `<div class="hx-head"><p>${tr('m.roster_note')}</p>${btn(tr('m.b_refresh'), 'refreshTab')}</div><div class="hx-list">${rows}</div>`, 'hx-wide');
};

HUB_RENDER.squad = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.x_squad_service_did_not_answer'));
    const sq = d.squad;
    if (!sq) {
        const inv = d.invite ? card(tr('m.c_incoming_invite'), `<p><b>${tr('m.wants_you', { from: esc(d.invite.from || tr('m.x_a_survivor')), name: esc(d.invite.name || tr('m.x_their_squad')) })}</p><div class="hx-form">${btn(tr('m.b_accept'), 'squadAccept', '', 'hx-btn--go')}${btn(tr('m.b_decline'), 'squadDecline')}</div>`, 'hx-row hx-alert" style="--i:0') : '';
        return `<div class="hx-grid">${inv}${card(tr('m.c_form_a_squad'), `<p>${tr('m.squad_is', { n: d.maxSize || 5 })}</p><div class="hx-form">${btn(tr('m.b_open_squad_console_f3'), 'squadConsole')}</div>`, 'hx-row" style="--i:1')}</div>`;
    }
    const lead = sq.isLeader, ranks = sq.ranks || [];
    const members = (sq.members || []).map((m, i) => {
        const rankCell = lead && !m.isLeader
            ? `<select class="hx-in hx-in--sm" data-hxchange="squadRank" data-char="${m.charId}">${ranks.map((r) => `<option value="${r.id}"${r.id === m.rankId ? ' selected' : ''}>${esc(r.label)}</option>`).join('')}</select>`
            : `<span class="hx-tag">${esc(m.rankLabel || '').toUpperCase()}</span>`;
        const acts = lead && !m.isLeader ? `${btn(tr('m.b_make_lead'), 'squadTransfer', `data-char="${m.charId}"`, 'hx-btn--sm')}${btn(tr('m.b_kick'), 'squadKick', `data-char="${m.charId}"`, 'hx-btn--sm hx-btn--bad')}` : '';
        return `<div class="hx-roster hx-roster--sq hx-row${m.charId === sq.myCharId ? ' is-you' : ''}" style="--i:${i}"><i class="hx-dot hx-dot--${m.online ? 'on' : 'off'}"></i><span class="hx-roster__name"><b>${m.isLeader ? '★ ' : ''}${esc(m.name)}</b><span class="faction-member__metrics">${m.level ? 'LV ' + num(m.level) + ' · ' : ''}${m.online ? tr('m.x_online') : tr('m.x_offline')}</span></span>${rankCell}<span class="hx-roster__acts">${acts}</span></div>`;
    }).join('');

    let editor = '';
    if (lead) {
        if (!S.rankDraft || S.rankDraft.sid !== sq.id) S.rankDraft = { sid: sq.id, ranks: ranks.map((r) => ({ id: r.id, label: r.label })) };
        const dr = S.rankDraft.ranks;
        editor = card(tr('m.c_squad_ranks'), `<p>${tr('m.ranks_top', { n: sq.maxRanks || 6 })}</p><div class="hx-list">${dr.map((r, i) => `<div class="hx-line hx-row" style="--i:${i}"><em class="hx-idx">${i + 1}</em><input class="hx-in" maxlength="20" data-rankedit="${i}" value="${esc(r.label)}">${btn('▲', 'rankUp', `data-idx="${i}"`, 'hx-btn--sm')}${btn('▼', 'rankDown', `data-idx="${i}"`, 'hx-btn--sm')}${dr.length > 1 ? btn('✕', 'rankDel', `data-idx="${i}"`, 'hx-btn--sm hx-btn--bad') : ''}</div>`).join('')}</div><div class="hx-form">${dr.length < (sq.maxRanks || 6) ? btn(tr('m.b_add_rank'), 'rankAdd') : ''}${btn(tr('m.b_save_ranks'), 'rankSave', '', 'hx-btn--go')}</div>`, 'hx-row" style="--i:2');
    }

    return `<div class="hx-grid">
        ${card(tr('m.c_squad'), `<div class="hx-sqhead"><h3>${esc(sq.name)}</h3><span class="hx-tag">${esc(sq.rankLabel || '').toUpperCase()}</span><span class="hx-muted">${(sq.members || []).length}/${sq.maxSize || d.maxSize || 5}</span></div>${lead ? `<div class="hx-form"><input id="sqRename" class="hx-in" maxlength="24" placeholder="${tr('m.rename_ph')}" value="${esc(sq.name)}">${btn(tr('m.b_rename'), 'squadRename')}</div>` : ''}<div class="hx-list">${members}</div><div class="hx-form">${btn(tr('m.b_leave_squad'), 'squadLeave')}${lead ? btn(tr('m.b_disband'), 'squadDisband', '', 'hx-btn--bad') : ''}</div>`, 'hx-row hx-span2" style="--i:0')}
        ${editor}
        ${card(tr('m.c_how_to_invite'), `<p>${tr('m.how_invite')}</p><div class="hx-form">${btn(tr('m.b_open_squad_console'), 'squadConsole', '', 'hx-btn--go')}</div>`, 'hx-row" style="--i:3')}
    </div>`;
};

HUB_RENDER.treasury = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.x_treasury_did_not_answer'));
    const cash = Math.floor((f.faction || {}).cash || 0);
    const left = Number(d.myDailyLeft);
    const caps = d.caps || {};
    const capEd = d.canEdit ? card(tr('m.c_daily_withdraw_caps'), `<p>${tr('m.cap_note')}</p><div class="hx-list">${(d.rankList || []).map((r, i) => `<div class="hx-line hx-row" style="--i:${i}"><span>${esc(r.label).toUpperCase()}</span><input id="cap_${esc(r.id)}" class="hx-in hx-in--sm" inputmode="numeric" value="${Math.floor(Number(caps[r.id]) || 0)}">${btn(tr('m.b_set'), 'setCap', `data-rank="${esc(r.id)}"`, 'hx-btn--sm')}</div>`).join('')}</div>`, 'hx-row" style="--i:1') : '';
    const log = (d.log || []).map((l, i) => `<div class="hx-log hx-row" style="--i:${Math.min(i, 20)}"><span class="hx-log__dir hx-log__dir--${l.direction === 'withdraw' ? 'out' : 'in'}">${l.direction === 'withdraw' ? '−' : '+'}$${num(l.amount)}</span><span>${esc(l.name || tr('m.x_system'))}</span><span class="hx-muted">${esc(l.note || l.direction || '')}</span><span class="hx-muted">${when(l.at)}</span></div>`).join('') || empty(tr('m.e_no_movements_yet'));
    return `<div class="hx-grid">
        ${card(tr('m.c_treasury'), `<strong class="hx-balance">$${num(d.balance)}</strong><p>${tr('m.you_carry', { n: '<b>$' + num(cash) + '</b>' })}${d.canWithdraw ? ` ${tr('m.withdraw_left', { n: '<b>' + (left < 0 ? tr('m.x_unlimited') : '$' + num(left)) + '</b>' })}` : ' ' + tr('m.cant_withdraw')}</p><div class="hx-form"><input id="bankAmount" class="hx-in" inputmode="numeric" placeholder="${tr('m.amount')}">${d.canDeposit !== false ? btn(tr('m.b_deposit'), 'bankDeposit', '', 'hx-btn--go') : ''}${d.canWithdraw ? btn(tr('m.b_withdraw'), 'bankWithdraw', '', 'hx-btn--bad') : ''}</div><div class="hx-form">${btn('$100', 'bankQuick', 'data-v="100"', 'hx-btn--sm')}${btn('$500', 'bankQuick', 'data-v="500"', 'hx-btn--sm')}${btn(tr('m.b_all_cash'), 'bankQuick', `data-v="${cash}"`, 'hx-btn--sm')}</div>`, 'hx-row" style="--i:0')}
        ${capEd}
        ${card(tr('m.c_ledger_last_50'), `<div class="hx-list hx-list--scroll">${log}</div>`, 'hx-row hx-span2" style="--i:2')}
    </div>`;
};

HUB_RENDER.ranks = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.x_permissions_did_not_answer'));
    const perms = d.perms || [];
    const rows = (d.ranks || []).map((r, i) => `<tr class="hx-row" style="--i:${i}"><th>${esc(r.label || r.id).toUpperCase()}</th>${perms.map((p) => {
        const on = !!((d.matrix || {})[r.id] || {})[p];
        const can = d.canEdit && !r.locked;
        return `<td><button class="hx-check${on ? ' is-on' : ''}" ${can ? '' : 'disabled'} data-hx="perm" data-rank="${r.id}" data-perm="${p}" data-on="${on ? 1 : 0}">${on ? '■' : '□'}</button></td>`;
    }).join('')}</tr>`).join('');
    const mine = perms.filter((p) => (d.mine || {})[p]).map((p) => `<span class="hx-tag">${esc(PERM_LABEL[p] || p).toUpperCase()}</span>`).join(' ') || `<span class="hx-muted">${tr('m.none')}</span>`;
    // Leader-only rank list: rename in place, move, delete, add. Leader stays on top.
    const list = d.ranks || [], max = d.maxRanks || 10;
    const editor = d.canEdit ? card(tr('m.c_rank_editor'), `<p>${tr('m.rank_editor_note', { n: max })}</p><div class="hx-list">${list.map((r, i) => `<div class="hx-line hx-row" style="--i:${i}"><em class="hx-idx">${i + 1}</em><input class="hx-in" maxlength="24" data-hxchange="fRankName" data-rank="${esc(r.id)}" value="${esc(r.label)}"><span class="hx-muted">${tr('m.rank_members', { n: num(r.members || 0) })}</span>${r.locked ? '' : btn('▲', 'fRankMove', `data-rank="${esc(r.id)}" data-dir="up"`, 'hx-btn--sm') + btn('▼', 'fRankMove', `data-rank="${esc(r.id)}" data-dir="down"`, 'hx-btn--sm') + btn('✕', 'fRankDel', `data-rank="${esc(r.id)}"`, 'hx-btn--sm hx-btn--bad')}</div>`).join('')}</div>${list.length < max ? `<div class="hx-form"><input id="fRankNew" class="hx-in" maxlength="24" placeholder="${tr('m.new_rank')}">${btn(tr('m.b_add_rank'), 'fRankAdd', '', 'hx-btn--go')}</div>` : ''}`, 'hx-span2') : '';
    return `<div class="hx-grid">${editor}${card(tr('m.c_rank_permissions'), `<p>${d.canEdit ? tr('m.x_click_a_box_to_grant_or_revoke') : tr('m.x_only_the_leader_can_change_the')}</p><div class="hx-tablewrap"><table class="hx-table"><thead><tr><th></th>${perms.map((p) => `<th>${esc(PERM_LABEL[p] || p).toUpperCase()}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table></div>`, 'hx-span2')}${card(tr('m.c_your_access'), `<div class="hx-tags">${mine}</div>`, 'hx-row hx-span2" style="--i:4')}</div>`;
};

HUB_RENDER.sanctions = (f, d) => {
    const t = d.templates || {}, l = d.list || {};
    const tpl = t.templates || [];
    let issue = '';
    if (t.canIssue && tpl.length) {
        const first = tpl.find((x) => x.id === S.snTemplate) || tpl[0];
        const targets = (f.members || []).filter((m) => !m.you);
        issue = card(tr('m.c_issue_sanction'), `<div class="hx-formgrid"><label>${tr('m.target')}<select id="snTarget" class="hx-in">${targets.map((m) => `<option value="${m.charId}">${esc(m.name)} · ${esc(rankName(m))}</option>`).join('')}</select></label><label>${tr('m.template')}<select id="snTemplate" class="hx-in" data-hxchange="snTemplate">${tpl.map((x) => `<option value="${esc(x.id)}"${x.id === first.id ? ' selected' : ''}>[${esc((x.tier || '').toUpperCase())}] ${esc(x.label)}</option>`).join('')}</select></label><label>${tr('m.minutes')} <span class="hx-muted">${first.min}-${first.max}</span><input id="snMinutes" class="hx-in" type="number" min="${first.min}" max="${first.max}" value="${first.default}"></label><label>${tr('m.reason')}<input id="snReason" class="hx-in" maxlength="120" placeholder="${tr('m.why')}"></label></div><p class="hx-muted">${tr('m.effects')}: ${Object.keys(first.effects || {}).map((k) => esc(k.replace(/_/g, ' '))).join(', ') || '-'}</p>${targets.length ? btn(tr('m.b_issue'), 'snIssue', '', 'hx-btn--bad') : empty(tr('m.e_nobody_to_sanction'))}`, 'hx-row hx-span2" style="--i:0');
    }
    const rows = (l.sanctions || []).map((s, i) => `<div class="hx-sanc hx-row${s.active ? ' is-active' : ''}" style="--i:${Math.min(i, 20)}"><span class="hx-tag hx-tag--${esc(s.tier || 'minor')}">${esc((s.tier || '').toUpperCase())}</span><span><b>${esc(s.label)}</b><small>${esc(s.name || (s.charId ? '#' + s.charId : tr('m.x_whole_faction')))} · ${tr('m.by', { name: esc(s.issuedBy || '?') })}${s.reason ? ' · ' + esc(s.reason) : ''}</small></span><span class="hx-muted">${s.active ? tr('m.left', { t: dur(s.remaining) }) : tr('m.x_ended')}</span>${s.canLift ? btn(tr('m.b_lift'), 'snLift', `data-id="${s.id}"`, 'hx-btn--sm') : '<span></span>'}</div>`).join('') || empty(tr('m.e_no_sanctions_on_record'));
    return `<div class="hx-grid">${issue}${card(t.canIssue ? tr('m.x_faction_sanctions') : tr('m.x_your_sanctions'), `<div class="hx-head"><span></span>${btn(tr('m.b_refresh'), 'refreshTab')}</div><div class="hx-list hx-list--scroll">${rows}</div>`, 'hx-row hx-span2" style="--i:1')}</div>`;
};

// Raids: declare a raid on a faction's outposts. Safezone flags never show up here.
HUB_RENDER.raids = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.raid_no_answer'));
    const mins = (s) => Math.max(1, Math.ceil((Number(s) || 0) / 60));
    const status = `<p>${tr('m.raid_rules', { w: esc(d.window || ''), m: num(d.duration || 0) })}</p><p><span class="hx-tag">${d.open ? tr('m.raid_open') : tr('m.raid_closed')}</span>${d.cooldown > 0 ? ` <span class="hx-muted">${tr('m.raid_cd', { m: mins(d.cooldown) })}</span>` : ''}</p>`;
    const targets = (d.targets || []).map((t, i) => `<div class="hx-line hx-row" style="--i:${i}"><span><b>${esc(t.label)}</b> <span class="hx-muted">${tr('m.raid_outposts', { n: num(t.outposts) })}</span></span>${t.declared ? `<span class="hx-tag">${tr('m.raid_active')}</span>` : (d.canDeclare && !(d.cooldown > 0) ? btn(tr('m.b_raid'), 'raidDeclare', `data-id="${esc(t.id)}"`, 'hx-btn--sm hx-btn--bad') : '<span></span>')}</div>`).join('') || empty(tr('m.raid_no_targets'));
    const list = (arr) => (arr || []).map((r, i) => `<div class="hx-line hx-row" style="--i:${i}"><span><b>${esc(r.label)}</b></span><span class="hx-muted">${tr('m.left', { t: dur(r.left) })}</span></div>`).join('') || empty(tr('m.none'));
    return `<div class="hx-grid">
        ${card(tr('m.c_raids'), `${status}${d.canDeclare ? '' : `<p class="hx-muted">${tr('m.raid_rank')}</p>`}<div class="hx-list">${targets}</div>`, 'hx-row hx-span2" style="--i:0')}
        ${card(tr('m.c_raid_out'), `<div class="hx-list">${list(d.outgoing)}</div>`, 'hx-row" style="--i:1')}
        ${card(tr('m.c_raid_in'), `<div class="hx-list">${list(d.incoming)}</div>`, 'hx-row" style="--i:2')}
    </div>`;
};

HUB_RENDER.jail = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.x_jail_service_did_not_answer'));
    const mine = d.jailed ? card(tr('m.c_you_are_jailed'), `<strong class="hx-balance hx-balance--bad">${dur(d.jailed.remaining)}</strong><p>${tr('m.cell_n', { n: esc(d.jailed.cell) })}</p>`, 'hx-row hx-alert" style="--i:0') : '';
    if (!d.canManage) return `<div class="hx-grid">${mine}${card(tr('m.c_jail'), `<p>${tr('m.jail_who')}</p>`)}</div>`;
    const j = d.jail;
    const o = (j && j.origin) || {};
    const setup = card(tr('m.c_jail_setup'), `<p>${tr('m.jail_here')}</p><div class="hx-form"><input id="jlRadius" class="hx-in hx-in--sm" type="number" min="5" placeholder="${tr('m.radius')}" value="${j ? Math.round(j.radius) : ''}">${btn(j ? tr('m.x_move_origin_here') : tr('m.x_set_origin_here'), 'jailOrigin', '', 'hx-btn--go')}${j ? btn(tr('m.b_set_exit_here'), 'jailExit') : ''}${j ? btn(tr('m.b_add_cell_here'), 'jailCell') : ''}</div>${j ? `<p class="hx-muted">${tr('m.jail_info', { x: Math.round(o.x || 0), y: Math.round(o.y || 0), r: Math.round(j.radius || 0), exit: j.exit ? tr('m.x_set') : tr('m.x_not_set') })}</p>` : `<p class="hx-muted">${tr('m.no_jail')}</p>`}`, 'hx-row" style="--i:1');
    const cells = j ? card(`${tr('m.cells')} · ${(j.cells || []).length}`, `<div class="hx-list">${(j.cells || []).map((c, i) => `<div class="hx-line hx-row" style="--i:${i}"><em class="hx-idx">${c.n}</em><span class="hx-muted">${Math.round(c.x)}, ${Math.round(c.y)}, ${Math.round(c.z)}</span><span>${c.occupied ? `<b class="hx-red">${tr('m.occupied')}</b>` : tr('m.x_free')}</span>${c.occupied ? '' : btn(tr('m.b_remove'), 'jailRmCell', `data-n="${c.n}"`, 'hx-btn--sm hx-btn--bad')}</div>`).join('') || empty(tr('m.e_no_cells_yet'))}</div>`, 'hx-row" style="--i:2') : '';
    const inm = card(tr('m.c_inmates'), `<div class="hx-list">${(d.inmates || []).map((m, i) => `<div class="hx-line hx-row" style="--i:${i}"><i class="hx-dot hx-dot--${m.online ? 'on' : 'off'}"></i><span>${esc(m.name)}</span><span class="hx-muted">${tr('m.cell_n', { n: m.cell })} · ${dur(m.remaining)}</span>${btn(tr('m.b_release'), 'jailRelease', `data-char="${m.charId}"`, 'hx-btn--sm')}</div>`).join('') || empty(tr('m.e_cells_are_empty'))}</div>`, 'hx-row hx-span2" style="--i:3');
    return `<div class="hx-grid">${mine}${setup}${cells}${inm}</div>`;
};

// Progression: faction level, missions, skill tree, donations, tag cosmetics.
const SKILL_UNIT = labelProxy('m.unit_', { stash_slots: ' slots', stash_slots2: ' slots', build_speed: '% build time', build_speed2: '% build time', trader_disc: '% prices', trader_disc2: '% prices', quartermaster: '% prices', booster_cd: '% cooldown', booster_cd2: '% cooldown', donation_rate: '% donation XP', mission_pay: '% mission pay' });
function missionRow(m, period, i) {
    const pct = m.target ? Math.min(100, (m.progress / m.target) * 100) : 0;
    const what = m.kind === 'deliver' ? tr('m.x_deliver') : m.kind === 'extract' ? tr('m.x_extract') : tr('m.x_field');
    const act = m.done ? `<span class="hx-tag hx-tag--done">${tr('m.done')}</span>`
        : m.kind === 'deliver' ? btn(tr('m.b_deliver'), 'msDeliver', `data-period="${period}" data-slot="${m.slot}"`, 'hx-btn--sm hx-btn--go') : '<span></span>';
    return `<div class="hx-mission hx-row${m.done ? ' is-done' : ''}" style="--i:${i}"><span class="hx-tag">${what}</span><span class="hx-mission__txt"><b>${esc(m.label || m.id)}</b><small>${num(m.progress)} / ${num(m.target)} · +${num(m.xp)} XP · +$${num(m.money)} ${tr('m.treasury_word')}</small><i class="hx-bar"><em style="width:${pct}%"></em></i></span>${act}</div>`;
}
HUB_RENDER.progress = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.x_progression_did_not_answer'));
    const p = d.prog, ms = d.missions || {}, sk = d.skills || {};
    const maxed = p.level >= p.maxLevel;
    const pct = maxed ? 100 : (p.xpToNext ? Math.min(100, (p.xpIntoLevel / p.xpToNext) * 100) : 0);
    const level = card(tr('m.c_faction_level'), `<div class="hx-level"><strong class="hx-level__num">${num(p.level)}<small>/ ${num(p.maxLevel)}</small></strong><div class="hx-level__xp"><span>${maxed ? tr('m.x_max_level') : `${num(p.xpIntoLevel)} / ${num(p.xpToNext)} XP`}</span><i class="hx-bar hx-bar--xp"><em style="width:${pct}%"></em></i><span class="hx-muted">${tr('m.xp_total', { xp: num(p.xp), n: num(p.points) })}</span></div></div><p>${tr('m.fxp_note')}</p>`, 'hx-row hx-span2" style="--i:0');

    const list = (arr, period) => (arr || []).map((m, i) => missionRow(m, period, i)).join('') || empty(tr('m.e_no_missions_rolled'));
    const missions = ms.ok === false ? card(tr('m.c_missions'), empty(ms.error || tr('m.x_missions_did_not_answer')), 'hx-row hx-span2" style="--i:1')
        : card(tr('m.c_daily_missions'), `<p class="hx-muted">${tr('m.resets_in', { t: dur((ms.resetsDaily || 0) - Date.now() / 1000) })} · ${tr('m.deliver_flags')}</p><div class="hx-list">${list(ms.daily, 'daily')}</div>`, 'hx-row" style="--i:1')
        + card(tr('m.c_weekly_missions'), `<p class="hx-muted">${tr('m.resets_in', { t: dur((ms.resetsWeekly || 0) - Date.now() / 1000) })}</p><div class="hx-list">${list(ms.weekly, 'weekly')}</div>`, 'hx-row" style="--i:2');

    const byId = {}; (sk.skills || []).forEach((s) => { byId[s.id] = s; });
    const nodes = (sk.skills || []).map((s, i) => {
        const reqs = Object.entries(s.requires || {});
        const reqOk = reqs.every(([id, r]) => (byId[id] ? byId[id].rank : 0) >= r);
        const lvlOk = (sk.level || 1) >= s.level;
        const max = s.rank >= s.ranks;
        const open = !max && lvlOk && reqOk;
        const pips = Array.from({ length: s.ranks }, (_, k) => `<i class="${k < s.rank ? 'is-on' : ''}"></i>`).join('');
        const lock = !lvlOk ? tr('m.level_n', { n: s.level }) : !reqOk ? tr('m.needs_word') + ' ' + reqs.map(([id, r]) => `${esc((byId[id] || {}).label || id).toUpperCase()} ${r}`).join(', ') : '';
        const spend = sk.canSpend && open && sk.points > 0 ? btn('+1', 'skSpend', `data-id="${esc(s.id)}"`, 'hx-btn--sm hx-btn--go') : '';
        return `<div class="hx-skill hx-row${max ? ' is-max' : open ? ' is-open' : ' is-locked'}" style="--i:${Math.min(i, 20)}"><span class="hx-skill__head"><b>${esc(s.label)}</b><span class="hx-pips">${pips}</span></span><small>${esc(s.desc || '')}</small><span class="hx-skill__foot"><span class="hx-muted">${max ? tr('m.x_maxed') : lock || tr('m.rank_of', { n: s.rank, max: s.ranks })}${s.rank ? ` · ${tr('m.now')} ${s.value * s.rank}${SKILL_UNIT[s.id] || ''}` : ''}</span>${spend}</span></div>`;
    }).join('') || empty(tr('m.e_no_skills_configured'));
    const skills = card(`${tr('m.skill_tree')} · ${tr('m.points_n', { n: num(sk.points || 0) })}`, `<p>${sk.canSpend ? tr('m.x_one_point_per_faction_level_sp') : tr('m.x_only_the_leader_and_ranks_with')}</p><div class="hx-skills">${nodes}</div>`, 'hx-row hx-span2" style="--i:3');

    const dn = p.donation || {};
    const donate = card(tr('m.c_donate_to_treasury'), `<p>${tr('m.donate_note', { usd: num(dn.dollarsPerXp || 25), cap: num(dn.dailyXpCap || 400) })}</p><div class="hx-form"><input id="donAmount" class="hx-in" inputmode="numeric" placeholder="$${num(dn.min || 100)} - $${num(dn.max || 50000)}">${btn(tr('m.b_donate'), 'donate', '', 'hx-btn--go')}</div>`, 'hx-row" style="--i:4');

    const c = p.cosmetics || {};
    const lead = f.rank === 'owner' || (f.myRankIdx || 99) <= 2;
    const cur = (c.colours || []).find((x) => x.id === c.colour) || {};
    const swatches = (c.colours || []).map((x) => `<button class="hx-swatch${x.id === c.colour ? ' is-sel' : ''}${x.unlocked ? '' : ' is-locked'}" style="--sw:${esc(x.hex)}" ${lead && x.unlocked ? '' : 'disabled'} data-hx="cosColour" data-id="${esc(x.id)}" title="${esc(x.id)}${x.unlocked ? '' : ' · ' + tr('m.level_n', { n: x.level })}">${x.unlocked ? '' : x.level}</button>`).join('');
    const styles = (c.styles || []).map((x) => `<button class="hx-btn hx-btn--sm${x.id === c.style ? ' is-sel' : ''}" ${lead && x.unlocked ? '' : 'disabled'} data-hx="cosStyle" data-id="${esc(x.id)}">${esc(x.label).toUpperCase()}${x.unlocked ? '' : ' · L' + x.level}</button>`).join('');
    const tag = (f.faction && f.faction.short) || 'TAG';
    const cosm = card(tr('m.c_tag_style'), `<div class="hx-tagprev hx-tagprev--${esc(c.style || 'plain')}" style="--sw:${esc(cur.hex || '#e08c46')}">${esc(tag)}</div><div class="hx-swatches">${swatches}</div><div class="hx-form">${styles}</div>${lead ? '' : `<p class="hx-muted">${tr('m.lead_only')}</p>`}`, 'hx-row" style="--i:5');

    return `<div class="hx-grid">${level}${missions}${skills}${donate}${cosm}</div>`;
};

// Interface scale override, stored as a bs_ui KVP (bs_ui/client/cl_uiscale.lua). [beyond] pages read it via bs_ui/html/shared/scale.js. 0 = auto.
const UISCALE = { ov: 0, loaded: false };
async function uiScaleCall(name, data) {
    try {
        const r = await fetch(`https://bs_ui/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
        return await r.json();
    } catch (_) { return null; }
}
async function uiScaleSet(v) {
    const r = await uiScaleCall('uiScaleSet', { scale: v });
    UISCALE.ov = r ? (Number(r.scale) || 0) : 0;
    if (window.BSScale) window.BSScale.set(UISCALE.ov);
    renderStage();
}
function uiScaleCard() {
    if (!UISCALE.loaded) {
        UISCALE.loaded = true;
        uiScaleCall('uiScaleGet').then((r) => { const v = r ? (Number(r.scale) || 0) : 0; if (v !== UISCALE.ov) { UISCALE.ov = v; renderStage(); } });
    }
    const auto = !(UISCALE.ov > 0);
    const cur = Math.round((auto ? (window.BSScale ? window.BSScale.get() : 1) : UISCALE.ov) * 100);
    return card(tr('m.c_interface'), `<div class="hx-toggle hx-row" style="--i:9"><span><b>${tr('m.auto_scale')}</b><small>${tr('m.auto_scale_n')}</small></span><button class="hx-switch${auto ? ' is-on' : ''}" data-uiscale-auto="${auto ? 1 : 0}"><i></i>${auto ? tr('m.x_on') : tr('m.x_off')}</button></div><div class="hx-toggle hx-row" style="--i:10"><span><b>${tr('m.ui_scale')}</b><small>${tr('m.ui_scale_n')}</small></span><span class="hx-range"><input type="range" min="60" max="140" step="5" value="${Math.max(60, Math.min(140, cur))}" data-hxchange="uiscale"><em id="uiScaleVal">${cur}%</em></span></div>`);
}

HUB_RENDER.settings = (f, d) => {
    const t = d.tags || {};
    const tg = (key, on, label, note, i) => `<div class="hx-toggle hx-row" style="--i:${i}"><span><b>${label}</b><small>${note}</small></span><button class="hx-switch${on ? ' is-on' : ''}" data-hx="pref" data-key="${key}" data-on="${on ? 1 : 0}"><i></i>${on ? tr('m.x_on') : tr('m.x_off')}</button></div>`;
    const range = Math.max(10, Math.min(150, Number(t.range) || 50));
    return `<div class="hx-grid">
        ${card(tr('m.c_name_tags'), `${tg('master', t.master !== false, tr('m.x_show_name_tags'), tr('m.x_master_switch_for_every_tag'), 0)}${tg('squad', t.squad !== false, tr('m.x_squad_mates'), tr('m.x_tags_on_your_squad_with_squad_'), 1)}${tg('faction', t.faction !== false, tr('m.x_faction_mates'), tr('m.x_tags_on_faction_mates_outside_'), 2)}${tg('self', t.self === true, tr('m.x_my_own_tag'), tr('m.x_show_your_own_name_tag_over_yo'), 3)}<div class="hx-toggle hx-row" style="--i:4"><span><b>${tr('m.tag_range')}</b><small>${tr('m.tag_range_n')}</small></span><span class="hx-range"><input type="range" min="10" max="150" step="5" value="${range}" data-hxchange="range"><em id="rangeVal">${range} m</em></span></div>`)}
        ${card(tr('m.c_hud_map'), `${tg('partyhud', d.partyhud !== false, tr('m.x_party_hud'), tr('m.x_side_frames_for_squad_and_fact'), 4)}${tg('blips', d.blips !== false, tr('m.x_squad_blips'), tr('m.x_squad_mates_on_the_map'), 5)}`)}
        ${d.fx ? card(tr('m.c_combat_feedback'), `${tg('fx:zombieHealthBars', d.fx.zombieHealthBars !== false, tr('m.x_zombie_health_bars'), tr('m.x_bar_over_the_walker_you_aim_at'), 6)}${tg('fx:hitMarker', d.fx.hitMarker === true, tr('m.x_hit_marker_sound'), tr('m.x_tick_when_a_shot_lands'), 7)}${tg('fx:hitMarkerVisual', d.fx.hitMarkerVisual !== false, tr('m.x_hit_marker_cross'), tr('m.x_small_cross_at_the_crosshair'), 8)}${tg('fx:hitMarkerHeadOnly', d.fx.hitMarkerHeadOnly === true, tr('m.x_headshots_only'), tr('m.x_silence_body_hits'), 9)}`) : ''}
        ${uiScaleCard()}
    </div>`;
};

HUB_RENDER.intel = (f) => ((f.directory || []).find((x) => x.id === S.factionView) ? renderFactionDirectory(f) : renderFactionRanking(f));
HUB_RENDER.admin = (f) => (f.admin ? renderFactionAdmin(f) : empty(tr('m.e_admins_only')));

function renderFactionRanking(f) {
    const rows = (f.directory || []).map((x, i) => `<button class="faction-ranking__row hx-row" style="--i:${i}" data-faction-open="${esc(x.id)}"><b>#${i + 1}</b>${factionCrest(x.logo, true)}<span>${esc(x.label)} <em>[${esc(x.short)}]</em></span><small>${num(x.members)} ${tr('m.members')} · ${num(x.zombieKills)} ${tr('m.walkers')} · ${num(x.survivorKills)} ${tr('m.survivors')}</small><strong>${num(x.reputation)} ${tr('m.score')}</strong></button>`).join('') || empty(tr('m.e_no_faction_has_enough_active_m'));
    return card(tr('m.c_faction_scoreboard'), `<p>${tr('m.ranked_note')}</p><div class="faction-ranking">${rows}</div>`, 'hx-wide');
}
function renderFactionDirectory(f) {
    const selected = (f.directory || []).find((x) => x.id === S.factionView);
    if (!selected) return '';
    const people = (selected.memberList || []).map((m, i) => `<div class="hx-roster hx-row" style="--i:${i}"><i class="hx-dot hx-dot--${m.src ? 'on' : 'off'}"></i><span class="hx-roster__name"><b>${esc(m.name)}</b>${memberMetrics(m)}</span><span class="hx-tag">${esc(rankName(m)).toUpperCase()}</span></div>`).join('') || empty(tr('m.e_no_members'));
    return card(tr('m.c_faction_profile'), `<button class="hx-btn hx-btn--sm" data-faction-back>&lt;- ${tr('m.all_factions')}</button><div class="hx-profile">${factionCrest(selected.logo)}<div><h3>${esc(selected.label)} <em>[${esc(selected.short)}]</em></h3><p>${esc(selected.description || tr('m.x_no_public_briefing_has_been_po'))}</p><div class="hx-tags"><span class="hx-tag">${num(selected.members)} ${tr('m.members')}</span><span class="hx-tag">${num(selected.reputation)} ${tr('m.score')}</span></div></div></div><div class="hx-list">${people}</div>`, 'hx-wide');
}
// Admin tab (staff console). Only present when the server sends f.admin; every button goes through factions:admin:*, which re-checks the ACE.
S.adm = { id: null, detail: null, overview: null, busy: false };

async function admLoad(force) {
    if (S.adm.busy) return;
    S.adm.busy = true;
    try {
        if (force || !S.adm.overview) S.adm.overview = await fx('factions:admin:overview');
        if (S.adm.id) {
            const d = await fx('factions:admin:detail', { id: S.adm.id });
            S.adm.detail = d && d.ok ? d : null;
            if (!S.adm.detail) S.adm.id = null;
        } else S.adm.detail = null;
    } finally {
        S.adm.busy = false;
        if (S.current === 'faction' && S.hubTab === 'admin') renderStage();
    }
}

// Runs an admin callback for the open faction, then refreshes the console.
async function admDo(name, args, okMsg) {
    const r = await fx('factions:admin:' + name, Object.assign({ id: S.adm.id }, args || {}));
    if (r && r.ok) {
        toast(okMsg || 'Done.');
        if (name === 'disband' && r.removed) S.adm.id = null;
        delete S.hub.roster; delete S.hub.treasury; delete S.hub.progress;
        await admLoad(true);
    }
    return r;
}

const admNum = (id) => { const n = Math.floor(Number(val(id))); return Number.isFinite(n) ? n : null; };

function renderFactionAdmin(f) {
    const ov = S.adm.overview;
    if (!ov) { admLoad(); return loading(); }
    if (ov.ok === false) return `<div class="hx-grid">${card(tr('m.c_admin'), empty(ov.error || 'Admin data unavailable.'))}</div>`;
    const list = ov.factions || [];
    const picker = card(tr('m.c_faction_control_staff'), `<div class="hx-form"><select class="hx-in" data-hxchange="admPick"><option value="">SELECT ANY FACTION...</option>${list.map((x) => `<option value="${esc(x.id)}"${x.id === S.adm.id ? ' selected' : ''}>[${esc(x.short)}] ${esc(x.label)} · ${x.isConfig ? 'LORE' : 'PLAYER'} · LV ${num(x.level)} · ${num(x.members)} MEMBERS</option>`).join('')}</select>${btn(tr('m.b_refresh'), 'admRefresh')}</div><p class="hx-muted">Every change is checked server-side and written to the server console.</p>`, 'hx-row hx-span2 hx-adm" style="--i:0');
    const d = S.adm.detail;
    if (!S.adm.id || !d) {
        if (S.adm.id && !d) { admLoad(); return `<div class="hx-grid">${picker}${card(tr('m.c_loading'), loading(), 'hx-span2')}</div>`; }
        const rows = list.map((x, i) => `<button class="hx-line hx-line--btn hx-row" style="--i:${Math.min(i, 20)}" data-hx="admOpen" data-id="${esc(x.id)}">${factionCrest(x.logo, true)}<b>${esc(x.label)} <em>[${esc(x.short)}]</em></b><span class="hx-muted">${x.isConfig ? 'LORE' : 'PLAYER'} · LV ${num(x.level)} · ${num(x.members)} MEMBERS</span></button>`).join('') || empty(tr('m.e_no_factions_registered'));
        return `<div class="hx-grid">${picker}${card(tr('m.c_all_factions'), `<div class="hx-list hx-list--scroll">${rows}</div>`, 'hx-row hx-span2" style="--i:1')}</div>`;
    }
    const p = d.progress || {};
    const members = d.members || [];
    let i = 1;

    const head = card(`${d.isConfig ? 'LORE' : 'PLAYER'} FACTION · ${esc(d.id)}`, `<div class="hx-profile">${factionCrest(d.logo)}<div><h3>${esc(d.label)} <em>[${esc(d.short)}]</em></h3><div class="hx-stats"><span><b>${num(p.level || 1)}</b>LEVEL</span><span><b>${num(p.xp || 0)}</b>XP</span><span><b>${num(p.points || 0)}</b>FREE POINTS</span><span><b>$${num(d.treasury || 0)}</b>TREASURY</span><span><b>${num(members.length)}</b>MEMBERS</span></div></div></div>`, 'hx-row hx-span2" style="--i:' + (i++));

    const who = `<select id="admRepWho" class="hx-in hx-in--sm"><option value="">ALL MEMBERS</option>${members.map((m) => `<option value="${m.charId}">${esc(m.name)} · ${num(m.rep)}</option>`).join('')}</select>`;
    const numRow = (label, id, ph, acts) => `<div class="hx-line hx-adm__row"><span>${label}</span><input id="${id}" class="hx-in hx-in--sm" inputmode="numeric" placeholder="${ph}">${acts}</div>`;
    const prog = card(tr('m.c_progression_economy'), `<p class="hx-muted">Level ${num(p.level || 1)}/${num(p.maxLevel || 30)} · ${num(p.xpIntoLevel || 0)} / ${num(p.xpToNext || 0)} XP into level · ${num(p.bonus || 0)} bonus point(s)</p>
        ${numRow('XP', 'admXp', 'e.g. 500 or -200', btn(tr('m.b_set'), 'admProg', 'data-op="setXp"', 'hx-btn--sm') + btn(tr('m.b_add'), 'admProg', 'data-op="addXp"', 'hx-btn--sm hx-btn--go'))}
        ${numRow(tr('m.a_level', { fallback: 'LEVEL' }), 'admLevel', '1 - ' + (p.maxLevel || 30), btn(tr('m.b_set'), 'admLevelSet', '', 'hx-btn--sm hx-btn--go'))}
        ${numRow(tr('m.a_points', { fallback: 'SKILL POINTS' }), 'admPts', tr('m.a_free_points', { fallback: 'free points' }), btn(tr('m.b_set'), 'admPts', 'data-op="set"', 'hx-btn--sm') + btn(tr('m.b_add'), 'admPts', 'data-op="add"', 'hx-btn--sm hx-btn--go'))}
        ${numRow(tr('m.a_treasury', { fallback: 'TREASURY' }), 'admBank', '$', btn(tr('m.b_set'), 'admBank', 'data-op="set"', 'hx-btn--sm') + btn(tr('m.b_add'), 'admBank', 'data-op="add"', 'hx-btn--sm hx-btn--go'))}
        <div class="hx-line hx-adm__row"><span>REPUTATION</span>${who}<input id="admRep" class="hx-in hx-in--sm" inputmode="numeric" placeholder="value">${btn(tr('m.b_set'), 'admRep', 'data-op="set"', 'hx-btn--sm')}${btn(tr('m.b_add'), 'admRep', 'data-op="add"', 'hx-btn--sm hx-btn--go')}</div>`, 'hx-row" style="--i:' + (i++));

    const skills = card(tr('m.c_skill_tree_grant_revoke'), `<div class="hx-list hx-list--scroll">${(p.skills || []).map((s, k) => `<div class="hx-line hx-row" style="--i:${Math.min(k, 20)}"><span><b>${esc(s.label)}</b> <span class="hx-muted">${s.rank}/${s.ranks}</span></span><span class="hx-roster__acts">${btn('−', 'admSkill', `data-sk="${esc(s.id)}" data-rank="${s.rank - 1}"`, 'hx-btn--sm hx-btn--bad')}${btn('+', 'admSkill', `data-sk="${esc(s.id)}" data-rank="${s.rank + 1}"`, 'hx-btn--sm hx-btn--go')}${btn(tr('m.b_max'), 'admSkill', `data-sk="${esc(s.id)}" data-rank="${s.ranks}"`, 'hx-btn--sm')}</span></div>`).join('') || empty(tr('m.e_progression_is_not_loaded'))}</div>`, 'hx-row" style="--i:' + (i++));

    const online = (ov.online || []).map((o) => `<option value="s:${o.src}">[${o.src}] ${esc(o.name)}${o.factionId ? ' · in ' + esc(o.factionId) : ''}</option>`).join('');
    const loose = (f.adminCandidates || []).map((c) => `<option value="c:${c.id}">#${c.id} ${esc(c.name)} · LV ${num(c.level)} (offline ok)</option>`).join('');
    const roster = members.map((m, k) => `<div class="hx-roster hx-row" style="--i:${Math.min(k, 20)}"><i class="hx-dot hx-dot--${m.src ? 'on' : 'off'}"></i><span class="hx-roster__name"><b>${esc(m.name)}</b><span class="faction-member__metrics">#${m.charId} · REP ${num(m.rep)}</span></span><select class="hx-in hx-in--sm" data-hxchange="admRank" data-char="${m.charId}">${(d.ranks || []).map((r) => `<option value="${esc(r.id)}"${r.id === m.rank ? ' selected' : ''}>${esc(r.label).toUpperCase()}</option>`).join('')}</select><span class="hx-roster__acts">${m.rank !== 'owner' ? btn(tr('m.b_make_leader'), 'admTransfer', `data-char="${m.charId}"`, 'hx-btn--sm') : ''}${btn(tr('m.b_remove'), 'admRemove', `data-char="${m.charId}"`, 'hx-btn--sm hx-btn--bad')}</span></div>`).join('') || empty(tr('m.e_no_members'));
    const mem = card(`MEMBERS · ${members.length}`, `<div class="hx-form"><select id="admAddWho" class="hx-in"><option value="">ADD A PLAYER...</option>${online ? `<optgroup label="ONLINE">${online}</optgroup>` : ''}${loose ? `<optgroup label="NO FACTION">${loose}</optgroup>` : ''}</select><input id="admAddCid" class="hx-in hx-in--sm" inputmode="numeric" placeholder="OR CHAR ID"><select id="admAddRank" class="hx-in hx-in--sm">${(d.ranks || []).filter((r) => r.id !== 'owner').reverse().map((r) => `<option value="${esc(r.id)}">${esc(r.label).toUpperCase()}</option>`).join('')}</select>${btn(tr('m.b_add'), 'admAdd', '', 'hx-btn--go')}</div><p class="hx-muted">Adding moves them out of any other faction. Leader changes go through MAKE LEADER.</p><div class="hx-list hx-list--scroll">${roster}</div>`, 'hx-row hx-span2" style="--i:' + (i++));

    const ms = d.missions || {};
    const mrow = (m, period) => `<div class="hx-mission hx-row${m.done ? ' is-done' : ''}"><span class="hx-tag">${period === 'daily' ? 'D' : 'W'}${m.slot}</span><span class="hx-mission__txt"><b>${esc(m.label || m.id)}</b><small>${num(m.progress)} / ${num(m.target)} · +${num(m.xp)} XP · +$${num(m.money)}</small></span>${m.done ? `<span class="hx-tag hx-tag--done">${tr('m.done')}</span>` : btn(tr('m.b_complete'), 'admComplete', `data-period="${period}" data-slot="${m.slot}"`, 'hx-btn--sm hx-btn--go')}</div>`;
    const missions = card(tr('m.c_missions'), `<div class="hx-list">${(ms.daily || []).map((m) => mrow(m, 'daily')).join('')}${(ms.weekly || []).map((m) => mrow(m, 'weekly')).join('') || ''}</div><div class="hx-form">${btn(tr('m.b_reroll_daily'), 'admReroll', 'data-period="daily"')}${btn(tr('m.b_reroll_weekly'), 'admReroll', 'data-period="weekly"')}${btn(tr('m.b_reset_daily_caps'), 'admCooldowns')}</div><p class="hx-muted">Reset clears today's donation-XP and withdraw caps.</p>`, 'hx-row" style="--i:' + (i++));

    const flags = card(`FLAGS & OUTPOSTS · ${(d.flags || []).length}`, `<div class="hx-list">${(d.flags || []).map((fl) => `<div class="hx-line hx-row"><span class="hx-tag">${esc((fl.kind || '').toUpperCase())}</span><span class="hx-muted">#${fl.id} · ${Math.round(fl.x)}, ${Math.round(fl.y)}, ${Math.round(fl.z)} · ${esc(fl.status)}</span><span class="hx-roster__acts">${btn(tr('m.b_teleport'), 'admFlagTp', `data-flag="${fl.id}"`, 'hx-btn--sm')}${btn(tr('m.b_remove'), 'admFlagRm', `data-flag="${fl.id}"`, 'hx-btn--sm hx-btn--bad')}</span></div>`).join('') || empty(tr('m.e_no_flags_placed'))}</div>`, 'hx-row" style="--i:' + (i++));

    // emblem editor without its own save button - SAVE IDENTITY covers it
    const emblem = factionEmblemEditor(d, 'adminFaction', 'noop').replace(/<button class="hx-btn hx-btn--go" data-act="noop">SAVE EMBLEM<\/button>/, '');
    const tagCol = `<select id="admTagColour" class="hx-in hx-in--sm"><option value="">TAG COLOUR: KEEP</option>${(p.colours || []).map((c) => `<option value="${esc(c.id)}"${c.id === p.colour ? ' selected' : ''}>${esc(c.id.toUpperCase())}</option>`).join('')}</select>`;
    const ident = card(tr('m.c_identity'), `<div class="hx-form"><input id="admName" class="hx-in" maxlength="48" value="${esc(d.label)}" placeholder="NAME"><input id="admTag" class="hx-in hx-in--tag" maxlength="8" value="${esc(d.short)}" placeholder="TAG">${tagCol}</div>${emblem}<div class="hx-form">${btn(tr('m.b_save_identity'), 'admIdentity', '', 'hx-btn--go')}${btn(tr('m.b_clear_briefing'), 'admClear')}</div><p class="hx-muted">Briefing: ${esc(d.description || '- empty -')}</p>`, 'hx-row hx-span2" style="--i:' + (i++));

    const danger = card(tr('m.c_danger_zone'), `<p>${d.isConfig ? 'Lore factions are emptied (members and flags cleared), never deleted.' : 'Removes every member, flag and permission row, then deletes the faction.'}</p>${btn(tr('m.b_force_disband'), 'admDisband', '', 'hx-btn--bad')}`, 'hx-row hx-span2 hx-alert" style="--i:' + (i++));

    return `<div class="hx-grid hx-adm">${picker}${head}${prog}${skills}${mem}${missions}${flags}${ident}${danger}</div>`;
}

// Admin actions, called from hubAction's default branch.
async function admAction(a, ds) {
    switch (a) {
    case 'admRefresh': return admLoad(true);
    case 'admOpen': S.adm.id = ds.id; S.adm.detail = null; renderStage(); return admLoad();
    case 'admProg': { const v = admNum('admXp'); if (v === null) return toast(tr('m.a_enter_number', { fallback: 'Enter a number.' }), 'bad'); return admDo('progress', { op: ds.op, value: v }, tr('m.a_xp', { fallback: 'XP updated.' })); }
    case 'admLevelSet': { const v = admNum('admLevel'); if (v === null) return toast(tr('m.a_enter_level', { fallback: 'Enter a level.' }), 'bad'); return admDo('progress', { op: 'setLevel', value: v }, tr('m.a_level_set', { fallback: 'Level set.' })); }
    case 'admPts': { const v = admNum('admPts'); if (v === null) return toast(tr('m.a_enter_number', { fallback: 'Enter a number.' }), 'bad'); return admDo('points', { op: ds.op, value: v }, tr('m.a_points_upd', { fallback: 'Skill points updated.' })); }
    case 'admBank': { const v = admNum('admBank'); if (v === null) return toast(tr('m.t_enter_amount', { fallback: 'Enter an amount.' }), 'bad'); return admDo('treasury', { op: ds.op, value: v }, tr('m.a_treasury_upd', { fallback: 'Treasury updated.' })); }
    case 'admRep': { const v = admNum('admRep'); if (v === null) return toast(tr('m.a_enter_number', { fallback: 'Enter a number.' }), 'bad'); const who = val('admRepWho'); return admDo('reputation', { op: ds.op, value: v, charId: who ? Number(who) : undefined }, tr('m.a_rep_upd', { fallback: 'Reputation updated.' })); }
    case 'admSkill': return admDo('skill', { skillId: ds.sk, rank: Number(ds.rank) }, tr('m.a_skill_upd', { fallback: 'Skill updated.' }));
    case 'admAdd': {
        const pick = val('admAddWho'), cid = admNum('admAddCid');
        const args = { rank: val('admAddRank') || 'member' };
        if (cid) args.charId = cid;
        else if (pick.startsWith('s:')) args.serverId = Number(pick.slice(2));
        else if (pick.startsWith('c:')) args.charId = Number(pick.slice(2));
        else return toast(tr('m.a_pick_player', { fallback: 'Pick a player or enter a character id.' }), 'bad');
        return admDo('addMember', args, tr('m.a_member_added', { fallback: 'Member added.' }));
    }
    case 'admRemove': return admDo('removeMember', { charId: Number(ds.char) }, tr('m.a_member_removed', { fallback: 'Member removed.' }));
    case 'admTransfer': return admDo('transfer', { charId: Number(ds.char) }, tr('m.a_transferred', { fallback: 'Leadership transferred.' }));
    case 'admComplete': return admDo('completeMission', { period: ds.period, slot: Number(ds.slot) }, tr('m.a_mission_done', { fallback: 'Mission completed.' }));
    case 'admReroll': return admDo('reroll', { period: ds.period }, tr('m.a_rerolled', { fallback: 'Board rerolled.' }));
    case 'admCooldowns': return admDo('resetCooldowns', {}, tr('m.a_caps_reset', { fallback: 'Daily caps reset.' }));
    case 'admFlagTp': { const r = await fx('factions:admin:flagTeleport', { flagId: Number(ds.flag) }); if (r.ok) toast(tr('m.a_teleported', { fallback: 'Teleported.' })); return; }
    case 'admFlagRm': return admDo('flagRemove', { flagId: Number(ds.flag) }, tr('m.a_flag_removed', { fallback: 'Flag removed.' }));
    case 'admIdentity': {
        const args = { label: val('admName'), short: val('admTag'), mark: val('adminFactionLogoMark'), color: val('adminFactionLogoColor') };
        const tc = val('admTagColour'); if (tc) args.tagColour = tc;
        return admDo('identity', args, tr('m.a_identity_saved', { fallback: 'Identity saved.' }));
    }
    case 'admClear': return admDo('clearBriefing', {}, tr('m.a_briefing_cleared', { fallback: 'Briefing cleared.' }));
    case 'admDisband': return admDo('disband', {}, tr('m.a_disbanded', { fallback: 'Faction disbanded.' }));
    default: return;
    }
}

function updateEmblemPreview(prefix) { const mark=(document.getElementById(`${prefix}LogoMark`) || {}).value || 'shield'; const colour=(document.getElementById(`${prefix}LogoColor`) || {}).value || '#e08c46'; const preview=document.getElementById(`${prefix}EmblemPreview`);if(preview){preview.textContent=FACTION_MARKS[mark] || FACTION_MARKS.shield;preview.style.setProperty('--crest',colour);} }

// Faction actions: description, emblem, invite, promote, kick, ...
function wireFaction(stage) {
    stage.querySelectorAll('[data-faction-open]').forEach(b => b.addEventListener('click', () => { S.factionView=b.dataset.factionOpen;renderStage(); }));
    const back=stage.querySelector('[data-faction-back]');if(back)back.addEventListener('click',()=>{S.factionView=null;renderStage();});const adminBack=stage.querySelector('[data-admin-back]');if(adminBack)adminBack.addEventListener('click',()=>{S.factionAdminView=null;renderStage();});
    stage.querySelectorAll('[data-emblem-select]').forEach(b => b.addEventListener('click',()=>{const input=document.getElementById(`${b.dataset.emblemSelect}LogoMark`);if(input){input.value=b.dataset.mark;updateEmblemPreview(b.dataset.emblemSelect);stage.querySelectorAll(`[data-emblem-select="${b.dataset.emblemSelect}"]`).forEach(x=>x.classList.toggle('is-selected',x.dataset.mark===b.dataset.mark));}}));
    stage.querySelectorAll('[id$="LogoMark"],[id$="LogoColor"]').forEach(x=>x.addEventListener('input',()=>updateEmblemPreview(x.id.replace(/Logo(?:Mark|Color)$/,''))));
    stage.querySelectorAll('[data-act]').forEach(b=>b.addEventListener('click',()=>{
        const act=b.dataset.act,target=b.dataset.target;
        // destructive ones want a second click first
        if((act==='leave'||act==='disband'||act==='kick')&&!armed(b))return;
        once(async()=>{
            if(act==='create'){const name=(document.getElementById('facName')||{}).value||'',short=(document.getElementById('facTag')||{}).value||'';if(name.trim().length<3)return toast('Name needs 3+ characters.','bad');return factionPost('factionCreate',{name:name.trim(),short:short.trim()});}
            if(act==='description')return factionPost('factionDescription',{description:(document.getElementById('factionDescription')||{}).value||''});
            if(act==='logo')return factionPost('factionLogo',{mark:(document.getElementById('factionLogoMark')||{}).value,color:(document.getElementById('factionLogoColor')||{}).value});
            if(act==='adminUpdate')return factionPost('factionAdminUpdate',{id:b.dataset.factionId,description:(document.getElementById('adminFactionDescription')||{}).value||'',mark:(document.getElementById('adminFactionLogoMark')||{}).value,color:(document.getElementById('adminFactionLogoColor')||{}).value});
            if(act==='adminAssignVanilla')return factionPost('factionAdminAssignVanilla',{id:b.dataset.factionId,characterId:(document.getElementById('adminVanillaOwner')||{}).value});
            if(act==='accept')return factionPost('factionAccept');
            if(act==='joinVanilla')return factionPost('factionJoin',{id:b.dataset.id});
            if(act==='leave')return factionPost('factionLeave');
            if(act==='disband')return factionPost('factionDisband');
            if(act==='invite')return factionPost('factionInvite',{target});
            if(act==='kick')return factionPost('factionKickChar',{charId:b.dataset.char});
            if(act==='promote')return factionPost('factionPromoteChar',{charId:b.dataset.char,rank:b.dataset.rank});
        });
    }));
}

/* Destructive buttons need a second click within 3 s. */
function armed(el) {
    if (el.dataset.armed) return true;
    el.dataset.armed = '1';
    const was = el.textContent;
    el.textContent = tr('m.confirm');
    el.classList.add('is-armed');
    setTimeout(() => { if (el.isConnected) { delete el.dataset.armed; el.textContent = was; el.classList.remove('is-armed'); } }, 3000);
    return false;
}
const HX_CONFIRM = ['jobLeave', 'jobKick', 'jobAbandon', 'jobPay', 'jobRelease', 'fRankDel', 'raidDeclare', 'admRemove', 'admTransfer', 'admDisband', 'admFlagRm', 'admClear', 'admReroll', 'admComplete', 'squadLeave', 'squadDisband', 'squadKick', 'squadTransfer', 'snIssue', 'snLift', 'jailRmCell', 'jailRelease'];

const val = (id) => String((document.getElementById(id) || {}).value || '').trim();

// Rank edits change labels everywhere (roster, hero, treasury), so the panel is fetched again too.
async function afterRanks(r) {
    if (r && r.ok) {
        S.hub.ranks = r;
        delete S.hub.treasury;
        const p = await post('fx', { name: 'factions:panel' });
        if (p && p.ok) S.faction = p;
    }
    renderStage();
}

async function afterSquad(r) {
    if (r && r.ok) { delete S.hub.roster; await reload('squad'); }
    else renderStage();
}

async function hubAction(el) {
    const a = el.dataset.hx, ds = el.dataset;
    const draft = S.rankDraft && S.rankDraft.ranks;
    switch (a) {
    case 'refreshTab': delete S.hub[S.hubTab]; return renderStage();
    case 'squadCreate': {
        const name = val('sqName');
        if (name.length < 2) return toast('Pick a squad name (2+ characters).', 'bad');
        return afterSquad(await fx('squad:create', { name }));
    }
    case 'squadConsole': return post('openSquadConsole');
    case 'raidDeclare': {
        const r = await fx('raids:declare', { id: ds.id });
        if (r.ok) toast(tr('m.raid_sent'));
        return reload('raids');
    }
    case 'squadAccept': return afterSquad(await fx('squad:accept'));
    case 'squadDecline': return afterSquad(await fx('squad:decline'));
    case 'squadLeave': return afterSquad(await fx('squad:leave'));
    case 'squadDisband': return afterSquad(await fx('squad:disband'));
    case 'squadKick': return afterSquad(await fx('squad:kick', { charId: Number(ds.char) }));
    case 'squadTransfer': return afterSquad(await fx('squad:transfer', { charId: Number(ds.char) }));
    case 'squadRename': return afterSquad(await fx('squad:rename', { name: val('sqRename') }));
    case 'squadInvite': {
        const r = await fx('squad:invite', { target: Number(ds.target) });
        if (r.ok) toast(tr('m.t_squad_invite', { fallback: 'Squad invite sent.' }));
        return;
    }
    case 'rankAdd': if (draft) draft.push({ label: tr('m.new_rank') }); return renderStage();
    case 'rankDel': if (draft) draft.splice(Number(ds.idx), 1); return renderStage();
    case 'rankUp': case 'rankDown': {
        const i = Number(ds.idx), j = a === 'rankUp' ? i - 1 : i + 1;
        if (draft && j >= 0 && j < draft.length) { const t = draft[i]; draft[i] = draft[j]; draft[j] = t; }
        return renderStage();
    }
    case 'rankSave': {
        const r = await fx('squad:saveRanks', { ranks: draft || [] });
        if (r.ok) { S.rankDraft = null; toast(tr('m.t_ranks_saved', { fallback: 'Ranks saved.' })); }
        return afterSquad(r);
    }
    case 'bankQuick': { const i = $('bankAmount'); if (i) i.value = ds.v; return; }
    case 'bankDeposit': case 'bankWithdraw': {
        const amount = Math.floor(Number(val('bankAmount')));
        if (!Number.isFinite(amount) || amount < 1) return toast(tr('m.t_enter_amount', { fallback: 'Enter an amount.' }), 'bad');
        const r = await post(a === 'bankDeposit' ? 'factionBankDeposit' : 'factionBankWithdraw', { amount });
        if (r && r.faction) S.faction = r.faction;
        return reload('treasury');
    }
    case 'setCap': {
        const amount = Math.floor(Number(val('cap_' + ds.rank)));
        const r = await fx('factions:bank:setCap', { rank: ds.rank, amount });
        if (r.ok) toast(tr('m.t_cap_saved', { fallback: 'Cap saved.' }));
        return reload('treasury');
    }
    case 'fRankAdd': {
        const r = await fx('factions:ranks:create', { label: val('fRankNew') });
        return afterRanks(r);
    }
    case 'fRankMove': return afterRanks(await fx('factions:ranks:move', { rank: ds.rank, dir: ds.dir }));
    case 'fRankDel': return afterRanks(await fx('factions:ranks:delete', { rank: ds.rank }));
    case 'perm': {
        const r = await fx('factions:perms:set', { rank: ds.rank, perm: ds.perm, bool: ds.on !== '1' });
        if (r.ok) S.hub.ranks = r;
        return renderStage();
    }
    case 'snIssue': {
        const r = await fx('sanctions:issue', { targetCharId: Number(val('snTarget')), template: val('snTemplate'), minutes: Number(val('snMinutes')), reason: val('snReason') });
        if (r.ok) toast(tr('m.t_sanction', { minutes: r.minutes, fallback: `Sanction issued (${r.minutes} min).` }));
        return reload('sanctions');
    }
    case 'snLift': {
        const r = await fx('sanctions:lift', { id: Number(ds.id) });
        if (r.ok) toast(tr('m.t_sanction_lifted', { fallback: 'Sanction lifted.' }));
        return reload('sanctions');
    }
    case 'jailOrigin': {
        const radius = Number(val('jlRadius'));
        await fx('jail:setOrigin', radius > 0 ? { radius } : {});
        return reload('jail');
    }
    case 'jailExit': await fx('jail:setExit'); return reload('jail');
    case 'jailCell': await fx('jail:addCell'); return reload('jail');
    case 'jailRmCell': await fx('jail:removeCell', { n: Number(ds.n) }); return reload('jail');
    case 'jailRelease': await fx('jail:release', { charId: Number(ds.char) }); return reload('jail');
    case 'msDeliver': {
        const r = await fx('factions:missions:deliver', { period: ds.period, slot: Number(ds.slot) });
        if (r.ok) { toast(tr('m.t_delivered', { n: num(r.delivered), fallback: `Delivered ${num(r.delivered)}.` })); if (S.hub.progress) S.hub.progress.missions = r; }
        return reload('progress');
    }
    case 'skSpend': {
        const r = await fx('factions:skills:spend', { skillId: ds.id });
        if (r.ok) toast(tr('m.t_skill_upgraded', { fallback: 'Skill upgraded.' }));
        return reload('progress');
    }
    case 'donate': {
        const amount = Math.floor(Number(val('donAmount')));
        if (!Number.isFinite(amount) || amount < 1) return toast(tr('m.t_enter_amount', { fallback: 'Enter an amount.' }), 'bad');
        const r = await fx('factions:donate', { amount });
        if (r.ok) toast(tr('m.t_donated', { amount: num(r.donated), xp: num(r.xp), left: num(r.xpLeftToday), fallback: `Donated $${num(r.donated)} · +${num(r.xp)} XP (${num(r.xpLeftToday)} left today)` }));
        return reload('progress');
    }
    case 'cosColour': case 'cosStyle': {
        const r = await fx('factions:cosmetics:set', a === 'cosColour' ? { colour: ds.id } : { style: ds.id });
        if (r.ok && S.hub.progress && S.hub.progress.prog) S.hub.progress.prog.cosmetics = r;
        return renderStage();
    }
    case 'pref': {
        const r = await post('hubPrefSet', { key: ds.key, value: ds.on !== '1' });
        if (r && r.ok) S.hub.settings = r;
        return renderStage();
    }
    default: if (a && a.startsWith('job')) return jobAction(a, ds); if (a && a.startsWith('adm')) return admAction(a, ds); return;
    }
}

// Faction jobs (bs_jobs): JOBS, JOB BOARD and JOB SCORES tabs. The server decides everything.
S.jobScore = 'week';
HUB_LOAD.jobs = () => fx('jobs:overview');
HUB_LOAD.board = () => fx('jobs:board');
HUB_LOAD.jobscore = () => fx('jobs:scores', { period: S.jobScore });

HUB_RENDER.jobs = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.tab_failed'));
    let i = 0;
    const row = () => `hx-row" style="--i:${i++}`;
    let mine;
    if (d.mine && d.mine.status === 'active') {
        mine = `<p><b>${esc(d.mine.label).toUpperCase()}</b></p><p class="hx-muted">${tr('m.j_leave_note', { h: num((d.settings || {}).leaveHours || 24) })}</p><div class="hx-form">${btn(tr('m.j_leave'), 'jobLeave', '', 'hx-btn--bad')}</div>`;
    } else if (d.mine) {
        mine = `<p>${tr('m.j_pending', { job: esc(d.mine.label) })}</p><div class="hx-form">${btn(tr('m.j_withdraw'), 'jobWithdraw')}</div>`;
    } else {
        mine = `<p>${tr('m.j_none')}</p>${d.cooldown > 0 ? `<p class="hx-muted">${tr('m.j_cooldown', { t: dur(d.cooldown) })}</p>` : ''}`;
    }
    const busy = !!d.mine;
    const jobs = (d.jobs || []).map((j, k) => {
        const full = (j.members || []).length >= j.cap;
        const who = (j.members || []).map((m) => `<span class="hx-tag">${m.online ? '● ' : ''}${esc(m.name)}${d.canManage && !m.you ? ` <a data-hx="jobKick" data-cid="${m.cid}">✕</a>` : ''}</span>`).join(' ');
        const act = busy ? '<span></span>' : (full ? `<span class="hx-tag">${tr('m.j_full')}</span>` : btn(tr('m.j_apply'), 'jobApply', `data-id="${esc(j.id)}"`, 'hx-btn--sm hx-btn--go'));
        return `<div class="hx-line hx-row" style="--i:${k}"><span><b>${esc(j.label)}</b> ${j.special ? `<span class="hx-tag">${tr('m.j_special')}</span>` : ''} <span class="hx-muted">${(j.members || []).length}/${j.cap}</span><small class="hx-muted" style="display:block">${esc(j.blurb)}</small>${who ? `<small style="display:block">${who}</small>` : ''}</span>${act}</div>`;
    }).join('') || empty(tr('m.none'));
    let out = card(tr('m.j_my_job'), mine, row()) + card(tr('m.j_jobs'), `<div class="hx-list">${jobs}</div>`, 'hx-span2 ' + row());
    if (d.canManage) {
        const apps = (d.applications || []).map((a, k) => `<div class="hx-line hx-row" style="--i:${k}"><span><b>${esc(a.name)}</b> <span class="hx-muted">${esc(a.jobLabel)}</span></span><span>${btn(tr('m.j_approve'), 'jobApprove', `data-cid="${a.cid}" data-yes="1"`, 'hx-btn--sm hx-btn--go')}${btn(tr('m.j_decline'), 'jobApprove', `data-cid="${a.cid}" data-yes="0"`, 'hx-btn--sm')}</span></div>`).join('') || empty(tr('m.j_no_apps'));
        out += card(tr('m.j_apps'), `<div class="hx-list">${apps}</div>`, row());
    }
    if (d.pool && d.canManage) {
        const pool = d.pool.map((p, k) => `<div class="hx-line hx-row" style="--i:${k}"><span>${esc(p.label)}</span>${btn(p.picked ? tr('m.j_unpick') : tr('m.j_pick'), 'jobPick', `data-id="${esc(p.id)}" data-on="${p.picked ? 0 : 1}"`, 'hx-btn--sm' + (p.picked ? ' hx-btn--bad' : ''))}</div>`).join('');
        out += card(tr('m.j_pool', { n: num((d.settings || {}).maxPicks || 2) }), `<p class="hx-muted">${tr('m.j_pool_note')}</p><div class="hx-list">${pool}</div>`, row());
        out += card(tr('m.j_station'), `<p>${tr('m.j_station_note')}</p><div class="hx-form">${btn(tr('m.j_place'), 'jobStation', '', 'hx-btn--go')}</div>`, row());
    }
    if ((d.ransoms || []).length) {
        const r = d.ransoms.map((x, k) => `<div class="hx-line hx-row" style="--i:${k}"><span><b>${esc(x.name)}</b> <span class="hx-muted">$${num(x.amount)} · ${tr('m.j_left', { t: dur(x.left) })}</span></span><span>${btn(tr('m.j_pay_cash'), 'jobPay', `data-target="${x.target}" data-from="cash"`, 'hx-btn--sm hx-btn--go')}${d.canTreasury ? btn(tr('m.j_pay_treasury'), 'jobPay', `data-target="${x.target}" data-from="treasury"`, 'hx-btn--sm') : ''}</span></div>`).join('');
        out += card(tr('m.j_ransoms'), `<div class="hx-list">${r}</div>`, 'hx-alert ' + row());
    }
    if ((d.captives || []).length) {
        const c = d.captives.map((x, k) => `<div class="hx-line hx-row" style="--i:${k}"><span><b>${esc(x.name)}</b> <span class="hx-muted">${x.ransom ? '$' + num(x.ransom) + ' · ' : ''}${tr('m.j_left', { t: dur(x.left) })}</span></span><span>${x.hasFaction ? `<input id="ransom_${x.target}" class="hx-in hx-in--sm" inputmode="numeric" placeholder="$ ≤ ${num((d.settings || {}).ransomCap || 0)}">${btn(tr('m.j_set_ransom'), 'jobRansom', `data-target="${x.target}"`, 'hx-btn--sm hx-btn--go')}` : ''}${btn(tr('m.j_release'), 'jobRelease', `data-target="${x.target}"`, 'hx-btn--sm')}</span></div>`).join('');
        out += card(tr('m.j_captives'), `<div class="hx-list">${c}</div>`, row());
    }
    return `<div class="hx-grid">${out}</div>`;
};

function jobContract(c, k) {
    const pct = c.target ? Math.min(100, ((c.progress || 0) / c.target) * 100) : 0;
    let act = '<span></span>';
    if (c.mine) act = `<span>${c.turnIn ? btn(tr('m.b_turnin'), 'jobTurnIn', `data-id="${c.id}"`, 'hx-btn--sm hx-btn--go') : ''}${btn(tr('m.b_drop'), 'jobAbandon', `data-id="${c.id}"`, 'hx-btn--sm hx-btn--bad')}</span>`;
    else if (c.canTake) act = btn(tr('m.b_take'), 'jobTake', `data-id="${c.id}"`, 'hx-btn--sm hx-btn--go');
    return `<div class="hx-mission hx-row" style="--i:${Math.min(k, 20)}"><span class="hx-tag">${esc(c.jobLabel)}</span><span class="hx-mission__txt"><b>${esc(c.label)}</b><small>${num(c.progress || 0)} / ${num(c.target || 1)} · ${tr('m.b_reward', { rep: num(c.rep), xp: num(c.xp) })}${c.left ? ' · ' + tr('m.j_left', { t: dur(c.left) }) : ''}</small><i class="hx-bar"><em style="width:${pct}%"></em></i></span>${act}</div>`;
}

HUB_RENDER.board = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.tab_failed'));
    const list = d.contracts || [];
    const mine = list.filter((c) => c.mine);
    const busy = mine.length > 0;
    const open = list.filter((c) => !c.mine).map((c) => Object.assign(c, { canTake: !busy && d.job === c.job }));
    const note = `<p class="hx-muted">${tr('m.b_note', { r: num(d.refreshMin || 0), t: num(d.takenMinutes || 0) })}</p>${d.job ? '' : `<p>${tr('m.b_need_job')}</p>`}`;
    return `<div class="hx-grid">
        ${mine.length ? card(tr('m.b_mine'), `<div class="hx-list">${mine.map(jobContract).join('')}</div>`, 'hx-row hx-span2" style="--i:0') : ''}
        ${card(tr('m.b_contracts'), `${note}<div class="hx-head"><span></span>${btn(tr('m.b_refresh'), 'refreshTab')}</div><div class="hx-list hx-list--scroll">${open.map(jobContract).join('') || empty(tr('m.b_none'))}</div>`, 'hx-row hx-span2" style="--i:1')}
    </div>`;
};

HUB_RENDER.jobscore = (f, d) => {
    if (!d.ok) return empty(d.error || tr('m.tab_failed'));
    const rows = d.rows || [];
    const tabs = `<div class="hx-form">${btn(tr('m.s_week'), 'jobScore', 'data-p="week"', S.jobScore === 'week' ? 'hx-btn--go' : '')}${btn(tr('m.s_all'), 'jobScore', 'data-p="all"', S.jobScore === 'all' ? 'hx-btn--go' : '')}</div>`;
    const list = (key) => rows.slice().sort((a, b) => b[key] - a[key]).filter((r) => r[key] > 0).map((r, k) => `<div class="hx-line hx-row" style="--i:${Math.min(k, 20)}"><em class="hx-idx">${k + 1}</em><span>${r.you ? '<b>' : ''}${esc(r.name)}${r.you ? '</b>' : ''} <span class="hx-muted">${esc(r.job || '')}</span></span><b>${num(r[key])}</b></div>`).join('') || empty(tr('m.s_none'));
    return `<div class="hx-grid">${card(tr('m.tab_jobscore'), tabs, 'hx-row hx-span2" style="--i:0')}${card(tr('m.s_by_rep'), `<div class="hx-list">${list('rep')}</div>`, 'hx-row" style="--i:1')}${card(tr('m.s_by_contracts'), `<div class="hx-list">${list('contracts')}</div>`, 'hx-row" style="--i:2')}</div>`;
};

async function jobAction(a, ds) {
    const after = async (r, tab, msg) => {
        if (r && r.ok) { if (msg) toast(msg); delete S.hub.jobs; delete S.hub.board; await reload(tab || S.hubTab); }
        else renderStage();
    };
    switch (a) {
    case 'jobApply': return after(await fx('jobs:apply', { job: ds.id }), 'jobs');
    case 'jobWithdraw': return after(await fx('jobs:withdraw'), 'jobs');
    case 'jobLeave': return after(await fx('jobs:leave'), 'jobs');
    case 'jobApprove': return after(await fx('jobs:approve', { cid: Number(ds.cid), yes: ds.yes === '1' }), 'jobs');
    case 'jobKick': return after(await fx('jobs:kick', { cid: Number(ds.cid) }), 'jobs');
    case 'jobPick': return after(await fx('jobs:pick', { job: ds.id, on: ds.on === '1' }), 'jobs');
    case 'jobStation': return after(await fx('jobs:placeStation'), 'jobs');
    case 'jobPay': return after(await fx('jobs:kid:pay', { target: Number(ds.target), from: ds.from }), 'jobs');
    case 'jobRansom': return after(await fx('jobs:kid:ransom', { target: Number(ds.target), amount: Number(val('ransom_' + ds.target)) }), 'jobs');
    case 'jobRelease': return after(await fx('jobs:kid:release', { target: Number(ds.target) }), 'jobs');
    case 'jobTake': return after(await fx('jobs:take', { id: Number(ds.id) }), 'board');
    case 'jobAbandon': return after(await fx('jobs:abandon', { id: Number(ds.id) }), 'board');
    case 'jobTurnIn': return after(await fx('jobs:turnin', { id: Number(ds.id) }), 'board');
    case 'jobScore': S.jobScore = ds.p === 'all' ? 'all' : 'week'; return reload('jobscore');
    default: return;
    }
}

// One set of delegated listeners on the stage, bound once.
(function wireHub() {
    const stage = $('stage');
    if (!stage) return;
    stage.addEventListener('click', (e) => {
        if (S.current !== 'faction') return;
        const tabBtn = e.target.closest('[data-hubtab]');
        if (tabBtn) {
            S.hubTab = tabBtn.dataset.hubtab;
            S.factionView = null; S.factionAdminView = null;
            return renderStage();
        }
        const adm = e.target.closest('[data-admin-faction]');
        if (adm) { S.factionAdminView = adm.dataset.adminFaction; return renderStage(); }
        const uia = e.target.closest('[data-uiscale-auto]');
        if (uia) { const on = uia.dataset.uiscaleAuto === '1'; uiScaleSet(on ? (window.BSScale ? window.BSScale.get() : 1) : 0); return; }
        const el = e.target.closest('[data-hx]');
        if (!el || el.disabled) return;
        if (HX_CONFIRM.includes(el.dataset.hx) && !armed(el)) return;
        once(() => hubAction(el));
    });
    stage.addEventListener('change', (e) => {
        const el = e.target.closest('[data-hxchange]');
        if (!el) return;
        const k = el.dataset.hxchange;
        if (k === 'squadRank') once(async () => afterSquad(await fx('squad:setRank', { charId: Number(el.dataset.char), rankId: Number(el.value) })));
        else if (k === 'admPick') { S.adm.id = el.value || null; S.adm.detail = null; renderStage(); if (S.adm.id) admLoad(); }
        else if (k === 'admRank') once(() => admDo('setRank', { charId: Number(el.dataset.char), rank: el.value }, tr('m.a_rank_set', { fallback: 'Rank set.' })));
        else if (k === 'facRank') once(() => factionPost('factionPromoteChar', { charId: el.dataset.char, rank: el.value }));
        else if (k === 'fRankName') once(async () => afterRanks(await fx('factions:ranks:rename', { rank: el.dataset.rank, label: el.value })));
        else if (k === 'snTemplate') { S.snTemplate = el.value; renderStage(); }
        else if (k === 'uiscale') uiScaleSet(Number(el.value) / 100);
        else if (k === 'range') once(async () => { const r = await post('hubPrefSet', { key: 'range', value: Number(el.value) }); if (r && r.ok) S.hub.settings = r; renderStage(); });
    });
    stage.addEventListener('input', (e) => {
        const el = e.target;
        if (!el.dataset) return;
        if (el.dataset.rankedit !== undefined && S.rankDraft) {
            const r = S.rankDraft.ranks[Number(el.dataset.rankedit)];
            if (r) r.label = el.value;
        } else if (el.dataset.hxchange === 'uiscale') {
            const o = $('uiScaleVal'); if (o) o.textContent = el.value + '%';
        } else if (el.dataset.hxchange === 'range') {
            const o = $('rangeVal'); if (o) o.textContent = el.value + ' m';
        }
    });
})();

// from client

window.addEventListener('message', (e) => {
    const d = e.data || {};

    if (d.action === 'open') {
        // The opening U keyup may arrive after the NUI is visible; do not let it close us.
        ignoreInitialURelease = true;
        S.entries = d.entries || [];
        S.data = d.data || null;
        S.emotes = d.emotes || [];
        S.clothing = d.clothing || [];
        S.recipes = d.recipes || [];
        S.build = d.build || null;
        S.faction = d.faction || null;
        S.tagPrefs = d.tagPrefs || null;
        // fresh data every time the hub opens
        S.hub = {}; S.hubBusy = {}; S.hubLastTab = null; S.rankDraft = null;
        S.adm.overview = null; S.adm.detail = null;
        // d.tab (e.g. the N key) opens a specific panel; plain U still remembers the last tab.
        S.current = d.tab || S.current || 'stats';
        document.body.classList.toggle('faction-only', d.tab === 'faction');
        document.body.classList.toggle('single-panel', Boolean(d.tab) && d.tab !== 'faction');

        $('name').textContent = S.data?.name || tr('m.survivor');
        $('class').textContent = S.data?.class || '';
        $('levelLine').textContent = tr('m.level_n', { n: S.data?.level ?? 1 });

        renderRail();
        renderStage();
        $('root').classList.remove('hidden');
    }

    if (d.action === 'close') $('root').classList.add('hidden');

    // Live squad change while the hub is open.
    if (d.action === 'squadSync') {
        if (S.hub.squad && S.hub.squad.ok) S.hub.squad.squad = d.squad || null;
        delete S.hub.roster;
        const typing = document.activeElement && /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName);
        if (S.current === 'faction' && S.hubTab === 'squad' && !typing) renderStage();
    }
});

// The U press that opens Faction ends as a keyup once NUI has focus. Ignore that one release so the panel does not behave like hold-to-view; later U presses toggle-close as normal.
let ignoreInitialURelease = false;

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') {
        post('close');
        return;
    }
    if (e.key === 'u' || e.key === 'U') {
        if (ignoreInitialURelease) {
            ignoreInitialURelease = false;
            return;
        }
        post('close');
    }
});


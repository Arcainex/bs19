// BeyondSurvival - scoreboard NUI. Display only, never takes focus.

const $ = (id) => document.getElementById(id);
const MAX_PLAYERS_SHOWN = 22;

function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
const num = (n) => Number(n || 0).toLocaleString('en-GB');
// only plain colours from bs_vip, nothing that could break out of style=""
const safeColour = (c) => (/^#[0-9a-f]{3,8}$|^[a-z]{3,20}$|^rgba?\([\d.,\s%]+\)$/i.test(String(c || '')) ? c : null);

function playerRow(p, self) {
    const bars = p.ping < 80 ? 3 : p.ping < 160 ? 2 : 1;
    const col = p.vip ? safeColour(p.vipColour) : null;
    const nameStyle = col ? ` style="color:${col}"` : '';
    const tag = p.factionTag ? `<b class="tag">${esc(p.factionTag)}</b>` : '';
    const vip = p.vip ? `<i class="badge badge--vip"${col ? ` style="border-color:${col};color:${col}"` : ''}>${esc(p.vipLabel || 'VIP')}</i>` : '';
    return `
    <div class="prow row${p.id === self ? ' is-self' : ''}${p.vip ? ' is-vip' : ''}">
        <span class="mono dim">${esc(p.id)}</span>
        <span class="cell name">${tag}<span class="ell"${nameStyle}>${esc(p.name)}</span>${vip}</span>
        <span class="ell dim">${esc(p.class || '')}</span>
        <span class="r mono">${p.level ? esc(p.level) : '-'}</span>
        <span class="r ping ping--${bars}"><span class="mono">${esc(p.ping ?? '')}</span><i></i><i></i><i></i></span>
    </div>`;
}

function board(label, rows, fmt) {
    const body = rows.length ? rows.map((r) => `
        <div class="brow row${r.rank === 1 ? ' is-first' : ''}">
            <span class="mono rank">${esc(r.rank)}</span>
            ${fmt(r)}
        </div>`).join('') : `<p class="hollow">${esc(t('ui.nobody_yet', { fallback: 'Nobody yet.' }))}</p>`;
    return `<div class="panel board"><h2 class="panel__label">${esc(label)}</h2>${body}</div>`;
}

function render(d) {
    $('title').textContent = String(d.title || 'BEYOND SURVIVAL');
    $('subtitle').textContent = String(d.subtitle || '');
    $('count').textContent = d.count ?? 0;
    $('max').textContent = `/ ${d.max ?? 32}`;

    const players = d.players || [];
    const me = players.find((p) => p.id === d.self);

    // VIP banner hook: a thin strip for the viewer's own banner choice
    const strip = $('vipStrip');
    if (me && me.vip && me.vipBanner) {
        const col = safeColour(me.vipColour);
        strip.textContent = `${me.vipLabel || 'VIP'} · ${me.vipBanner}`;
        strip.style.setProperty('--vip', col || '#e08c46');
        strip.classList.remove('hidden');
    } else strip.classList.add('hidden');

    // own row first so it's never cut off by the cap
    const ordered = me ? [me, ...players.filter((p) => p !== me)] : players;
    const shown = ordered.slice(0, MAX_PLAYERS_SHOWN);
    const extra = ordered.length - shown.length;
    $('players').innerHTML = shown.map((p) => playerRow(p, d.self)).join('')
        + (extra > 0 ? `<p class="hollow">+ ${extra} more out there</p>` : '')
        || `<p class="hollow">${esc(t('ui.nobody_else', { fallback: 'Nobody else is out there.' }))}</p>`;

    const boards = (d.boards || []).map((b) => board(b.label, b.rows || [], (r) => `
            <span class="ell">${esc(r.name)}</span>
            <span class="r mono val">${num(r.value)}<small>${esc((b.suffix || '').trim())}</small></span>`));

    boards.push(board(t('ui.faction_rankings', { fallback: 'FACTION RANKINGS' }), d.factions || [], (f) => `
            <span class="cell">${f.tag ? `<b class="tag">${esc(f.tag)}</b>` : ''}<span class="ell">${esc(f.name)}</span></span>
            <span class="r mono val"><i class="badge">LV ${esc(f.level)}</i> ${num(f.xp)}<small>XP</small> <em class="dim">${esc(f.members)}&#9679;</em></span>`));

    $('boards').innerHTML = boards.join('');
}

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') { render(d.data || {}); $('root').classList.remove('hidden'); }
    if (d.action === 'update' && !$('root').classList.contains('hidden')) render(d.data || {});
    if (d.action === 'close') $('root').classList.add('hidden');
});

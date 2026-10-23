// Squad console. Talks to cl_squad.lua through squadFx / squadClose.
(() => {
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_factions';
const post = (ep, data = {}) => fetch(`https://${RES}/${ep}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
    .then((r) => r.json()).catch(() => ({ ok: false, error: t('sq.no_answer') }));
const fx = (name, args) => post('squadFx', { name, args: args || {} });
const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const root = document.createElement('div'); root.id = 'sq';
const banner = document.createElement('div'); banner.id = 'sqBanner';
document.body.append(root, banner);

let S = { open: false, data: null, near: [], draft: null, key: 'F3' };
let poll = null, toastT = null, bannerT = null;

function toast(msg, bad) {
    const t = root.querySelector('.sq-toast'); if (!t) return;
    t.textContent = msg; t.className = 'sq-toast show' + (bad ? ' bad' : '');
    clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 2600);
}

function memberRow(m, sq, i) {
    const lead = sq.isLeader, me = m.charId === sq.myCharId;
    const hp = m.online && typeof m.health === 'number' ? `<div class="sq-hp"><b style="width:${m.health}%"></b></div>` : '';
    const status = m.online ? (typeof m.health === 'number' ? `${t('sq.online')} · ${m.health}% HP` : t('sq.online')) : t('sq.offline');
    let acts = '';
    if (lead && !me) {
        acts = `<select data-rank="${m.charId}">${sq.ranks.map((r) => `<option value="${r.id}"${r.id === m.rankId ? ' selected' : ''}>${esc(r.label)}</option>`).join('')}</select>`
            + `<button class="sm" data-a="transfer" data-c="${m.charId}" data-confirm>${t('sq.make_lead')}</button>`
            + `<button class="sm bad" data-a="kick" data-c="${m.charId}" data-confirm>${t('sq.kick')}</button>`;
    }
    return `<div class="sq-m ${m.online ? 'is-on' : 'is-off'}" style="--i:${i}"><i class="sq-dot"></i>
        <div><div class="sq-name">${esc(m.name || '?')}${m.isLeader ? `<em>${t('sq.lead')}</em>` : ''}${me ? `<em>${t('sq.you')}</em>` : ''}</div>
        <div class="sq-meta">${esc(m.rankLabel || '')}${m.level ? ' · LV ' + esc(m.level) : ''} · ${status}</div>${hp}</div>
        <div class="sq-acts">${acts}</div></div>`;
}

function render() {
    const d = S.data || {}, sq = d.squad, inv = d.invite;
    let body = '';
    const invCard = inv ? `<section class="sq-inv" style="--i:0"><h2>${t('sq.incoming')} <small>${Math.max(0, inv.expiresIn | 0)}S</small></h2>
        <p><b>${esc(inv.from)}</b> wants you in <b>${esc(inv.name)}</b>.</p>
        <div class="sq-row"><button class="go" data-a="accept">${t('sq.accept')}</button><button class="bad" data-a="decline">${t('sq.decline')}</button></div></section>` : '';
    if (!d.ok) {
        body = `<section><h2>${t('sq.signal_lost')}</h2><p>${esc(d.error || t('sq.no_service'))}</p></section>`;
    } else if (!sq) {
        body = `<div>${invCard}<section style="--i:1"><h2>${t('sq.form')}</h2><p>${t('sq.up_to', { n: d.maxSize || 5 })}</p>
            <div class="sq-row"><input id="sqNew" maxlength="24" placeholder="${t('sq.name_ph')}"><button class="go" data-a="create">${t('sq.create')}</button></div></section></div>
            <div><section style="--i:2"><h2>${t('sq.notes')}</h2><p>${t('sq.notes_text')}</p></section></div>`;
    } else {
        const online = sq.members.filter((m) => m.online).length;
        const left = `${invCard}<section style="--i:0"><h2>${t('sq.operatives')} <small>${t('sq.online_count', { on: online, total: sq.members.length, max: sq.maxSize })}</small></h2>
            ${sq.members.map((m, i) => memberRow(m, sq, i)).join('')}
            <div class="sq-row"><button class="bad" data-a="leave" data-confirm>${t('sq.leave')}</button>${sq.isLeader ? `<button class="bad" data-a="disband" data-confirm>${t('sq.disband')}</button>` : ''}</div></section>`;
        let right = '';
        if (sq.isLeader) {
            const near = S.near.length ? S.near.map((p, i) => `<div class="sq-m is-on" style="--i:${i}"><i class="sq-dot"></i><div><div class="sq-name">${esc(p.name)}</div><div class="sq-meta">${p.level ? t('sq.lv') + ' ' + esc(p.level) + ' · ' : ''}${p.dist} M</div></div><div class="sq-acts"><button class="sm go" data-a="invite" data-t="${p.src}">${t('sq.invite')}</button></div></div>`).join('')
                : `<div class="sq-empty">${t('sq.none_near')}</div>`;
            const dr = S.draft || sq.ranks.map((r) => ({ id: r.id, label: r.label }));
            S.draft = dr;
            right = `<section style="--i:1"><h2>${t('sq.recruit')} <small><button class="sm" data-a="scan">${t('sq.scan')}</button></small></h2>${near}</section>
                <section style="--i:2"><h2>${t('sq.squad_name')}</h2><div class="sq-row"><input id="sqRename" maxlength="24" value="${esc(sq.name)}"><button data-a="rename">${t('sq.save')}</button></div></section>
                <section style="--i:3"><h2>${t('sq.ranks')} <small>${t('sq.ranks_hint', { n: sq.maxRanks })}</small></h2>
                ${dr.map((r, i) => `<div class="sq-row"><input data-rk="${i}" maxlength="20" value="${esc(r.label)}"><button class="sm" data-a="rup" data-i="${i}">▲</button><button class="sm" data-a="rdown" data-i="${i}">▼</button>${dr.length > 1 ? `<button class="sm bad" data-a="rdel" data-i="${i}">✕</button>` : ''}</div>`).join('')}
                <div class="sq-row">${dr.length < sq.maxRanks ? `<button data-a="radd">${t('sq.add_rank')}</button>` : ''}<button class="go" data-a="rsave">${t('sq.save_ranks')}</button></div></section>`;
        } else {
            right = `<section style="--i:1"><h2>${t('sq.post')}</h2><p>${t('sq.rank')}: <b>${esc(sq.rankLabel)}</b></p><p>${t('sq.post_text')}</p></section>`;
        }
        body = `<div>${left}</div><div>${right}</div>`;
    }
    const title = sq ? esc(sq.name) : t('sq.no_squad');
    root.innerHTML = `<div class="sq-veil" data-a="close"></div><div class="sq-panel">
        <header><div class="sq-mark"><i></i></div><div><h1>${title}</h1><div class="sq-sub">${t('sq.link')} · ${sq ? esc(sq.rankLabel) : t('sq.standby')}</div></div>
        <button class="sq-x" data-a="close">${t('sq.close')}</button></header>
        <main>${body}</main>
        <footer><span>/SQUAD · ${esc(S.key)}</span><span>${t('sq.keep_seat')}</span></footer><div class="sq-toast"></div></div>`;
}

async function refresh(scan) {
    const r = await fx('squad:get');
    let near = S.near;
    if (scan && r.ok && r.squad && r.squad.isLeader) { const n = await fx('squad:nearby'); near = n.ok ? n.players || [] : []; }
    // polling is skipped unless something changed
    const sig = JSON.stringify([r, near]);
    if (sig === S.sig) return;
    S.sig = sig; S.data = r; S.near = near;
    if (S.open) render();
}

function armed(el) {
    if (!el.hasAttribute('data-confirm') || el.dataset.armed) return true;
    el.dataset.armed = '1'; const was = el.textContent; el.textContent = t('sq.confirm'); el.classList.add('is-armed');
    setTimeout(() => { if (el.isConnected) { delete el.dataset.armed; el.textContent = was; el.classList.remove('is-armed'); } }, 3000);
    return false;
}

async function act(el) {
    const a = el.dataset.a, c = Number(el.dataset.c), i = Number(el.dataset.i);
    if (!armed(el)) return;
    const done = async (r, ok) => { if (r && r.ok) { if (ok) toast(ok); S.draft = null; await refresh(true); } else toast((r && r.error) || t('sq.failed'), true); };
    const dr = S.draft || [];
    switch (a) {
    case 'close': return post('squadClose');
    case 'scan': return refresh(true);
    case 'create': return done(await fx('squad:create', { name: (document.getElementById('sqNew') || {}).value || '' }), t('sq.formed'));
    case 'accept': return done(await fx('squad:accept'), t('sq.joined'));
    case 'decline': return done(await fx('squad:decline'), t('sq.declined'));
    case 'leave': return done(await fx('squad:leave'), t('sq.left'));
    case 'disband': return done(await fx('squad:disband'), t('sq.disbanded'));
    case 'kick': return done(await fx('squad:kick', { charId: c }), t('sq.removed'));
    case 'transfer': return done(await fx('squad:transfer', { charId: c }), t('sq.transferred'));
    case 'invite': { const r = await fx('squad:invite', { target: Number(el.dataset.t) }); return toast(r.ok ? t('sq.inv_sent') : (r.error || t('sq.inv_failed')), !r.ok); }
    case 'rename': return done(await fx('squad:rename', { name: (document.getElementById('sqRename') || {}).value || '' }), t('sq.renamed'));
    case 'radd': dr.push({ label: t('sq.new_rank') }); return render();
    case 'rdel': dr.splice(i, 1); return render();
    case 'rup': if (i > 0) [dr[i - 1], dr[i]] = [dr[i], dr[i - 1]]; return render();
    case 'rdown': if (i < dr.length - 1) [dr[i + 1], dr[i]] = [dr[i], dr[i + 1]]; return render();
    case 'rsave': return done(await fx('squad:saveRanks', { ranks: dr }), t('sq.ranks_saved'));
    }
}

root.addEventListener('click', (e) => { const el = e.target.closest('[data-a]'); if (el) act(el); });
root.addEventListener('input', (e) => { const k = e.target.dataset.rk; if (k != null && S.draft && S.draft[k]) S.draft[k].label = e.target.value; });
root.addEventListener('change', async (e) => {
    const c = e.target.dataset.rank; if (c == null) return;
    const r = await fx('squad:setRank', { charId: Number(c), rankId: Number(e.target.value) });
    if (!r.ok) toast(r.error || t('sq.failed'), true); else refresh(false);
});
window.addEventListener('keydown', (e) => { if (S.open && e.key === 'Escape') post('squadClose'); });
if (window.BSI18n) BSI18n.onChange(() => { if (S.open) render(); });

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'squadOpen') {
        S.open = true; S.draft = null; S.near = []; if (d.key) S.key = d.key;
        root.classList.add('is-open'); banner.classList.remove('show');
        S.sig = null; S.data = d.state || { ok: true, loading: true }; render(); refresh(true);
        clearInterval(poll); poll = setInterval(() => { if (S.open && !root.querySelector('input:focus')) refresh(false); }, 2500);
    } else if (d.action === 'squadClose') {
        S.open = false; root.classList.remove('is-open'); root.innerHTML = ''; clearInterval(poll);
    } else if (d.action === 'squadSync') {
        if (S.open && !root.querySelector('input:focus')) refresh(false);
    } else if (d.action === 'squadInvite') {
        if (S.open) return refresh(false);
        const sec = Number(d.seconds) || 60;
        const hl = (s) => `<b style="display:inline;letter-spacing:0;color:#e9e2cf">${esc(s)}</b>`;
        banner.innerHTML = `<b>${t('sq.banner')}</b><span>${t('sq.banner_text', { from: hl(d.from), name: hl(d.name), key: esc(d.key || S.key) })}</span><i style="animation:sqBar ${sec}s linear both"></i>`;
        banner.classList.add('show'); clearTimeout(bannerT); bannerT = setTimeout(() => banner.classList.remove('show'), Math.min(sec, 20) * 1000);
    }
});
})();

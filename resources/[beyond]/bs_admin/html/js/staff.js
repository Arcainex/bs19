// bs_admin - Simple / Advanced views (QUICK, PLAYER and SERVER tabs)

const ST = { advanced: false, players: [], sel: null, info: null, factions: null, logs: null, inv: null };

const T = (k, fb, vars) => {
    let s = tt(k, fb);
    if (vars) s = s.replace(/\{(\w+)\}/g, (m, n) => (vars[n] !== undefined ? String(vars[n]) : m));
    return s;
};
const act = (action, args) => post('server', { action, args: args || {} });
const fmtTime = (ts) => {
    if (!ts) return '-';
    const d = new Date(ts * 1000);
    return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' }) + ' ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
};
const fmtDur = (sec) => {
    sec = Math.max(0, Math.floor(Number(sec) || 0));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    return h ? `${h}h ${m}m` : `${m}m`;
};

// Destructive buttons want a second click within 3 s.
function armed(b) {
    if (b.dataset.armed) return true;
    b.dataset.armed = '1';
    const was = b.innerHTML;
    b.textContent = T('admin.u.confirm', 'SURE?');
    b.classList.add('is-armed');
    b._timer = setTimeout(() => { disarm(b, was); }, 3000);
    b._was = was;
    return false;
}

function disarm(b, was) {
    if (!b.isConnected) return;
    delete b.dataset.armed;
    b.innerHTML = was !== undefined ? was : (b._was || b.innerHTML);
    b.classList.remove('is-armed');
}

// Static destructive buttons (data-confirm): the first click arms, the second within 3 s runs the action
document.addEventListener('click', (e) => {
    const b = e.target.closest && e.target.closest('[data-confirm]');
    if (!b) return;
    if (!b.dataset.armed) {
        e.stopImmediatePropagation();
        e.preventDefault();
        armed(b);
        return;
    }
    clearTimeout(b._timer);
    disarm(b);
}, true);

// Mode

function applyMode(advanced) {
    ST.advanced = !!advanced;
    const menu = document.querySelector('.menu');
    menu.classList.toggle('is-simple', !ST.advanced);
    $('modeBtn').innerHTML = ST.advanced
        ? `<span>${esc(T('admin.u.advanced', 'ADVANCED'))}</span>`
        : `<span>${esc(T('admin.u.simple', 'SIMPLE'))}</span>`;
    const active = document.querySelector('.mtab.is-active');
    const hidden = active && getComputedStyle(active).display === 'none';
    if (!active || hidden) {
        const first = [...document.querySelectorAll('.mtab')].find((t) => getComputedStyle(t).display !== 'none');
        if (first) first.click();
    }
}

$('modeBtn').addEventListener('click', async () => {
    const r = await post('local', { action: 'advanced' });
    if (r && 'advanced' in r) applyMode(r.advanced);
});

// Players (shared by QUICK and PLAYER)

const matches = (p, q) => !q || String(p.source) === q || (p.name || '').toLowerCase().includes(q) || (p.character || '').toLowerCase().includes(q);

async function refreshPlayers() {
    const list = await post('refreshPlayers');
    ST.players = Array.isArray(list) ? list : [];
    renderQuick();
    renderPmList();
}

function renderQuick() {
    const q = ($('qkSearch').value || '').trim().toLowerCase();
    const list = ST.players.filter((p) => matches(p, q));
    const box = $('qkPlayers');
    if (!list.length) { box.innerHTML = `<p class="hint">${esc(T('admin.u.nobody', 'Nobody matches.'))}</p>`; return; }
    box.innerHTML = list.map((p) => `
        <div class="player">
            <div class="player__top"><span>${esc(p.character || p.name)}</span><span class="player__id">#${p.source} · ${p.ping}MS</span></div>
            <div class="player__acts">
                <button data-q="goto" data-id="${p.source}">${esc(T('admin.u.tp', 'TP TO'))}</button>
                <button data-q="bring" data-id="${p.source}">${esc(T('admin.u.bring', 'BRING'))}</button>
                <button data-q="heal" data-id="${p.source}">${esc(T('admin.u.heal', 'HEAL'))}</button>
                <button data-q="revive" data-id="${p.source}">${esc(T('admin.u.revive', 'REVIVE'))}</button>
                <button data-q="target" data-id="${p.source}">${esc(T('admin.u.act_on', 'ACT ON'))}</button>
                <button data-q="kick" data-id="${p.source}" class="danger">${esc(T('admin.u.kick', 'KICK'))}</button>
            </div>
        </div>`).join('');
    box.querySelectorAll('[data-q]').forEach((b) => b.addEventListener('click', async () => {
        const id = Number(b.dataset.id), what = b.dataset.q;
        if (what === 'target') { setTarget(id); return msg(T('admin.u.acting_on', 'acting on #{id}', { id })); }
        if (what === 'kick') {
            if (!armed(b)) return;
            return report(await act('kick', { target: id, reason: $('qkReason').value || '' }));
        }
        report(await act(what, { target: id }));
    }));
}

function setTarget(id) {
    const sel = $('targetSelect');
    if (![...sel.options].some((o) => o.value === String(id))) renderTargets(ST.players);
    sel.value = String(id);
    sel.dispatchEvent(new Event('change'));
}

$('qkSearch').addEventListener('input', renderQuick);

async function sendAnnounce(prefix) {
    const text = ($(prefix + 'AnnText').value || '').trim();
    if (!text) return msg(T('admin.u.need_text', 'write a message first'), true);
    const r = report(await act('announce', { title: $(prefix + 'AnnTitle').value || '', text, duration: Number($(prefix + 'AnnDur').value) || 10 }),
        T('admin.u.sent', 'sent'));
    if (r && r.ok) $(prefix + 'AnnText').value = '';
}
$('qkAnnSend').addEventListener('click', () => sendAnnounce('qk'));
$('svAnnSend').addEventListener('click', () => sendAnnounce('sv'));

// Item names for the datalists, from the catalogue app.js already loaded.
function fillItemNames() {
    if (!ITEMS.length) return false;
    $('itemNames').innerHTML = ITEMS.map((i) => `<option value="${esc(i.item)}">${esc(i.label)}</option>`).join('');
    return true;
}

// Accepts the item id or its label.
function resolveItem(text) {
    const s = String(text || '').trim().toLowerCase();
    if (!s) return null;
    const hit = ITEMS.find((i) => i.item === s) || ITEMS.find((i) => i.label.toLowerCase() === s);
    return hit ? hit.item : s;
}

$('qkGive').addEventListener('click', async () => {
    const item = resolveItem($('qkItem').value);
    if (!item) return msg(T('admin.u.need_item', 'pick an item'), true);
    const amount = Math.max(1, Number($('qkItemAmt').value) || 1);
    report(await post('server', { action: 'giveitem', args: withTarget({ item, amount }) }), T('admin.u.given', 'given'));
});

// PLAYER (advanced)

function renderPmList() {
    const q = ($('pmSearch').value || '').trim().toLowerCase();
    const list = ST.players.filter((p) => matches(p, q));
    $('pmList').innerHTML = list.map((p) => `<button class="pmchip${ST.sel === p.source ? ' is-on' : ''}" data-pm="${p.source}">#${p.source} ${esc(p.character || p.name)}</button>`).join('')
        || `<p class="hint">${esc(T('admin.u.nobody', 'Nobody matches.'))}</p>`;
    $('pmList').querySelectorAll('[data-pm]').forEach((b) => b.addEventListener('click', () => selectPlayer(Number(b.dataset.pm))));
}
$('pmSearch').addEventListener('input', renderPmList);
$('pmRefresh').addEventListener('click', async () => { await refreshPlayers(); if (ST.sel) loadDetail(); });

async function selectPlayer(id) {
    ST.sel = id; ST.logs = null; ST.inv = null;
    setTarget(id);
    renderPmList();
    await loadDetail();
}

async function loadDetail() {
    if (!ST.sel) return;
    const [info, inv] = await Promise.all([act('playerInfo', { target: ST.sel }), act('invView', { target: ST.sel })]);
    if (!ST.factions) {
        const f = await act('factionList');
        ST.factions = (f && f.ok && f.factions) || [];
    }
    if (!info || !info.ok) { $('pmDetail').innerHTML = `<p class="hint">${esc((info && info.error) || 'no data')}</p>`; return; }
    ST.info = info.info;
    ST.inv = (inv && inv.ok && inv.items) || [];
    renderDetail();
}

const section = (title, inner) => `<p class="mpane__label">${esc(title)}</p>${inner}`;
const btns = (list) => `<div class="player__acts">${list.map(([a, label, cls]) => `<button data-pa="${a}" class="${cls || ''}">${esc(label)}</button>`).join('')}</div>`;
const until = (b) => (b.expires ? fmtTime(b.expires) : T('admin.u.permanent', 'PERMANENT'));

function renderDetail() {
    const p = ST.info;
    const fac = p.faction;
    const facOpts = `<option value="">${esc(T('admin.u.no_faction', '- NO FACTION -'))}</option>` +
        ST.factions.map((f) => `<option value="${esc(f.id)}"${fac && fac.id === f.id ? ' selected' : ''}>${esc(f.label)}</option>`).join('');

    const head = `<div class="pmcard">
        <div class="player__top"><span>${esc(p.character || '-')} <em class="hint">(${esc(p.name)})</em></span><span class="player__id">#${p.source}${p.charId ? ' · CHAR ' + p.charId : ''}</span></div>
        <div class="kv">
            <span>${esc(T('admin.u.level', 'LEVEL'))}</span><b>${p.level ?? '-'} ${esc(p.class || '')}</b>
            <span>HP / ARMOUR</span><b>${p.health} / ${p.armour}</b>
            <span>${esc(T('admin.u.money', 'MONEY'))}</span><b>$${p.cash ?? 0} · BANK $${p.bank ?? 0}</b>
            <span>${esc(T('admin.u.faction', 'FACTION'))}</span><b>${fac ? esc(fac.label) + ' · ' + esc(fac.rankLabel || fac.rank) : '-'}</b>
            <span>PING</span><b>${p.ping} MS</b>
            <span>${esc(T('admin.u.playtime', 'PLAYTIME'))}</span><b>${fmtDur(p.playtime)}</b>
            <span>${esc(T('admin.u.position', 'POSITION'))}</span><b>${Math.round(p.coords.x)}, ${Math.round(p.coords.y)}, ${Math.round(p.coords.z)}</b>
            <span>${esc(T('admin.u.warnings', 'WARNINGS'))}</span><b class="${p.warnings ? 'bad' : ''}">${p.warnings}</b>
        </div>
        <div class="hint ids">${p.identifiers.map(esc).join('<br>')}</div>
    </div>`;

    const control = section(T('admin.u.control', 'CONTROL'), btns([
        ['spectate', T('admin.u.spectate', 'SPECTATE')], ['goto', T('admin.u.tp', 'TP TO')], ['bring', T('admin.u.bring', 'BRING')],
        ['returnPlayer', T('admin.u.return', 'RETURN')], ['freeze', p.frozen ? T('admin.u.unfreeze', 'UNFREEZE') : T('admin.u.freeze', 'FREEZE')],
        ['heal', T('admin.u.heal', 'HEAL')], ['revive', T('admin.u.revive', 'REVIVE')], ['forceTutorial', T('admin.u.force_tutorial', 'TUTORIAL')], ['kill', T('admin.u.kill', 'KILL'), 'danger'],
    ]));

    const invRows = ST.inv.map((i) => `<div class="noterow"><span>${esc(i.label)} <em class="hint">${esc(i.item)}</em> <b>x${i.amount}</b></span>
        <button data-rm="${esc(i.item)}" data-n="1">-1</button><button data-rm="${esc(i.item)}" data-all="1" class="danger">${esc(T('admin.u.all', 'ALL'))}</button></div>`).join('')
        || `<p class="hint">${esc(T('admin.u.empty_bag', 'Empty bag.'))}</p>`;
    const inventory = section(T('admin.u.inventory', 'INVENTORY'), `<div class="invlist">${invRows}</div>
        <div class="split"><input id="pmItem" type="text" class="sx-wide" list="itemNames" autocomplete="off" placeholder="${esc(T('admin.u.item', 'ITEM'))}" />
        <input id="pmItemAmt" type="number" value="1" min="1" /><button class="row row--inline" data-pa="giveitem">${esc(T('admin.u.give', 'GIVE'))}</button></div>`);

    const money = section(T('admin.u.money', 'MONEY'), `<div class="split"><input id="pmMoney" type="number" min="1" value="100" />
        <select id="pmAcc" class="sx-select"><option value="cash">CASH</option><option value="bank">BANK</option></select>
        <button class="row row--inline" data-pa="givemoney">${esc(T('admin.u.give', 'GIVE'))}</button><button class="row row--inline row--danger" data-pa="takemoney">${esc(T('admin.u.take', 'TAKE'))}</button></div>`);

    const faction = section(T('admin.u.faction', 'FACTION'), `<div class="split"><select id="pmFaction" class="sx-select">${facOpts}</select>
        <select id="pmRank" class="sx-select"></select><button class="row row--inline" data-pa="setFaction">${esc(T('admin.u.set', 'SET'))}</button></div>`);

    const days = esc(T('admin.u.days', 'DAYS'));
    const sanction = section(T('admin.u.kick_ban', 'KICK / BAN'), `<input id="pmReason" type="text" class="fld" maxlength="200" placeholder="${esc(T('admin.u.reason', 'REASON'))}" />
        <div class="split"><select id="pmBanHours" class="sx-select">
            <option value="1">1 H</option><option value="24">1 ${esc(T('admin.u.day', 'DAY'))}</option><option value="72">3 ${days}</option>
            <option value="168">7 ${days}</option><option value="720">30 ${days}</option><option value="0">${esc(T('admin.u.permanent', 'PERMANENT'))}</option></select>
        <button class="row row--inline row--danger" data-pa="kick">${esc(T('admin.u.kick', 'KICK'))}</button><button class="row row--inline row--danger" data-pa="ban">${esc(T('admin.u.ban', 'BAN'))}</button></div>
        ${(p.bans || []).map((b) => `<div class="noterow${b.active ? ' bad' : ''}"><span>${esc(b.reason || '')} <em class="hint">${esc(b.by || '')} · ${fmtTime(b.at)} → ${esc(until(b))}</em></span>${b.active ? `<button data-unban="${b.id}">${esc(T('admin.u.unban', 'UNBAN'))}</button>` : ''}</div>`).join('')}`);

    const notes = section(T('admin.u.notes', 'WARNINGS & NOTES'), `<textarea id="pmNote" class="fld" maxlength="400" rows="2" placeholder="${esc(T('admin.u.note_ph', 'What happened?'))}"></textarea>
        <div class="split"><button class="row row--inline row--danger" data-pa="warn">${esc(T('admin.u.warn', 'WARN (PLAYER SEES IT)'))}</button><button class="row row--inline" data-pa="note">${esc(T('admin.u.note', 'STAFF NOTE'))}</button></div>
        ${(p.notes || []).map((n) => `<div class="noterow${n.kind === 'warn' ? ' bad' : ''}"><span>${n.kind === 'warn' ? '! ' : ''}${esc(n.text)} <em class="hint">${esc(n.by || '')} · ${fmtTime(n.at)}</em></span><button data-delnote="${n.id}">X</button></div>`).join('')}`);

    const logs = section(T('admin.u.logs', 'LOGS'), ST.logs
        ? (ST.logs.map((l) => `<div class="noterow"><span><b>${esc(l.kind)}</b> ${esc(l.details || '')} <em class="hint">${esc(l.name || '')} · ${fmtTime(l.at)}</em></span></div>`).join('') || '<p class="hint">-</p>')
        : `<button class="row row--ghost" data-pa="logs">${esc(T('admin.u.load_logs', 'LOAD LOGS'))}</button>`);

    $('pmDetail').innerHTML = head + control + inventory + money + faction + sanction + notes + logs;
    fillRanks(fac && fac.rank);
    $('pmFaction').addEventListener('change', () => fillRanks());
    wireDetail();
}

function fillRanks(current) {
    const f = ST.factions.find((x) => x.id === $('pmFaction').value);
    $('pmRank').innerHTML = f ? (f.ranks || []).map((r) => `<option value="${esc(r.id)}"${r.id === current ? ' selected' : ''}>${esc(r.label)}</option>`).join('') : '';
    $('pmRank').disabled = !f;
}

const DANGER = ['kill', 'kick', 'ban', 'takemoney'];

function wireDetail() {
    const id = ST.sel;
    const box = $('pmDetail');
    const gone = (r) => { report(r); if (r && r.ok) { ST.sel = null; $('pmDetail').innerHTML = ''; refreshPlayers(); } };
    box.querySelectorAll('[data-pa]').forEach((b) => b.addEventListener('click', async () => {
        const a = b.dataset.pa;
        if (DANGER.includes(a) && !armed(b)) return;
        let r;
        switch (a) {
        case 'spectate': return report(await post('guard', { cb: 'guard:spectate', args: { src: id } }));
        case 'logs':
            r = await act('playerLogs', { target: id });
            ST.logs = (r && r.ok && r.rows) || [];
            return renderDetail();
        case 'giveitem': {
            const item = resolveItem($('pmItem').value);
            if (!item) return msg(T('admin.u.need_item', 'pick an item'), true);
            r = await act('giveitem', { target: id, item, amount: Math.max(1, Number($('pmItemAmt').value) || 1) });
            break;
        }
        case 'givemoney': case 'takemoney':
            r = await act(a, { target: id, amount: Number($('pmMoney').value) || 0, account: $('pmAcc').value });
            break;
        case 'setFaction':
            r = await act('setFaction', { target: id, faction: $('pmFaction').value, rank: $('pmRank').value });
            break;
        case 'kick': return gone(await act('kick', { target: id, reason: $('pmReason').value || '' }));
        case 'ban': return gone(await act('ban', { target: id, reason: $('pmReason').value || '', hours: Number($('pmBanHours').value) }));
        case 'warn': case 'note':
            r = await act('addNote', { target: id, kind: a, text: $('pmNote').value || '' });
            break;
        default:
            r = await act(a, { target: id });
        }
        report(r);
        if (r && r.ok) loadDetail();
    }));
    box.querySelectorAll('[data-rm]').forEach((b) => b.addEventListener('click', async () => {
        const args = { target: id, item: b.dataset.rm };
        if (b.dataset.all) { if (!armed(b)) return; args.all = true; } else args.amount = Number(b.dataset.n) || 1;
        report(await act('removeitem', args));
        loadDetail();
    }));
    box.querySelectorAll('[data-delnote]').forEach((b) => b.addEventListener('click', async () => {
        if (!armed(b)) return;
        report(await act('delNote', { id: Number(b.dataset.delnote) }));
        loadDetail();
    }));
    box.querySelectorAll('[data-unban]').forEach((b) => b.addEventListener('click', async () => {
        if (!armed(b)) return;
        report(await act('unban', { id: Number(b.dataset.unban) }));
        loadDetail();
    }));
}

// SERVER (advanced)

async function loadServer() {
    const [s, bans, cars] = await Promise.all([act('serverStats'), act('bans'), act('storedCars')]);
    if (s && s.ok) {
        const st = s.stats, w = st.world || {};
        const cell = (k, v) => `<div class="stat"><b>${esc(String(v ?? '-'))}</b><span>${esc(k)}</span></div>`;
        const clock = w.hour !== undefined ? `${String(w.hour).padStart(2, '0')}:${String(w.minute).padStart(2, '0')}${w.timeFrozen ? ' *' : ''}` : '-';
        $('svStats').innerHTML = [
            cell(T('admin.u.players', 'PLAYERS'), `${st.players}/${st.maxPlayers}`),
            cell(T('admin.u.uptime', 'UPTIME'), fmtDur(st.uptime)),
            cell(T('admin.u.walkers', 'WALKERS'), st.walkers),
            cell(T('admin.u.vehicles', 'VEHICLES'), st.vehicles),
            cell('PEDS', st.peds), cell(T('admin.u.objects', 'OBJECTS'), st.objects),
            cell(T('admin.u.resources', 'RESOURCES'), st.resources), cell(T('admin.u.bans', 'ACTIVE BANS'), st.activeBans),
            cell(T('admin.u.clock', 'CLOCK'), clock),
            cell(T('admin.u.weather', 'WEATHER'), w.weather ? `${w.weather}${w.weatherFrozen ? ' *' : ''}` : '-'),
        ].join('');
        setToggle('blackout', w.blackout);
    }
    $('svBans').innerHTML = ((bans && bans.bans) || []).map((b) => `<div class="noterow bad"><span>${esc(b.name || '?')} · ${esc(b.reason || '')} <em class="hint">${esc(b.by || '')} · ${fmtTime(b.at)} → ${esc(until(b))}</em></span><button data-unban="${b.id}">${esc(T('admin.u.unban', 'UNBAN'))}</button></div>`).join('')
        || '<p class="hint">-</p>';
    $('svCars').innerHTML = ((cars && cars.cars) || []).map((c) => `<div class="noterow"><span><b>${esc(c.plate)}</b> ${esc(c.model)} <em class="hint">${esc(c.owner)}</em></span><button data-unstore="${esc(c.plate)}">${esc(T('admin.u.unstore', 'BRING OUT HERE'))}</button></div>`).join('')
        || '<p class="hint">-</p>';
    $('svBans').querySelectorAll('[data-unban]').forEach((b) => b.addEventListener('click', async () => {
        if (!armed(b)) return;
        report(await act('unban', { id: Number(b.dataset.unban) }));
        loadServer();
    }));
    $('svCars').querySelectorAll('[data-unstore]').forEach((b) => b.addEventListener('click', async () => {
        report(await act('unstoreVehicle', { plate: b.dataset.unstore }));
        loadServer();
    }));
}
$('svRefresh').addEventListener('click', loadServer);
$('svBlackout').addEventListener('click', async () => { report(await act('blackout')); loadServer(); });
$('svDzGo').addEventListener('click', async () => {
    const r = await act('clearZombies', { radius: Number($('svDz').value) || 50 });
    report(r, r && r.ok ? T('admin.u.cleared', 'removed {n}', { n: r.count }) : undefined);
});

// Tabs load their data when opened.
document.querySelectorAll('.mtab').forEach((t) => t.addEventListener('click', () => {
    if (t.dataset.tab === 'server') loadServer();
    if (t.dataset.tab === 'manage') { renderPmList(); if (ST.sel) loadDetail(); }
    if (t.dataset.tab === 'quick') renderQuick();
}));

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') {
        ST.players = Array.isArray(d.players) ? d.players : [];
        ST.factions = null;
        applyMode(d.state && d.state.advanced);
        renderQuick();
        renderPmList();
        // the item catalogue arrives a moment after open (app.js)
        let tries = 0;
        const wait = setInterval(() => { if (fillItemNames() || ++tries > 20) clearInterval(wait); }, 250);
        const active = document.querySelector('.mtab.is-active');
        if (active && active.dataset.tab === 'server') loadServer();
        if (active && active.dataset.tab === 'manage' && ST.sel) loadDetail();
    }
    if (d.action === 'mode') applyMode(d.advanced);
});

// Teleport to coords (QUICK and SELF). Server checks rights and logs it; Z empty = find ground.

// Pull x, y, z out of "x, y, z", "x y z" or vector3/vector4(...)
function tpParse(text) {
    const nums = String(text || '').replace(/vector\d\s*\(/gi, ' ').match(/-?\d+(?:\.\d+)?/g) || [];
    return nums.slice(0, 3).map(Number);
}

function tpWire(p) {
    if (!$(p + 'TpGo')) return;
    $(p + 'TpPaste').addEventListener('input', () => {
        const n = tpParse($(p + 'TpPaste').value);
        if (n.length >= 2) {
            $(p + 'TpX').value = n[0];
            $(p + 'TpY').value = n[1];
            $(p + 'TpZ').value = n.length >= 3 ? n[2] : '';
        }
    });
    $(p + 'TpGo').addEventListener('click', async () => {
        const x = parseFloat($(p + 'TpX').value), y = parseFloat($(p + 'TpY').value);
        const zRaw = String($(p + 'TpZ').value).trim();
        if (!isFinite(x) || !isFinite(y)) return msg(T('admin.u.tpc_bad', 'enter X and Y'), true);
        const args = { x, y };
        if (zRaw !== '' && isFinite(parseFloat(zRaw))) args.z = parseFloat(zRaw);
        report(await act('tpCoords', args), T('admin.u.tpc_ok', 'teleported'));
    });
    $(p + 'TpMine').addEventListener('click', async () => {
        const r = await post('local', { action: 'copyCoords' });
        if (!r || r.x === undefined) return report(r);
        const f = (v) => Number(v).toFixed(2);
        const line = `${f(r.x)}, ${f(r.y)}, ${f(r.z)}`;
        $(p + 'TpX').value = f(r.x); $(p + 'TpY').value = f(r.y); $(p + 'TpZ').value = f(r.z);
        $(p + 'TpPaste').value = line;
        gdCopy(line);
    });
}
tpWire('qk');
tpWire('sf');


// F10 layout helpers (cards, target search, narrow rail, Test server tab)

// Group each pane's direct children under their section title, so every section reads as one card
function buildCards() {
    document.querySelectorAll('.mpane').forEach((pane) => {
        const kids = [...pane.children];
        if (!kids.some((k) => k.classList.contains('mpane__label'))) return;
        let card = null;
        kids.forEach((k) => {
            if (k.classList.contains('mpane__label')) {
                card = document.createElement('section');
                card.className = 'card';
                pane.insertBefore(card, k);
                k.classList.remove('mpane__label');
                k.classList.add('card__title');
                card.appendChild(k);
            } else {
                if (!card) { card = document.createElement('section'); card.className = 'card'; pane.insertBefore(card, k); }
                card.appendChild(k);
            }
        });
    });
}
buildCards();

// Player search in the acting-on bar: filters the dropdown, Enter picks the first match.
(function targetSearch() {
    const input = $('targetSearch');
    const sel = $('targetSelect');
    const bar = document.querySelector('.target');
    const apply = () => {
        const q = input.value.trim().toLowerCase();
        [...sel.options].forEach((o) => {
            const hit = !q || o.value === '' || o.textContent.toLowerCase().includes(q);
            o.hidden = !hit;
            o.disabled = !hit;
        });
    };
    const mark = () => bar.classList.toggle('has-target', sel.value !== '');
    input.addEventListener('input', apply);
    input.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter') return;
        const first = [...sel.options].find((o) => o.value !== '' && !o.disabled);
        if (first) { sel.value = first.value; sel.dispatchEvent(new Event('change')); }
        mark();
    });
    sel.addEventListener('change', mark);
    // The list is rebuilt whenever players refresh; re-apply the filter then.
    new MutationObserver(() => { apply(); mark(); }).observe(sel, { childList: true });
})();

// Narrow window: icons only.
(function narrow() {
    const menu = document.querySelector('.menu');
    if (!window.ResizeObserver) return;
    new ResizeObserver(() => menu.classList.toggle('is-narrow', menu.getBoundingClientRect().width < 560)).observe(menu);
})();

// Test server tab
async function loadTestServer() {
    const r = await post('server', { action: 'testServerState', args: {} });
    const box = $('tsFlags');
    if (!r || !r.ok) {
        $('tsMode').textContent = (r && r.error) || 'failed';
        $('tsMode').classList.remove('on');
        box.innerHTML = '';
        return;
    }
    const st = r.state;
    $('tsMode').classList.toggle('on', !!st.testServer);
    $('tsMode').textContent = st.testServer
        ? T('admin.t.mode_on', 'ON - every player has the tester menu')
        : T('admin.t.mode_off', 'OFF - testers are granted per player');
    const rows = [
        ['vehicles', 'admin.t.f_vehicles', 'Vehicle spawns'], ['kits', 'admin.t.f_kits', 'Weapon kits'],
        ['teleport', 'admin.t.f_teleport', 'Teleport to waypoint'], ['god', 'admin.t.f_god', 'God mode'],
        ['infAmmo', 'admin.t.f_infammo', 'Infinite ammo'], ['env', 'admin.t.f_env', 'Time and weather (self)'],
    ];
    box.innerHTML = rows.map(([k, key, fb]) => `<div class="tsflag${st[k] ? '' : ' off'}"><span>${esc(T(key, fb))}</span><b>${st[k] ? esc(T('admin.t.on', 'ON')) : esc(T('admin.t.off', 'OFF'))}</b></div>`).join('')
        + `<div class="tsflag"><span>${esc(T('admin.t.max_veh', 'Max test vehicles'))}</span><b>${esc(st.maxVehicles)}</b></div>`;
}
document.querySelector('.mtab[data-tab="test"]').addEventListener('click', loadTestServer);
$('tsRefresh').addEventListener('click', loadTestServer);

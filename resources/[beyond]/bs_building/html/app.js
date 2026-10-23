// bs_building NUI: build wheel, placement hint, code keypad, inspect card, staff bases panel.
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_building';
const $ = (id) => document.getElementById(id);
const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => ({}));
const tr = (k, v, fb) => (typeof t === 'function' ? t(k, Object.assign({ fallback: fb !== undefined ? fb : k }, v || {})) : (fb || k));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ---------------------------------------------------------------- wheel
const W = { data: null, cats: [], cat: null };
const NS = 'http://www.w3.org/2000/svg';

function arc(r0, r1, a0, a1) {
    const p = (r, a) => [Math.cos(a) * r, Math.sin(a) * r];
    const big = a1 - a0 > Math.PI ? 1 : 0;
    const [x0, y0] = p(r1, a0), [x1, y1] = p(r1, a1), [x2, y2] = p(r0, a1), [x3, y3] = p(r0, a0);
    return `M${x0},${y0} A${r1},${r1} 0 ${big} 1 ${x1},${y1} L${x2},${y2} A${r0},${r0} 0 ${big} 0 ${x3},${y3} Z`;
}

function hub(title, blurb, costs, foot) {
    $('hubTitle').textContent = title || '';
    $('hubBlurb').textContent = blurb || '';
    $('hubCost').innerHTML = (costs || []).map(c => `<li class="${c.have < c.need ? 'short' : ''}"><span>${esc(c.label)}</span><b>${c.have}/${c.need}</b></li>`).join('');
    $('hubFoot').textContent = foot || '';
}

function baseFoot() {
    const d = W.data;
    if (!d) return '';
    const parts = [tr('ui.pieces', { n: d.built, max: d.max }, `${d.built}/${d.max} pieces`)];
    if (d.mode === 'claim') {
        if (!d.hasFlag) parts.push(tr('ui.no_flag', null, 'no flag yet'));
        else if (!d.inClaim) parts.push(tr('ui.outside', null, 'outside your claim'));
    }
    if (d.raids) parts.push(d.raidOpen ? tr('ui.raid_open', null, 'RAID OPEN') : tr('ui.raid_at', { w: d.raidWindow }, `raids ${d.raidWindow}`));
    return parts.join(' - ');
}

function drawRing(items, onPick, onHover) {
    const svg = $('ring');
    svg.innerHTML = '';
    const n = Math.max(items.length, 1);
    const step = (Math.PI * 2) / n;
    items.forEach((it, i) => {
        const a0 = -Math.PI / 2 + i * step + 0.012, a1 = a0 + step - 0.024;
        const g = document.createElementNS(NS, 'g');
        g.setAttribute('class', 'seg' + (it.poor ? ' poor' : ''));
        const path = document.createElementNS(NS, 'path');
        path.setAttribute('d', arc(104, 196, a0, a1));
        g.appendChild(path);
        const mid = (a0 + a1) / 2;
        const tx = document.createElementNS(NS, 'text');
        tx.setAttribute('x', Math.cos(mid) * 150); tx.setAttribute('y', Math.sin(mid) * 150);
        tx.textContent = it.label.length > 16 ? it.label.slice(0, 15) + '.' : it.label;
        g.appendChild(tx);
        if (it.sub) {
            const s = document.createElementNS(NS, 'text');
            s.setAttribute('class', 'sub');
            s.setAttribute('x', Math.cos(mid) * 150); s.setAttribute('y', Math.sin(mid) * 150 + 13);
            s.textContent = it.sub;
            g.appendChild(s);
        }
        g.addEventListener('mouseenter', () => onHover(it));
        g.addEventListener('click', () => onPick(it));
        svg.appendChild(g);
    });
}

function showCats() {
    W.cat = null;
    const items = W.cats.map(c => {
        const list = W.data.pieces.filter(p => p.cat === c.id);
        return { id: c.id, label: tr('cat.' + c.id, null, c.id), sub: `${list.length}`, list };
    }).filter(c => c.list.length > 0);
    drawRing(items, (c) => showPieces(c.id), (c) => hub(c.label, tr('cat.' + c.id + '.d', null, ''), null, baseFoot()));
    hub(tr('ui.build', null, 'Build'), tr('ui.pick_cat', null, 'Pick a category'), null, baseFoot());
}

function showPieces(cat) {
    W.cat = cat;
    // blocked = not allowed here (storage in a safezone): greyed out, the reason shows instead of placing
    const items = W.data.pieces.filter(p => p.cat === cat).map(p => Object.assign({}, p, { poor: !p.afford || !!p.blocked, sub: p.blocked ? tr('ui.blocked', null, 'blocked') : (p.afford ? '' : tr('ui.short', null, 'short')) }));
    drawRing(items, (p) => { if (p.blocked) { hub(p.label, p.blocked, p.costs, ''); return; } post('wheelPick', { id: p.id }); closeWheel(); },
        (p) => hub(p.label, p.blocked || p.blurb, p.costs, tr('ui.frame_note', null, 'Places a frame. Deposit, then hammer.')));
    hub(tr('cat.' + cat, null, cat), tr('ui.pick_piece', null, 'Pick a piece'), null, baseFoot());
}

function closeWheel() { $('wheel').classList.add('hidden'); }

document.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (!$('wheel').classList.contains('hidden')) {
        if (W.cat) showCats(); else { closeWheel(); post('wheelClose'); }
    }
});

// ---------------------------------------------------------------- keypad
let code = '';
function kpShow() { $('kpDisplay').textContent = (code + '____').slice(0, 4).replace(/\d/g, '*'); }
function kpDone(v) { $('keypad').classList.add('hidden'); post('keypad', { code: v }); }
(function buildKeys() {
    const g = $('kpGrid');
    [1, 2, 3, 4, 5, 6, 7, 8, 9, '', 0, '<'].forEach(k => {
        const b = document.createElement('button');
        b.textContent = k;
        if (k === '') { b.style.visibility = 'hidden'; }
        b.addEventListener('click', () => {
            if (k === '<') code = code.slice(0, -1);
            else if (code.length < 4) code += String(k);
            kpShow();
        });
        g.appendChild(b);
    });
    $('kpClear').onclick = () => { code = ''; kpShow(); };
    $('kpCancel').onclick = () => kpDone(false);
    $('kpOk').onclick = () => kpDone(code);
})();

// ---------------------------------------------------------------- inspect
let inspectTimer = null;
function inspect(m) {
    const p = m.piece;
    $('inTitle').textContent = m.label;
    $('inBar').style.width = Math.max(0, Math.min(100, (p.hp / p.mhp) * 100)) + '%';
    let body = `<div>${tr('ui.health', null, 'Health')}: <b>${p.hp}/${p.mhp}</b></div>`;
    if (!p.b) {
        body += `<div>${tr('ui.frame', null, 'Frame - needs materials and a hammer')}</div>`;
        (m.costs || []).forEach(c => { body += `<div>${esc(tr('item.' + c.item, null, c.item))}: <b>${(p.dep && p.dep[c.item]) || 0}/${c.amount}</b></div>`; });
    }
    if (p.lm === 'faction') body += `<div>${tr('ui.lock_faction', null, 'Faction lock')}</div>`;
    else if (p.lm === 'none') body += `<div>${tr('ui.lock_none', null, 'Unlocked')}</div>`;
    else if (p.lk) body += `<div>${tr('ui.locked', null, 'Code locked')}</div>`;
    if (p.fuel !== undefined && p.fuel !== null) body += `<div>${tr('ui.fuel', null, 'Fuel')}: <b>${Math.floor(p.fuel)}</b> ${p.on ? tr('ui.running', null, '(running)') : ''}</div>`;
    if (m.water) body += `<div>${tr('ui.water', null, 'Water')}: <b>${Math.floor(m.water)}</b></div>`;
    if (p.decay) body += `<div style="color:var(--danger)">${tr('ui.decaying', null, 'Decaying - nobody has visited')}</div>`;
    $('inBody').innerHTML = body;
    $('inspect').classList.remove('hidden');
    clearTimeout(inspectTimer);
    inspectTimer = setTimeout(() => $('inspect').classList.add('hidden'), 6000);
}

// ---------------------------------------------------------------- admin
const A = { data: null, fac: null };
function adminRender() {
    const d = A.data;
    $('adRaid').textContent = d.raidOpen ? tr('ui.raid_open', null, 'RAID OPEN') : tr('ui.raid_closed', null, 'RAIDS CLOSED');
    $('adRaid').classList.toggle('on', !!d.raidOpen);
    $('adRaid').classList.toggle('hidden', !d.raids);
    $('adBases').innerHTML = d.bases.map(b => {
        const days = b.lastVisit ? Math.floor((Date.now() / 1000 - b.lastVisit) / 86400) : '?';
        const visit = d.decay ? ` &middot; ${tr('ui.visit', { d: days }, days + 'd since visit')}` : '';
        const bal = b.balance > 0 ? ` &middot; $${b.balance}` : '';
        return `<div class="ad-item${A.fac === b.key ? ' on' : ''}" data-fac="${esc(b.key)}"><b>${esc(b.label)}</b>
            <span>${b.count} ${tr('ui.pieces_word', null, 'pieces')} &middot; ${b.frames} ${tr('ui.frames', null, 'frames')}${visit}${bal}</span>
            ${b.decaying ? `<span class="dec"> &middot; ${tr('ui.decaying_short', null, 'decaying')}</span>` : ''}</div>`;
    }).join('') || `<p class="muted" style="padding:12px">${tr('ui.no_bases', null, 'No bases yet.')}</p>`;
    document.querySelectorAll('.ad-item').forEach(el => el.onclick = () => adminBase(el.dataset.fac));
}
async function adminBase(fac) {
    A.fac = fac;
    adminRender();
    const b = A.data.bases.find(x => x.key === fac);
    const res = await post('adminPieces', { fac });
    const opts = A.data.factions.map(f => `<option value="${esc(f.id)}">${esc(f.label)}</option>`).join('');
    $('adDetail').innerHTML = `<h3 style="font:600 18px var(--serif)">${esc(b ? b.label : fac)}</h3>
        <div class="ad-actions">
            <button data-a="tp">${tr('ui.teleport', null, 'TELEPORT')}</button>
            ${A.data.decay ? `<button data-a="decay">${tr('ui.reset_decay', null, 'RESET DECAY')}</button>` : ''}
            <select id="adTo">${opts}</select><button data-a="transfer">${tr('ui.transfer', null, 'TRANSFER')}</button>
            <button class="bad" data-a="delete">${tr('ui.delete_base', null, 'DELETE BASE')}</button>
        </div>
        <table><tr><th>ID</th><th>${tr('ui.piece', null, 'PIECE')}</th><th>HP</th><th></th></tr>
        ${(res.pieces || []).map(p => `<tr><td>${p.id}</td><td>${esc(tr('piece.' + p.piece, null, p.piece))}${p.built ? '' : ' (frame)'}</td><td>${p.hp}/${p.mhp}</td>
            <td><button data-tp="${p.id}">TP</button> <button class="bad" data-del="${p.id}">${tr('ui.delete', null, 'DEL')}</button></td></tr>`).join('')}</table>`;
    const act = async (action, a, bb) => {
        const r = await post('adminAct', { action, a, b: bb });
        if (r && r.list && r.list.ok) { A.data = r.list; adminRender(); if (action !== 'deleteBase') adminBase(fac); else $('adDetail').innerHTML = ''; }
    };
    $('adDetail').querySelectorAll('[data-a]').forEach(btn => btn.onclick = () => {
        const a = btn.dataset.a;
        if (a === 'tp' && b) act('teleport', { x: b.x, y: b.y, z: b.z });
        if (a === 'decay') act('resetDecay', fac);
        if (a === 'transfer') act('transfer', fac, $('adTo').value);
        if (a === 'delete' && btn.dataset.sure) act('deleteBase', fac);
        else if (a === 'delete') { btn.dataset.sure = '1'; btn.textContent = tr('ui.sure', null, 'CLICK AGAIN'); }
    });
    $('adDetail').querySelectorAll('[data-tp]').forEach(btn => btn.onclick = () => {
        const p = (res.pieces || []).find(x => x.id == btn.dataset.tp);
        if (p) act('teleport', { x: p.x, y: p.y, z: p.z });
    });
    $('adDetail').querySelectorAll('[data-del]').forEach(btn => btn.onclick = () => act('deletePiece', Number(btn.dataset.del)));
}
$('adClose').onclick = () => { $('admin').classList.add('hidden'); post('adminClose'); };

// ---------------------------------------------------------------- vending
const V = { data: null };
function vendMsg(text, ok) { $('vdMsg').textContent = text || ''; $('vdMsg').classList.toggle('ok', !!ok); }
function vendRender() {
    const d = V.data;
    $('vdTitle').textContent = tr('piece.vending_crate', null, 'Vending crate');
    $('vdCash').textContent = tr('ui.vend_cash', { amount: d.cash }, `Your cash: ${d.cash}`);
    $('vdOwner').classList.toggle('hidden', !d.owner);
    if (d.owner) $('vdCollect').textContent = tr('ui.vend_collect', { amount: d.balance || 0 }, `COLLECT ${d.balance || 0}`);
    const rows = (d.items || []).map(it => {
        const left = tr('ui.vend_left', { n: it.amount }, `${it.amount} left`);
        if (d.owner) {
            return `<div class="vd-row${it.sellable ? '' : ' off'}"><div class="nm">${esc(it.label)}<small>${left}</small></div>
                <span class="muted">${tr('ui.vend_price', null, 'Price')}</span>
                <input type="number" min="0" max="${d.maxPrice}" value="${it.price}" data-item="${esc(it.item)}" ${it.sellable ? '' : 'disabled'}>
                <button data-set="${esc(it.item)}" ${it.sellable ? '' : 'disabled'}>${tr('ui.vend_set', null, 'SET')}</button></div>`;
        }
        return `<div class="vd-row"><div class="nm">${esc(it.label)}<small>${left}</small></div><span class="pr">$${it.price}</span>
            <input type="number" min="1" max="${it.amount}" value="1" data-item="${esc(it.item)}">
            <button class="go" data-buy="${esc(it.item)}">${tr('ui.vend_buy', null, 'BUY')}</button></div>`;
    }).join('');
    $('vdList').innerHTML = rows || `<p class="muted" style="padding:14px 16px">${tr('ui.vend_empty', null, 'Nothing for sale.')}</p>`;
    const inputOf = (item) => [...$('vdList').querySelectorAll('input')].find(i => i.dataset.item === item);
    $('vdList').querySelectorAll('[data-buy]').forEach(btn => btn.onclick = async () => {
        const qty = Math.max(1, Math.floor(Number(inputOf(btn.dataset.buy).value) || 1));
        vendApply(await post('vendBuy', { item: btn.dataset.buy, qty }));
    });
    $('vdList').querySelectorAll('[data-set]').forEach(btn => btn.onclick = async () => {
        const price = Math.max(0, Math.floor(Number(inputOf(btn.dataset.set).value) || 0));
        vendApply(await post('vendPrice', { item: btn.dataset.set, price }), true);
    });
}
function vendApply(r, saved) {
    if (r && r.ok) { V.data = r; vendRender(); vendMsg(saved ? tr('build.vend_price_set', null, 'Price saved.') : '', true); }
    else vendMsg((r && r.error) || tr('build.err.failed', null, 'That did not work.'));
}
function vendClose() { $('vend').classList.add('hidden'); post('vendClose'); }
$('vdClose').onclick = vendClose;
$('vdStock').onclick = () => { $('vend').classList.add('hidden'); post('vendStock'); };
$('vdCollect').onclick = async () => vendApply(await post('vendCollect'));

// ---------------------------------------------------------------- messages
const hammer = new Audio('hammer.wav');
window.addEventListener('message', (e) => {
    const m = e.data || {};
    switch (m.action) {
        case 'wheel':
            W.data = m.data; W.cats = m.cats || [];
            $('wheel').classList.remove('hidden');
            showCats();
            break;
        case 'wheelClose': closeWheel(); break;
        case 'hint':
            if (!m.state) { $('hint').classList.add('hidden'); break; }
            $('hint').classList.remove('hidden');
            $('hintTitle').textContent = m.state.label;
            $('hintState').textContent = m.state.valid ? tr('ui.ok_here', null, 'Good spot') : (m.state.reason || '');
            $('hintState').classList.toggle('bad', !m.state.valid);
            $('hintSnap').textContent = m.state.snap ? tr('ui.on', null, 'ON') : tr('ui.off', null, 'OFF');
            if (m.state.free) $('hintCost').innerHTML = `<li><span>${esc(tr('ui.free_build', null, 'Free build (admin)'))}</span><b></b></li>`;
            else $('hintCost').innerHTML = (m.state.costs || []).map(c => `<li class="${c.have < c.need ? 'short' : ''}"><span>${esc(c.label)}</span><b>${c.have}/${c.need}</b></li>`).join('');
            break;
        case 'keypad':
            code = ''; kpShow();
            $('keypad').classList.remove('hidden');
            break;
        case 'inspect': inspect(m); break;
        case 'admin':
            A.data = m.data; A.fac = null;
            $('adDetail').innerHTML = '';
            $('admin').classList.remove('hidden');
            adminRender();
            break;
        case 'adminHide': $('admin').classList.add('hidden'); break;
        case 'vend':
            V.data = m.data; vendMsg('');
            $('vend').classList.remove('hidden');
            vendRender();
            break;
        case 'vendClose': $('vend').classList.add('hidden'); break;
        case 'sound':
            try { const s = hammer.cloneNode(); s.volume = m.volume || 0.5; s.play(); } catch (err) {}
            break;
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('wheel').classList.contains('hidden')) { closeWheel(); post('wheelClose'); }
    if (!$('keypad').classList.contains('hidden')) kpDone(false);
    if (!$('admin').classList.contains('hidden')) { $('admin').classList.add('hidden'); post('adminClose'); }
    if (!$('vend').classList.contains('hidden')) vendClose();
});
document.addEventListener('keydown', (e) => {
    if ($('keypad').classList.contains('hidden')) return;
    if (/^\d$/.test(e.key) && code.length < 4) { code += e.key; kpShow(); }
    if (e.key === 'Backspace') { code = code.slice(0, -1); kpShow(); }
    if (e.key === 'Enter') kpDone(code);
});

// Drag / resize the staff base panel.
if (window.BSWindow) BSWindow.make(document.getElementById('admin'), { id: 'bs_building_admin', handle: '#admin header', minW: 560, minH: 360 });

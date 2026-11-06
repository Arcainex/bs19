// bs_building NUI: build menus (wheel, bar, catalogue), placement hint, keypad, inspect, generator, pour game, vending, staff panel.
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_building';
const $ = (id) => document.getElementById(id);
const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => ({}));
const tr = (k, v, fb) => (typeof t === 'function' ? t(k, Object.assign({ fallback: fb !== undefined ? fb : k }, v || {})) : (fb || k));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const show = (id, on) => $(id).classList.toggle('hidden', !on);
const visible = (id) => !$(id).classList.contains('hidden');

function costHtml(costs, free) {
    if (free) return `<li><span>${esc(tr('ui.free_build', null, 'Free build (admin)'))}</span><b></b></li>`;
    return (costs || []).map(c => `<li class="${c.have < c.need ? 'short' : ''}"><span>${esc(c.label)}</span><b>${c.have}/${c.need}</b></li>`).join('');
}
function tierChip(el, label) {
    el.textContent = label || '';
    el.classList.toggle('hidden', !label);
}

// ---------------------------------------------------------------- wheel
const W = { data: null, cats: [], cat: null };
const NS = 'http://www.w3.org/2000/svg';

function arc(r0, r1, a0, a1) {
    const p = (r, a) => [Math.cos(a) * r, Math.sin(a) * r];
    const big = a1 - a0 > Math.PI ? 1 : 0;
    const [x0, y0] = p(r1, a0), [x1, y1] = p(r1, a1), [x2, y2] = p(r0, a1), [x3, y3] = p(r0, a0);
    return `M${x0},${y0} A${r1},${r1} 0 ${big} 1 ${x1},${y1} L${x2},${y2} A${r0},${r0} 0 ${big} 0 ${x3},${y3} Z`;
}

function hub(title, blurb, costs, foot, tier, free) {
    $('hubTitle').textContent = title || '';
    $('hubBlurb').textContent = blurb || '';
    $('hubCost').innerHTML = costs ? costHtml(costs, free) : '';
    $('hubFoot').textContent = foot || '';
    tierChip($('hubTier'), tier);
}

function baseFoot(d) {
    d = d || W.data;
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

function pieceNote(p) {
    if (p.construction ? p.construction === 'direct' : W.data && W.data.instant) return p.snap ? tr('ui.note_snap', null, 'Snaps to your other pieces. Pays on place.') : tr('ui.note_free', null, 'Place it anywhere. Pays on place.');
    return tr('ui.frame_note', null, 'Places a frame. Deposit, then hammer.');
}

function showPieces(cat) {
    W.cat = cat;
    const free = W.data.freeBuild;
    const items = W.data.pieces.filter(p => p.cat === cat).map(p => Object.assign({}, p, { poor: (p.construction !== 'blueprint' && !p.afford) || !!p.blocked, sub: p.blocked ? tr('ui.blocked', null, 'blocked') : (p.tierLabel || (p.afford ? '' : tr('ui.short', null, 'short'))) }));
    drawRing(items, (p) => { if (p.blocked) { hub(p.label, p.blocked, p.costs, '', p.tierLabel, free); return; } post('wheelPick', { id: p.id }); closeWheel(); },
        (p) => hub(p.label, p.blocked || p.blurb, p.costs, pieceNote(p), p.tierLabel, free));
    hub(tr('cat.' + cat, null, cat), tr('ui.pick_piece', null, 'Pick a piece'), null, baseFoot());
}

function closeWheel() { show('wheel', false); }

document.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (visible('wheel')) {
        if (W.cat) showCats(); else { closeWheel(); post('wheelClose'); }
    }
});

// ---------------------------------------------------------------- bottom bar (no focus, the game sends the arrows)
const B = { data: null, cats: [], cat: null, idx: 1 };
function barCats(data) {
    return (B.catsCfg || []).map(c => ({ id: c.id, list: data.pieces.filter(p => p.cat === c.id) })).filter(c => c.list.length > 0);
}
function barRender() {
    const d = B.data;
    if (!d) return;
    B.cats = barCats(d);
    const cat = B.cats.find(c => c.id === B.cat) || B.cats[0];
    if (!cat) return;
    $('barCats').innerHTML = B.cats.map(c => `<span class="${c.id === cat.id ? 'on' : ''}">${esc(tr('cat.' + c.id, null, c.id))}</span>`).join('');
    const sel = Math.max(1, Math.min(B.idx, cat.list.length));
    $('barItems').innerHTML = cat.list.map((p, i) => `<div class="bi${i + 1 === sel ? ' on' : ''}${((p.construction !== 'blueprint' && !p.afford) || p.blocked) ? ' poor' : ''}">
        <div class="bi-name">${esc(p.label)}</div><div class="bi-detail">${i + 1} / ${cat.list.length} · ${p.construction === 'blueprint' ? 'Material plan' : 'Direct placement'}</div>${p.blurb ? `<p class="bi-detail">${esc(p.blurb)}</p>` : ''}
        ${p.tierLabel ? `<div class="tier-chip">${esc(p.tierLabel)}</div>` : ''}
        <ul class="cost">${p.blocked ? `<li class="short"><span>${esc(p.blocked)}</span><b></b></li>` : costHtml(p.costs, d.freeBuild)}</ul></div>`).join('');
    const on = $('barItems').querySelector('.bi.on');
    if (on) on.scrollIntoView({ block: 'nearest', inline: 'center' });
}

// ---------------------------------------------------------------- catalogue
const C = { data: null, cats: [], tab: 'all', sel: null };
function catRender() {
    const d = C.data;
    if (!d) return;
    const q = ($('catSearch').value || '').trim().toLowerCase();
    const present = C.cats.filter(c => d.pieces.some(p => p.cat === c.id));
    $('catTabs').innerHTML = [`<span data-tab="all" class="${C.tab === 'all' ? 'on' : ''}">${esc(tr('ui.all', null, 'All'))}</span>`]
        .concat(present.map(c => `<span data-tab="${c.id}" class="${C.tab === c.id ? 'on' : ''}">${esc(tr('cat.' + c.id, null, c.id))}</span>`)).join('');
    $('catTabs').querySelectorAll('[data-tab]').forEach(el => el.onclick = () => { C.tab = el.dataset.tab; catRender(); });
    const list = d.pieces.filter(p => (C.tab === 'all' || p.cat === C.tab) && (!q || (p.label + ' ' + (p.blurb || '') + ' ' + tr('cat.' + p.cat, null, p.cat)).toLowerCase().includes(q)));
    $('catCount').textContent = baseFoot(d);
    $('catList').innerHTML = list.map(p => `<div class="ci${C.sel === p.id ? ' on' : ''}${((p.construction !== 'blueprint' && !p.afford) || p.blocked) ? ' poor' : ''}" data-id="${esc(p.id)}">
        <div class="ci-top"><b>${esc(p.label)}</b>${p.tierLabel ? `<span class="tier-chip">${esc(p.tierLabel)}</span>` : ''}</div>
        <div class="ci-cost">${(p.costs || []).map(c => `<span class="${c.have < c.need && !d.freeBuild ? 'short' : ''}">${esc(c.label)} ${c.have}/${c.need}</span>`).join('')}</div></div>`).join('')
        || `<p class="muted" style="padding:14px">${esc(tr('ui.no_match', null, 'Nothing matches.'))}</p>`;
    $('catList').querySelectorAll('.ci').forEach(el => {
        el.onmouseenter = () => catSelect(el.dataset.id, false);
        el.onclick = () => catSelect(el.dataset.id, true);
        el.ondblclick = () => catPlace(el.dataset.id);
    });
}
function catSelect(id, sticky) {
    const p = C.data.pieces.find(x => x.id === id);
    if (!p) return;
    if (sticky) { C.sel = id; $('catList').querySelectorAll('.ci').forEach(el => el.classList.toggle('on', el.dataset.id === id)); }
    else if (C.sel && C.sel !== id) return;
    post('catHover', { id });
    show('catInfo', true);
    $('ciCat').textContent = tr('cat.' + p.cat, null, p.cat).toUpperCase();
    $('ciName').textContent = p.label;
    $('ciTier').innerHTML = (p.tiers || []).map(t => `<span class="tier-chip${t.id === p.tier ? '' : ' dim'}" title="${esc(t.name)}">${esc(t.label)}</span>`).join(p.tiers && p.tiers.length > 1 ? '<i>&rsaquo;</i>' : '');
    $('ciBlurb').textContent = p.blocked || p.blurb || '';
    $('ciHp').textContent = p.hp || '-';
    $('ciCost').innerHTML = costHtml(p.costs, C.data.freeBuild);
    $('ciNote').textContent = pieceNote(p);
    $('ciPlace').disabled = !!p.blocked;
    $('ciPlace').onclick = () => catPlace(id);
}
function catPlace(id) {
    const p = C.data && C.data.pieces.find(x => x.id === id);
    if (!p || p.blocked) return;
    show('cat', false);
    post('catPick', { id });
}
$('catSearch').addEventListener('input', () => catRender());
$('catClose').onclick = () => { show('cat', false); post('menuClose'); };

// ---------------------------------------------------------------- keypad
let code = '';
function kpShow() { $('kpDisplay').textContent = (code + '____').slice(0, 4).replace(/\d/g, '*'); }
function kpDone(v) { show('keypad', false); post('keypad', { code: v }); }
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

// ---------------------------------------------------------------- hint
function key(k, label) { return `<span><b>${k}</b> <i>${esc(label)}</i></span>`; }
function hintRender(s) {
    if (!s) { show('hint', false); return; }
    show('hint', true);
    $('hintTitle').textContent = s.label;
    tierChip($('hintTier'), s.tier);
    $('hintState').textContent = s.valid ? (s.snapped ? tr('ui.snapped', null, 'Snapped - good spot') : tr('ui.ok_here', null, 'Good spot')) : (s.reason || '');
    $('hintState').classList.toggle('bad', !s.valid);
    $('hintCost').innerHTML = costHtml(s.costs, s.free);
    const on = s.snap ? tr('ui.on', null, 'ON') : tr('ui.off', null, 'OFF');
    const keys = [key('LMB', tr('ui.k_place', null, 'place')), key('WHEEL', tr('ui.k_rotate', null, 'rotate'))];
    if (s.snaps) keys.push(key('SHIFT', `${tr('ui.k_snap', null, 'snap')} ${on}`));
    else {
        keys.push(key('SHIFT', `${tr('ui.k_surface', null, 'surface')} ${on}`));
        keys.push(key('PGUP/PGDN', `${tr('ui.k_height', null, 'height')} ${s.lift > 0 ? '+' : ''}${s.lift}cm`));
        keys.push(key(s.bar ? 'NUM 4/6/8/5' : '&larr;&rarr;&uarr;&darr;', tr('ui.k_nudge', null, 'nudge')));
        keys.push(key('ALT', tr('ui.k_fine', null, 'fine')));
        keys.push(key('R', tr('ui.k_reset', null, 'reset')));
    }
    keys.push(key('RMB', tr('ui.k_cancel', null, 'cancel')));
    $('hintKeys').innerHTML = keys.join('');
    $('hint').classList.toggle('raised', !!s.bar);
}

// ---------------------------------------------------------------- inspect
let inspectTimer = null;
function inspect(m) {
    const p = m.piece;
    $('inTitle').textContent = m.label;
    tierChip($('inTier'), m.tierLabel);
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
    const pw = m.power;
    if (pw && pw.gen) body += `<div>${tr('ui.load', null, 'Load')}: <b>${pw.used}/${pw.out}</b></div>`;
    if (pw && pw.need !== undefined) body += `<div>${tr('ui.power', null, 'Power')}: <b class="${pw.pw ? 'ok' : 'no'}">${pw.pw ? tr('ui.powered', null, 'powered') : tr('ui.no_power', null, 'no power')}</b>${pw.lit ? '' : ' (' + tr('ui.switched_off', null, 'switched off') + ')'}</div>`;
    if (pw && pw.node) body += `<div>${tr('ui.power', null, 'Power')}: <b class="${pw.pw ? 'ok' : 'no'}">${pw.pw ? tr('ui.powered', null, 'powered') : tr('ui.no_power', null, 'no power')}</b> - ${tr('ui.wires', { n: pw.wires }, pw.wires + ' wires')}</div>`;
    if (m.water) body += `<div>${tr('ui.water', null, 'Water')}: <b>${Math.floor(m.water)}</b></div>`;
    if (p.ab) {
        const h = Math.max(0, Math.round((p.ab - Date.now() / 1000) / 3600));
        body += `<div style="color:var(--danger)">${tr('ui.abandoned', { h }, `Abandoned - gone in ${h} h`)}</div>`;
    } else if (p.decay) body += `<div style="color:var(--danger)">${tr('ui.decaying', null, 'Decaying - nobody has visited')}</div>`;
    $('inBody').innerHTML = body;
    show('inspect', true);
    clearTimeout(inspectTimer);
    inspectTimer = setTimeout(() => show('inspect', false), 7000);
}

// ---------------------------------------------------------------- generator
const G = { data: null };
function genMsg(text, ok) { $('gnMsg').textContent = text || ''; $('gnMsg').classList.toggle('ok', !!ok); }
function genRender() {
    const d = G.data;
    $('gnTitle').textContent = d.label;
    const st = d.running ? tr('ui.gen_running', null, 'RUNNING') : (d.mode === 'battery' ? tr('ui.gen_battery', null, 'ON BATTERY') : tr('ui.gen_stopped', null, 'STOPPED'));
    $('gnState').textContent = st;
    $('gnState').classList.toggle('good', !!d.running);
    $('gnFuelTxt').textContent = `${d.fuel}/${d.tank}`;
    $('gnFuel').style.width = Math.min(100, d.fuel / Math.max(1, d.tank) * 100) + '%';
    $('gnBurn').textContent = tr('ui.gen_burn', { n: d.fuelHour, out: d.output }, `Burns up to ${d.fuelHour}/h, gives ${d.output} power`);
    $('gnLoadTxt').textContent = `${d.used}/${d.out}`;
    $('gnLoad').style.width = (d.out > 0 ? Math.min(100, d.used / d.out * 100) : 0) + '%';
    $('gnMode').textContent = d.mode === 'battery' ? tr('ui.gen_on_bat', null, 'Engine off, batteries carry the load') : (d.out === 0 ? tr('ui.gen_no_out', null, 'Nothing is getting power') : '');
    const slots = [];
    // jerrycan slot
    slots.push(`<div class="gs${d.res > 0 ? ' full' : ''}"><div class="gs-ico">&#9981;</div><div class="gs-name">${esc(tr('ui.gen_can', null, 'Jerrycan'))}</div>
        <div class="gs-val">${d.res}/${d.resCap}</div>
        <div class="gs-btns"><button data-a="reserve" ${d.held > 0 && d.res < d.resCap ? '' : 'disabled'}>${esc(tr('ui.gen_store', null, 'STORE'))}</button>
        <button data-a="reserveTake" ${d.res > 0 ? '' : 'disabled'}>${esc(tr('ui.gen_take', null, 'TAKE'))}</button></div>
        <div class="gs-note">${esc(tr('ui.gen_auto', null, 'Tops the tank up by itself'))}</div></div>`);
    (d.bats || []).forEach((b, i) => {
        if (b) slots.push(`<div class="gs full"><div class="gs-ico">&#128267;</div><div class="gs-name">${esc(tr('ui.gen_bat', null, 'Battery'))}</div>
            <div class="gs-val">${b.charge}%</div><div class="gs-btns"><button data-a="batOut" data-s="${i + 1}">${esc(tr('ui.gen_take', null, 'TAKE'))}</button></div></div>`);
        else slots.push(`<div class="gs"><div class="gs-ico dim">&#128267;</div><div class="gs-name">${esc(tr('ui.gen_bat_empty', null, 'Empty slot'))}</div>
            <div class="gs-val">-</div><div class="gs-btns"><button data-a="batIn" ${d.batteries > 0 ? '' : 'disabled'}>${esc(tr('ui.gen_insert', null, 'INSERT'))}</button></div></div>`);
    });
    $('gnSlots').innerHTML = slots.join('');
    $('gnSlots').querySelectorAll('[data-a]').forEach(b => b.onclick = async () => genApply(await post('genAct', { action: b.dataset.a, slot: Number(b.dataset.s) || null })));
    $('gnToggle').textContent = d.on ? tr('ui.gen_stop', null, 'STOP') : tr('ui.gen_start', null, 'START');
    $('gnToggle').classList.toggle('bad', !!d.on);
    $('gnToggle').classList.toggle('go', !d.on);
    $('gnRefuel').disabled = d.held <= 0 || d.fuel >= d.tank;
}
function genApply(r) {
    if (r && r.ok) { G.data = r; genRender(); genMsg(''); }
    else genMsg((r && r.error) || tr('build.err.failed', null, 'That did not work.'));
}
$('gnToggle').onclick = async () => genApply(await post('genAct', { action: 'toggle' }));
$('gnRefuel').onclick = () => { show('gen', false); post('genRefuel'); };
$('gnClose').onclick = () => { show('gen', false); post('genClose'); };

// ---------------------------------------------------------------- pour game
const PG = { on: false, round: 0, rounds: 4, scores: [], pos: 0, dir: 1, speed: 0.9, zone: [40, 60], raf: 0, last: 0 };
function pourZone() {
    const w = 22 - PG.round * 3;
    const a = 10 + Math.random() * (80 - w);
    PG.zone = [a, a + w];
    $('pourZone').style.left = a + '%';
    $('pourZone').style.width = w + '%';
}
function pourDots() {
    $('pourDots').innerHTML = Array.from({ length: PG.rounds }, (_, i) => {
        const s = PG.scores[i];
        return `<span class="${s === undefined ? '' : (s > 0.6 ? 'good' : (s > 0 ? 'meh' : 'bad'))}"></span>`;
    }).join('');
}
function pourTick(ts) {
    if (!PG.on) return;
    const dt = PG.last ? Math.min(50, ts - PG.last) : 16;
    PG.last = ts;
    PG.pos += PG.dir * PG.speed * dt / 10;
    if (PG.pos >= 100) { PG.pos = 100; PG.dir = -1; }
    if (PG.pos <= 0) { PG.pos = 0; PG.dir = 1; }
    $('pourNeedle').style.left = PG.pos + '%';
    PG.raf = requestAnimationFrame(pourTick);
}
function pourHit() {
    if (!PG.on) return;
    const [a, b] = PG.zone;
    const mid = (a + b) / 2, half = (b - a) / 2;
    const s = PG.pos >= a && PG.pos <= b ? Math.max(0.35, 1 - Math.abs(PG.pos - mid) / half * 0.65) : 0;
    PG.scores.push(s);
    PG.round++;
    pourDots();
    try { const snd = splash.cloneNode(); snd.volume = s > 0 ? 0.35 : 0.2; snd.play(); } catch (e) {}
    if (PG.round >= PG.rounds) return pourEnd();
    PG.speed += 0.25;
    pourZone();
}
function pourEnd() {
    PG.on = false;
    cancelAnimationFrame(PG.raf);
    const score = PG.scores.length ? PG.scores.reduce((x, y) => x + y, 0) / PG.rounds : 0;
    setTimeout(() => { show('pour', false); post('pourDone', { score }); }, 350);
}
function pourStart(rounds) {
    Object.assign(PG, { on: true, round: 0, rounds: rounds || 4, scores: [], pos: 0, dir: 1, speed: 0.9, last: 0 });
    pourZone(); pourDots();
    show('pour', true);
    PG.raf = requestAnimationFrame(pourTick);
    clearTimeout(PG.timer);
    PG.timer = setTimeout(() => { if (PG.on) { while (PG.scores.length < PG.rounds) PG.scores.push(0); pourEnd(); } }, 15000);
}
document.addEventListener('keydown', (e) => {
    if (!PG.on) return;
    if (e.code === 'Space' || e.key === 'e' || e.key === 'E' || e.key === 'Enter') { e.preventDefault(); pourHit(); }
    if (e.key === 'Escape') { while (PG.scores.length < PG.rounds) PG.scores.push(0); pourEnd(); }
});
$('pour').addEventListener('mousedown', () => pourHit());

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
$('adClose').onclick = () => { show('admin', false); post('adminClose'); };

// ---------------------------------------------------------------- vending
const V = { data: null };
function vendMsg(text, ok) { $('vdMsg').textContent = text || ''; $('vdMsg').classList.toggle('ok', !!ok); }
function vendRender() {
    const d = V.data;
    $('vdTitle').textContent = tr('piece.vending_crate', null, 'Vending crate');
    $('vdCash').textContent = tr('ui.vend_cash', { amount: d.cash }, `Your cash: ${d.cash}`);
    show('vdOwner', !!d.owner);
    if (d.owner) $('vdCollect').textContent = tr('ui.vend_collect', { amount: d.balance || 0 }, `COLLECT ${d.balance || 0}`);
    const rows = (d.items || []).map(it => {
        const left = tr('ui.vend_left', { n: it.amount }, `${it.amount} left`);
        if (d.owner) {
            if (!it.sellable) {
                return `<div class="vd-row off"><div class="nm">${esc(it.label)}<small>${left} - ${esc(tr('build.err.vend_items', null, 'Only stackable items can be sold here.'))}</small></div></div>`;
            }
            return `<div class="vd-row"><div class="nm">${esc(it.label)}<small>${left}${it.price > 0 ? '' : ' - ' + esc(tr('ui.vend_not_listed', null, 'not for sale'))}</small></div>
                <button class="step" data-step="-10" data-item="${esc(it.item)}">-</button>
                <input type="text" inputmode="numeric" maxlength="8" value="${it.price}" data-item="${esc(it.item)}">
                <button class="step" data-step="10" data-item="${esc(it.item)}">+</button>
                <button class="go" data-set="${esc(it.item)}">${tr('ui.vend_set', null, 'SET')}</button></div>`;
        }
        return `<div class="vd-row"><div class="nm">${esc(it.label)}<small>${left}</small></div><span class="pr">$${it.price}</span>
            <input type="text" inputmode="numeric" maxlength="4" value="1" data-item="${esc(it.item)}">
            <button class="go" data-buy="${esc(it.item)}">${tr('ui.vend_buy', null, 'BUY')}</button></div>`;
    }).join('');
    $('vdList').innerHTML = rows || `<p class="muted" style="padding:14px 16px">${d.owner ? tr('ui.vend_empty_owner', null, 'Empty. Press STOCK and put items in, then open the crate again to set prices.') : tr('ui.vend_empty', null, 'Nothing for sale.')}</p>`;
    const inputOf = (item) => [...$('vdList').querySelectorAll('input')].find(i => i.dataset.item === item);
    const num = (el, def) => { const n = Math.floor(Number(String(el.value).replace(/[^0-9]/g, ''))); return Number.isFinite(n) ? n : def; };
    $('vdList').querySelectorAll('input').forEach(inp => {
        inp.addEventListener('input', () => { inp.value = inp.value.replace(/[^0-9]/g, ''); });
        inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { const b = $('vdList').querySelector(`[data-set="${CSS.escape(inp.dataset.item)}"],[data-buy="${CSS.escape(inp.dataset.item)}"]`); if (b) b.click(); } });
    });
    $('vdList').querySelectorAll('[data-step]').forEach(btn => btn.onclick = () => {
        const inp = inputOf(btn.dataset.item);
        inp.value = Math.max(0, Math.min(d.maxPrice || 100000, num(inp, 0) + Number(btn.dataset.step)));
    });
    $('vdList').querySelectorAll('[data-buy]').forEach(btn => btn.onclick = async () => {
        const qty = Math.max(1, num(inputOf(btn.dataset.buy), 1));
        vendApply(await post('vendBuy', { item: btn.dataset.buy, qty }));
    });
    $('vdList').querySelectorAll('[data-set]').forEach(btn => btn.onclick = async () => {
        const price = Math.max(0, num(inputOf(btn.dataset.set), 0));
        vendApply(await post('vendPrice', { item: btn.dataset.set, price }), true);
    });
}
function vendApply(r, saved) {
    if (r && r.ok) { V.data = r; vendRender(); vendMsg(saved ? tr('build.vend_price_set', null, 'Price saved.') : '', true); }
    else vendMsg((r && r.error) || tr('build.err.failed', null, 'That did not work.'));
}
function vendClose() { show('vend', false); post('vendClose'); }
$('vdClose').onclick = vendClose;
$('vdStock').onclick = () => { show('vend', false); post('vendStock'); };
$('vdCollect').onclick = async () => vendApply(await post('vendCollect'));

// ---------------------------------------------------------------- sound
const hammer = new Audio('hammer.wav');
const splash = new Audio('pour.ogg');
// Generator hum: one looping source per running generator, volume and pan set by the game
const Hum = { ctx: null, buf: null, loading: false, nodes: {} };
async function humBuf() {
    if (Hum.buf || Hum.loading) return Hum.buf;
    Hum.loading = true;
    try {
        Hum.ctx = Hum.ctx || new (window.AudioContext || window.webkitAudioContext)();
        const data = await fetch('gen_loop.ogg').then(r => r.arrayBuffer());
        Hum.buf = await Hum.ctx.decodeAudioData(data);
    } catch (e) { Hum.buf = null; }
    Hum.loading = false;
    return Hum.buf;
}
async function humSet(list) {
    const buf = await humBuf();
    if (!buf) return;
    if (Hum.ctx.state === 'suspended') Hum.ctx.resume();
    const now = Hum.ctx.currentTime;
    const keep = {};
    (list || []).forEach(h => {
        keep[h.id] = true;
        let n = Hum.nodes[h.id];
        if (!n) {
            const src = Hum.ctx.createBufferSource();
            src.buffer = buf; src.loop = true;
            src.playbackRate.value = 0.94 + Math.random() * 0.12;
            const gain = Hum.ctx.createGain(); gain.gain.value = 0;
            const pan = Hum.ctx.createStereoPanner ? Hum.ctx.createStereoPanner() : null;
            src.connect(gain);
            if (pan) { gain.connect(pan); pan.connect(Hum.ctx.destination); } else gain.connect(Hum.ctx.destination);
            src.start(0, Math.random() * buf.duration);
            n = Hum.nodes[h.id] = { src, gain, pan };
        }
        n.gain.gain.setTargetAtTime(Math.max(0, Math.min(1, h.vol)) * 0.55, now, 0.15);
        if (n.pan) n.pan.pan.setTargetAtTime(Math.max(-1, Math.min(1, h.pan)), now, 0.1);
    });
    Object.keys(Hum.nodes).forEach(id => {
        if (keep[id]) return;
        const n = Hum.nodes[id];
        n.gain.gain.setTargetAtTime(0, now, 0.2);
        setTimeout(() => { try { n.src.stop(); } catch (e) {} }, 900);
        delete Hum.nodes[id];
    });
}

// ---------------------------------------------------------------- messages
window.addEventListener('message', (e) => {
    const m = e.data || {};
    switch (m.action) {
        case 'wheel':
            W.data = m.data; W.cats = m.cats || [];
            show('wheel', true);
            showCats();
            break;
        case 'wheelClose': closeWheel(); break;
        case 'catalogue':
            C.data = m.data; C.cats = m.cats || []; C.tab = 'all'; C.sel = null;
            $('catSearch').value = '';
            show('catInfo', false);
            show('cat', true);
            catRender();
            setTimeout(() => $('catSearch').focus(), 50);
            break;
        case 'previewSelection': C.sel=null; C.tab='all'; $('catSearch').value=''; catRender(); if(m.id) catSelect(m.id,true); break;
        case 'barScale': document.documentElement.style.setProperty('--build-bar-size',String(m.value)); break;
        case 'bar':
            document.documentElement.style.setProperty('--build-bar-size',String(m.barScale || 1));
            B.data = m.data; B.catsCfg = m.cats || []; B.cat = m.cat; B.idx = m.idx || 1;
            show('bar', true);
            barRender();
            break;
        case 'barSel': B.cat = m.cat; B.idx = m.idx || 1; barRender(); break;
        case 'barData': B.data = m.data; B.cat = m.cat; B.idx = m.idx || 1; barRender(); break;
        case 'menuClose': closeWheel(); show('bar', false); show('cat', false); break;
        case 'hint': hintRender(m.state); break;
        case 'keypad':
            code = ''; kpShow();
            show('keypad', true);
            break;
        case 'inspect': inspect(m); break;
        case 'gen': G.data = m.data; genMsg(''); show('gen', true); genRender(); break;
        case 'genClose': show('gen', false); break;
        case 'pour': pourStart(m.rounds); break;
        case 'admin':
            A.data = m.data; A.fac = null;
            $('adDetail').innerHTML = '';
            show('admin', true);
            adminRender();
            break;
        case 'adminHide': show('admin', false); break;
        case 'vend':
            V.data = m.data; vendMsg('');
            show('vend', true);
            vendRender();
            break;
        case 'vendClose': show('vend', false); break;
        case 'sound':
            try { const s = hammer.cloneNode(); s.volume = m.volume || 0.5; s.play(); } catch (err) {}
            break;
        case 'hum': humSet(m.list); break;
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || PG.on) return;
    if (visible('wheel')) { closeWheel(); post('wheelClose'); }
    if (visible('cat')) { show('cat', false); post('menuClose'); }
    if (visible('keypad')) kpDone(false);
    if (visible('admin')) { show('admin', false); post('adminClose'); }
    if (visible('vend')) vendClose();
    if (visible('gen')) { show('gen', false); post('genClose'); }
});
document.addEventListener('keydown', (e) => {
    if (!visible('keypad')) return;
    if (/^\d$/.test(e.key) && code.length < 4) { code += e.key; kpShow(); }
    if (e.key === 'Backspace') { code = code.slice(0, -1); kpShow(); }
    if (e.key === 'Enter') kpDone(code);
});

// Drag / resize the staff base panel.
if (window.BSWindow) BSWindow.make(document.getElementById('admin'), { id: 'bs_building_admin', handle: '#admin header', minW: 560, minH: 360 });

$('previewReturn').onclick = () => post('previewReturn', {});

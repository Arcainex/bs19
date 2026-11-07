// bs_building NUI: build wheel, placement hint, code keypad, inspect card, staff bases panel.
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_building';
const $ = (id) => document.getElementById(id);
const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => ({}));
const tr = (k, v, fb) => (typeof t === 'function' ? t(k, Object.assign({ fallback: fb !== undefined ? fb : k }, v || {})) : (fb || k));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ---------------------------------------------------------------- wheel
const W = { data: null, cats: [], cat: null, page: 0, pageItems: [], pageHover: null };
const PAGE_SIZE = 8;
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
    const parts = [tr('ui.pieces', { n: d.built, max: d.max }, `${d.built}/${d.max} Bauteile`)];
    if (d.mode === 'claim') {
        if (!d.hasFlag) parts.push(tr('ui.no_flag', null, 'no flag yet'));
        else if (!d.inClaim) parts.push(tr('ui.outside', null, 'outside your claim'));
    }
    if (d.raids) parts.push(d.raidOpen ? tr('ui.raid_open', null, 'RAID OPEN') : tr('ui.raid_at', { w: d.raidWindow }, `raids ${d.raidWindow}`));
    return parts.join(' - ');
}

function drawRing(items, onPick, onHover) {
    W.pageItems = items; W.pageHover = onHover;
    const svg = $('ring');
    svg.innerHTML = '';
    const n = Math.max(items.length, 1);
    const step = (Math.PI * 2) / n;
    items.forEach((it, i) => {
        const a0 = -Math.PI / 2 - step / 2 + i * step + 0.012, a1 = a0 + step - 0.024;
        const g = document.createElementNS(NS, 'g');
        g.setAttribute('class', 'seg' + (it.poor ? ' poor' : ''));
        const path = document.createElementNS(NS, 'path');
        path.setAttribute('d', arc(104, 196, a0, a1));
        g.appendChild(path);
        const mid = (a0 + a1) / 2;
        const tx = document.createElementNS(NS, 'text');
        tx.setAttribute('x', Math.cos(mid) * 150); tx.setAttribute('y', Math.sin(mid) * 150);
        // A narrow radial segment can only fit a *short* label. Use compact
        // German labels here and keep the FULL text in the searchable browser.
        const fullLabel = String(it.label || '');
        let compact = fullLabel
            .replace('Fundamente & Böden', 'Böden')
            .replace('Geländer & Kanten', 'Geländer')
            .replace('Stützen & Pfeiler', 'Stützen')
            .replace('Wände & Ecken', 'Wände')
            .replace('Fensterwände', 'Fenster')
            .replace('Türen & Durchgänge', 'Türen')
            .replace('Fundamente & Böden', 'Böden')
            .replace('Treppen & Geländer', 'Treppen')
            .replace('Dächer & Decken', 'Dächer')
            .replace('Details & Rohre', 'Details')
            .replace(/^Fensterwand /, 'Fenster ')
            .replace(/^Wandecke /, 'Ecke ')
            .replace(/^Treppe geschlossen/, 'Treppe zu')
            .replace(/^Treppe offen/, 'Treppe auf')
            .replace(/^Hohes /, 'H. ');
        const limit = n <= 3 ? 17 : (n <= 5 ? 14 : 11);
        const label = compact.length > limit ? compact.slice(0, limit - 1).trimEnd() + '…' : compact;
        tx.textContent = label;
        tx.style.fontSize = n <= 3 ? '13px' : (n <= 5 ? '11.5px' : '10.5px');
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
    updatePager();
}

function updatePager() {
    const prev = $('wheelPrev'), next = $('wheelNext'), info = $('wheelPage');
    if (!prev || !next || !info) return;
    const total = W.pageItems.length;
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    // Pager always remains visible: a back arrow must not disappear on page one.
    prev.classList.remove('hidden'); next.classList.remove('hidden'); info.classList.remove('hidden');
    prev.disabled = W.page <= 0; next.disabled = W.page >= pages - 1;
    info.textContent = `${W.page + 1} / ${pages}`;
}

function drawPaged(items, onPick, onHover) {
    W.pageItems = items; W.pageHover = onHover;
    const pages = Math.max(1, Math.ceil(items.length / PAGE_SIZE));
    W.page = Math.max(0, Math.min(W.page, pages - 1));
    const start = W.page * PAGE_SIZE;
    drawRing(items.slice(start, start + PAGE_SIZE), onPick, onHover);
    // drawRing only sees the visible slice, so restore the full list for pager calculations.
    W.pageItems = items; updatePager();
}

function redrawPage() {
    if (W.cat) showPieces(W.cat, true); else showCats(true);
}

// V19: F2-Gruppierung ist reine UI-Ansicht. Die originalen IDs, F10-Kategorien,
// Crafting-/Bett-/Kisten-/Claim-Callbacks und gespeicherten Props bleiben unveraendert.
// Ein Bauteil kann nicht aus seiner echten F10/Server-Kategorie migriert werden,
// nur weil es im Radialmenue zusammen mit passenden Teilen angezeigt wird.
const AZ_FIRST_PAGE = [
    {id:'az_utility',  label:'Utility',             sources:['utility']},
    {id:'az_floors',   label:'Fundamente & Böden',  sources:['kenney_boeden']},
    {id:'az_walls',    label:'Wände',                sources:['kenney_waende','kenney_fenster']},
    {id:'az_doors',    label:'Türen & Tore',         sources:['kenney_tueren','openings']},
    {id:'az_stairs',   label:'Treppen & Geländer',  sources:['kenney_treppen','kenney_gelaender']},
    {id:'az_roofs',    label:'Dächer & Decken',     sources:['kenney_daecher']},
    {id:'az_defense',  label:'Verteidigung',         sources:['defense','kenney_barrikaden']},
    {id:'az_claim',    label:'Claim',                sources:['claim']}
];
function wheelGroups(rawCats, pieces) {
    const actual = new Map(rawCats.map(c=>[c.id,c]));
    const assigned = new Set();
    const primary = AZ_FIRST_PAGE.map(g=>{
        const sources=g.sources.filter(s=>actual.has(s));
        sources.forEach(s=>assigned.add(s));
        return {...g,sources};
    }).filter(g=>g.sources.some(s=>pieces.some(p=>p.cat===s)));
    const extra = rawCats.filter(c=>!assigned.has(c.id) && pieces.some(p=>p.cat===c.id))
        .map(c=>({id:c.id,label:c.label||c.id,sources:[c.id]}))
        .sort((a,b)=>a.label.localeCompare(b.label,'de'));
    return [...primary,...extra];
}
function wheelPieces(cat) {
    const group=W.cats.find(c=>c.id===cat);
    if(!group || !W.data || !Array.isArray(W.data.pieces))return [];
    const sources=new Set(group.sources);
    return W.data.pieces.filter(p=>sources.has(p.cat));
}

function itemDisabled(p){ return !!(p.blocked || p.modelAvailable === false); }
function pickItem(p){
    if(itemDisabled(p)) { hub(p.label, p.modelAvailable === false ? 'Modell fehlt – bs_building_assets prüfen' : p.blocked, p.costs, ''); return; }
    post('wheelPick', {id:p.id}); closeWheel();
}
function buildBrowser(){
    const input=$('wheelSearch'),list=$('wheelList'),panel=$('wheelBrowser');
    if(!W.data || !W.cat){ panel.classList.add('hidden'); return; }
    panel.classList.remove('hidden');
    const category=W.cats.find(c=>c.id===W.cat);
    $('wheelBrowserTitle').textContent=category?.label || 'BAUTEILE';
    const q=input.value.toLocaleLowerCase('de-DE').trim();
    const matches=wheelPieces(W.cat).filter(p=>!q || `${p.label} ${p.id}`.toLocaleLowerCase('de-DE').includes(q));
    $('wheelBrowserCount').textContent=`${matches.length} von ${wheelPieces(W.cat).length}`;
    list.replaceChildren();
    for(const p of matches){
        const btn=document.createElement('button');btn.type='button';btn.className='wheel-browser-item';
        if(itemDisabled(p))btn.classList.add('unavailable');
        const name=document.createElement('strong');name.textContent=p.label;
        const desc=document.createElement('span');desc.textContent=p.modelAvailable===false?'MODELL FEHLT':p.blocked?'GESPERRT':`${p.size?.[0]||'?'} × ${p.size?.[1]||'?'} × ${p.size?.[2]||'?'} m`;
        btn.append(name,desc);btn.onmouseenter=()=>{ hub(p.label,p.blurb,p.costs,'Klick: Bauteil auswählen');window.AZPreview?.select(p); };
        btn.onfocus=()=>window.AZPreview?.select(p);
        btn.onclick=()=>pickItem(p);list.append(btn);
    }
    if(!matches.length){const el=document.createElement('p');el.className='wheel-browser-empty';el.textContent='Keine passenden Bauteile';list.append(el);}
}
function showCats(keepPage){
    W.cat=null;
    window.AZPreview?.select(null);
    $('wheelSearch').value='';
    if(!keepPage)W.page=0;
    // Reihenfolge = Bauablauf, feste acht Positionen auf Seite 1.
    // Kein Auto-Fokus, keine automatisch ausgewaehlte Kategorie.
    const items=W.cats.map(c=>{
        const list=wheelPieces(c.id);
        return {id:c.id,label:c.label,sub:`${list.length} Teile`,list};
    }).filter(c=>c.list.length>0);
    drawPaged(items,c=>showPieces(c.id),c=>hub(c.label,`${c.list.length} Bauteile`,null,baseFoot()));
    hub('ALPHA-Z', 'Kategorie im Radialmenü auswählen',null,baseFoot());
    buildBrowser();
}
function showPieces(cat,keepPage){
    W.cat=cat;
    if(!keepPage){W.page=0;$('wheelSearch').value='';}
    const items=wheelPieces(cat).map(p=>Object.assign({},p,{
        poor:!p.afford || itemDisabled(p),sub:itemDisabled(p)?'NICHT VERFÜGBAR':(p.afford?'':'MATERIAL FEHLT')
    }));
    drawPaged(items,pickItem,p=>{
        hub(p.label,p.modelAvailable===false?'Modell nicht gefunden':(p.blocked||p.blurb),p.costs,
            p.modelAvailable===false?'Server-Resource prüfen':'Radialmenü oder Liste links');
        window.AZPreview?.select(p);
    });
    hub(W.cats.find(c=>c.id===cat)?.label||cat,'Bauteil wählen · alternativ links suchen',null,baseFoot());
    buildBrowser();
}
$('wheelSearch').addEventListener('input',()=>buildBrowser());
$('wheelPrev').addEventListener('click', () => { if (W.page > 0) { W.page--; redrawPage(); } });
$('wheelNext').addEventListener('click', () => { const pages = Math.ceil(W.pageItems.length / PAGE_SIZE); if (W.page < pages - 1) { W.page++; redrawPage(); } });

function closeWheel() { $('wheel').classList.add('hidden'); $('wheelBrowser').classList.add('hidden'); window.AZPreview?.close(); }

document.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    // In the active build preview, right-click behaves like ESC: return to F2.
    // Never override the collision confirmation dialog.
    if (!$('survivalOverlay').classList.contains('hidden')) {
        if ($('survivalCollision').classList.contains('hidden')) post('placementAction', {action:'cancel'});
        return;
    }
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

// ---------------------------------------------------------------- F2 survival placement overlay (does not touch F10)
const survivalHeightCall = async (op, fine=false) => { const r = await post('placementHeight', {op, fine}); if (r && Number.isFinite(Number(r.height))) $('survivalHeightValue').textContent = `${Number(r.height)>=0?'+':''}${Number(r.height).toFixed(2).replace('.', ',')} m`; };
window.addEventListener('keydown', (e) => {
    if ($('survivalOverlay').classList.contains('hidden')) return;
    if (!$('survivalCollision').classList.contains('hidden')) { if(e.key==='Escape'){e.preventDefault();post('placementCollisionDecision',{accept:false});} return; }
    if (e.repeat) return;
    const key = e.key.toLowerCase();
    if (['+','=','add','-','subtract','numpadadd','numpadsubtract'].includes(key) && !$('survivalHeight').classList.contains('hidden')) { e.preventDefault(); survivalHeightCall(['+','=','add','numpadadd'].includes(key)?'up':'down', e.shiftKey && key !== '+'); return; }
    if (key === 'delete' || key === 'del') { e.preventDefault(); post('placementAction', {action:'reset'}); return; }
    if (key === 'alt') { e.preventDefault(); post('placementAction', {action:'walk'}); return; }
    const actions = {escape:'cancel', r:'rotate', e:'place', enter:'place', x:'magnet'};
    if (actions[key]) { e.preventDefault(); post('placementAction', {action:actions[key]}); }
});
// Wheel rotation is delivered through the focused NUI, not disabled GTA controls.
window.addEventListener('wheel', (e) => {
    if ($('survivalOverlay').classList.contains('hidden')) return;
    if (e.target.closest('#survivalHeight')) return;
    e.preventDefault();
    post('placementAction', {action:'wheel', delta:e.deltaY < 0 ? 1 : -1, fine:e.shiftKey});
}, {passive:false});
// Clicking the F2 snapping row uses the exact same action as the X key.
$('survivalSnapRow').setAttribute('role', 'button');
$('survivalSnapRow').setAttribute('tabindex', '0');
$('survivalSnapRow').addEventListener('click', () => {
    if (!$('survivalOverlay').classList.contains('hidden')) post('placementAction', {action:'magnet'});
});
$('survivalSnapRow').addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); $('survivalSnapRow').click(); }
});
// ---------------------------------------------------------------- messages
const hammer = new Audio('hammer.wav');
window.addEventListener('message', (e) => {
    const m = e.data || {};
    switch (m.action) {
        case 'placementCollisionPrompt':
            if (m.visible) $('survivalCollisionText').textContent = m.text || 'Hier steht möglicherweise bereits etwas. Trotzdem platzieren?';
            $('survivalCollision').classList.toggle('hidden', !m.visible);
            break;
        case 'survivalOverlay':
            $('survivalOverlay').classList.toggle('hidden', !m.visible);
            if (m.visible) {
                $('survivalName').textContent = m.label || 'Bauteil';
                $('survivalHeight').classList.remove('hidden');
                $('survivalHeightRange').textContent = m.foundation ? '−1,00 bis +2,00 m' : '−0,50 bis +0,50 m';
            }
            break;
        case 'survivalState':
            $('survivalStatus').textContent = m.snapped ? '● ANSCHLUSS GEFUNDEN' : '● FREIE PLATZIERUNG';
            $('survivalStatus').classList.toggle('is-snapped', !!m.snapped);
            $('survivalHeight').classList.remove('is-locked');
            $('survivalHeightValue').textContent = `${m.height >= 0 ? '+' : ''}${Number(m.height || 0).toFixed(2).replace('.', ',')} m`;
            $('survivalSnapValue').textContent = m.magnet ? 'EIN' : 'AUS';
            $('survivalWalkValue').textContent = m.walking ? 'EIN' : 'AUS';
            $('survivalSnapRow').classList.toggle('is-active', !!m.magnet);
            $('survivalWalkRow').classList.toggle('is-active', !!m.walking);
            $('survivalMode').textContent = m.walking ? 'BEWEGUNGSMODUS AKTIV' : 'BAUMODUS AKTIV';
            $('survivalMode').classList.toggle('is-walking', !!m.walking);

            break;
        case 'wheel':
            W.data = m.data; W.cats = wheelGroups(m.cats || [], (m.data && m.data.pieces) || []);
            $('wheel').classList.remove('hidden');
            window.AZPreview?.open();
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

$('survivalCollisionCancel').onclick = () => post('placementCollisionDecision', {accept:false});
$('survivalCollisionAccept').onclick = () => post('placementCollisionDecision', {accept:true});

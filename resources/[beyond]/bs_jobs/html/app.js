// bs_jobs panels: mechanic garage and gunsmith bench. The server decides; this only shows and asks.
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_jobs';
const $ = (id) => document.getElementById(id);
const t = (k, v) => (window.BSI18n ? window.BSI18n.t(k, v) : k);
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// Rough swatches for the GTA colour indices used in the garage config.
const SWATCH = { 12: '#1a1a1a', 13: '#3c3d3f', 14: '#64676a', 22: '#2c2e30', 48: '#5b231c', 105: '#9c8b6c', 106: '#4f3a2a', 107: '#3a2a20', 113: '#cfc7b5', 115: '#9a5a2a', 151: '#2f3a28', 152: '#4b4e32', 153: '#4a3d2f', 154: '#9c8a68' };
const S = { mode: null, data: null, list: [] };

async function post(name, data) {
    try {
        const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) });
        return await r.json();
    } catch (e) { return { ok: false }; }
}

function costLine(cost, mult) {
    return (cost || []).map((c) => {
        const need = c.amount * (mult || 1);
        const miss = c.have < need;
        return `<span class="${miss ? 'miss' : ''}">${need}x ${esc(c.label)}</span>`;
    }).join(' · ');
}

function msg(text, kind) { const m = $('msg'); if (m) { m.textContent = text || ''; m.className = 'msg ' + (kind || ''); } }

function renderGarage() {
    const d = S.data;
    $('eyebrow').textContent = `${t('ui.workshop')} · ${esc(d.plate)}${d.owned ? '' : ' · ' + t('ui.not_saved')}`;
    $('title').textContent = d.kind === 'bike' ? t('ui.bike_garage') : t('ui.garage');
    let h = `<div class="msg" id="msg"></div>`;
    h += `<div class="sec">${t('ui.repair')}</div><div class="row"><span><b>${t('ui.repair_all')}</b><small>${costLine(d.repair.cost)}</small></span><div class="btns"><button class="b" data-a="repair">${t('ui.do')}</button></div></div>`;
    h += `<div class="sec">${t('ui.paint')}</div>`;
    h += (d.paints || []).map((p) => `<div class="row"><span><b><i class="sw" style="background:${SWATCH[p.p1] || '#555'}"></i><i class="sw" style="background:${SWATCH[p.p2] || '#555'}"></i>${esc(p.label)}</b><small>${costLine(p.cost)}</small></span><div class="btns"><button class="b${d.colours && d.colours.p1 === p.p1 && d.colours.p2 === p.p2 ? ' on' : ''}" data-a="paint" data-id="${esc(p.id)}">${t('ui.spray')}</button></div></div>`).join('');
    if ((d.slots || []).length) {
        h += `<div class="sec">${t('ui.parts')}</div>`;
        h += d.slots.map((s) => {
            const lv = [];
            for (let i = 0; i <= s.max; i++) lv.push(`<button class="b${s.level === i ? ' on' : ''}" data-a="mod" data-id="${esc(s.id)}" data-level="${i}">${i === 0 ? t('ui.stock') : i}</button>`);
            return `<div class="row"><span><b>${esc(s.label)}</b><small>${t('ui.per_level')}: ${costLine(s.cost)}</small></span><div class="btns">${lv.join('')}</div></div>`;
        }).join('');
    }
    if ((d.props || []).length) {
        const fitted = (d.cosmetic && d.cosmetic.props) || {};
        h += `<div class="sec">${t('ui.bolt_on')}</div>`;
        h += d.props.map((p) => `<div class="row"><span><b>${esc(p.label)}</b><small>${costLine(p.cost)}</small></span><div class="btns"><button class="b${fitted[p.id] ? ' on' : ''}" ${fitted[p.id] ? 'disabled' : ''} data-a="prop" data-id="${esc(p.id)}">${fitted[p.id] ? t('ui.fitted') : t('ui.fit')}</button></div></div>`).join('');
        h += `<div class="row"><span><b>${t('ui.strip_props')}</b></span><div class="btns"><button class="b" data-a="clearprops">${t('ui.do')}</button></div></div>`;
    }
    $('body').innerHTML = h;
    $('foot').innerHTML = `<input id="bill" inputmode="numeric" placeholder="${t('ui.bill_ph', { n: d.maxBill })}"><button class="b" data-a="bill">${t('ui.send_bill')}</button>`;
}

function renderGunsmith() {
    $('eyebrow').textContent = t('ui.armory');
    $('title').textContent = t('ui.gunsmith');
    let h = `<div class="msg" id="msg"></div>`;
    h += (S.list || []).map((r) => `<div class="row"><span><b>${r.amount > 1 ? r.amount + 'x ' : ''}${esc(r.label)}</b><small>${costLine(r.cost)} · ${r.seconds}s</small></span><div class="btns"><button class="b" ${r.can ? '' : 'disabled'} data-a="craft" data-id="${esc(r.id)}">${t('ui.craft')}</button></div></div>`).join('');
    $('body').innerHTML = h;
    $('foot').innerHTML = '';
}

function render() { if (S.mode === 'garage') renderGarage(); else if (S.mode === 'gunsmith') renderGunsmith(); }

let busy = false;
document.addEventListener('click', async (e) => {
    if (e.target.id === 'close') { post('close'); return; }
    const el = e.target.closest('[data-a]');
    if (!el || el.disabled || busy) return;
    const a = el.dataset.a;
    busy = true;
    try {
        if (a === 'craft') { await post('gsCraft', { id: el.dataset.id }); return; }
        if (a === 'bill') {
            const amount = Number(($('bill') || {}).value || 0);
            const r = await post('bill', { amount });
            msg(r && r.ok ? t('ui.bill_sent') : (r && r.error) || t('ui.failed'), r && r.ok ? 'ok' : 'bad');
            return;
        }
        const r = await post('garage', { what: a, id: el.dataset.id, level: el.dataset.level !== undefined ? Number(el.dataset.level) : undefined });
        if (r && r.ok) {
            if (r.data) S.data = r.data;
            render();
            msg(r.saved ? t('ui.done_saved') : t('ui.done'), 'ok');
        } else msg((r && r.error) || t('ui.failed'), 'bad');
    } finally { busy = false; }
});

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'garage') { S.mode = 'garage'; S.data = d.data; render(); $('root').classList.remove('hidden'); }
    else if (d.action === 'gunsmith') { S.mode = 'gunsmith'; S.list = d.list || []; render(); $('root').classList.remove('hidden'); }
    else if (d.action === 'close') { $('root').classList.add('hidden'); S.mode = null; }
});

document.addEventListener('keyup', (e) => { if (e.key === 'Escape') post('close'); });
if (window.BSI18n && window.BSI18n.onChange) window.BSI18n.onChange(render);

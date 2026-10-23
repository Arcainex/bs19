// craft.js - the CRAFT tab. Talks to bs_crafting (hand + stations) and bs_recycler (machines) by resource name.
(() => {
  'use strict';
  const pane = document.querySelector('.pane[data-pane="craft"]');
  const root = document.getElementById('craftRoot');
  if (!pane || !root) return;

  const call = (res, name, body) => fetch(`https://${res}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
  }).then(r => r.json()).catch(() => null);

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const icon = (item, cat) => (typeof BSIcons !== 'undefined' ? BSIcons.get(item, cat) : '');
  const fmtT = (s) => { s = Math.max(0, Math.round(s)); const m = Math.floor(s / 60); return m ? `${m}:${String(s % 60).padStart(2, '0')}` : `${s}s`; };

  let dict = {};
  const t = (k, v) => {
    let s = dict[k]; if (s == null) return k;
    if (v) s = String(s).replace(/\{(\w+)\}/g, (m, n) => (v[n] != null ? v[n] : m));
    return s;
  };

  const S = { ctx: null, data: null, cat: 'all', q: '', sel: null, qty: 1, timer: null, tick: null, busy: false, lastFetch: 0 };

  // ---------------------------------------------------------------- loading
  async function load() {
    const r = await call('bs_crafting', 'state');
    if (!r) { root.innerHTML = '<div class="cempty">...</div>'; return; }
    dict = r.dict || dict;
    S.ctx = r.context || { kind: 'hand' };
    if (S.ctx.kind === 'recycler') {
      const m = await call('bs_recycler', 'state');
      if (m && m.dict) dict = Object.assign({}, dict, m.dict);
      S.data = m && m.data;
      S.lastFetch = Date.now();
      return renderMachine();
    }
    S.data = r.data;
    S.lastFetch = Date.now();
    if (!S.data || !S.data.ok) { root.innerHTML = `<div class="cempty">${esc((S.data && S.data.error) || '...')}</div>`; return; }
    render();
  }

  function start() { stop(); S.sel = null; S.cat = 'all'; S.q = ''; load(); S.timer = setInterval(load, 2500); S.tick = setInterval(countdown, 1000); }
  function stop() { clearInterval(S.timer); clearInterval(S.tick); S.timer = S.tick = null; }

  new MutationObserver(() => { if (pane.classList.contains('is-active')) { if (!S.timer) start(); } else stop(); })
    .observe(pane, { attributes: true, attributeFilter: ['class'] });
  window.addEventListener('message', (e) => { if (e.data && e.data.action === 'close') stop(); });

  // Local countdown between fetches so bars move every second.
  function countdown() {
    const gone = (Date.now() - S.lastFetch) / 1000;
    root.querySelectorAll('[data-left]').forEach((el) => {
      const left = Math.max(0, Number(el.dataset.left) - gone), dur = Number(el.dataset.dur) || 1;
      const txt = el.querySelector('.cjob__state'); if (txt && el.dataset.run === '1') txt.textContent = `${t('ui.running')} ${fmtT(left)}`;
      const bar = el.querySelector('.cbar i'); if (bar) bar.style.width = `${Math.min(100, 100 * (1 - left / dur))}%`;
    });
  }

  // ---------------------------------------------------------------- hand / station
  function head() {
    const d = S.data, st = d.station;
    const faster = Math.round(Math.min(0.5, (d.level || 0) * 0.025) * 100);
    return `<header class="craft__head">
      <span class="craft__title">${esc(st ? st.label.toUpperCase() : t('ui.hand'))}</span>
      <span class="craft__hint">${esc(st ? t('ui.station_hint') : t('ui.hand_hint'))}</span>
      ${d.sourceCount ? `<span class="craft__chip craft__chip--warn">${esc(t('ui.nearby', { n: d.sourceCount }))}</span>` : ''}
      <span class="craft__chip craft__chip--good">${esc(t('ui.level', { level: d.level || 0 }))}${faster ? ' &middot; ' + esc(t('ui.faster', { pct: faster })) : ''}</span>
    </header>`;
  }

  function visibleRecipes() {
    const q = S.q.trim().toLowerCase();
    return (S.data.recipes || []).filter(r => (S.cat === 'all' || r.cat === S.cat)
      && (!q || r.label.toLowerCase().includes(q) || r.costs.some(c => c.label.toLowerCase().includes(q))));
  }

  function listHtml() {
    const cats = ['all', ...(S.data.categories || []).filter(c => (S.data.recipes || []).some(r => r.cat === c))];
    const list = visibleRecipes();
    return `<div class="cbox"><div class="cbox__head"><b>${esc(S.data.station ? S.data.station.label.toUpperCase() : t('ui.craft'))}</b><span>${list.length}</span></div>
      <div class="cbox__body">
        <div class="ctools"><input class="csearch" id="cSearch" placeholder="${esc(t('ui.search'))}" value="${esc(S.q)}" spellcheck="false" autocomplete="off">
        <div class="ccats">${cats.map(c => `<button class="ccat${S.cat === c ? ' is-on' : ''}" data-ccat="${c}">${esc(c === 'all' ? t('ui.all') : t('ui.cat.' + c))}</button>`).join('')}</div></div>
        ${list.map(r => `<div class="crow${r.can ? '' : ' is-off'}${S.sel === r.id ? ' is-sel' : ''}" data-rec="${esc(r.id)}">
          <div class="cicon" data-cat="${esc(r.category)}">${icon(r.item, r.category)}</div>
          <div class="crow__main"><div class="crow__name">${esc(r.label)}${r.amount > 1 ? ` <span class="crow__sub">x${r.amount}</span>` : ''}</div>
          <div class="crow__sub crow__clip">${esc(r.costs.map(c => `${c.need} ${c.label}`).join(' · '))}</div></div>
          <div class="crow__sub crow__time">${fmtT(r.time)}</div></div>`).join('') || `<div class="cempty">-</div>`}
      </div></div>`;
  }

  function detailHtml() {
    const r = (S.data.recipes || []).find(x => x.id === S.sel);
    if (!r) return `<div class="cbox"><div class="cbox__head"><b>${esc(t('ui.makes'))}</b></div><div class="cempty">${esc(t('ui.select_recipe'))}</div></div>`;
    const max = Math.max(1, Math.min(10, ...r.costs.map(c => Math.floor(c.have / c.need))));
    return `<div class="cbox"><div class="cbox__head"><b>${esc(t('ui.makes'))}</b>${r.explosive ? `<span class="craft__chip craft__chip--warn">${esc(t('ui.explosive'))}</span>` : ''}</div>
      <div class="cbox__body"><div class="cdetail">
        <div class="cdetail__top"><div class="cicon cicon--lg" data-cat="${esc(r.category)}">${icon(r.item, r.category)}</div>
          <div class="crow__main"><div class="cdetail__name">${esc(r.label)}${r.amount > 1 ? ' x' + r.amount : ''}</div>
          <div class="cdetail__meta">${esc(t('ui.time'))} ${fmtT(r.time)}${r.time < r.baseTime ? ` <s>${fmtT(r.baseTime)}</s>` : ''}</div>
          ${r.tools && r.tools.length ? `<div class="cdetail__meta">${esc(t('ui.tools'))}: ${esc(r.tools.join(' / '))}</div>` : ''}</div></div>
        <div><div class="clabel">${esc(t('ui.needs'))}</div>
          ${r.costs.map(c => `<div class="ccost ${c.have >= c.need ? 'is-ok' : 'is-short'}"><div class="cicon" data-cat="${esc(c.category)}">${icon(c.item, c.category)}</div><span class="ccost__name">${esc(c.label)}</span><span class="ccost__n">${c.have} / ${c.need}</span></div>`).join('')}</div>
        ${r.blocked ? `<div class="cblock">${esc(r.blocked)}</div>` : ''}
        <div class="cqty"><span class="clabel" style="margin:0">${esc(t('ui.amount'))}</span>
          <button class="cbtn cbtn--sm" data-qty="-1">-</button><input id="cQty" type="number" min="1" max="${max}" value="${Math.min(S.qty, max)}"><button class="cbtn cbtn--sm" data-qty="1">+</button>
          <span style="flex:1"></span><button class="cbtn cbtn--go" id="cGo" ${r.can && !S.busy ? '' : 'disabled'}>${esc(t('ui.craft'))}</button></div>
      </div></div></div>`;
  }

  function jobHtml(j, canCancel) {
    const state = j.status === 'full' ? `<span class="cjob__state is-full">${esc(t('ui.waiting_space'))}</span>`
      : j.running ? `<span class="cjob__state is-run">${esc(t('ui.running'))} ${fmtT(j.left)}</span>` : `<span class="cjob__state">${esc(t('ui.queued'))} ${fmtT(j.dur)}</span>`;
    return `<div class="cjob" data-left="${j.left}" data-dur="${j.dur}" data-run="${j.running && j.status !== 'full' ? 1 : 0}">
      <div class="cjob__top"><div class="cicon cicon--sm" data-cat="${esc(j.category)}">${icon(j.item, j.category)}</div>
      <span>${esc(j.label)}${j.amount > 1 ? ' x' + j.amount : ''}${j.owner && !j.mine ? ` <small class="crow__sub">${esc(t('ui.by', { name: j.owner }))}</small>` : ''}</span>${state}
      ${canCancel && j.mine ? `<button class="cbtn cbtn--sm cbtn--bad" data-cancel="${esc(j.id)}">${esc(t('ui.cancel'))}</button>` : ''}</div>
      ${j.running ? `<div class="cbar"><i style="width:${Math.min(100, 100 * (1 - j.left / Math.max(1, j.dur)))}%"></i></div>` : ''}</div>`;
  }

  function sideHtml() {
    const d = S.data;
    const q = d.station ? (d.queue || []) : (d.hand || []);
    const max = d.station ? d.stationMax : d.handMax;
    let html = `<div class="cbox cbox--queue"><div class="cbox__head"><b>${esc(t('ui.queue'))}</b><span>${q.length} / ${max}</span></div>
      <div class="cbox__body">${q.length ? q.map(j => jobHtml(j, true)).join('') : `<div class="cempty">${esc(t('ui.empty_queue'))}</div>`}</div></div>`;
    if (d.station) {
      const st = d.storage || [];
      html += `<div class="cbox cbox--fill"><div class="cbox__head"><b>${esc(t('ui.storage'))}</b>${st.length ? `<button class="cbtn cbtn--sm" data-take="*">${esc(t('ui.take_all'))}</button>` : ''}</div>
        <div class="cbox__body">${st.length ? `<div class="cstore">${st.map(s => `<div class="cslot" data-cat="${esc(s.category)}" data-take="${esc(s.item)}" title="${esc(s.label)}">${icon(s.item, s.category)}<b>${s.amount}</b></div>`).join('')}</div>` : `<div class="cempty">${esc(t('ui.storage_empty'))}</div>`}</div></div>`;
    } else {
      const dl = d.dismantle || [];
      html += `<div class="cbox cbox--fill"><div class="cbox__head"><b>${esc(t('ui.dismantle'))}</b></div>
        <div class="cbox__body"><div class="cyield">${esc(t('ui.dismantle_hint'))}</div>
        ${dl.length ? dl.map(x => `<div class="crow${x.hasTool ? '' : ' is-off'}" data-dis="${esc(x.item)}"><div class="cicon" data-cat="${esc(x.category)}">${icon(x.item, x.category)}</div>
          <div class="crow__main"><div class="crow__name">${esc(x.label)} <span class="crow__sub">x${x.count}</span></div><div class="crow__sub crow__clip">${esc(x.preview || '')}</div></div>
          <div class="crow__sub crow__time">${esc(x.toolLabel || '')}</div></div>`).join('') : `<div class="cempty">${esc(t('ui.nothing_to_dismantle'))}</div>`}</div></div>`;
    }
    return `<div class="craft__side">${html}</div>`;
  }

  function farmHtml() {
    const f = S.data.farm || {}, c = f.crop;
    let body;
    if (!c) {
      body = `<div class="cempty">${esc(t('ui.no_crop'))}</div><div class="cfarm__row">${(f.seeds || []).map(s => `<button class="cbtn" data-farm="plant" data-arg="${esc(s.item)}" ${s.have > 0 ? '' : 'disabled'}>${esc(t('ui.plant'))}: ${esc(s.label)} (${s.have})</button>`).join('')}</div>`;
    } else {
      const ready = c.progress >= 1;
      body = `<div class="cfarm__state">${esc(c.label)} &middot; ${esc(ready ? t('ui.ready') : t('ui.growing'))}${c.left != null && !ready ? ' &middot; ' + esc(t('ui.left', { t: fmtT(c.left) })) : ''}</div>
        <div class="cbar" style="height:6px"><i style="width:${Math.round(c.progress * 100)}%"></i></div>
        <div class="cfarm__row"><span class="ctag${c.water ? ' is-on' : ''}">${esc(t('ui.water'))}</span><span class="ctag${c.fert ? ' is-on' : ''}">${esc(t('ui.fertilize'))}</span></div>
        ${!(c.water && c.fert) ? `<div class="cyield">${esc(t('ui.needs_care'))}</div>` : ''}
        <div class="cfarm__row">
          <button class="cbtn" data-farm="water" ${c.water || !f.haveWater ? 'disabled' : ''}>${esc(t('ui.water'))} (${f.haveWater || 0})</button>
          <button class="cbtn" data-farm="fert" ${c.fert || !f.haveFert ? 'disabled' : ''}>${esc(t('ui.fertilize'))} (${f.haveFert || 0})</button>
          <button class="cbtn cbtn--go" data-farm="harvest" ${ready ? '' : 'disabled'}>${esc(t('ui.harvest'))}</button></div>`;
    }
    return `<div class="cbox" style="grid-column:1/3"><div class="cbox__head"><b>${esc(S.data.station.label.toUpperCase())}</b></div><div class="cbox__body"><div class="cfarm">${body}</div></div></div>`;
  }

  function render() {
    const keepFocus = document.activeElement && document.activeElement.id === 'cSearch';
    const caret = keepFocus ? document.activeElement.selectionStart : 0;
    const scrolls = [...root.querySelectorAll('.cbox__body')].map(b => b.scrollTop);
    if (S.data.station && S.data.station.farm) {
      root.innerHTML = head() + `<div class="craft__cols">${farmHtml()}${sideHtml()}</div>`;
    } else {
      root.innerHTML = head() + `<div class="craft__cols">${listHtml()}${detailHtml()}${sideHtml()}</div>`;
    }
    root.querySelectorAll('.cbox__body').forEach((b, i) => { if (scrolls[i]) b.scrollTop = scrolls[i]; });
    if (keepFocus) { const s = document.getElementById('cSearch'); s.focus(); s.setSelectionRange(caret, caret); }
  }

  // ---------------------------------------------------------------- recycler machine
  function machineSlots(list, attr) {
    const cells = (list || []).map(s => `<div class="cslot" data-cat="${esc(s.category)}" ${attr}="${esc(s.item)}" title="${esc(s.label)}">${icon(s.item, s.category)}<b>${s.amount}</b></div>`);
    while (cells.length < 12) cells.push('<div class="cslot cslot--empty"></div>');
    return `<div class="cstore">${cells.join('')}</div>`;
  }

  function renderMachine() {
    const m = S.data;
    if (!m || !m.ok) { root.innerHTML = `<div class="cempty">${esc((m && m.error) || '...')}</div>`; return; }
    const fuelPct = Math.min(100, 100 * m.fuel / Math.max(1, m.fuelMax));
    const status = m.status ? t('rec.status.' + m.status) : '';
    root.innerHTML = `<header class="craft__head"><span class="craft__title">${esc(t('rec.title'))}</span>
        <span class="craft__hint">${esc(t('rec.hint'))}</span>
        <span class="craft__chip ${m.running ? 'craft__chip--good' : 'craft__chip--warn'}">${esc(status)}</span>
        <span class="craft__chip craft__chip--good">+${m.bonus || 0}% ${esc(t('rec.yield'))}</span></header>
      <div class="craft__head" style="border-left-color:var(--good)">
        <div class="cfuel"><span class="clabel" style="margin:0">${esc(t('rec.fuel'))}</span><div class="cfuel__track"><i style="width:${fuelPct}%"></i></div>
          <span class="craft__chip">${m.fuel.toFixed(1)} / ${m.fuelMax} L</span>
          <button class="cbtn cbtn--sm" data-mact="fuel" ${m.canFuel ? '' : 'disabled'}>${esc(t('rec.add_fuel'))}</button></div>
        <span class="craft__chip">${esc(t('rec.per_item', { s: m.itemSeconds, n: m.itemsPerLitre }))}</span>
        <button class="cbtn ${m.running ? 'cbtn--bad' : 'cbtn--go'}" data-mact="${m.running ? 'stop' : 'start'}">${esc(m.running ? t('rec.stop') : t('rec.start'))}</button>
      </div>
      <div class="cmach">
        <div class="cbox"><div class="cbox__head"><b>${esc(t('rec.bag'))}</b><span>${esc(t('rec.bag_hint'))}</span></div>
          <div class="cbox__body">${(m.bag || []).map(s => `<div class="crow" data-load="${esc(s.item)}"><div class="cicon" data-cat="${esc(s.category)}">${icon(s.item, s.category)}</div>
            <div class="crow__main"><div class="crow__name">${esc(s.label)} <span class="crow__sub">x${s.amount}</span></div><div class="crow__sub">${esc(s.preview || '')}</div></div><div></div></div>`).join('') || `<div class="cempty">${esc(t('rec.nothing'))}</div>`}</div></div>
        <div class="cbox"><div class="cbox__head"><b>${esc(t('rec.input'))}</b>${m.progress != null ? `<span>${Math.round(m.progress * 100)}%</span>` : ''}</div>
          <div class="cbox__body">${machineSlots(m.input, 'data-unload')}
          ${m.preview && m.preview.length ? `<div class="clabel" style="margin-top:10px">${esc(t('rec.preview'))}</div><div class="cyield">${m.preview.map(p => `<b>~${p.amount}</b> ${esc(p.label)}`).join('<br>')}</div>` : ''}</div></div>
        <div class="cbox"><div class="cbox__head"><b>${esc(t('rec.output'))}</b>${(m.output || []).length ? `<button class="cbtn cbtn--sm" data-mtake="*">${esc(t('ui.take_all'))}</button>` : ''}</div>
          <div class="cbox__body">${machineSlots(m.output, 'data-mtake')}</div></div>
      </div>`;
  }

  async function machine(action, body) {
    if (S.busy) return; S.busy = true;
    const r = await call('bs_recycler', action, Object.assign({ id: S.ctx.id }, body || {}));
    S.busy = false;
    if (r && r.ok === false && r.error) toast(r.error);
    load();
  }

  function toast(msg) {
    const el = document.createElement('div'); el.className = 'craft__chip craft__chip--warn';
    el.style.cssText = 'position:fixed;left:50%;bottom:8vh;transform:translateX(-50%);background:rgba(10,10,9,.9);z-index:99;font-size:13px;padding:10px 16px';
    el.textContent = msg; document.body.appendChild(el); setTimeout(() => el.remove(), 2600);
  }

  // ---------------------------------------------------------------- input
  root.addEventListener('click', async (e) => {
    const el = e.target.closest('[data-ccat],[data-rec],[data-qty],#cGo,[data-cancel],[data-take],[data-dis],[data-farm],[data-load],[data-unload],[data-mtake],[data-mact]');
    if (!el) return;
    if (el.dataset.ccat) { S.cat = el.dataset.ccat; return render(); }
    if (el.dataset.rec) { S.sel = el.dataset.rec; S.qty = 1; return render(); }
    if (el.dataset.qty) { const i = document.getElementById('cQty'); const v = Math.max(1, Math.min(Number(i.max), Number(i.value) + Number(el.dataset.qty))); i.value = v; S.qty = v; return; }
    if (el.id === 'cGo') {
      if (S.busy) return; S.busy = true; el.disabled = true;
      const r = await call('bs_crafting', 'queue', { id: S.sel, count: Number(document.getElementById('cQty').value) || 1 });
      S.busy = false;
      if (r && r.ok === false && r.error) toast(r.error);
      return load();
    }
    if (el.dataset.cancel) { const r = await call('bs_crafting', 'cancel', { id: el.dataset.cancel }); if (r && r.ok === false && r.error) toast(r.error); return load(); }
    if (el.dataset.take) { await call('bs_crafting', 'take', { item: el.dataset.take }); return load(); }
    if (el.dataset.dis) { return call('bs_crafting', 'dismantle', { item: el.dataset.dis }); }
    if (el.dataset.farm) { const r = await call('bs_crafting', 'farm', { action: el.dataset.farm, arg: el.dataset.arg }); if (r && r.ok === false && r.error) toast(r.error); return load(); }
    if (el.dataset.load) return machine('load', { item: el.dataset.load, all: e.shiftKey });
    if (el.dataset.unload) return machine('unload', { item: el.dataset.unload, all: e.shiftKey });
    if (el.dataset.mtake) return machine('takeOutput', { item: el.dataset.mtake });
    if (el.dataset.mact) return machine(el.dataset.mact);
  });
  root.addEventListener('input', (e) => {
    if (e.target.id === 'cSearch') { S.q = e.target.value; render(); }
    if (e.target.id === 'cQty') S.qty = Number(e.target.value) || 1;
  });
})();

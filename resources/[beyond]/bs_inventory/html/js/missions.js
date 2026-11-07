// missions.js - the MISSION LOG tab. Data comes from any resource registered with RegisterMissionSource (server/sv_missions.lua).
(() => {
  'use strict';
  const pane = document.querySelector('.pane[data-pane="missions"]');
  const root = document.getElementById('missionsRoot');
  const tab = document.querySelector('.tab[data-tab="missions"]');
  if (!pane || !root || !tab) return;
  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'bs_inventory';
  const call = (name, body) => fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
  }).then(r => r.json()).catch(() => null);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  let dict = {};
  const t = (k) => (dict[k] != null ? dict[k] : k);

  // Saved player choices (localStorage may be unavailable).
  const LS = 'bs_mlog_prefs';
  const defaults = { group: 'all', status: '', sort: 'default', q: '', dense: 'comfy', pins: {}, closed: {} };
  let P = Object.assign({}, defaults);
  try { const s = JSON.parse(localStorage.getItem(LS) || '{}'); if (s && typeof s === 'object') P = Object.assign(P, s); } catch (e) { /* ignore */ }
  if (!P.pins || typeof P.pins !== 'object') P.pins = {};
  if (!P.closed || typeof P.closed !== 'object') P.closed = {};
  const save = () => { try { localStorage.setItem(LS, JSON.stringify(P)); } catch (e) { /* ignore */ } };

  let list = [];
  const key = (m) => m.source + ':' + m.id;
  const base = (g) => String(g || '').split(/\s+[-–—]\s+/)[0];
  const state = (m) => (m.claimed ? 'claimed' : (m.complete ? 'complete' : 'active'));
  const isReady = (m) => !m.claimed && m.complete && !m.noClaim;
  // Progress 0..1 and a label, from count/target when present, else steps.
  function prog(m) {
    const tg = Number(m.target), c = Number(m.count);
    if (tg > 0 && !isNaN(c)) return { v: Math.min(1, c / tg), a: Math.min(c, tg), b: tg };
    const st = m.steps || [];
    if (st.length) { const d = st.filter(s => s.done).length; return { v: d / st.length, a: d, b: st.length }; }
    return { v: (m.complete || m.claimed) ? 1 : 0, a: (m.complete || m.claimed) ? 1 : 0, b: 1 };
  }
  const rewardSum = (m) => (m.reward || []).reduce((n, r) => n + (Number(r.amount) || 1), 0);
  const icon = (it) => (typeof BSIcons !== 'undefined' ? BSIcons.get(it) : '');

  // Static shell, built once so the search box keeps focus.
  root.innerHTML = '<div class="mlog__bar"></div><div class="mlog__list"></div>';
  const bar = root.querySelector('.mlog__bar');
  const body = root.querySelector('.mlog__list');
  root.classList.add('mlog');

  function chip(attr, val, label, on, n) {
    return `<button type="button" class="mlog__chip${on ? ' on' : ''}" data-${attr}="${esc(val)}">${esc(label)}${n != null ? `<i>${n}</i>` : ''}</button>`;
  }

  function drawBar() {
    const groups = [];
    list.forEach(m => { const g = base(m.group); if (g && groups.indexOf(g) < 0) groups.push(g); });
    if (P.group !== 'all' && groups.indexOf(P.group) < 0) P.group = 'all';
    const act = list.filter(m => !m.claimed && !isReady(m)).length;
    const rdy = list.filter(isReady).length;
    const done = list.filter(m => m.claimed).length;
    const sum = `<div class="mlog__sum"><span class="s-act"><b>${act}</b>${esc(t('mlog.sum.active'))}</span><span class="s-rdy"><b>${rdy}</b>${esc(t('mlog.sum.ready'))}</span><span class="s-done"><b>${done}</b>${esc(t('mlog.sum.done'))}</span></div>`;
    const gch = chip('g', 'all', t('mlog.all'), P.group === 'all') + groups.map(g => chip('g', g, g, P.group === g)).join('');
    const sch = [['active', 'mlog.st.active'], ['ready', 'mlog.st.ready'], ['done', 'mlog.st.done']].map(s => chip('s', s[0], t(s[1]), P.status === s[0])).join('');
    const opts = [['default', 'mlog.sort.default'], ['near', 'mlog.sort.near'], ['reward', 'mlog.sort.reward']].map(o => `<option value="${o[0]}"${P.sort === o[0] ? ' selected' : ''}>${esc(t(o[1]))}</option>`).join('');
    bar.innerHTML = `${sum}<div class="mlog__row">${gch}</div><div class="mlog__row">${sch}<select class="mlog__sel" aria-label="${esc(t('mlog.sort'))}">${opts}</select>` +
      `<input class="mlog__q" type="text" maxlength="40" placeholder="${esc(t('mlog.search'))}" value="${esc(P.q)}" />` +
      `<button type="button" class="mlog__chip mlog__dens" data-d="1">${esc(t(P.dense === 'compact' ? 'mlog.dens.compact' : 'mlog.dens.comfy'))}</button></div>`;
  }

  function cardHtml(m, i) {
    const st = state(m), pr = prog(m), k = key(m), pinned = !!P.pins[k];
    const steps = (m.steps || []).map(s => `<li class="${s.done ? 'ok' : ''}"><i class="mlog__box">${s.done ? '&#10007;' : ''}</i>${esc(s.label)}</li>`).join('');
    const rw = (m.reward || []).length ? `<div class="mlog__rw"><em>${esc(t('mlog.reward'))}</em><div>${m.reward.map(r =>
      `<span class="mlog__item" title="${esc(r.label || r.item)}">${icon(r.item)}<small>${esc(r.label || r.item)}</small>${r.amount > 1 ? `<b class="mlog__x">x${esc(r.amount)}</b>` : ''}</span>`).join('')}</div></div>` : '';
    const note = m.hint ? `<p class="mlog__hint">${esc(m.hint)}</p>` : '';
    const btn = isReady(m) ? `<button class="mlog__btn" data-i="${i}">${esc(t('mlog.finish'))}</button><p class="mlog__hint">${esc(t('mlog.anywhere'))}</p>` : '';
    const bartxt = `<div class="mlog__prog" title="${pr.a}/${pr.b}"><span style="width:${Math.round(pr.v * 100)}%"></span><em>${pr.a}/${pr.b}</em></div>`;
    return `<div class="mlog__card is-${st}${isReady(m) ? ' is-ready' : ''}${pinned ? ' is-pinned' : ''}"><div class="mlog__clip"></div>` +
      `<button type="button" class="mlog__pin${pinned ? ' on' : ''}" data-k="${esc(k)}" title="${esc(t(pinned ? 'mlog.unpin' : 'mlog.pin'))}" aria-label="${esc(t(pinned ? 'mlog.unpin' : 'mlog.pin'))}">${pinned ? '&#9733;' : '&#9734;'}</button>` +
      `<div class="mlog__head"><b>${esc(m.title)}</b></div><span class="mlog__stamp">${esc(t('mlog.' + st))}</span>${bartxt}<ul>${steps}</ul>${rw}${btn}${note}</div>`;
  }

  function visible() {
    const q = P.q.trim().toLowerCase();
    let v = list.map((m, i) => ({ m, i })).filter(({ m }) => {
      if (P.group !== 'all' && base(m.group) !== P.group) return false;
      if (P.status === 'active' && (m.claimed || isReady(m))) return false;
      if (P.status === 'ready' && !isReady(m)) return false;
      if (P.status === 'done' && !m.claimed) return false;
      if (q) {
        const hay = [m.title, m.hint, m.group].concat((m.steps || []).map(s => s.label), (m.reward || []).map(r => r.label || r.item)).join(' ').toLowerCase();
        if (hay.indexOf(q) < 0) return false;
      }
      return true;
    });
    // Stable sort; list order is the server order (group, unclaimed, title).
    const cmp = {
      near: (a, b) => (a.m.claimed ? 1 : 0) - (b.m.claimed ? 1 : 0) || prog(b.m).v - prog(a.m).v,
      reward: (a, b) => rewardSum(b.m) - rewardSum(a.m),
    }[P.sort];
    const pin = (x) => (P.pins[key(x.m)] ? 0 : 1);
    v = v.map((x, n) => Object.assign(x, { n }));
    v.sort((a, b) => pin(a) - pin(b) || (cmp ? cmp(a, b) : 0) || a.n - b.n);
    return v;
  }

  function drawList() {
    if (!list.length) { body.innerHTML = `<div class="mlog__empty">${esc(t('mlog.empty'))}</div>`; return; }
    const v = visible();
    if (!v.length) { body.innerHTML = `<div class="mlog__empty">${esc(t('mlog.nomatch'))}</div>`; return; }
    let html = '', cur = null;
    const flat = P.sort !== 'default';
    const pinned = v.filter(x => P.pins[key(x.m)]);
    const rest = flat ? v.filter(x => !P.pins[key(x.m)]) : v;
    const section = (name, items, isPin) => {
      const ck = (isPin ? '*pin' : name), shut = !!P.closed[ck];
      return `<div class="mlog__group${shut ? ' shut' : ''}" data-c="${esc(ck)}"><span class="mlog__caret">${shut ? '&#9656;' : '&#9662;'}</span>${isPin ? '&#9733; ' : ''}${esc(isPin ? t('mlog.pinned') : name)}<i>${items.length}</i></div>` +
        (shut ? '' : `<div class="mlog__cards">${items.map(x => cardHtml(x.m, x.i)).join('')}</div>`);
    };
    if (pinned.length) html += section('', pinned, true);
    if (flat) {
      html += `<div class="mlog__cards">${rest.map(x => cardHtml(x.m, x.i)).join('')}</div>`;
    } else {
      const order = [], by = {};
      rest.forEach(x => { const g = x.m.group || ''; if (!by[g]) { by[g] = []; order.push(g); } by[g].push(x); });
      order.forEach(g => { html += section(g, by[g], false); });
    }
    body.innerHTML = html;
  }

  function draw() { drawBar(); drawList(); body.classList.toggle('dense', P.dense === 'compact'); }

  bar.addEventListener('click', (e) => {
    const c = e.target.closest('button'); if (!c) return;
    if (c.dataset.g != null) P.group = c.dataset.g;
    else if (c.dataset.s != null) P.status = (P.status === c.dataset.s) ? '' : c.dataset.s;
    else if (c.dataset.d) P.dense = P.dense === 'compact' ? 'comfy' : 'compact';
    else return;
    save(); draw();
  });
  bar.addEventListener('change', (e) => { if (e.target.matches('select')) { P.sort = e.target.value; save(); draw(); } });
  bar.addEventListener('input', (e) => { if (e.target.matches('input')) { P.q = e.target.value; save(); drawList(); } });
  body.addEventListener('click', async (e) => {
    const pin = e.target.closest('.mlog__pin');
    if (pin) { const k = pin.dataset.k; if (P.pins[k]) delete P.pins[k]; else P.pins[k] = 1; save(); drawList(); return; }
    const g = e.target.closest('.mlog__group');
    if (g) { const c = g.dataset.c; if (P.closed[c]) delete P.closed[c]; else P.closed[c] = 1; save(); drawList(); return; }
    const b = e.target.closest('.mlog__btn');
    if (b) {
      const m = list[+b.dataset.i];
      if (!m) return;
      b.disabled = true;
      await call('missionClaim', { source: m.source, id: m.id });
      load();
    }
  });

  async function load() {
    const r = await call('missionsList');
    if (!r) return;
    dict = r.dict || dict;
    tab.textContent = t('ui.missions');
    list = Array.isArray(r.list) ? r.list : [];
    draw();
  }

  tab.addEventListener('click', load);
  window.addEventListener('message', (e) => { if (e.data && e.data.action === 'open') load(); });
})();

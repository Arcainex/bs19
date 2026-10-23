// bs_pause page. Lua sends everything on open; settings go back through bs_inventory's handlers.
(() => {
  'use strict';
  const RES = 'bs_pause';
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
    .then((r) => r.json()).catch(() => ({}));

  const S = { strings: {}, tabs: [], settings: {}, presets: {}, keybinds: [], info: {}, server: null, view: 'resume', languages: [], native: {}, devlogLoaded: false };
  const t = (k, d) => S.strings[k] || d || k;

  const ON_OFF = [[true, 'o.on'], [false, 'o.off']];
  const SHOW_HIDE = [[true, 'o.show'], [false, 'o.hide']];
  const RANGE = (k, min, max, step) => ({ k, type: 'range', min, max, step });
  // Groups: Display/HUD, Audio, Gameplay, Chat, Accessibility; Controls is built from the key list below.
  const SETTINGS = [
    { g: 'st.g_display', items: [
      { k: 'hudMode', type: 'seg', opts: [['full', 'o.full'], ['minimal', 'o.minimal']] },
      { k: 'hudAnchor', type: 'seg', opts: [['bottom-left', 'o.left'], ['bottom-right', 'o.right']] },
      RANGE('hudOpacity', 0, 1, 0.05),
      { k: 'hudStyle', type: 'choice', list: 'styles', pre: 'st.hs_', def: 'classic' },
      { k: 'menuPalette', type: 'choice', list: 'palettes', pre: 'st.pal_', def: 'default' },
      { k: 'xpPosition', type: 'seg', opts: [['top', 'o.top'], ['bottom', 'o.bottom']] },
      RANGE('xpOpacity', 0, 1, 0.05),
      { k: 'hideWhenFull', type: 'seg', opts: ON_OFF },
      { k: 'hotbarAlways', type: 'seg', opts: [[true, 'o.always'], [false, 'o.hold_alt']] },
      { k: 'carHud', type: 'seg', opts: ON_OFF },
      { k: 'carHudUnit', type: 'seg', opts: [['kmh', 'km/h'], ['mph', 'mph']] },
      { k: 'carHudSide', type: 'seg', opts: [['auto', 'o.auto'], ['L', 'o.left'], ['R', 'o.right']] },
      RANGE('carHudScale', 0.6, 2.4, 0.05),
      RANGE('carHudOpacity', 10, 100, 5),
    ] },
    { g: 'st.g_audio', items: [
      RANGE('zombieVoiceVolume', 0, 1, 0.05),
      RANGE('radioVolume', 0, 100, 5),
    ] },
    { g: 'st.g_gameplay', items: [
      { k: 'dodge', type: 'seg', opts: ON_OFF },
      { k: 'missionTracker', type: 'seg', opts: SHOW_HIDE },
      { k: 'safeZoneMarkers', type: 'seg', opts: SHOW_HIDE },
      { k: 'damageNumbers', type: 'seg', opts: SHOW_HIDE },
    ] },
    { g: 'st.g_camera', items: [
      { k: 'camSmooth', type: 'seg', opts: ON_OFF },
      RANGE('camSmoothAmount', 0, 100, 5),
      { k: 'camSmoothAim', type: 'seg', opts: [['reduced', 'o.reduced'], ['off', 'o.off']] },
      { k: 'camSway', type: 'seg', opts: ON_OFF },
      { k: 'camFov', type: 'seg', opts: ON_OFF },
      { k: 'camChase', type: 'seg', opts: ON_OFF },
    ] },
    { g: 'st.g_chat', items: [
      { k: 'chatMode', type: 'seg', opts: [['fade', 'o.fade'], ['always', 'o.always'], ['hidden', 'o.hidden']] },
      { k: 'chatBackdrop', type: 'seg', opts: ON_OFF },
      RANGE('chatBgOpacity', 0, 100, 5),
    ] },
    { g: 'st.g_access', items: [
      { k: 'language', type: 'lang' },
      { k: 'uiScale', type: 'seg', opts: [['0', 'o.auto'], ['0.8', '80%'], ['0.9', '90%'], ['1', '100%'], ['1.1', '110%'], ['1.2', '120%']] },
    ] },
  ];

  const BASE = [
    { id: 'resume', icon: '&#9654;', label: 'p.resume' },
    { id: 'map', icon: '&#9873;', label: 'p.map' },
    { id: 'settings', icon: '&#9881;', label: 'p.settings' },
    { id: 'gfx', icon: '&#9681;', label: 'p.graphics' },
    { id: 'server', icon: '&#9776;', label: 'p.server' },
    { id: 'devlog', icon: '&#9998;', label: 'p.devlog' },
  ];

  // Tab icons are glyphs only. Named icons map here; anything unknown gets a generic diamond, never the raw name as text.
  const ICONS = { ticket: '&#127915;', pass: '&#127915;', star: '&#9733;', trophy: '&#127942;', gift: '&#127873;', shop: '&#128722;', cart: '&#128722;',
    book: '&#128214;', user: '&#128100;', users: '&#128101;', group: '&#128101;', map: '&#9873;', gear: '&#9881;', cog: '&#9881;', info: '&#8505;',
    bell: '&#128276;', chart: '&#128202;', crown: '&#9819;', flag: '&#9873;', heart: '&#9829;', skull: '&#9760;', shield: '&#128737;', list: '&#9776;' };
  const GENERIC = '&#9670;';
  function iconHtml(icon) {
    const s = String(icon || '').trim();
    if (/^&#x?[0-9a-f]+;$/i.test(s)) return s;
    if (ICONS[s.toLowerCase()]) return ICONS[s.toLowerCase()];
    if (s && [...s].length === 1 && s.codePointAt(0) > 255) return esc(s);
    return GENERIC;
  }

  function nav() {
    const base = BASE.filter((b) => b.id !== 'devlog' || S.info.devlog);
    const ext = S.tabs.map((x) => `<button data-tab="${esc(x.id)}"><span class="ic">${iconHtml(x.icon)}</span>${esc(x.label)}${x.badge ? `<span class="badge">${esc(x.badge)}</span>` : ''}</button>`).join('');
    $('nav').innerHTML = base.map((b) => `<button data-v="${b.id}" class="${S.view === b.id ? 'on' : ''}"><span class="ic">${b.icon}</span>${esc(t(b.label))}</button>`).join('')
      + (ext ? '<hr>' + ext : '')
      + `<hr><button data-v="gta"><span class="ic">&#9638;</span>${esc(t('p.gta'))}</button><button data-v="quit" class="quit"><span class="ic">&#10005;</span>${esc(t('p.quit'))}</button>`;
    document.querySelectorAll('[data-t]').forEach((el) => { el.textContent = t(el.dataset.t, el.textContent); });
  }

  const locked = (d) => !!d.vip && S.settings.hudVip !== true;
  function activeChoice(it, list) {
    const d = list.filter((x) => x.id === S.settings[it.k])[0];
    return d && !locked(d) ? d.id : it.def;
  }
  const optLabel = (l) => (S.strings[l] ? S.strings[l] : l);
  function control(it) {
    const v = S.settings[it.k];
    if (v === undefined && it.type !== 'lang') return null;
    if (it.type === 'lang') {
      return `<div class="seg" data-set="language">${S.languages.map((l) => `<button data-val="${l}" class="${S.settings.language === l ? 'on' : ''}">${esc(S.native[l] || l)}</button>`).join('')}</div>`;
    }
    if (it.type === 'choice') {
      const list = (S.choices && S.choices[it.list]) || [];
      const cur = activeChoice(it, list);
      return `<div class="seg" data-set="${it.k}">${list.map((d) => `<button data-val="${esc(d.id)}" class="${cur === d.id ? 'on' : ''}${locked(d) ? ' lock' : ''}">${d.sw ? `<span class="swatch">${d.sw.map((c) => `<i style="background:${esc(c)}"></i>`).join('')}</span>` : ''}${esc(String(t(it.pre + d.id, d.label)).toLocaleUpperCase())}</button>`).join('')}</div>`;
    }
    if (it.type === 'seg') {
      return `<div class="seg" data-set="${it.k}">${it.opts.map(([val, l]) => `<button data-val="${esc(String(val))}" class="${String(v) === String(val) ? 'on' : ''}">${esc(optLabel(l))}</button>`).join('')}</div>`;
    }
    return `<div><input type="range" data-set="${it.k}" min="${it.min}" max="${it.max}" step="${it.step}" value="${Number(v)}"><span class="val">${Number(v)}</span></div>`;
  }

  function viewSettings() {
    const groups = SETTINGS.map((g) => {
      const rows = g.items.map((it) => {
        const c = control(it);
        if (!c) return '';
        const d = S.strings['st.d_' + it.k];
        return `<div class="set" data-q="${esc((t('set.' + it.k) + ' ' + (d || '')).toLowerCase())}"><label>${esc(t('set.' + it.k))}${d ? `<small>${esc(d)}</small>` : ''}</label>${c}</div>`;
      }).join('');
      return rows ? `<div class="card" data-grp>
        <h3>${esc(t(g.g))}</h3>${rows}</div>` : '';
    }).join('');
    const keys = S.keybinds.map((k) => `<div><span>${esc(k.label)}</span><kbd>${esc(k.key)}</kbd></div>`).join('');
    return `<h1>${esc(t('p.settings'))}</h1><div class="sub">${esc(t('p.settings_sub'))}</div>
      <input type="search" id="setSearch" class="search" placeholder="${esc(t('st.search'))}" value="${esc(S.q || '')}" autocomplete="off">
      ${groups}
      <div class="card" data-grp data-keep><h3>${esc(t('st.g_controls'))}</h3>
        <div class="keys">${keys}</div><div class="note">${esc(t('p.rebind_note'))}</div>
        <div class="set" data-q="${esc(t('p.troubleshoot').toLowerCase())}"><label>${esc(t('p.troubleshoot'))}</label><div><button class="btn" data-fix="refreshui">${esc(t('p.refresh_ui'))}</button> <button class="btn" data-fix="unblur">${esc(t('p.unblur'))}</button></div></div></div>
      <div class="note hidden" id="setNone">${esc(t('st.noresults'))}</div>`;
  }
  // Hides rows (and groups with no visible row) that miss the query. Pure DOM, so typing keeps focus.
  function applySearch() {
    const q = (S.q || '').trim().toLowerCase();
    let shown = 0;
    document.querySelectorAll('#main [data-grp]').forEach((g) => {
      let any = 0;
      g.querySelectorAll('.set').forEach((row) => {
        const hit = !q || (row.dataset.q || '').indexOf(q) !== -1;
        row.classList.toggle('hidden', !hit);
        if (hit) any++;
      });
      const keep = g.hasAttribute('data-keep') && !q;
      g.classList.toggle('hidden', any === 0 && !keep);
      if (any || keep) shown++;
    });
    const none = $('setNone'); if (none) none.classList.toggle('hidden', shown > 0);
  }
  function viewGfx() {
    const p = S.presets;
    const seg = (key, opts) => `<div class="seg" data-preset="${key}">${opts.map(([v, l]) => `<button data-val="${v}" class="${String(p[key]) === String(v) ? 'on' : ''}">${esc(t(l))}</button>`).join('')}</div>`;
    const zv = S.settings.zombieVoiceVolume;
    return `<h1>${esc(t('p.graphics'))}</h1><div class="sub">${esc(t('g.sub'))}</div>
      <div class="card"><h3>${esc(t('g.title'))}</h3>
        <div class="set"><label>${esc(t('g.preset'))}</label>${seg('gfx', [['performance', 'g.performance'], ['balanced', 'g.balanced'], ['quality', 'g.quality']])}</div>
        <div class="set"><label>${esc(t('g.distant'))}</label>${seg('distantLights', [[true, 'o.on'], [false, 'o.off']])}</div>
        <div class="note">${esc(t('g.note'))}</div></div>
      <div class="card"><h3>${esc(t('a.title'))}</h3>
        <div class="set"><label>${esc(t('a.preset'))}</label>${seg('audio', [['default', 'a.default'], ['immersive', 'a.immersive']])}</div>
        ${zv !== undefined ? `<div class="set"><label>${esc(t('set.zombieVoiceVolume'))}</label><div><input type="range" data-set="zombieVoiceVolume" min="0" max="1" step="0.05" value="${Number(zv)}"><span class="val">${Number(zv)}</span></div></div>` : ''}
      </div>`;
  }

  function fmtUp(s) { s = Number(s) || 0; const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return `${h}h ${m}m`; }
  function viewServer() {
    const sv = S.server || {};
    return `<h1>${esc(sv.name || t('p.server'))}</h1><div class="sub">${esc(S.info.website || '')}</div>
      <div class="stats"><div class="stat"><b>${sv.online != null ? `${sv.online} / ${sv.max}` : '...'}</b><span>${esc(t('p.online'))}</span></div>
        <div class="stat"><b>${sv.uptime != null ? fmtUp(sv.uptime) : '...'}</b><span>${esc(t('p.uptime'))}</span></div>
        <div class="stat"><b style="font-size:16px">${esc(S.info.discord || '-')}</b><span>${esc(t('p.discord'))}</span></div></div>
      <div class="card"><h3>${esc(t('p.rules'))}</h3><ol class="rules">${(S.info.rules || []).map((r) => `<li>${esc(r)}</li>`).join('')}</ol></div>
      <div class="card news"><h3>${esc(t('p.news'))}</h3>${(S.info.news || []).map((n) => `<div class="d">${esc(n.date)}</div><b>${esc(n.title)}</b><p>${esc(n.text)}</p>`).join('')}</div>`;
  }

  // The devlog page is only requested when this tab is opened, and dropped again on close.
  function viewDevlog() {
    return `<h1>${esc(t('p.devlog'))}</h1><div class="frame"><div class="msg" id="dlMsg">${esc(t('p.devlog_loading'))}</div><iframe id="dl" sandbox="allow-scripts allow-same-origin" referrerpolicy="no-referrer"></iframe></div>`;
  }
  function loadDevlog() {
    const f = $('dl'); if (!f || !S.info.devlog) return;
    let done = false;
    f.addEventListener('load', () => { done = true; const m = $('dlMsg'); if (m) m.remove(); });
    f.src = S.info.devlog;
    setTimeout(() => { if (!done && $('dlMsg')) $('dlMsg').textContent = t('p.devlog_fail'); }, 10000);
  }

  function render() {
    nav();
    const m = $('main');
    if (S.view === 'settings') m.innerHTML = viewSettings();
    else if (S.view === 'gfx') m.innerHTML = viewGfx();
    else if (S.view === 'server') m.innerHTML = viewServer();
    else if (S.view === 'devlog') { m.innerHTML = viewDevlog(); loadDevlog(); }
    else m.innerHTML = `<div class="resume-art">${esc(t('p.hint_esc'))}</div>`;
  }

  function confirmBox(text, yes) {
    $('confirmText').textContent = text; $('cYes').textContent = t('p.yes'); $('cNo').textContent = t('p.no');
    $('confirm').classList.remove('hidden');
    $('cYes').onclick = () => { $('confirm').classList.add('hidden'); yes(); };
    $('cNo').onclick = () => $('confirm').classList.add('hidden');
  }

  function close() { post('close'); }

  document.addEventListener('click', async (e) => {
    const v = e.target.closest('[data-v]'), tab = e.target.closest('[data-tab]');
    const segBtn = e.target.closest('[data-set] button'), pre = e.target.closest('[data-preset] button'), fix = e.target.closest('[data-fix]');
    if (v) {
      const id = v.dataset.v;
      if (id === 'resume') return close();
      if (id === 'map') return post('map');
      if (id === 'gta') return post('gta');
      if (id === 'quit') return confirmBox(t('p.quit_confirm'), () => post('quit'));
      S.view = id; return render();
    }
    if (tab) return post('tab', { id: tab.dataset.tab });
    if (segBtn) {
      if (segBtn.classList.contains('lock')) return;
      const key = segBtn.parentElement.dataset.set; let val = segBtn.dataset.val;
      if (key === 'menuPalette' && window.BSPalette) {
        const d = ((S.choices && S.choices.palettes) || []).filter((x) => x.id === val)[0];
        BSPalette.apply((d && d.vars) || null, val);
      }
      if (val === 'true') val = true; else if (val === 'false') val = false;
      S.settings[key] = val; render();
      const r = await post('settings', { patch: { [key]: val } });
      if (r && r.settings) { S.settings = r.settings; render(); }
      return;
    }
    if (pre) {
      const key = pre.parentElement.dataset.preset; let val = pre.dataset.val;
      if (val === 'true') val = true; else if (val === 'false') val = false;
      S.presets[key] = val; render();
      const r = await post('presets', { patch: { [key]: val } });
      if (r && r.presets) { S.presets = r.presets; render(); }
      return;
    }
    if (fix) return post('fix', { name: fix.dataset.fix });
  });

  document.addEventListener('input', (e) => {
    if (e.target.id === 'setSearch') { S.q = e.target.value; applySearch(); return; }
    if (e.target.matches('input[type=range][data-set]')) { const s = e.target.nextElementSibling; if (s) s.textContent = e.target.value; if (e.target.dataset.set === 'chatBgOpacity') post('settings', { patch: { chatBgOpacity: Number(e.target.value) } }); }
  });
  document.addEventListener('change', (e) => {
    if (e.target.matches('input[type=range][data-set]')) {
      const key = e.target.dataset.set, val = Number(e.target.value);
      S.settings[key] = val; post('settings', { patch: { [key]: val } });
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('pause').classList.contains('hidden')) return;
    if (!$('confirm').classList.contains('hidden')) { $('confirm').classList.add('hidden'); return; }
    close();
  });

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
      Object.assign(S, { strings: d.strings || {}, tabs: d.tabs || [], settings: d.settings || {}, presets: d.presets || {}, keybinds: d.keybinds || [],
        info: d.info || {}, languages: d.languages || [], native: d.native || {}, choices: d.choices || null, q: '', server: null, view: 'resume' });
      $('confirm').classList.add('hidden');
      $('pause').classList.remove('hidden'); render();
    } else if (d.action === 'close') {
      $('pause').classList.add('hidden'); $('main').innerHTML = '';
    } else if (d.action === 'serverInfo') {
      S.server = d.info; if (S.view === 'server') render();
    } else if (d.action === 'tabs') {
      S.tabs = d.tabs || []; nav();
    } else if (d.action === 'strings') {
      S.strings = d.strings || S.strings; S.tabs = d.tabs || S.tabs; S.keybinds = d.keybinds || S.keybinds; S.info = d.info || S.info; render();
    }
  });
})();

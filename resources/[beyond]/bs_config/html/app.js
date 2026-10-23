(() => {
  'use strict';
  const RES = (window.GetParentResourceName ? GetParentResourceName() : 'bs_config');
  const $ = (id) => document.getElementById(id);
  const RESET = '__reset__';
  const S = { schema: [], byId: {}, defaults: {}, cats: [], profiles: [], active: 'Default', isOwner: false,
              view: 'Default', overrides: {}, pending: {}, cat: 'zombies', query: '', builtin: true,
              mode: (() => { try { return localStorage.getItem('bsConfigMode') || 'simple'; } catch (e) { return 'simple'; } })() };

  const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) })
    .then(r => r.json()).catch(() => ({ ok: false, error: T('cfg.err_nui', 'NUI error') }));
  const rpc = (action, a, b, c) => post('rpc', { action, a, b, c });

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (v) => typeof v === 'number' ? (Number.isInteger(v) ? String(v) : String(+v.toFixed(4))) : (typeof v === 'boolean' ? (v ? T('cfg.on', 'on') : T('cfg.off', 'off')) : String(v));

  // i18n: T(key, fallback, vars); TX(english) looks up a label by its text
  const T = (k, fb, v) => { let s = (window.BSI18n ? BSI18n.t(k, { fallback: fb }) : fb); if (v) s = s.replace(/\{(\w+)\}/g, (m, n) => v[n] !== undefined ? v[n] : m); return s; };
  const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  const TX = (s) => s ? T('cfg.t.' + slug(s), s) : s;

  let toastT;
  function toast(msg, err) { const t = $('toast'); t.textContent = msg; t.className = 'toast show' + (err ? ' err' : ''); clearTimeout(toastT); toastT = setTimeout(() => t.className = 'toast', 2600); }

  // Values
  const fileDef = (id) => S.defaults[id] !== undefined ? S.defaults[id] : (S.byId[id] || {}).fb;
  const saved = (id) => S.overrides[id] !== undefined ? S.overrides[id] : fileDef(id);
  const eff = (id) => { const p = S.pending[id]; if (p === RESET) return fileDef(id); return p !== undefined ? p : saved(id); };
  const pendCount = () => Object.keys(S.pending).length;
  const isBuiltin = (n) => !!(S.profiles.find(p => p.name === n) || {}).builtin;

  function setPending(id, v) {
    const e = S.byId[id];
    if (e.type === 'int') v = Math.round(v);
    if (e.type === 'int' || e.type === 'number') { v = Number(v); if (isNaN(v)) return; v = Math.min(e.max, Math.max(e.min, v)); }
    if (v === saved(id)) delete S.pending[id];
    else if (v === fileDef(id) && S.overrides[id] !== undefined) S.pending[id] = RESET;
    else S.pending[id] = v;
    if (S.mode === 'simple' && !S.query && !S.cat.startsWith('_')) { const sc = $('main').scrollTop; renderSimple(); $('main').scrollTop = sc; updateBar(); renderRail(); return; }
    updateRow(id); updateBar(); renderRail();
  }

  // Rendering
  function renderProfiles() {
    const sel = $('profile');
    sel.innerHTML = S.profiles.map(p => `<option value="${esc(p.name)}"${p.name === S.view ? ' selected' : ''}>${p.name === S.active ? '● ' : ''}${esc(p.name)}${p.builtin ? ' (' + T('cfg.preset', 'preset') + ')' : ''}</option>`).join('');
    $('activeBadge').classList.toggle('hidden', S.view !== S.active);
    $('btnActivate').disabled = S.view === S.active;
    $('btnDelete').classList.toggle('hidden', !S.isOwner);
    S.builtin = isBuiltin(S.view);
  }

  function visible() {
    const q = S.query.trim().toLowerCase();
    if (q) return S.schema.filter(e => (e.label + ' ' + TX(e.label) + ' ' + e.path + ' ' + e.desc + ' ' + e.res).toLowerCase().includes(q));
    if (S.cat === '_modified') return S.schema.filter(e => S.overrides[e.id] !== undefined || S.pending[e.id] !== undefined);
    return S.schema.filter(e => e.cat === S.cat);
  }

  // Simple mode (see simple.js)
  const SIMPLE = () => (window.BSSimple || []).map(sec => ({ section: sec.section,
    items: sec.items.filter(it => it.kind === 'single' ? !!S.byId[it.id]
      : (it.ids ? it.ids.some(id => S.byId[id]) : it.options.some(o => Object.keys(o.set || {}).some(id => S.byId[id])))) }))
    .filter(sec => sec.items.length);
  function clampFor(id, v) {
    const e = S.byId[id]; if (!e) return v;
    if (e.type === 'int') v = Math.round(v);
    if (e.type === 'int' || e.type === 'number') v = Math.min(e.max, Math.max(e.min, v));
    if (e.type === 'number') v = +v.toFixed(3);
    return v;
  }
  function optionTargets(it, o) {
    const out = {};
    if (o.set) Object.entries(o.set).forEach(([id, v]) => { if (S.byId[id]) out[id] = clampFor(id, v); });
    else (it.ids || []).forEach(id => { if (S.byId[id]) out[id] = clampFor(id, Number(fileDef(id)) * o.mul); });
    return out;
  }
  const near = (a, b) => typeof a === 'number' && typeof b === 'number' ? Math.abs(a - b) <= Math.max(0.001, Math.abs(b) * 0.01) : a === b;
  function choiceIndex(it) {
    for (let i = 0; i < it.options.length; i++) {
      const t = optionTargets(it, it.options[i]);
      if (Object.keys(t).length && Object.entries(t).every(([id, v]) => near(eff(id), v))) return i;
    }
    return -1;
  }
  function itemDirty(it) {
    const ids = it.kind === 'single' ? [it.id] : (it.ids || [...new Set(it.options.flatMap(o => Object.keys(o.set || {})))]);
    return ids.some(id => S.pending[id] !== undefined);
  }
  function renderSimple() {
    const m = $('main');
    let html = `<h2 class="cat">${esc(T('cfg.quick', 'Quick setup'))}</h2><p class="shint">${T('cfg.quick_hint', 'The settings most servers change, in plain words. Pick, then press Apply at the bottom. Need something else? Switch to <b>Advanced</b> at the top.')}</p>`;
    SIMPLE().forEach((sec, si) => {
      html += `<div class="card" id="sec_${si}"><h4>${esc(TX(sec.section))}</h4>`;
      sec.items.forEach((it, ii) => {
        const dirty = itemDirty(it) ? ' dirty' : '';
        if (it.kind === 'single') {
          const e = S.byId[it.id];
          html += `<div class="srow${dirty}"><div class="lbl"><b>${esc(TX(it.label))}</b>${it.help ? `<div class="d">${esc(TX(it.help))}</div>` : ''}${e.live !== true ? `<div class="meta"><span class="badge rs">${esc(T('cfg.needs_restart', 'needs restart of {res}', { res: e.res }))}</span></div>` : ''}</div><div class="ctl">${control(e)}</div></div>`;
        } else {
          const cur = choiceIndex(it);
          html += `<div class="srow${dirty}"><div class="lbl"><b>${esc(TX(it.label))}</b>${it.help ? `<div class="d">${esc(TX(it.help))}</div>` : ''}</div><div class="chips">`
            + it.options.map((o, oi) => `<div class="chip${oi === cur ? ' on' : ''}" data-sc="${si}:${ii}:${oi}">${esc(TX(o.label))}</div>`).join('')
            + (cur < 0 ? `<div class="chip custom" title="${esc(T('cfg.custom_title', 'Changed in Advanced mode'))}">${esc(T('cfg.custom', 'Custom'))}</div>` : '') + '</div></div>';
        }
      });
      html += '</div>';
    });
    m.innerHTML = html;
  }
  function setMode(mode) {
    S.mode = mode; try { localStorage.setItem('bsConfigMode', mode); } catch (e) {}
    document.querySelectorAll('#modeSw button').forEach(b => b.classList.toggle('on', b.dataset.mode === mode));
    if (mode === 'simple' && !S.cat.startsWith('_')) S.cat = 'zombies';
    render();
  }

  function renderRail() {
    if (S.mode === 'simple') {
      const it = (id, label, right) => `<div class="it${S.cat === id && !S.query ? ' on' : ''}" data-cat="${id}"><span>${esc(label)}</span>${right}</div>`;
      $('rail').innerHTML = SIMPLE().map((sec, i) => `<div class="it" data-jump="${i}"><span>${esc(TX(sec.section))}</span><i>${sec.items.length}</i></div>`).join('')
        + '<div class="sep"></div>' + extRail(it) + it('_profiles', T('cfg.rail.profiles', 'Profiles'), `<i>${S.profiles.length}</i>`) + it('_audit', T('cfg.rail.audit', 'Audit log'), '<i>&#8635;</i>');
      return;
    }
    const counts = {}, mods = {};
    S.schema.forEach(e => { counts[e.cat] = (counts[e.cat] || 0) + 1; if (S.overrides[e.id] !== undefined || S.pending[e.id] !== undefined) mods[e.cat] = (mods[e.cat] || 0) + 1; });
    const totalMod = Object.values(mods).reduce((a, b) => a + b, 0);
    const it = (id, label, right) => `<div class="it${S.cat === id && !S.query ? ' on' : ''}" data-cat="${id}"><span>${esc(label)}</span>${right}</div>`;
    $('rail').innerHTML = S.cats.map(c => it(c.id, TX(c.label), mods[c.id] ? `<i class="m">${mods[c.id]}/${counts[c.id] || 0}</i>` : `<i>${counts[c.id] || 0}</i>`)).join('')
      + '<div class="sep"></div>' + extRail(it) + it('_modified', T('cfg.rail.modified', 'Modified only'), `<i class="m">${totalMod}</i>`)
      + it('_profiles', T('cfg.rail.profiles', 'Profiles'), `<i>${S.profiles.length}</i>`) + it('_audit', T('cfg.rail.audit', 'Audit log'), '<i>&#8635;</i>');
  }

  // Extension pages (html/ext_*.js push into window.BSConfigExt).
  const EXT = () => window.BSConfigExt || [];
  function extRail(it) { return EXT().map(x => it(x.id, x.label, '<i>&#9881;</i>')).join(''); }

  function control(e) {
    const v = eff(e.id);
    if (e.type === 'bool') return `<div class="tog${v ? ' on' : ''}" data-id="${e.id}" data-k="tog"></div><span class="mm">${v ? T('cfg.ctl_on', 'ON') : T('cfg.ctl_off', 'OFF')}</span>`;
    if (e.type === 'enum') return `<select data-id="${e.id}" data-k="sel">${e.opts.map(o => `<option${o === v ? ' selected' : ''}>${esc(o)}</option>`).join('')}</select>`;
    if (e.type === 'string') return `<input type="text" maxlength="32" data-id="${e.id}" data-k="txt" value="${esc(v)}">`;
    return `<span class="mm">${fmt(e.min)}</span><input type="range" min="${e.min}" max="${e.max}" step="${e.step}" value="${v}" data-id="${e.id}" data-k="rng"><span class="mm">${fmt(e.max)}</span><input type="number" min="${e.min}" max="${e.max}" step="${e.step}" value="${v}" data-id="${e.id}" data-k="num">`;
  }

  function rowHtml(e) {
    const mod = S.overrides[e.id] !== undefined, pen = S.pending[e.id] !== undefined;
    const live = e.live === true ? `<span class="badge live">${esc(T('cfg.live', 'live'))}</span>` : `<span class="badge rs" title="${esc(T('cfg.restart_title', 'Needs a restart of {res}', { res: e.res }))}">${esc(T('cfg.restart_badge', 'restart {res}', { res: e.res }))}</span>`;
    return `<div class="row${mod ? ' mod' : ''}${pen ? ' dirty' : ''}" id="r_${cssId(e.id)}">
      <div class="lbl"><b>${esc(TX(e.label))}</b> ${mod ? `<span class="badge mod">${esc(T('cfg.modified', 'modified'))}</span>` : ''} ${pen ? `<span class="badge pen">${esc(T('cfg.pending', 'pending'))}</span>` : ''}
        <div class="d">${esc(e.desc)}</div><div class="meta">${live}<span>${esc(e.res === '_global' ? T('cfg.global_hook', 'global hook') : e.res)} &middot; ${esc(e.path)}</span></div></div>
      <div class="ctl">${control(e)}</div>
      <div class="acts"><span class="def">${esc(T('cfg.default', 'default'))} <b>${esc(fmt(fileDef(e.id)))}</b></span>
        <button class="btn" data-reset="${e.id}" ${(mod || pen) ? '' : 'disabled'} title="${esc(T('cfg.reset_title', 'Reset to file default'))}">&#8634;</button>
        ${e.live !== true ? `<button class="btn" data-restart="${esc(e.res)}" title="${esc(T('cfg.restart_res_title', 'Restart {res}', { res: e.res }))}">&#9211;</button>` : ''}</div></div>`;
  }
  const cssId = (id) => id.replace(/[^a-zA-Z0-9_-]/g, '_');

  function render() {
    renderRail(); renderProfiles(); updateBar();
    const m = $('main');
    if (!S.query && S.cat === '_audit') return renderAudit();
    if (!S.query && S.cat === '_profiles') return renderProfilePage();
    const ext = !S.query && EXT().find(x => x.id === S.cat);
    if (ext) { m.innerHTML = `<h2 class="cat">${esc(ext.label)}</h2><div class="empty">${esc(T('cfg.loading', 'Loading...'))}</div>`; return ext.render(m); }
    if (S.mode === 'simple' && !S.query) return renderSimple();
    const list = visible();
    if (!list.length) { m.innerHTML = `<div class="empty">${esc(T('cfg.nomatch', 'No setting matches.'))}</div>`; return; }
    const title = S.query ? esc(T('cfg.search_title', 'Search: {q} ({n})', { q: S.query, n: list.length })) : esc(TX((S.cats.find(c => c.id === S.cat) || { label: 'Modified' }).label));
    const groups = {};
    list.forEach(e => { const g = S.query ? TX((S.cats.find(c => c.id === e.cat) || {}).label) : e.path.split('.').slice(0, -1).join('.') || e.path; (groups[g] = groups[g] || []).push(e); });
    m.innerHTML = `<h2 class="cat">${title}</h2>` + Object.entries(groups).map(([g, arr]) => `<div class="card"><h4>${esc(g)}</h4>${arr.map(rowHtml).join('')}</div>`).join('');
    m.scrollTop = 0;
  }

  function updateRow(id) {
    const el = document.getElementById('r_' + cssId(id)); if (!el) return;
    const tmp = document.createElement('div'); tmp.innerHTML = rowHtml(S.byId[id]);
    const fresh = tmp.firstElementChild;
    const focused = document.activeElement && el.contains(document.activeElement) ? document.activeElement.dataset.k : null;
    if (focused === 'num' || focused === 'txt') {   // keep the caret while typing
      el.className = fresh.className; el.querySelector('.lbl').innerHTML = fresh.querySelector('.lbl').innerHTML; el.querySelector('.acts').innerHTML = fresh.querySelector('.acts').innerHTML;
      const r = el.querySelector('[data-k=rng]'); if (r) r.value = eff(id);
    } else el.replaceWith(fresh);
  }

  function updateBar() {
    const n = pendCount();
    $('pendInfo').innerHTML = T('cfg.pend', '{n} pending change(s) on {p}', { n: `<b>${n}</b>`, p: `<b>${esc(S.view)}</b>` });
    $('bar').classList.toggle('has', n > 0);
    $('btnApply').disabled = n === 0; $('btnDiscard').disabled = n === 0;
    $('barNote').textContent = S.builtin ? T('cfg.bar.readonly', 'Presets are read-only - Apply will ask for a new profile name.') : (S.view === S.active ? T('cfg.bar.live', 'Applies live to the running server.') : T('cfg.bar.inactive', 'This profile is not active - changes are saved but not applied until you set it active.'));
  }

  // Audit & profiles pages
  async function renderAudit() {
    const m = $('main'); m.innerHTML = `<h2 class="cat">${esc(T('cfg.rail.audit', 'Audit log'))}</h2><div class="empty">${esc(T('cfg.loading', 'Loading...'))}</div>`;
    const r = await rpc('audit'); if (!r.ok) return toast(r.error || T('cfg.failed', 'Failed'), true);
    const val = (s) => s == null ? `<i style="color:#5d5a57">${esc(T('cfg.default', 'default'))}</i>` : esc(s);
    m.innerHTML = `<h2 class="cat">${esc(T('cfg.rail.audit', 'Audit log'))}</h2><div class="card"><table class="audit"><tr><th>${esc(T('cfg.a.when', 'When'))}</th><th>${esc(T('cfg.a.who', 'Who'))}</th><th>${esc(T('cfg.a.action', 'Action'))}</th><th>${esc(T('cfg.a.profile', 'Profile'))}</th><th>${esc(T('cfg.a.setting', 'Setting'))}</th><th>${esc(T('cfg.a.old', 'Old'))}</th><th>${esc(T('cfg.a.new', 'New'))}</th><th></th></tr>`
      + r.rows.map(x => `<tr><td>${new Date(x.ts * 1000).toLocaleString()}</td><td>${esc(x.actor)}</td><td>${esc(x.action)}</td><td>${esc(x.profile)}</td><td class="k">${esc(TX((S.byId[x.setting] || {}).label) || x.setting || '')}</td><td>${val(x.old_value)}</td><td>${val(x.new_value)}</td><td>${(x.action === 'set' || x.action === 'revert') ? `<button class="btn" data-revert="${x.id}">${esc(T('cfg.revert', 'Revert'))}</button>` : ''}</td></tr>`).join('')
      + '</table></div>';
  }

  function renderProfilePage() {
    const m = $('main');
    m.innerHTML = `<h2 class="cat">${esc(T('cfg.rail.profiles', 'Profiles'))}</h2><div class="card plist">` + S.profiles.map(p => `<div class="p"><div class="n"><b>${esc(p.name)}</b><small>${esc(T('cfg.overrides', '{n} override(s)', { n: p.count }))}${p.builtin ? ' &middot; ' + esc(T('cfg.preset', 'preset')) : ''}${p.by ? ' &middot; ' + esc(p.by) : ''}</small></div>
      ${p.name === S.active ? `<span class="badge live">${esc(T('cfg.active_l', 'active'))}</span>` : `<button class="btn" data-pact="activate" data-p="${esc(p.name)}">${esc(T('cfg.set_active', 'Set active'))}</button>`}
      <button class="btn" data-pact="view" data-p="${esc(p.name)}">${esc(T('cfg.edit', 'Edit'))}</button>
      <button class="btn" data-pact="export" data-p="${esc(p.name)}">${esc(T('cfg.share', 'Share'))}</button>
      ${S.isOwner && !p.builtin && p.name !== S.active ? `<button class="btn danger" data-pact="delete" data-p="${esc(p.name)}">${esc(T('cfg.delete', 'Delete'))}</button>` : ''}</div>`).join('') + '</div>';
  }

  // Modal
  function modal(title, bodyHtml, buttons) {
    $('mTitle').textContent = title; $('mBody').innerHTML = bodyHtml; $('mBtns').innerHTML = '';
    buttons.forEach(b => { const el = document.createElement('button'); el.className = 'btn' + (b.primary ? ' primary' : '') + (b.danger ? ' danger' : ''); el.textContent = b.label; el.onclick = () => b.fn(); $('mBtns').appendChild(el); });
    $('modal').classList.remove('hidden');
    const f = $('mBody').querySelector('input,textarea'); if (f) setTimeout(() => f.focus(), 30);
  }
  const closeModal = () => $('modal').classList.add('hidden');
  function ask(title, label, value) {
    return new Promise(res => modal(title, `<label>${esc(label)}</label><input type="text" id="mIn" maxlength="32" value="${esc(value || '')}">`,
      [{ label: T('cfg.cancel', 'Cancel'), fn: () => { closeModal(); res(null); } }, { label: T('cfg.ok', 'OK'), primary: true, fn: () => { const v = $('mIn').value; closeModal(); res(v); } }]));
  }
  function confirmBox(title, text) {
    return new Promise(res => modal(title, `<p>${esc(text)}</p>`, [{ label: T('cfg.cancel', 'Cancel'), fn: () => { closeModal(); res(false); } }, { label: T('cfg.confirm', 'Confirm'), danger: true, primary: true, fn: () => { closeModal(); res(true); } }]));
  }
  const toCode = (json) => 'BSC1:' + btoa(unescape(encodeURIComponent(json)));
  function fromText(t) {
    t = (t || '').trim();
    if (t.startsWith('BSC1:')) { try { return decodeURIComponent(escape(atob(t.slice(5)))); } catch (e) { return null; } }
    return t;
  }
  function copyText(text) {
    const ta = document.createElement('textarea'); ta.value = text; document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); toast(T('cfg.copied', 'Copied to clipboard')); } catch (e) { toast(T('cfg.copyfail', 'Copy failed - select and Ctrl+C'), true); }
    ta.remove();
  }

  // State changes
  function applyState(st) { if (!st) return; S.profiles = st.profiles; S.active = st.active; S.isOwner = st.isOwner; }
  async function viewProfile(name) {
    if (pendCount() && !(await confirmBox(T('cfg.discard_q', 'Discard changes?'), T('cfg.discard_msg', 'You have {n} pending change(s). Switch profile and drop them?', { n: pendCount() })))) { renderProfiles(); return; }
    const r = await rpc('getProfile', name); if (!r.ok) return toast(r.error, true);
    S.view = name; S.overrides = r.overrides || {}; S.pending = {};
    if (S.cat === '_profiles') S.cat = S.cats[0].id;
    render();
  }

  async function doApply() {
    const changes = {}; Object.assign(changes, S.pending);
    if (S.builtin) {
      const name = await ask(T('cfg.savenew_title', 'Save as new profile'), T('cfg.savenew_label', '"{name}" is read-only. Name for the new profile:', { name: S.view }), T('cfg.suffix_custom', '{name} custom', { name: S.view })); if (!name) return;
      const merged = Object.assign({}, S.overrides);
      Object.entries(changes).forEach(([k, v]) => { if (v === RESET) delete merged[k]; else merged[k] = v; });
      const r = await rpc('saveAs', name, merged); if (!r.ok) return toast(r.error, true);
      applyState(r.state); S.pending = {}; await viewProfile(r.name); toast(T('cfg.saved_as', 'Saved as "{name}" - set it active to apply', { name: r.name })); return;
    }
    const r = await rpc('save', S.view, changes); if (!r.ok) return toast(r.error, true);
    applyState(r.state); S.overrides = r.overrides || {}; S.pending = {}; render();
    toast(S.view === S.active ? T('cfg.saved_n_live', '{n} change(s) saved and applied live', { n: r.changed }) : T('cfg.saved_n', '{n} change(s) saved', { n: r.changed }));
  }

  async function profileAction(act, name) {
    name = name || S.view;
    if (act === 'activate') {
      const r = await rpc('setActive', name); if (!r.ok) return toast(r.error, true);
      applyState(r.state); render(); toast(T('cfg.now_active', '"{name}" is now active', { name }));
    } else if (act === 'view') { await viewProfile(name);
    } else if (act === 'saveas' || act === 'duplicate') {
      const n = await ask(act === 'saveas' ? T('cfg.saveas', 'Save as') : T('cfg.duplicate', 'Duplicate'), T('cfg.newname', 'New profile name'), T('cfg.copy_suffix', '{name} copy', { name })); if (!n) return;
      let r;
      if (act === 'saveas') { const merged = Object.assign({}, S.overrides); Object.entries(S.pending).forEach(([k, v]) => { if (v === RESET) delete merged[k]; else merged[k] = v; }); r = await rpc('saveAs', n, merged); S.pending = {}; }
      else r = await rpc('duplicate', name, n);
      if (!r.ok) return toast(r.error, true);
      applyState(r.state); await viewProfile(r.name); toast(T('cfg.created', 'Created "{name}"', { name: r.name }));
    } else if (act === 'rename') {
      if (isBuiltin(name)) return toast(T('cfg.no_rename', 'Presets cannot be renamed'), true);
      const n = await ask(T('cfg.rename_title', 'Rename profile'), T('cfg.newname2', 'New name'), name); if (!n || n === name) return;
      const r = await rpc('rename', name, n); if (!r.ok) return toast(r.error, true);
      applyState(r.state); if (S.view === name) S.view = r.name; render(); toast(T('cfg.renamed', 'Renamed'));
    } else if (act === 'delete') {
      if (!(await confirmBox(T('cfg.del_title', 'Delete profile'), T('cfg.del_msg', 'Delete "{name}" for good?', { name })))) return;
      const r = await rpc('delete', name); if (!r.ok) return toast(r.error, true);
      applyState(r.state); if (S.view === name) { S.view = S.active; const g = await rpc('getProfile', S.active); S.overrides = g.overrides || {}; S.pending = {}; }
      render(); toast(T('cfg.deleted', 'Deleted'));
    } else if (act === 'export') {
      const r = await rpc('export', name); if (!r.ok) return toast(r.error, true);
      const code = toCode(r.json);
      modal(T('cfg.share_title', 'Share "{name}"', { name }), `<label>${esc(T('cfg.share_code', 'Share code'))}</label><textarea readonly id="mCode" style="min-height:70px">${esc(code)}</textarea>
        <label>JSON</label><textarea readonly id="mJson">${esc(JSON.stringify(JSON.parse(r.json), null, 2))}</textarea>
        <p style="font-size:11px;color:#8a8580">${esc(T('cfg.saved_on_server', 'Also saved on the server as resources/[beyond]/bs_config/{file}', { file: r.file }))}</p>`,
        [{ label: T('cfg.copy_code', 'Copy code'), fn: () => copyText(code) }, { label: T('cfg.copy_json', 'Copy JSON'), fn: () => copyText(r.json) }, { label: T('cfg.download', 'Download .json'), fn: () => download(name, r.json) }, { label: T('cfg.close', 'Close'), primary: true, fn: closeModal }]);
    } else if (act === 'import') {
      modal(T('cfg.import_title', 'Import profile'), `<label>${esc(T('cfg.newname', 'New profile name'))}</label><input type="text" id="mName" maxlength="32"><label>${esc(T('cfg.import_paste', 'Paste a share code (BSC1:...) or JSON'))}</label><textarea id="mTxt"></textarea>`,
        [{ label: T('cfg.cancel', 'Cancel'), fn: closeModal }, { label: T('cfg.import', 'Import'), primary: true, fn: async () => {
          const txt = fromText($('mTxt').value); if (!txt) return toast(T('cfg.bad_code', 'Invalid code'), true);
          let nm = $('mName').value.trim(); if (!nm) { try { nm = (JSON.parse(txt).name || 'Imported') + ' import'; } catch (e) { return toast(T('cfg.bad_json', 'Not valid JSON'), true); } }
          const r = await rpc('import', nm, txt); if (!r.ok) return toast(r.error, true);
          closeModal(); applyState(r.state); await viewProfile(r.name); toast(T('cfg.imported', 'Imported "{name}" ({n} values)', { name: r.name, n: r.count }));
        } }]);
    }
  }
  function download(name, text) {
    try { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' })); a.download = name.replace(/[^\w-]/g, '_') + '.json'; document.body.appendChild(a); a.click(); a.remove(); toast(T('cfg.dl_started', 'Download started (if the game blocks it, use Copy JSON)')); }
    catch (e) { toast(T('cfg.dl_blocked', 'Download blocked - use Copy JSON'), true); }
  }

  // Events
  document.addEventListener('click', async (ev) => {
    const sc = ev.target.closest('[data-sc],[data-jump],[data-mode]');
    if (sc && sc.dataset.mode) return setMode(sc.dataset.mode);
    if (sc && sc.dataset.jump !== undefined) {
      if (S.cat.startsWith('_')) { S.cat = 'zombies'; render(); }
      const el = document.getElementById('sec_' + sc.dataset.jump); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' }); return;
    }
    if (sc && sc.dataset.sc) {
      const [si, ii, oi] = sc.dataset.sc.split(':').map(Number);
      const it = SIMPLE()[si].items[ii];
      Object.entries(optionTargets(it, it.options[oi])).forEach(([id, v]) => setPending(id, v));
      return;
    }
    const t = ev.target.closest('[data-cat],[data-reset],[data-restart],[data-revert],[data-pact],[data-k=tog],#drop button,#btnMenu');
    if (!t) { $('drop').classList.remove('open'); return; }
    if (t.id === 'btnMenu') { $('drop').classList.toggle('open'); return; }
    if (t.dataset.act) { $('drop').classList.remove('open'); return profileAction(t.dataset.act); }
    if (t.dataset.cat) { S.cat = t.dataset.cat; S.query = ''; $('search').value = ''; return render(); }
    if (t.dataset.k === 'tog') return setPending(t.dataset.id, !eff(t.dataset.id));
    if (t.dataset.reset) { const id = t.dataset.reset; if (S.overrides[id] !== undefined) S.pending[id] = RESET; else delete S.pending[id]; updateRow(id); updateBar(); renderRail(); return; }
    if (t.dataset.restart) { if (!(await confirmBox(T('cfg.restart_res', 'Restart resource'), T('cfg.restart_ask', 'Restart {res} now? Players may see it reload.', { res: t.dataset.restart })))) return; const r = await rpc('restart', t.dataset.restart); return toast(r.ok ? T('cfg.restarting', '{res} restarting', { res: t.dataset.restart }) : r.error, !r.ok); }
    if (t.dataset.revert) { const r = await rpc('revert', t.dataset.revert); if (!r.ok) return toast(r.error, true); applyState(r.state); const g = await rpc('getProfile', S.view); S.overrides = g.overrides || {}; toast(T('cfg.reverted', 'Reverted')); return renderAudit(); }
    if (t.dataset.pact) return profileAction(t.dataset.pact, t.dataset.p);
  });
  document.addEventListener('input', (ev) => {
    const t = ev.target; if (!t.dataset || !t.dataset.id) return;
    if (t.dataset.k === 'rng') { const n = t.parentElement.querySelector('[data-k=num]'); if (n) n.value = t.value; setPending(t.dataset.id, parseFloat(t.value)); }
  });
  document.addEventListener('change', (ev) => {
    const t = ev.target; if (!t.dataset || !t.dataset.id) return;
    if (t.dataset.k === 'num') setPending(t.dataset.id, parseFloat(t.value));
    else if (t.dataset.k === 'sel') setPending(t.dataset.id, t.value);
    else if (t.dataset.k === 'txt') setPending(t.dataset.id, t.value.slice(0, 32));
  });
  $('search').addEventListener('input', (e) => { S.query = e.target.value; render(); });
  $('profile').addEventListener('change', (e) => viewProfile(e.target.value));
  $('btnActivate').onclick = () => profileAction('activate');
  $('btnApply').onclick = doApply;
  $('btnDiscard').onclick = () => { S.pending = {}; render(); };
  $('btnClose').onclick = () => close();
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { if (!$('modal').classList.contains('hidden')) closeModal(); else close(); }
    else if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') { e.preventDefault(); $('search').focus(); }
  });

  window.BSConfigUI = { rpc, esc, T, TX, toast, modal: (t, b, btns) => modal(t, b, btns), closeModal: () => closeModal(), confirmBox: (a, b) => confirmBox(a, b) };

  if (window.BSI18n) BSI18n.onChange(() => { if (!$('app').classList.contains('hidden') && S.schema.length) { closeModal(); render(); } });

  function close() { closeModal(); $('app').classList.add('hidden'); post('close'); }

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
      const x = d.data;
      S.schema = x.schema || []; S.byId = {}; S.schema.forEach(e => S.byId[e.id] = e);
      S.defaults = x.defaults || {}; S.cats = x.categories || []; applyState(x);
      S.view = x.active; S.overrides = x.overrides || {}; S.pending = {};
      if (!S.cats.find(c => c.id === S.cat) && !S.cat.startsWith('_')) S.cat = (S.cats[0] || {}).id;
      $('app').classList.remove('hidden'); setMode(S.mode);
    } else if (d.action === 'close') { closeModal(); $('app').classList.add('hidden'); }
  });
})();

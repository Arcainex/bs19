// F1 page for bs_operations: power station, control points and mission chain editor.
(() => {
  'use strict';
  const ui = () => window.BSConfigUI;
  const ext = (action, payload) => ui().rpc('ext', 'bs_operations', action, payload);
  const E = (s) => ui().esc(s);
  const X = (k, fb, v) => ui().T(k, fb, v);
  const fmt = (s) => { s = Math.max(0, Math.floor(s || 0)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m ${s % 60}s`; };
  const xyz = (p) => `${Number(p.x).toFixed(1)}, ${Number(p.y).toFixed(1)}, ${Number(p.z).toFixed(1)}`;
  let R = null, main = null;

  function drawPower() {
    const p = R.power || {};
    const fopt = R.factions.map(f => `<option value="${E(f)}">${E(f)}</option>`).join('');
    const info = [`${E(X('cfg.x.ops.phase', 'Phase'))}: <b>${E(X('cfg.x.ops.ph_' + p.phase, p.phase))}</b>`];
    if (p.phase !== 'idle') info.push(`${E(X('cfg.x.ops.control', 'Control'))}: ${E(p.controllerLabel || '-')}`, `${E(X('cfg.x.ops.left', 'Time left'))}: ${fmt(p.left)}`);
    if (p.cooldown > 0) info.push(`${E(X('cfg.x.ops.cooldown', 'Cooldown'))}: ${fmt(p.cooldown)}`);
    if (p.buff) info.push(`${E(X('cfg.x.ops.buff', 'Buff'))}: ${E(p.buff.label)} (${fmt(p.buff.left)})`);
    return `<div class="card"><h4>${E(X('cfg.x.ops.power', 'Power station'))} <span class="d">${E(p.label)} · ${xyz(p)}</span></h4>
      <div style="padding:8px 14px">${info.join(' &nbsp;·&nbsp; ')}</div>
      <div class="row" style="grid-template-columns:auto auto 1fr"><select id="xoFac">${fopt}</select>
        <button class="btn primary" data-xo="pstart">${E(X('cfg.x.ops.start', 'Start for faction'))}</button><span>
        <button class="btn danger" data-xo="pstop">${E(X('cfg.x.ops.stop', 'Stop'))}</button>
        <button class="btn" data-xo="pcd">${E(X('cfg.x.ops.clear_cd', 'Clear cooldown'))}</button>
        <button class="btn" data-xo="pbuff">${E(X('cfg.x.ops.clear_buff', 'Clear buff'))}</button>
        <button class="btn" data-xo="goto" data-x="${p.x}" data-y="${p.y}" data-z="${p.z}">${E(X('cfg.x.rc.goto', 'Go to'))}</button></span></div>
      <table class="audit"><tr><th>#</th><th>${E(X('cfg.x.rc.position', 'Position'))}</th><th></th></tr>
      ${(p.panels || []).map((q, i) => `<tr><td class="k">${i + 1}</td><td>${xyz(q)}</td><td style="white-space:nowrap">
        <button class="btn" data-xo="pmove" data-i="${i + 1}">${E(X('cfg.x.rc.move', 'Move here'))}</button>
        <button class="btn danger" data-xo="prm" data-i="${i + 1}">${E(X('cfg.x.rc.remove', 'Remove'))}</button></td></tr>`).join('')}
      </table><div class="mBtns" style="padding:8px 14px"><button class="btn" data-xo="pmove" data-i="${(p.panels || []).length + 1}">${E(X('cfg.x.ops.panel_add', 'Add panel here'))}</button></div></div>`;
  }

  function drawPoints() {
    const fsel = (id, cur) => `<select data-xo-owner="${E(id)}"><option value="">${E(X('cfg.x.ops.hostile', 'hostile'))}</option>${R.factions.map(f => `<option value="${E(f)}"${f === cur ? ' selected' : ''}>${E(f)}</option>`).join('')}</select>`;
    return `<div class="card"><h4>${E(X('cfg.x.ops.points', 'Control points ({n})', { n: R.points.length }))}</h4>
      <div class="row" style="grid-template-columns:1fr 1fr auto"><input type="text" id="xoNid" maxlength="32" placeholder="${E(X('cfg.x.ops.id_hint', 'Id (a-z 0-9 _)'))}"><input type="text" id="xoNlabel" maxlength="48" placeholder="${E(X('cfg.x.rc.label_h', 'Label'))}">
        <button class="btn primary" data-xo="cnew">${E(X('cfg.x.ops.point_new', 'New point here'))}</button></div>
      <table class="audit"><tr><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.rc.label_h', 'Label'))}</th><th>${E(X('cfg.x.rc.position', 'Position'))}</th><th>${E(X('cfg.x.ops.owner', 'Owner'))}</th><th>${E(X('cfg.x.state', 'State'))}</th><th></th></tr>
      ${R.points.map(c => `<tr><td class="k">${E(c.id)}</td><td>${E(c.label)}</td><td>${xyz(c)} r${E(c.radius)}</td><td>${fsel(c.id, c.owner)}</td>
        <td>${c.disabled ? `<span class="badge pen">${E(X('cfg.x.off', 'off'))}</span>` : E(X('cfg.x.ops.ph_' + c.phase, c.phase))}${c.edited ? ` <span class="badge mod">${E(X('cfg.x.pass.edited', 'edited'))}</span>` : ''}</td>
        <td style="white-space:nowrap"><button class="btn" data-xo="goto" data-x="${c.x}" data-y="${c.y}" data-z="${c.z}">${E(X('cfg.x.rc.goto', 'Go to'))}</button>
        <button class="btn" data-xo="cedit" data-id="${E(c.id)}">${E(X('cfg.edit', 'Edit'))}</button>
        ${c.edited ? `<button class="btn" data-xo="creset" data-id="${E(c.id)}">&#8634;</button>` : ''}</td></tr>`).join('')}
      </table></div>`;
  }

  function drawChains() {
    const act = R.active || [];
    return `<div class="card"><h4>${E(X('cfg.x.ops.chains', 'Mission chains ({n})', { n: R.chains.length }))}</h4>
      <div class="row" style="grid-template-columns:1fr auto"><span class="d">${E(X('cfg.x.ops.chain_hint', 'Chains come from config_ops.lua. Edits are saved in the database and win over the config. Reset drops the edit.'))}</span>
        <button class="btn primary" data-xo="hnew">${E(X('cfg.x.ops.chain_new', 'New chain'))}</button></div>
      <table class="audit"><tr><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.ops.title', 'Title'))}</th><th>${E(X('cfg.x.ops.faction', 'Faction'))}</th><th>${E(X('cfg.x.ops.tier', 'Tier'))}</th><th>${E(X('cfg.x.ops.steps', 'Steps'))}</th><th>${E(X('cfg.x.state', 'State'))}</th><th></th></tr>
      ${R.chains.map(c => `<tr><td class="k">${E(c.id)}</td><td>${E(c.title)}</td><td>${E(c.faction || '-')}</td><td>${E(c.tier)}</td><td>${E(c.steps)}</td>
        <td>${c.disabled ? `<span class="badge pen">${E(X('cfg.x.off', 'off'))}</span>` : ''}${c.edited ? ` <span class="badge mod">${E(X('cfg.x.pass.edited', 'edited'))}</span>` : ''}${c.builtin ? '' : ` <span class="badge mod">${E(X('cfg.x.custom', 'custom'))}</span>`}</td>
        <td style="white-space:nowrap"><button class="btn" data-xo="hedit" data-id="${E(c.id)}">${E(X('cfg.edit', 'Edit'))}</button>
        <button class="btn${c.disabled ? '' : ' danger'}" data-xo="htoggle" data-id="${E(c.id)}">${E(c.disabled ? X('cfg.x.ops.enable', 'Enable') : X('cfg.x.ops.disable', 'Disable'))}</button>
        ${c.edited ? `<button class="btn" data-xo="hreset" data-id="${E(c.id)}">&#8634;</button>` : ''}</td></tr>`).join('')}
      </table></div>
      <div class="card"><h4>${E(X('cfg.x.ops.active', 'Running chains ({n})', { n: act.length }))}</h4>
      ${act.length ? `<table class="audit"><tr><th>${E(X('cfg.x.ops.player', 'Player'))}</th><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.ops.step', 'Step'))}</th><th>${E(X('cfg.x.ops.party', 'Party'))}</th></tr>
        ${act.map(a => `<tr><td>${E(a.name)} (${E(a.src)})</td><td class="k">${E(a.chain)}</td><td>${E(a.step)}</td><td>${E(a.party)}</td></tr>`).join('')}</table>`
        : `<div class="empty">${E(X('cfg.x.ops.none', 'Nothing running.'))}</div>`}</div>`;
  }

  function draw() {
    main.innerHTML = `<h2 class="cat">${E(X('cfg.x.ops.label', 'Operations editor'))}</h2>
      <p class="shint">${E(X('cfg.x.ops.hint', 'Power station, control points and mission chains. Changes are live and saved in the database. Numbers and switches are in the Operations category. Every change is logged.'))}</p>
      ${drawPower()}${drawPoints()}${drawChains()}`;
  }

  async function act(action, payload, msg) {
    const res = await ext(action, payload);
    if (!res || !res.ok) { ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true); return false; }
    if (res.power) { R = res; draw(); }
    if (msg) ui().toast(msg);
    return res;
  }

  function editPoint(id) {
    const c = R.points.find(p => p.id === id); if (!c) return;
    ui().modal(X('cfg.x.cr.edit_t', 'Edit {id}', { id }), `
      <label>${E(X('cfg.x.rc.label_h', 'Label'))}</label><input type="text" id="xoL" maxlength="48" value="${E(c.label)}">
      <label>${E(X('cfg.x.ops.rgb', 'Radius / guards / brutes'))}</label><div style="display:flex;gap:6px"><input type="number" id="xoR" min="10" max="200" value="${E(c.radius)}"><input type="number" id="xoG" min="0" max="40" value="${E(c.guards)}"><input type="number" id="xoB" min="0" max="10" value="${E(c.brutes)}"></div>
      <label><input type="checkbox" id="xoHere"> ${E(X('cfg.x.ops.move_here', 'Move it to where I stand'))}</label>
      <label><input type="checkbox" id="xoOff" ${c.disabled ? 'checked' : ''}> ${E(X('cfg.x.ops.disabled', 'Disabled'))}</label>`,
      [{ label: X('cfg.cancel', 'Cancel'), fn: () => ui().closeModal() }, { label: X('cfg.x.save', 'Save'), primary: true, fn: () => {
        const v = (k) => document.getElementById(k);
        ui().closeModal();
        act('pointSave', { id, label: v('xoL').value, radius: v('xoR').value, guards: v('xoG').value, brutes: v('xoB').value, here: v('xoHere').checked, disabled: v('xoOff').checked }, X('cfg.x.saved', 'Saved'));
      } }]);
  }

  async function editChain(id) {
    const res = await ext('chainGet', { id: id || '' });
    if (!res || !res.ok) return ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true);
    ui().modal(id ? X('cfg.x.cr.edit_t', 'Edit {id}', { id }) : X('cfg.x.ops.chain_new', 'New chain'), `
      <label>${E(X('cfg.x.ops.id_hint', 'Id (a-z 0-9 _)'))}</label><input type="text" id="xoCid" maxlength="40" value="${E(id || '')}" ${id ? 'readonly' : ''}>
      <p class="shint">${E(X('cfg.x.ops.steps_help', 'Step types: goto, kill, collect, deliver, defend, escort. Each step has type, place, x, y, z, radius. kill: count, spawn, brutes, elite. collect and deliver: item, count, give. defend: seconds, waves, size. escort: model, to. title and desc replace the translated text.'))}</p>
      <div style="display:flex;gap:6px;align-items:center"><button class="btn" id="xoPos">${E(X('cfg.x.ops.mypos', 'My position'))}</button><input type="text" id="xoPosV" readonly style="flex:1"></div>
      <textarea id="xoJson" spellcheck="false" style="min-height:320px;font-family:monospace;font-size:12px">${E(res.json)}</textarea>`,
      [{ label: X('cfg.cancel', 'Cancel'), fn: () => ui().closeModal() }, { label: X('cfg.x.save', 'Save'), primary: true, fn: async () => {
        const cid = document.getElementById('xoCid').value.trim();
        const ok = await act('chainSave', { id: cid, json: document.getElementById('xoJson').value }, X('cfg.x.saved', 'Saved'));
        if (ok) ui().closeModal();
      } }]);
    document.getElementById('xoPos').addEventListener('click', async () => {
      const r = await ext('pos');
      if (r && r.ok && r.pos) document.getElementById('xoPosV').value = `"x": ${r.pos.x}, "y": ${r.pos.y}, "z": ${r.pos.z}`;
    });
  }

  async function render(m) {
    main = m;
    const res = await ext('state');
    if (!res || !res.ok) { m.innerHTML = `<div class="empty">${E((res && res.error) || X('cfg.x.ops.noanswer', 'bs_operations did not answer.'))}</div>`; return; }
    R = res; draw();
  }

  document.addEventListener('change', (e) => {
    const s = e.target.closest('[data-xo-owner]'); if (!s || !R) return;
    act('pointOwner', { id: s.dataset.xoOwner, faction: s.value }, X('cfg.x.saved', 'Saved'));
  });

  document.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-xo]'); if (!b || !R) return;
    const op = b.dataset.xo, id = b.dataset.id, i = Number(b.dataset.i);
    if (op === 'pstart') return act('powerStart', { faction: document.getElementById('xoFac').value }, X('cfg.x.ops.started', 'Started'));
    if (op === 'pstop') { if (await ui().confirmBox(X('cfg.x.ops.stop', 'Stop'), X('cfg.x.ops.stop_msg', 'Stop the power station now? Nobody gets rewards.'))) act('powerStop', {}, X('cfg.x.ops.stopped', 'Stopped')); return; }
    if (op === 'pcd') return act('powerCooldown', {}, X('cfg.x.saved', 'Saved'));
    if (op === 'pbuff') return act('powerBuff', {}, X('cfg.x.saved', 'Saved'));
    if (op === 'pmove') return act('panelHere', { idx: i }, X('cfg.x.saved', 'Saved'));
    if (op === 'prm') return act('panelRemove', { idx: i }, X('cfg.x.saved', 'Saved'));
    if (op === 'goto') return act('goto', { x: Number(b.dataset.x), y: Number(b.dataset.y), z: Number(b.dataset.z) });
    if (op === 'cnew') return act('pointSave', { id: document.getElementById('xoNid').value.trim(), label: document.getElementById('xoNlabel').value.trim(), here: true }, X('cfg.x.saved', 'Saved'));
    if (op === 'cedit') return editPoint(id);
    if (op === 'creset') return act('pointReset', { id }, X('cfg.x.saved', 'Saved'));
    if (op === 'hnew') return editChain(null);
    if (op === 'hedit') return editChain(id);
    if (op === 'htoggle') return act('chainToggle', { id }, X('cfg.x.saved', 'Saved'));
    if (op === 'hreset') { if (await ui().confirmBox(X('cfg.x.ops.reset_t', 'Reset chain'), X('cfg.x.ops.reset_msg', 'Drop the editor version of {id}? A chain that is not in the config is deleted.', { id }))) act('chainReset', { id }, X('cfg.x.saved', 'Saved')); }
  });

  window.BSConfigExt = (window.BSConfigExt || []).concat([{ id: '_ext_ops', get label() { return X('cfg.x.ops.label', 'Operations editor'); }, render }]);
})();

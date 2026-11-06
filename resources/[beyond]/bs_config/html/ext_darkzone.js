// F1 page for bs_darkzone: status, start/stop/next, zone list editor.
(() => {
  'use strict';
  const ui = () => window.BSConfigUI;
  const ext = (action, payload) => ui().rpc('ext', 'bs_darkzone', action, payload);
  const E = (s) => ui().esc(s);
  const X = (k, fb, v) => ui().T(k, fb, v);
  const fmt = (s) => { s = Math.max(0, Math.floor(s || 0)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m ${s % 60}s`; };
  let R = null, main = null;

  function drawStatus() {
    const a = R.active;
    const info = [];
    if (!R.enabled) info.push(`<b>${E(X('cfg.x.dz.off_hint', 'The Dark Zone is off. Turn it on in the Dark Zone category.'))}</b>`);
    else if (R.paused) info.push(`<b>${E(X('cfg.x.dz.stopped', 'Stopped by staff'))}</b>`);
    if (a) info.push(`${E(X('cfg.x.dz.active', 'Active'))}: <b>${E(a.label)}</b>`, `${E(X('cfg.x.dz.moves_in', 'Moves in'))}: ${fmt(a.left)}`, `${E(X('cfg.x.dz.inside', 'Players inside'))}: ${E(a.inside)}`);
    else if (R.enabled && !R.paused) info.push(E(X('cfg.x.dz.none', 'No zone active yet.')));
    if (R.heli) info.push(`${E(X('cfg.x.dz.heli', 'Helicopter'))}: ${fmt(R.heli.left)}`);
    return `<div class="card"><h4>${E(X('cfg.x.dz.status', 'Status'))}</h4>
      <div style="padding:8px 14px">${info.join(' &nbsp;·&nbsp; ')}</div>
      <div class="mBtns" style="padding:8px 14px">
        <button class="btn primary" data-xd="start">${E(X('cfg.x.dz.start', 'Start'))}</button>
        <button class="btn" data-xd="next">${E(X('cfg.x.dz.next', 'Move to next zone'))}</button>
        <button class="btn danger" data-xd="stop">${E(X('cfg.x.dz.stop', 'Stop'))}</button></div></div>`;
  }

  function drawZones() {
    return `<div class="card"><h4>${E(X('cfg.x.dz.zones', 'Zones ({n})', { n: R.zones.length }))}</h4>
      <div class="row" style="grid-template-columns:1fr 1fr auto"><input type="text" id="xdNid" maxlength="32" placeholder="${E(X('cfg.x.ops.id_hint', 'Id (a-z 0-9 _)'))}"><input type="text" id="xdNlabel" maxlength="48" placeholder="${E(X('cfg.x.rc.label_h', 'Label'))}">
        <button class="btn primary" data-xd="znew">${E(X('cfg.x.dz.new_here', 'New zone here'))}</button></div>
      <table class="audit"><tr><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.rc.label_h', 'Label'))}</th><th>${E(X('cfg.x.rc.position', 'Position'))}</th><th>${E(X('cfg.x.dz.points', 'Points'))}</th><th>${E(X('cfg.x.state', 'State'))}</th><th></th></tr>
      ${R.zones.map(z => `<tr><td class="k">${E(z.id)}</td><td>${E(z.label)}</td><td>${Number(z.x).toFixed(0)}, ${Number(z.y).toFixed(0)} r${E(z.radius)}</td>
        <td>${z.heli ? 'H' : '-'} / ${E(z.walks)}</td>
        <td>${z.active ? `<span class="badge mod">${E(X('cfg.x.dz.active', 'Active'))}</span> ` : ''}${z.enabled ? '' : `<span class="badge pen">${E(X('cfg.x.off', 'off'))}</span> `}${z.conflict ? `<span class="badge pen">${E(X('cfg.x.dz.near', 'near {name}', { name: z.conflict }))}</span> ` : ''}${z.edited ? `<span class="badge mod">${E(X('cfg.x.pass.edited', 'edited'))}</span>` : ''}${z.builtin ? '' : ` <span class="badge mod">${E(X('cfg.x.custom', 'custom'))}</span>`}</td>
        <td style="white-space:nowrap"><button class="btn" data-xd="goto" data-x="${z.x}" data-y="${z.y}" data-z="${z.z}">${E(X('cfg.x.rc.goto', 'Go to'))}</button>
        <button class="btn" data-xd="move" data-id="${E(z.id)}">${E(X('cfg.x.dz.move', 'Activate'))}</button>
        <button class="btn" data-xd="zedit" data-id="${E(z.id)}">${E(X('cfg.edit', 'Edit'))}</button>
        ${z.edited ? `<button class="btn" data-xd="zreset" data-id="${E(z.id)}">&#8634;</button>` : ''}
        <button class="btn danger" data-xd="zdel" data-id="${E(z.id)}">&#10005;</button></td></tr>`).join('')}
      </table></div>`;
  }

  function draw() {
    main.innerHTML = `<h2 class="cat">${E(X('cfg.x.dz.label', 'Dark Zone editor'))}</h2>
      <p class="shint">${E(X('cfg.x.dz.hint', 'Zones come from config_darkzone.lua. Edits are saved in the database and win over the config. Numbers and switches are in the Dark Zone category. Every change is logged.'))}</p>
      ${drawStatus()}${drawZones()}`;
  }

  async function act(action, payload, msg) {
    const res = await ext(action, payload);
    if (!res || !res.ok) { ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true); return false; }
    if (res.zones) { R = res; draw(); }
    if (msg) ui().toast(msg);
    return res;
  }

  function editZone(id) {
    const z = R.zones.find(q => q.id === id); if (!z) return;
    ui().modal(X('cfg.x.cr.edit_t', 'Edit {id}', { id }), `
      <label>${E(X('cfg.x.rc.label_h', 'Label'))}</label><input type="text" id="xdL" maxlength="48" value="${E(z.label)}">
      <label>${E(X('cfg.x.dz.radius', 'Radius (m)'))}</label><input type="number" id="xdR" min="60" max="1500" value="${E(z.radius)}">
      <label><input type="checkbox" id="xdOn" ${z.enabled ? 'checked' : ''}> ${E(X('cfg.x.dz.enabled', 'In the rotation'))}</label>
      <label><input type="checkbox" id="xdHere"> ${E(X('cfg.x.ops.move_here', 'Move it to where I stand'))}</label>
      <div class="mBtns" style="margin-top:8px">
        <button class="btn" id="xdHeli">${E(X('cfg.x.dz.heli_here', 'Helicopter point here'))}</button>
        <button class="btn" id="xdWalk">${E(X('cfg.x.dz.walk_add', 'Add walk-out point here'))}</button>
        <button class="btn danger" id="xdClear">${E(X('cfg.x.dz.points_clear', 'Back to automatic points'))}</button></div>`,
      [{ label: X('cfg.cancel', 'Cancel'), fn: () => ui().closeModal() }, { label: X('cfg.x.save', 'Save'), primary: true, fn: () => {
        const v = (k) => document.getElementById(k);
        ui().closeModal();
        act('zoneSave', { id, label: v('xdL').value, radius: Number(v('xdR').value), enabled: v('xdOn').checked, here: v('xdHere').checked }, X('cfg.x.saved', 'Saved'));
      } }]);
    document.getElementById('xdHeli').addEventListener('click', () => act('heliHere', { id }, X('cfg.x.saved', 'Saved')));
    document.getElementById('xdWalk').addEventListener('click', () => act('walkAdd', { id }, X('cfg.x.saved', 'Saved')));
    document.getElementById('xdClear').addEventListener('click', () => act('walkClear', { id }, X('cfg.x.saved', 'Saved')));
  }

  async function render(m) {
    main = m;
    const res = await ext('state');
    if (!res || !res.ok) { m.innerHTML = `<div class="empty">${E((res && res.error) || X('cfg.x.dz.noanswer', 'bs_darkzone did not answer.'))}</div>`; return; }
    R = res; draw();
  }

  document.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-xd]'); if (!b || !R) return;
    const op = b.dataset.xd, id = b.dataset.id;
    if (op === 'start') return act('start', {}, X('cfg.x.saved', 'Saved'));
    if (op === 'next') return act('next', {}, X('cfg.x.saved', 'Saved'));
    if (op === 'stop') { if (await ui().confirmBox(X('cfg.x.dz.stop', 'Stop'), X('cfg.x.dz.stop_msg', 'Stop the Dark Zone now? Crates go, running extractions are cancelled. Bags are kept.'))) act('stop', {}, X('cfg.x.saved', 'Saved')); return; }
    if (op === 'move') return act('move', { id }, X('cfg.x.saved', 'Saved'));
    if (op === 'goto') return act('goto', { x: Number(b.dataset.x), y: Number(b.dataset.y), z: Number(b.dataset.z) });
    if (op === 'znew') return act('zoneSave', { id: document.getElementById('xdNid').value.trim(), label: document.getElementById('xdNlabel').value.trim(), radius: 300, enabled: true, here: true }, X('cfg.x.saved', 'Saved'));
    if (op === 'zedit') return editZone(id);
    if (op === 'zreset') return act('zoneReset', { id }, X('cfg.x.saved', 'Saved'));
    if (op === 'zdel') { if (await ui().confirmBox(X('cfg.x.dz.delete', 'Remove zone'), X('cfg.x.dz.delete_msg', 'Remove {id} from the rotation?', { id }))) act('zoneDelete', { id }, X('cfg.x.saved', 'Saved')); }
  });

  window.BSConfigExt = (window.BSConfigExt || []).concat([{ id: '_ext_dz', get label() { return X('cfg.x.dz.label', 'Dark Zone editor'); }, render }]);
})();

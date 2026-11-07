// F1 pages for bs_crafting (recipe editor) and bs_recycler (machine spots + blacklist).
(() => {
  'use strict';
  const ui = () => window.BSConfigUI;
  const ext = (res, action, payload) => ui().rpc('ext', res, action, payload);
  const E = (s) => ui().esc(s);
  const X = (k, fb, v) => ui().T(k, fb, v);
  let R = null, q = '', main = null;

  const costText = (list) => (list || []).map(c => `${c.item}:${c.amount}`).join(', ');
  const parseCost = (txt) => String(txt || '').split(',').map(x => x.trim()).filter(Boolean).map(x => { const [item, n] = x.split(':'); return { item: item.trim(), amount: Number(n) || 1 }; });

  // ------------------------------------------------------------ recipes
  function drawRecipes() {
    const list = R.recipes.filter(r => !q || (r.id + ' ' + (r.recipe && r.recipe.result.item) + ' ' + (r.recipe && r.recipe.station || 'hand')).toLowerCase().includes(q));
    const st = (s) => s ? (R.stations.find(x => x.id === s) || { label: s }).label : X('cfg.x.cr.hand', 'Hand');
    main.innerHTML = `<h2 class="cat">${E(X('cfg.x.cr.label', 'Recipe editor'))}</h2>
      <p class="shint">${E(X('cfg.x.cr.hint', 'Every recipe is known to every player. Changes are live and saved to bs_crafting/data/recipes.json on top of config_recipes.lua.'))}</p>
      <div class="card"><h4>${E(X('cfg.x.cr.recipes', 'Recipes ({n})', { n: list.length }))}</h4>
      <div class="row" style="grid-template-columns:1fr auto auto"><input type="text" id="xrQ" placeholder="${E(X('cfg.x.cr.filter', 'Filter by id, item or station'))}" value="${E(q)}" style="width:100%;box-sizing:border-box">
        <button class="btn primary" data-xr="new">${E(X('cfg.x.cr.new', 'New recipe'))}</button><span></span></div>
      <table class="audit"><tr><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.cr.makes', 'Makes'))}</th><th>${E(X('cfg.x.cr.station', 'Station'))}</th><th>${E(X('cfg.x.cr.time', 'Time'))}</th><th>${E(X('cfg.x.cr.cost', 'Cost'))}</th><th>${E(X('cfg.x.state', 'State'))}</th><th></th></tr>
      ${list.map(x => { const r = x.recipe || { result: {} }; return `<tr><td class="k">${E(x.id)}</td><td>${E(r.result.item)} x${E(r.result.amount || 1)}</td><td>${E(st(r.station))}</td><td>${E(r.time)}s</td><td class="k">${E(costText(r.cost))}</td>
        <td>${x.disabled ? `<span class="badge pen">${E(X('cfg.x.off', 'off'))}</span>` : x.custom ? `<span class="badge mod">${E(X('cfg.x.custom', 'custom'))}</span>` : x.edited ? `<span class="badge mod">${E(X('cfg.x.pass.edited', 'edited'))}</span>` : `<span class="badge ro">${E(X('cfg.x.cr.file', 'file'))}</span>`}${r.explosive ? ` <span class="badge rs">${E(X('cfg.x.cr.explosive', 'explosive'))}</span>` : ''}</td>
        <td style="white-space:nowrap"><button class="btn" data-xr="edit" data-id="${E(x.id)}">${E(X('cfg.edit', 'Edit'))}</button>
        ${x.disabled ? '' : `<button class="btn danger" data-xr="off" data-id="${E(x.id)}">${E(X('cfg.x.cr.disable', 'Disable'))}</button>`}
        ${x.edited ? `<button class="btn" data-xr="reset" data-id="${E(x.id)}">&#8634;</button>` : ''}</td></tr>`; }).join('')}
      </table></div>`;
  }

  function editRecipe(id) {
    const x = R.recipes.find(r => r.id === id);
    const r = (x && x.recipe) || { cat: 'misc', result: { item: '', amount: 1 }, time: 10, cost: [] };
    const opt = (v, cur) => `<option value="${E(v)}"${v === cur ? ' selected' : ''}>${E(v || X('cfg.x.cr.hand', 'Hand').toLowerCase())}</option>`;
    ui().modal(id ? X('cfg.x.cr.edit_t', 'Edit {id}', { id }) : X('cfg.x.cr.new', 'New recipe'), `
      <datalist id="xrItems">${R.items.map(i => `<option value="${E(i.id)}">${E(i.label)}</option>`).join('')}</datalist>
      <label>${E(X('cfg.x.cr.id', 'Recipe id'))}</label><input type="text" id="xrId" maxlength="48" value="${E(id || '')}" ${id ? 'readonly' : ''}>
      <label>${E(X('cfg.x.cr.makes_f', 'Makes (item, amount)'))}</label><div style="display:flex;gap:6px"><input type="text" list="xrItems" id="xrItem" value="${E(r.result.item)}" style="flex:1"><input type="number" id="xrAmt" min="1" max="100" value="${E(r.result.amount || 1)}" style="width:80px"></div>
      <label>${E(X('cfg.x.cr.station', 'Station'))}</label><select id="xrSt">${['', ...R.stations.map(s => s.id)].map(v => opt(v, r.station || '')).join('')}</select>
      <label>${E(X('cfg.x.cr.category', 'Category'))}</label><select id="xrCat">${R.categories.map(v => opt(v, r.cat)).join('')}</select>
      <label>${E(X('cfg.x.cr.time0', 'Time at level 0 (seconds)'))}</label><input type="number" id="xrTime" min="1" max="3600" value="${E(r.time)}">
      <label>${E(X('cfg.x.cr.cost_f', 'Cost (item:amount, item:amount)'))}</label><textarea id="xrCost" style="min-height:60px">${E(costText(r.cost))}</textarea>
      <label>${E(X('cfg.x.cr.tool', 'Tool needed, not used up (item, item)'))}</label><input type="text" id="xrTool" value="${E((r.tool || []).join(', '))}" style="width:100%;box-sizing:border-box">
      <label>${E(X('cfg.x.cr.burn', 'Burns into (cooking, optional)'))}</label><input type="text" list="xrItems" id="xrBurn" value="${E(r.burn || '')}">
      <label><input type="checkbox" id="xrExp" ${r.explosive ? 'checked' : ''}> ${E(X('cfg.x.cr.explosive_f', 'Explosive (off when explosives are disabled)'))}</label>`,
      [{ label: X('cfg.cancel', 'Cancel'), fn: () => ui().closeModal() }, { label: X('cfg.x.save', 'Save'), primary: true, fn: async () => {
        const v = (k) => document.getElementById(k).value;
        const rec = { cat: v('xrCat'), station: v('xrSt'), result: { item: v('xrItem').trim(), amount: Number(v('xrAmt')) }, time: Number(v('xrTime')),
          cost: parseCost(v('xrCost')), tool: v('xrTool').split(',').map(s => s.trim()).filter(Boolean), burn: v('xrBurn').trim() || null,
          explosive: document.getElementById('xrExp').checked, label: x && x.recipe && x.recipe.label };
        const res = await ext('bs_crafting', 'saveRecipe', { id: v('xrId').trim(), recipe: rec });
        if (!res || !res.ok) return ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true);
        R = res; ui().closeModal(); drawRecipes(); ui().toast(X('cfg.x.cr.saved', 'Recipe saved'));
      } }]);
  }

  async function renderRecipes(m) {
    main = m;
    const res = await ext('bs_crafting', 'recipes');
    if (!res || !res.ok) { m.innerHTML = `<div class="empty">${E((res && res.error) || X('cfg.x.cr.noanswer', 'bs_crafting did not answer.'))}</div>`; return; }
    R = res; drawRecipes();
  }

  // ------------------------------------------------------------ recyclers
  let P = null;
  function drawRecyclers() {
    main.innerHTML = `<h2 class="cat">${E(X('cfg.x.rc.label', 'Recyclers'))}</h2>
      <p class="shint">${E(X('cfg.x.rc.hint', 'Hidden machines, no map blips. A machine inside a safezone only exists if you put it there here. Use Add / Move to place one where you stand.'))}</p>
      <div class="card"><h4>${E(X('cfg.x.rc.machines', 'Machines ({n})', { n: P.points.length }))}</h4>
      <div class="row" style="grid-template-columns:1fr auto"><span class="d">${E(X('cfg.x.rc.stand', 'Stand where the machine should go.'))}</span><button class="btn primary" data-xp="add">${E(X('cfg.x.rc.add', 'Add here'))}</button></div>
      <table class="audit"><tr><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.rc.label_h', 'Label'))}</th><th>${E(X('cfg.x.rc.position', 'Position'))}</th><th>${E(X('cfg.x.state', 'State'))}</th><th></th></tr>
      ${P.points.map(p => `<tr><td class="k">${E(p.id)}</td><td>${E(p.label)}</td><td>${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}</td><td>${p.running ? `<span class="badge live">${E(X('cfg.x.rc.running', 'running'))}</span>` : `<span class="badge ro">${E(X('cfg.x.rc.idle', 'idle'))}</span>`}</td>
        <td style="white-space:nowrap"><button class="btn" data-xp="goto" data-id="${E(p.id)}">${E(X('cfg.x.rc.goto', 'Go to'))}</button><button class="btn" data-xp="move" data-id="${E(p.id)}">${E(X('cfg.x.rc.move', 'Move here'))}</button>
        <button class="btn" data-xp="edit" data-id="${E(p.id)}">${E(X('cfg.edit', 'Edit'))}</button><button class="btn danger" data-xp="remove" data-id="${E(p.id)}">${E(X('cfg.x.rc.remove', 'Remove'))}</button></td></tr>`).join('')}
      </table></div>
      <div class="card"><h4>${E(X('cfg.x.rc.blacklist', 'Blacklist'))}</h4><div style="padding:10px 14px">
        <p class="shint">${E(X('cfg.x.rc.bl_hint', 'Items the machine refuses, on top of the built-in list: {list}', { list: P.fixed.join(', ') }))}</p>
        <textarea id="xpBl" style="min-height:60px" placeholder="item_id, item_id">${E(P.blacklist.join(', '))}</textarea>
        <div class="mBtns"><button class="btn primary" data-xp="bl">${E(X('cfg.x.rc.bl_save', 'Save blacklist'))}</button></div></div></div>`;
  }

  async function act(action, payload, msg) {
    const res = await ext('bs_recycler', action, payload);
    if (!res || !res.ok) return ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true);
    P = res; drawRecyclers(); if (msg) ui().toast(msg);
  }

  async function renderRecyclers(m) {
    main = m;
    const res = await ext('bs_recycler', 'points');
    if (!res || !res.ok) { m.innerHTML = `<div class="empty">${E((res && res.error) || X('cfg.x.rc.noanswer', 'bs_recycler did not answer.'))}</div>`; return; }
    P = res; drawRecyclers();
  }

  // ------------------------------------------------------------ input
  document.addEventListener('click', async (e) => {
    const r = e.target.closest('[data-xr]'), p = e.target.closest('[data-xp]');
    if (r) {
      const id = r.dataset.id;
      if (r.dataset.xr === 'new') return editRecipe(null);
      if (r.dataset.xr === 'edit') return editRecipe(id);
      if (r.dataset.xr === 'off' || r.dataset.xr === 'reset') {
        if (r.dataset.xr === 'off' && !(await ui().confirmBox(X('cfg.x.cr.dis_title', 'Disable recipe'), X('cfg.x.cr.dis_msg', 'Players will no longer see {id}.', { id })))) return;
        const res = await ext('bs_crafting', r.dataset.xr === 'off' ? 'disableRecipe' : 'resetRecipe', id);
        if (!res || !res.ok) return ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true);
        R = res; return drawRecipes();
      }
    }
    if (p) {
      const id = p.dataset.id, pt = P && P.points.find(x => x.id === id);
      if (p.dataset.xp === 'add') return act('addHere', 'Recycler', X('cfg.x.rc.placed', 'Machine placed'));
      if (p.dataset.xp === 'goto') return act('goto', id);
      if (p.dataset.xp === 'move') return act('edit', { id, here: true }, X('cfg.x.rc.moved', 'Moved'));
      if (p.dataset.xp === 'remove') { if (await ui().confirmBox(X('cfg.x.rc.rm_title', 'Remove machine'), X('cfg.x.rc.rm_msg', 'Remove {id}? Items inside stay in the database.', { id }))) act('remove', id, X('cfg.x.rc.removed', 'Removed')); return; }
      if (p.dataset.xp === 'bl') return act('blacklist', document.getElementById('xpBl').value.split(',').map(s => s.trim()).filter(Boolean), X('cfg.x.rc.bl_saved', 'Blacklist saved'));
      if (p.dataset.xp === 'edit' && pt) {
        ui().modal(X('cfg.x.cr.edit_t', 'Edit {id}', { id }), `<label>${E(X('cfg.x.rc.label_h', 'Label'))}</label><input type="text" id="xpL" value="${E(pt.label)}">
          <label>${E(X('cfg.x.rc.xyzh', 'X / Y / Z / heading'))}</label><div style="display:flex;gap:6px"><input type="number" id="xpX" value="${pt.x}"><input type="number" id="xpY" value="${pt.y}"><input type="number" id="xpZ" value="${pt.z}"><input type="number" id="xpH" value="${pt.h || 0}"></div>`,
          [{ label: X('cfg.cancel', 'Cancel'), fn: () => ui().closeModal() }, { label: X('cfg.x.save', 'Save'), primary: true, fn: () => {
            const v = (k) => document.getElementById(k).value;
            ui().closeModal(); act('edit', { id, label: v('xpL'), x: v('xpX'), y: v('xpY'), z: v('xpZ'), h: v('xpH') }, X('cfg.x.saved', 'Saved'));
          } }]);
      }
    }
  });
  document.addEventListener('input', (e) => { if (e.target.id === 'xrQ') { q = e.target.value.toLowerCase(); const pos = e.target.selectionStart; drawRecipes(); const el = document.getElementById('xrQ'); el.focus(); el.setSelectionRange(pos, pos); } });

  window.BSConfigExt = (window.BSConfigExt || []).concat([
    { id: '_ext_recipes', get label() { return X('cfg.x.cr.label', 'Recipe editor'); }, render: renderRecipes },
    { id: '_ext_recyclers', get label() { return X('cfg.x.rc.label', 'Recyclers'); }, render: renderRecyclers },
  ]);
})();

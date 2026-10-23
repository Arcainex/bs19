// F1 page for bs_tutorial: chapter text per language, camera points, enable/disable, preview.
(() => {
  'use strict';
  const ui = () => window.BSConfigUI;
  const ext = (action, payload) => ui().rpc('ext', 'bs_tutorial', action, payload);
  const E = (s) => ui().esc(s);
  const X = (k, fb, v) => ui().T(k, fb, v);
  let D = null, lang = 'en', main = null;

  const v = (p) => (p ? `${Number(p.x).toFixed(1)}, ${Number(p.y).toFixed(1)}, ${Number(p.z).toFixed(1)}` : '-');

  function draw() {
    main.innerHTML = `<h2 class="cat">${E(X('cfg.x.tut.label', 'Tutorial editor'))}</h2>
      <p class="shint">${E(X('cfg.x.tut.hint', 'Edits are live and saved to bs_tutorial/data/overrides.json. Text is per language; anything not edited uses the locale files. Camera: stand where the shot should start (or end), look at the subject, then press Cam 1 / Cam 2. Own chapters go in config_tutorial.lua (Tutorial.CustomChapters).'))}</p>
      <div class="card"><h4>${E(X('cfg.x.tut.lang', 'Language'))}</h4><select id="xtLang">${D.langs.map((l) => `<option${l === lang ? ' selected' : ''}>${E(l)}</option>`).join('')}</select></div>
      <div class="card"><h4>${E(X('cfg.x.tut.chapters', 'Chapters ({n})', { n: D.chapters.length }))}</h4>
      <table class="audit"><tr><th>${E(X('cfg.x.id', 'Id'))}</th><th>${E(X('cfg.x.title', 'Title'))}</th><th>${E(X('cfg.x.tut.cam1', 'Cam 1'))}</th><th>${E(X('cfg.x.tut.cam2', 'Cam 2'))}</th><th>${E(X('cfg.x.state', 'State'))}</th><th></th></tr>
      ${D.chapters.map((c) => `<tr><td class="k">${E(c.id)}${c.builtin ? '' : ` <span class="badge mod">${E(X('cfg.x.custom', 'custom'))}</span>`}</td><td>${E(c.title)}</td>
        <td class="k">${E(v(c.cam[0] && c.cam[0].pos))}</td><td class="k">${E(v(c.cam[1] && c.cam[1].pos))}</td>
        <td>${c.disabled ? `<span class="badge pen">${E(X('cfg.x.off', 'off'))}</span>` : `<span class="badge ro">${E(X('cfg.x.on', 'on'))}</span>`}${c.edited ? ` <span class="badge mod">${E(X('cfg.x.tut.text_badge', 'text'))}</span>` : ''}${c.camEdited ? ` <span class="badge mod">${E(X('cfg.x.tut.cam_badge', 'cam'))}</span>` : ''}</td>
        <td style="white-space:nowrap"><button class="btn" data-xt="text" data-id="${E(c.id)}">${E(X('cfg.x.tut.btn_text', 'Text'))}</button>
          <button class="btn" data-xt="cam1" data-id="${E(c.id)}">${E(X('cfg.x.tut.btn_cam1', 'Cam 1 here'))}</button><button class="btn" data-xt="cam2" data-id="${E(c.id)}">${E(X('cfg.x.tut.btn_cam2', 'Cam 2 here'))}</button>
          ${c.camEdited ? `<button class="btn" data-xt="resetCam" data-id="${E(c.id)}">&#8634;</button>` : ''}
          <button class="btn" data-xt="preview" data-id="${E(c.id)}">${E(X('cfg.x.tut.btn_preview', 'Preview'))}</button>
          <button class="btn ${c.disabled ? '' : 'danger'}" data-xt="toggle" data-id="${E(c.id)}">${E(c.disabled ? X('cfg.x.tut.enable', 'Enable') : X('cfg.x.tut.disable', 'Disable'))}</button></td></tr>`).join('')}
      </table></div>`;
  }

  async function act(action, payload, msg) {
    const res = await ext(action, Object.assign({ lang }, payload || {}));
    if (!res || !res.ok) return ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true);
    D = res; draw(); if (msg) ui().toast(msg);
  }

  function editText(id) {
    const c = D.chapters.find((x) => x.id === id); if (!c) return;
    ui().modal(`${id} (${lang})`, `<label>${E(X('cfg.x.title', 'Title'))}</label><input type="text" id="xtT" maxlength="60" value="${E(c.title)}">
      ${[0, 1, 2].map((i) => `<label>${E(X('cfg.x.tut.line', 'Line {n}', { n: i + 1 }))}</label><textarea id="xtL${i}" rows="3" maxlength="400" style="width:100%;box-sizing:border-box">${E((c.lines || [])[i] || '')}</textarea>`).join('')}`,
      [{ label: X('cfg.x.reset', 'Reset'), fn: () => { ui().closeModal(); act('resetText', { id }, X('cfg.x.reset', 'Reset')); } },
       { label: X('cfg.cancel', 'Cancel'), fn: () => ui().closeModal() },
       { label: X('cfg.x.save', 'Save'), primary: true, fn: () => {
         const g = (k) => document.getElementById(k).value;
         ui().closeModal(); act('saveText', { id, title: g('xtT'), lines: [g('xtL0'), g('xtL1'), g('xtL2')] }, X('cfg.x.saved', 'Saved'));
       } }]);
  }

  async function render(m) {
    main = m;
    const res = await ext('state', { lang });
    if (!res || !res.ok) { m.innerHTML = `<div class="empty">${E((res && res.error) || X('cfg.x.tut.noanswer', 'bs_tutorial did not answer.'))}</div>`; return; }
    D = res; draw();
  }

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-xt]'); if (!b || !D) return;
    const id = b.dataset.id, a = b.dataset.xt;
    if (a === 'text') return editText(id);
    if (a === 'cam1') return act('camHere', { id, idx: 1 }, X('cfg.x.tut.cam1set', 'Camera 1 set'));
    if (a === 'cam2') return act('camHere', { id, idx: 2 }, X('cfg.x.tut.cam2set', 'Camera 2 set'));
    if (a === 'resetCam') return act('resetCam', { id }, X('cfg.x.tut.camreset', 'Camera reset'));
    if (a === 'toggle') return act('toggle', { id });
    if (a === 'preview') return act('preview', { id }, X('cfg.x.tut.preview_msg', 'Close F1 to watch'));
  });
  document.addEventListener('change', (e) => { if (e.target.id === 'xtLang' && main) { lang = e.target.value; render(main); } });

  window.BSConfigExt = (window.BSConfigExt || []).concat([{ id: '_ext_tutorial', get label() { return X('cfg.x.tut.label', 'Tutorial editor'); }, render }]);
})();

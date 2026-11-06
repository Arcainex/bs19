(() => {
  'use strict';
  const ui = () => window.BSConfigUI, E = v => ui().esc(String(v ?? ''));
  const T = (k, d) => ui().T(k, d);
  const rpc = (action, pack) => ui().rpc('themeApi', action, pack);
  let main, st;

  // One card per pack. Previews are fixture shots of the selector and inventory (img/themes/<pack>-*.jpg).
  const pack = (id, name, desc) => ({ id, name: () => T('cfg.x.th.' + id, name), desc: () => T('cfg.x.th.' + id + '_d', desc) });
  const PACKS = [
    pack('dossier', 'Dossier', 'Gritty survivor-file look: stencil headers, hazard tape, amber on charcoal and worn grain.'),
    pack('classic', 'Classic', 'The earlier look: flat tinted panels, monospace and serif type, no grain or tape.'),
    pack('fieldradio', 'Field Radio', 'Army signals kit: olive drab canvas, khaki label tape on headers, map contour lines and stitched webbing edges.'),
    pack('rustbelt', 'Rust Belt', 'Scrapyard steel: oxidised plate, riveted bands, burnt orange and heavy cast-plate lettering.'),
    pack('quarantine', 'Quarantine', 'Field hospital records: off-white stained paper, red hazard tape, typewritten forms and red stamped headers.'),
    pack('nightops', 'Night Ops', 'Blackout command post: near-black panels, dim green phosphor readouts, monospace type and bracketed corners.'),
  ];
  const shots = (p) => `<div class="thimgs">${[['selector', T('cfg.x.th.sel', 'Character select')], ['inventory', T('cfg.x.th.inv', 'Inventory')]]
    .map(([k, l]) => `<figure><img src="img/themes/${p.id}-${k}.jpg" alt=""><figcaption>${E(l)}</figcaption></figure>`).join('')}</div>`;

  function draw() {
    const active = st.active;
    main.innerHTML = `<h2 class="cat">${E(T('cfg.t.themes_ui', 'Themes & UI'))}</h2>
      <style>
        .thgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:18px}
        .thcard{background:var(--char2);border:2px solid var(--line);padding:16px;display:flex;flex-direction:column;gap:12px}
        .thcard.on{border-color:var(--rust)}
        .thcard h3{margin:0;font-size:22px;letter-spacing:2px;text-transform:uppercase;display:flex;gap:12px;align-items:center}
        .thcard h3 span{font-size:12px;letter-spacing:2px;background:var(--rust);color:var(--char);padding:3px 8px}
        .thcard p{margin:0;font-size:15px;line-height:1.5;color:var(--bone)}
        .thimgs{display:grid;grid-template-columns:1fr 1fr;gap:8px}
        .thimgs figure{margin:0}
        .thimgs img{width:100%;display:block;border:1px solid var(--line)}
        .thimgs figcaption{font-size:12px;letter-spacing:1px;text-transform:uppercase;color:var(--ash);margin-top:4px}
        .thcard .btn{font-size:16px;padding:12px 18px}
        .thbar{margin:18px 0 0;display:flex;gap:16px;align-items:center;flex-wrap:wrap}
        .thbar p{margin:0;font-size:14px;color:var(--ash);flex:1;min-width:260px}
      </style>
      <div class="thgrid">${PACKS.map(p => `<section class="thcard${p.id === active ? ' on' : ''}">
        <h3>${E(p.name())}${p.id === active ? `<span>${E(T('cfg.x.th.active', 'IN USE'))}</span>` : ''}</h3>
        ${shots(p)}
        <p>${E(p.desc())}</p>
        <button class="btn primary" data-th="use" data-pack="${p.id}"${p.id === active ? ' disabled' : ''}>${E(T('cfg.x.th.use', 'Use this theme'))}</button>
      </section>`).join('')}</div>
      <div class="thbar"><button class="btn" data-th="refresh">${E(T('cfg.x.th.refresh', 'Refresh UI for everyone'))}</button>
      <p>${E(T('cfg.x.th.refresh_h', 'Players with a UI open reload its styles now. No resource restart needed. Admin action, logged.'))}</p></div>`;
  }

  async function act(action, pack) {
    const r = await rpc(action, pack);
    if (!r || !r.ok) { ui().toast((r && r.error) || T('cfg.x.th.fail', 'Theme action failed.'), true); return; }
    st = r; draw();
    ui().toast(action === 'refresh' ? T('cfg.x.th.refreshed', 'UI refreshed for everyone.') : T('cfg.x.th.saved', 'Theme changed.'));
  }

  document.addEventListener('click', e => {
    const b = e.target.closest('[data-th]');
    if (!b || !main || !main.contains(b)) return;
    if (b.dataset.th === 'use') act('set', b.dataset.pack);
    else if (b.dataset.th === 'refresh') act('refresh');
  });

  async function render(m) {
    main = m;
    const r = await rpc('get');
    if (!r || !r.ok) { m.innerHTML = `<div class="empty">${E((r && r.error) || T('cfg.x.th.fail', 'Theme action failed.'))}</div>`; return; }
    st = r; draw();
  }

  window.BSConfigExt = (window.BSConfigExt || []).concat([{ id: 'themes', label: 'Themes & UI', render }]);
})();

// bs_darkzone HUD: zone, timer, bag, rank, heli and walk-out countdowns.
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (s) => { s = Math.max(0, Math.floor(s || 0)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return h ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}:${String(s % 60).padStart(2, '0')}`; };
  const fill = (str, vars) => String(str || '').replace(/\{(\w+)\}/g, (_, k) => (vars && vars[k] != null ? vars[k] : ''));

  const S = { T: {}, state: null, inside: false, bag: null, prog: null, heli: null, walk: null, leftAt: 0 };
  let xpTimer = null;

  function draw() {
    const el = $('dz');
    const st = S.state;
    const hasBag = S.bag && S.bag.stacks > 0;
    if (!st || (!S.inside && !hasBag && S.heli == null)) { el.classList.add('hide'); return; }
    const T = S.T;
    const left = Math.max(0, (S.leftAt - Date.now()) / 1000);
    let h = `<h4>${esc(fill(T.title, { zone: st.zone }))}</h4>`;
    if (S.inside) h += `<div class="l in">${esc(T.inside)}</div>`;
    h += `<div class="l dim">${esc(fill(T.moves, { time: fmt(left) }))}</div>`;
    if (S.bag) {
      h += `<div class="l">${esc(fill(T.bag, { n: S.bag.stacks, kg: S.bag.weight, max: S.bag.max }))}</div>`;
      h += `<div class="bar"><i style="width:${Math.min(100, (S.bag.weight / Math.max(1, S.bag.max)) * 100)}%"></i></div>`;
      if (hasBag) h += `<div class="l dim">${esc(S.bag.walkOk ? T.walkOk : T.walkBig)}</div>`;
    }
    if (S.prog) {
      const span = S.prog.nextXp ? (S.prog.xp - S.prog.baseXp) / Math.max(1, S.prog.nextXp - S.prog.baseXp) : 1;
      h += `<div class="l">${esc(fill(T.rank, { rank: S.prog.title, xp: S.prog.xp }))}</div><div class="bar g"><i style="width:${Math.min(100, span * 100)}%"></i></div>`;
    }
    if (S.heli != null) h += `<div class="l warn">${esc(fill(T.heli, { s: S.heli }))}</div>`;
    if (S.walk) h += `<div class="l warn">${esc(fill(T.walk, { s: S.walk.left }))}</div><div class="bar g"><i style="width:${100 - Math.min(100, (S.walk.left / Math.max(1, S.walk.total)) * 100)}%"></i></div>`;
    if (hasBag) h += `<div class="l dim">${esc(T.hint)}</div>`;
    el.innerHTML = h;
    el.classList.remove('hide');
  }

  window.addEventListener('message', (e) => {
    const m = e.data || {};
    const d = m.data;
    switch (m.action) {
      case 'labels': S.T = d || {}; break;
      case 'state': S.state = d; if (d) S.leftAt = Date.now() + (d.leftMs || 0); break;
      case 'inside': S.inside = !!d; break;
      case 'bag': S.bag = d; break;
      case 'prog': S.prog = d; break;
      case 'heli': S.heli = d ? d.left : null; break;
      case 'heliLeft': S.heli = d; break;
      case 'walk': S.walk = d ? { left: d.left, total: d.left } : null; break;
      case 'walkLeft': if (S.walk) { S.walk.left = d.left; S.walk.total = d.total; } break;
      case 'xp': {
        const x = $('xp'); x.textContent = fill(S.T.xp, { n: d }); x.classList.remove('hide');
        clearTimeout(xpTimer); xpTimer = setTimeout(() => x.classList.add('hide'), 2500);
        break;
      }
      default: return;
    }
    draw();
  });
  setInterval(draw, 1000);
})();

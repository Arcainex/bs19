// bs_operations NUI: status panel, mission tracker, mission board, panel wire puzzle.
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = (name, data) => fetch(`https://${GetParentResourceName()}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).then((r) => r.json()).catch(() => ({}));
  const fmt = (s) => { s = Math.max(0, Math.floor(s || 0)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

  function status(lines) {
    const el = $('status');
    if (!lines || !lines.length) { el.innerHTML = ''; return; }
    let html = '', open = false;
    for (const l of lines) {
      if (l.h) { if (open) html += '</div>'; html += `<div class="panel"><h4>${esc(l.h)}</h4>`; open = true; continue; }
      if (!open) { html += '<div class="panel">'; open = true; }
      if (l.bar !== undefined) html += `<div class="l">${esc(l.t)}</div><div class="bar"><i style="width:${Math.min(100, Math.max(0, l.bar * 100))}%"></i></div>`;
      else html += `<div class="l${l.warn ? ' warn' : ''}${l.dim ? ' dim' : ''}">${esc(l.t)}</div>`;
    }
    if (open) html += '</div>';
    el.innerHTML = html;
  }

  let trackT = null, trackLeftAt = 0;
  function track(t) {
    trackT = t;
    const el = $('track');
    if (!t) { el.classList.add('hide'); return; }
    trackLeftAt = Date.now();
    el.classList.remove('hide');
    drawTrack();
  }
  function drawTrack() {
    const t = trackT; if (!t) return;
    let prog = '';
    if (t.target > 1) prog = `<div class="bar"><i style="width:${Math.min(100, (t.progress / t.target) * 100)}%"></i></div><div class="l dim">${esc(t.progress)} / ${esc(t.target)}</div>`;
    let left = '';
    if (t.left != null) left = `<div class="l">${fmt(t.left - (Date.now() - trackLeftAt) / 1000)}</div>`;
    $('track').innerHTML = `<div class="panel"><h4>${esc(t.title)}</h4><div class="tier">${esc(t.step)} / ${esc(t.steps)}</div><div class="l">${esc(t.text)}</div>${prog}${left}</div>`;
  }
  setInterval(() => { if (trackT && trackT.left != null) drawTrack(); }, 1000);

  let B = null;
  function board(d) {
    B = d;
    const L = d.labels;
    const rew = (r) => { r = r || {}; const p = []; if (r.xp) p.push(`${r.xp} XP`); if (r.money) p.push(`$${r.money}`); if (r.rep) p.push(`+${r.rep} ${L.rep || ''}`); (r.items || []).forEach((i) => p.push(`${i.amount}x ${i.item}`)); return p.join(' · '); };
    const rows = (d.list || []).map((c) => `<div class="ch">
      <div><span class="t">${esc(c.title)}</span><span class="tg">${esc(c.tierLabel)}</span>${c.done ? `<span class="tg">${esc(L.done)} ${c.done}</span>` : ''}</div>
      <div class="d">${esc(c.desc)}</div>
      <ol>${c.steps.map((s) => `<li>${esc(s)}</li>`).join('')}</ol>
      <div class="row"><span>${esc(L.reward)}: ${esc(rew(c.reward))}</span>
      ${c.active ? `<button data-op="abandon">${esc(L.abandon)}</button>` : c.locked ? `<span class="lk">${esc(c.locked)}</span>` : `<button data-op="accept" data-id="${esc(c.id)}" ${d.busy ? 'disabled' : ''}>${esc(L.accept)}</button>`}</div></div>`).join('');
    $('board').innerHTML = `<div class="box"><h2>${esc(L.title)}</h2>${rows || '<div class="d">-</div>'}<div class="foot"><button data-op="close">${esc(L.close)}</button></div></div>`;
    $('board').classList.remove('hide');
  }
  function closeBoard() { $('board').classList.add('hide'); B = null; }

  $('board').addEventListener('click', async (e) => {
    const b = e.target.closest('button[data-op]'); if (!b) return;
    const op = b.dataset.op;
    if (op === 'close') { closeBoard(); post('board', { op: 'close' }); return; }
    b.disabled = true;
    const r = await post('board', { op, id: b.dataset.id });
    if (r && r.ok) closeBoard(); else b.disabled = false;
  });

  // Wire puzzle: match each left wire to the same colour on the right.
  const COLORS = ['#d94141', '#4199d9', '#e3c23b', '#4bbf5a'];
  let PZ = null;
  function puzzle(d) {
    const right = COLORS.map((c, i) => i).sort(() => Math.random() - 0.5);
    PZ = { sel: null, done: 0 };
    $('puzzle').innerHTML = `<div class="box"><h3>${esc(d.title)}</h3><p>${esc(d.hint)}</p><div class="wires">
      <div class="col">${COLORS.map((c, i) => `<div class="w" data-s="l" data-i="${i}" style="background:${c}"></div>`).join('')}</div>
      <div class="col">${right.map((i) => `<div class="w" data-s="r" data-i="${i}" style="background:${COLORS[i]}"></div>`).join('')}</div>
      </div><div class="foot"><button data-op="cancel">X</button></div></div>`;
    $('puzzle').classList.remove('hide');
  }
  function endPuzzle(ok) { $('puzzle').classList.add('hide'); PZ = null; post('puzzle', { ok }); }
  $('puzzle').addEventListener('click', (e) => {
    if (e.target.closest('button[data-op="cancel"]')) return endPuzzle(false);
    const w = e.target.closest('.w'); if (!w || !PZ || w.classList.contains('ok')) return;
    if (w.dataset.s === 'l') { document.querySelectorAll('#puzzle .w.sel').forEach((x) => x.classList.remove('sel')); w.classList.add('sel'); PZ.sel = w; return; }
    if (!PZ.sel) return;
    if (PZ.sel.dataset.i === w.dataset.i) {
      PZ.sel.classList.remove('sel'); PZ.sel.classList.add('ok'); w.classList.add('ok'); PZ.sel = null; PZ.done++;
      if (PZ.done >= COLORS.length) setTimeout(() => endPuzzle(true), 250);
    } else { PZ.sel.classList.remove('sel'); PZ.sel = null; }
  });

  window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (B) { closeBoard(); post('board', { op: 'close' }); }
    if (PZ) endPuzzle(false);
  });

  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'status') status(m.data);
    else if (m.action === 'track') track(m.data);
    else if (m.action === 'board') board(m.data);
    else if (m.action === 'puzzle') puzzle(m.data);
    else if (m.action === 'close') closeBoard();
  });
})();

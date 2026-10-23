// bs_tutorial page: faction picker, tour overlay, first-spawn offer and mission tracker.
(() => {
  'use strict';
  const RES = 'bs_tutorial';
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
    .then((r) => r.json()).catch(() => ({}));
  let STR = {};
  const t = (k, vars) => { let s = STR[k] || k; if (vars) s = s.replace(/\{(\w+)\}/g, (m, n) => (vars[n] != null ? vars[n] : m)); return s; };
  const applyT = (root) => (root || document).querySelectorAll('[data-t]').forEach((el) => { if (STR[el.dataset.t]) el.textContent = STR[el.dataset.t]; });

  // Small animated icons, one per chapter type.
  const ICONS = {
    heart: '<path class="pulse" d="M32 52 C12 38 8 28 14 20 C20 12 28 15 32 22 C36 15 44 12 50 20 C56 28 52 38 32 52Z"/><polyline class="dash" points="8,34 22,34 26,26 32,42 36,30 40,34 56,34"/>',
    bag: '<rect class="bob" x="16" y="20" width="32" height="34" rx="4"/><path d="M24 20 V14 H40 V20"/><line x1="16" y1="34" x2="48" y2="34"/>',
    skull: '<g class="bob"><path d="M18 34 C14 16 50 16 46 34 L44 42 H20Z"/><circle cx="26" cy="32" r="4"/><circle cx="38" cy="32" r="4"/><path d="M24 42 V50 H40 V42"/></g>',
    cross: '<path class="pulse" d="M26 12 H38 V26 H52 V38 H38 V52 H26 V38 H12 V26 H26Z"/>',
    fuel: '<rect x="14" y="14" width="22" height="38" rx="2"/><rect x="18" y="18" width="14" height="10"/><path class="dash" d="M36 22 H44 V44 C44 48 50 48 50 44 V26"/>',
    gear: '<g class="spin"><circle cx="32" cy="32" r="8"/><path d="M32 12 V18 M32 46 V52 M12 32 H18 M46 32 H52 M18 18 L22 22 M42 42 L46 46 M46 18 L42 22 M22 42 L18 46"/></g>',
    flag: '<line x1="18" y1="10" x2="18" y2="54"/><path class="bob" d="M18 12 H48 L42 22 L48 32 H18"/>',
    hammer: '<g class="bob"><path d="M14 20 H38 V30 H14Z"/><line x1="30" y1="30" x2="48" y2="52"/></g>',
    coin: '<g class="spin"><circle cx="32" cy="32" r="18"/><path d="M32 22 V42 M27 27 H36 C40 27 40 32 32 32 C24 32 24 37 28 37 H37"/></g>',
    shield: '<path class="pulse" d="M32 10 L50 18 V32 C50 44 42 50 32 54 C22 50 14 44 14 32 V18Z"/><polyline points="24,32 30,38 41,26"/>',
    drop: '<g class="bob"><path d="M14 26 C14 12 50 12 50 26Z"/><line x1="16" y1="26" x2="28" y2="40"/><line x1="48" y1="26" x2="36" y2="40"/><rect x="26" y="40" width="12" height="12"/></g>',
    sliders: '<line x1="14" y1="18" x2="50" y2="18"/><line x1="14" y1="32" x2="50" y2="32"/><line x1="14" y1="46" x2="50" y2="46"/><circle class="bob" cx="24" cy="18" r="4"/><circle cx="40" cy="32" r="4" class="pulse"/><circle cx="30" cy="46" r="4"/>',
    info: '<circle cx="32" cy="32" r="20" class="pulse"/><line x1="32" y1="28" x2="32" y2="44"/><circle cx="32" cy="21" r="1.5"/>',
  };
  const icon = (k) => `<svg viewBox="0 0 64 64">${ICONS[k] || ICONS.info}</svg>`;

  // Soft ambient bed made in the browser, no audio file needed.
  let audio = null;
  function ambient(on, vol) {
    if (!on) { if (audio) { const a = audio; audio = null; a.g.gain.linearRampToValueAtTime(0, a.ctx.currentTime + 1); setTimeout(() => a.ctx.close(), 1200); } return; }
    if (audio || !vol) return;
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const g = ctx.createGain(); g.gain.value = 0; g.connect(ctx.destination);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 520; lp.connect(g);
    [55, 82.4, 110.2, 164.8].forEach((f, i) => {
      const o = ctx.createOscillator(); o.type = i % 2 ? 'triangle' : 'sine'; o.frequency.value = f; o.detune.value = (i - 1.5) * 6;
      const og = ctx.createGain(); og.gain.value = 0.18 / (i + 1);
      const lfo = ctx.createOscillator(); lfo.frequency.value = 0.05 + i * 0.03; const lg = ctx.createGain(); lg.gain.value = 0.06 / (i + 1);
      lfo.connect(lg); lg.connect(og.gain); o.connect(og); og.connect(lp); o.start(); lfo.start();
    });
    g.gain.linearRampToValueAtTime(vol, ctx.currentTime + 3);
    audio = { ctx, g };
  }

  // ---------------------------------------------------------------- picker
  const PK = { cards: [], sel: null, busy: false };
  function drawPicker() {
    $('pkCards').innerHTML = PK.cards.map((c) => `<div class="pk-card ${PK.sel === c.id ? 'on' : ''}" data-pk="${esc(c.id)}" style="--c:${esc(c.colour || '')}">
      ${c.bonus ? `<span class="bonus">${esc(t('pick.bonus', { cash: PK.bonusCash, xp: PK.bonusXp }))}</span>` : ''}
      <h3>${esc(c.name)}</h3><div class="d">${esc(c.desc)}</div>
      <ul>${c.perks.filter(Boolean).map((p) => `<li>${esc(p)}</li>`).join('')}</ul>
      <div class="jobs"><b>${esc(t('pick.jobs'))}:</b> ${esc(c.jobs)}</div>
      <div class="mem">${esc(t('pick.members'))}: <b>${Number(c.members) || 0}</b></div></div>`).join('');
  }
  function select(id) { if (PK.sel === id) return; PK.sel = id; drawPicker(); post('pickSelect', { id }); }

  // ---------------------------------------------------------------- tour
  const TR = { chapters: [], done: {}, idx: 1, seconds: 24, timer: null, start: 0 };
  function drawList() {
    $('chList').innerHTML = TR.chapters.map((c, i) => `<li data-ch="${i + 1}" class="${TR.idx === i + 1 ? 'on' : ''}"><span class="ck">${TR.done[c.id] ? '&#10003;' : ''}</span><span class="n">${i + 1}</span>${esc(c.title)}</li>`).join('');
  }
  function drawChapter() {
    const c = TR.chapters[TR.idx - 1]; if (!c) return;
    $('tourEnd').classList.add('hidden');
    $('capIcon').innerHTML = icon(c.icon);
    $('capNum').textContent = t('tut.chapter_n', { n: TR.idx, total: TR.chapters.length });
    $('capTitle').textContent = c.title;
    $('capLines').innerHTML = (c.lines || []).filter((l) => l).map((l) => `<p>${esc(l)}</p>`).join('');
    $('capKeys').innerHTML = (c.keys || []).map((k) => `<span><kbd>${esc(k.key)}</kbd>${esc(k.label)}</span>`).join('');
    const cap = document.querySelector('.caption'); cap.style.animation = 'none'; void cap.offsetWidth; cap.style.animation = '';
    TR.start = Date.now();
    clearInterval(TR.timer);
    TR.timer = setInterval(() => { $('capBar').style.width = Math.min(100, ((Date.now() - TR.start) / (TR.seconds * 1000)) * 100) + '%'; }, 100);
    drawList();
  }

  // ---------------------------------------------------------------- input
  document.addEventListener('click', (e) => {
    const pk = e.target.closest('[data-pk]'); if (pk) return select(pk.dataset.pk);
    const ch = e.target.closest('[data-ch]'); if (ch) return post('tourGo', { index: Number(ch.dataset.ch) });
    const id = e.target.id;
    if (id === 'pkGo') {
      if (!PK.sel || PK.busy) return; PK.busy = true; $('pkErr').textContent = '';
      post('pickConfirm', { id: PK.sel }).then((r) => { PK.busy = false; if (!r || !r.ok) $('pkErr').textContent = (r && r.error) || t('pick.failed'); });
    }
    if (id === 'tPrev') post('tourGo', { dir: 'prev' });
    if (id === 'tNext') post('tourGo', { dir: 'next' });
    if (id === 'tExit' || id === 'eExit') post('tourExit');
    if (id === 'eAgain') post('tourGo', { index: 1 });
    if (id === 'eMission') post('tourMission');
    if (id === 'oYes') post('offerAnswer', { yes: true });
    if (id === 'oSkip') post('offerAnswer', { yes: false });
  });

  document.addEventListener('keydown', (e) => {
    if (!$('tour').classList.contains('hidden')) {
      if (e.key === 'Escape') post('tourExit');
      else if (e.key === 'ArrowRight' || e.key === 'd') post('tourGo', { dir: 'next' });
      else if (e.key === 'ArrowLeft' || e.key === 'a') post('tourGo', { dir: 'prev' });
    } else if (!$('picker').classList.contains('hidden')) {
      const i = PK.cards.findIndex((c) => c.id === PK.sel);
      if (e.key === 'ArrowRight') select(PK.cards[(i + 1) % PK.cards.length].id);
      if (e.key === 'ArrowLeft') select(PK.cards[(i - 1 + PK.cards.length) % PK.cards.length].id);
      if (e.key === 'Enter') $('pkGo').click();
    } else if (!$('offer').classList.contains('hidden') && e.key === 'Escape') {
      post('offerAnswer', { yes: false });
    }
  });

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.strings) STR = d.strings;
    switch (d.action) {
      case 'picker':
        $('picker').classList.toggle('hidden', !d.show);
        if (d.show) {
          PK.cards = d.cards || []; PK.bonusCash = d.bonusCash; PK.bonusXp = d.bonusXp; PK.sel = null;
          applyT($('picker')); $('pkErr').textContent = '';
          document.querySelector('.pk-head p').textContent = t('pick.sub');
          if (PK.cards[0]) { PK.sel = PK.cards[0].id; } drawPicker();
        }
        break;
      case 'tour':
        $('tour').classList.toggle('hidden', !d.show);
        if (d.show) {
          TR.chapters = d.chapters || []; TR.done = d.done || {}; applyT($('tour'));
          $('tourEnd').querySelector('p').textContent = t('tut.end_text');
          $('eMission').classList.toggle('hidden', !d.mission);
          ambient(true, Number(d.ambient) || 0);
        } else { clearInterval(TR.timer); ambient(false); }
        break;
      case 'chapter': TR.idx = d.index; TR.seconds = d.seconds || 24; drawChapter(); break;
      case 'done': TR.done = d.done || TR.done; drawList(); break;
      case 'tourEnd': TR.done = d.done || TR.done; clearInterval(TR.timer); drawList(); $('tourEnd').classList.remove('hidden'); break;
      case 'offer':
        $('offer').classList.toggle('hidden', !d.show);
        if (d.show) { applyT($('offer')); $('offer').querySelector('p').textContent = t('offer.text'); }
        break;
      case 'mission':
        $('mission').classList.toggle('hidden', !d.show);
        if (d.show) {
          applyT($('mission'));
          $('mLoot').classList.toggle('ok', !!d.loot); $('mCraft').classList.toggle('ok', !!d.craft);
          $('mKill').textContent = t('mis.kill', { n: Math.min(d.kills, d.need), need: d.need });
          $('mKill').classList.toggle('ok', d.kills >= d.need);
          $('mDone').classList.toggle('hidden', !d.done);
        }
        break;
      default: break;
    }
  });
})();

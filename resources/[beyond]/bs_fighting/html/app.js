// bs_fighting HUD. Lua sends prefs/combo/flash/style/active, nothing goes back.
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const root = $('fight'), style = $('style'), combo = $('combo'), flash = $('flash');
  const ICONS = {
    fist: 'M7 9V6a1.5 1.5 0 0 1 3 0v3V5a1.5 1.5 0 0 1 3 0v4V6a1.5 1.5 0 0 1 3 0v4a1.5 1.5 0 0 1 3 0v4a6 6 0 0 1-6 6h-1a6 6 0 0 1-6-6V9z',
    glove: 'M6 10a5 5 0 0 1 10 0v2h1a2 2 0 0 1 0 4h-1v2H6z M6 18h10v3H6z',
    bottle: 'M10 2h4v4l2 3v13H8V9l2-3z',
    knife: 'M3 21l9-9 2 2-9 9z M12 12l8-9 1 1-7 10z',
    wave: 'M2 15c3-5 6-5 9 0s6 5 9 0 M2 9c3-5 6-5 9 0s6 5 9 0',
    hand: 'M5 13l8-8 2 2-6 6h10v3H8z',
    knee: 'M8 2l3 8-2 6 4 6h-3l-4-6 2-6-3-7z',
    grip: 'M4 12a8 8 0 1 0 16 0 8 8 0 0 0-16 0zm4 0a4 4 0 1 0 8 0 4 4 0 0 0-8 0z',
  };
  const svg = (d) => `url("data:image/svg+xml,${encodeURIComponent(`<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='${d}'/></svg>`)}")`;
  // impact sound: a short low thump plus a noise slap, built with WebAudio so no files are needed
  let ctx = null;
  function thump(strength, vol) {
    try {
      ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
      const t = ctx.currentTime, g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(Math.max(0.001, vol * (0.45 + strength * 0.55)), t + 0.008);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16 + strength * 0.14);
      g.connect(ctx.destination);
      const o = ctx.createOscillator();
      o.type = 'sine';
      o.frequency.setValueAtTime(120 - strength * 40, t);
      o.frequency.exponentialRampToValueAtTime(45, t + 0.15);
      o.connect(g); o.start(t); o.stop(t + 0.32);
      const len = Math.floor(ctx.sampleRate * 0.06), buf = ctx.createBuffer(1, len, ctx.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 3);
      const n = ctx.createBufferSource(), f = ctx.createBiquadFilter(), ng = ctx.createGain();
      f.type = 'lowpass'; f.frequency.value = 900 + strength * 900; ng.gain.value = vol * 0.6;
      n.buffer = buf; n.connect(f); f.connect(ng); ng.connect(ctx.destination); n.start(t);
    } catch (e) { /* no audio, no problem */ }
  }
  let prefs = { mode: 'minimal' }, active = false, comboT = 0, styleT = 0, sticky = false;

  function setMode() { root.className = 'fight mode-' + (prefs.mode || 'minimal'); }
  function showStyle(on) { style.classList.toggle('show', on); }

  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'prefs') { prefs = m.prefs || prefs; setMode(); if (prefs.mode === 'full' && active) showStyle(true); }
    else if (m.action === 'active') {
      active = !!m.on;
      if (prefs.mode === 'full') showStyle(active);
      else if (!active) showStyle(false);
    }
    else if (m.action === 'style') {
      $('styleName').textContent = m.label || '';
      style.style.setProperty('--icon', svg(ICONS[m.icon] || ICONS.fist));
      sticky = !!m.sticky; style.classList.toggle('sticky', sticky);
      showStyle(true);
      clearTimeout(styleT);
      if (prefs.mode !== 'full') styleT = setTimeout(() => showStyle(false), 2200);
    }
    else if (m.action === 'combo') {
      const n = Number(m.n) || 0;
      const min = prefs.mode === 'full' ? 1 : 2;
      clearTimeout(comboT);
      if (n < min) { combo.classList.remove('show'); return; }
      $('comboN').textContent = n;
      combo.classList.add('show');
      combo.classList.remove('pop'); void combo.offsetWidth; combo.classList.add('pop');
      comboT = setTimeout(() => combo.classList.remove('show'), 1400);
    }
    else if (m.action === 'charge') {
      const c = $('charge');
      if (m.v === null || m.v === undefined) { c.classList.remove('show', 'full'); return; }
      $('chargeBar').style.width = Math.round(Math.max(0, Math.min(1, m.v)) * 100) + '%';
      c.classList.add('show'); c.classList.toggle('full', m.v >= 0.99);
    }
    else if (m.action === 'prompt') {
      const p = $('prompt');
      p.textContent = m.text || '';
      p.classList.toggle('show', !!m.text);
    }
    else if (m.action === 'impact') { thump(Number(m.s) || 0.5, Number(m.vol) || 0.6); }
    else if (m.action === 'flash') {
      flash.className = 'fflash k-' + (m.kind || 'block');
      flash.textContent = m.label || '';
      void flash.offsetWidth; flash.classList.add('go');
    }
  });
})();

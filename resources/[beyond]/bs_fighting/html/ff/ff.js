// bs_fighting v3 HUD. Lua sends prefs/combo/counter/finisher/flash/impact; nothing goes back.
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const root = $('ff'), combo = $('combo'), counter = $('counter'), flash = $('flash');
  let prefs = { mode: 'minimal' }, comboT = 0, counterT = 0;
  let ctx = null;
  // short low thump, built with WebAudio so no sound files are needed
  function thump(strength, vol) {
    try {
      ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
      const t = ctx.currentTime, g = ctx.createGain(), o = ctx.createOscillator();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(Math.max(0.001, vol * (0.45 + strength * 0.55)), t + 0.008);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16 + strength * 0.14);
      g.connect(ctx.destination);
      o.type = 'sine';
      o.frequency.setValueAtTime(120 - strength * 40, t);
      o.frequency.exponentialRampToValueAtTime(45, t + 0.15);
      o.connect(g); o.start(t); o.stop(t + 0.32);
    } catch (e) { /* no audio */ }
  }
  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'prefs') {
      prefs = m.prefs || prefs;
      root.className = 'ff mode-' + (prefs.mode || 'minimal');
      const l = m.labels || {};
      if (l.hits) $('hitsLabel').textContent = l.hits;
      if (l.counter) $('counterLabel').textContent = l.counter;
      if (l.finisher) $('finLabel').textContent = l.finisher;
      if (l.locked) $('lockLabel').textContent = l.locked;
    } else if (m.action === 'combo') {
      const n = Number(m.n) || 0;
      clearTimeout(comboT);
      if (n < (prefs.mode === 'full' ? 1 : 2)) { combo.classList.remove('show'); return; }
      $('comboN').textContent = n;
      combo.classList.add('show');
      combo.classList.toggle('hot', n >= 5);
      combo.classList.remove('pop'); void combo.offsetWidth; combo.classList.add('pop');
      comboT = setTimeout(() => combo.classList.remove('show'), 2500);
    } else if (m.action === 'counter') {
      clearTimeout(counterT);
      counter.classList.remove('run');
      if (!m.on) { counter.classList.remove('show'); return; }
      $('counterKey').textContent = m.key || 'E';
      counter.style.setProperty('--ms', Math.max(50, Number(m.ms) || 450) + 'ms');
      counter.classList.add('show');
      void counter.offsetWidth; counter.classList.add('run');
      counterT = setTimeout(() => counter.classList.remove('show', 'run'), Math.max(50, Number(m.ms) || 450) + 80);
    } else if (m.action === 'locked') {
      $('locked').classList.toggle('show', !!m.on);
    } else if (m.action === 'finisher') {
      $('finisher').classList.toggle('show', !!m.on);
    } else if (m.action === 'flash') {
      flash.className = 'ffflash k-' + (m.kind || 'counter');
      flash.textContent = m.label || '';
      void flash.offsetWidth; flash.classList.add('go');
    } else if (m.action === 'impact') {
      thump(Number(m.s) || 0.5, Number(m.vol) || 0.6);
    }
  });
})();

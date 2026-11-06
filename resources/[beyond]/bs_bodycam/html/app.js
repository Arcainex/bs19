// Bodycam overlay. Lua sends show/hide only; the clock runs here.
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const root = $('cam');
  const pad = (n) => String(n).padStart(2, '0');
  let timer = null;

  function tick() {
    const d = new Date();
    $('date').textContent = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    $('time').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  function show(d) {
    const film = Math.max(0, Math.min(1, Number(d.film)));
    root.style.setProperty('--film', String(Number.isFinite(film) ? film : 0.5));
    root.classList.toggle('nofringe', d.chroma === false);
    root.classList.toggle('nostamp', d.stamp === false);
    $('label').textContent = String(d.label || 'BS19 CAM');
    $('unit').textContent = String(d.unit || '');
    const wasHidden = root.classList.contains('hidden');
    root.classList.remove('hidden');
    if (wasHidden) { root.style.animation = 'none'; void root.offsetWidth; root.style.animation = ''; }
    if (d.stamp !== false && !timer) { tick(); timer = setInterval(tick, 1000); }
    if (d.stamp === false && timer) { clearInterval(timer); timer = null; }
  }

  function hide() {
    root.classList.add('hidden');
    if (timer) { clearInterval(timer); timer = null; }
  }

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'show') show(d);
    else if (d.action === 'hide') hide();
  });
})();

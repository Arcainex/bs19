// Drug HUD: Lua sends the list on change, we count down once per second.
const ICONS = {
  cocaine: '<path d="M4 18h16M6 14l6-8 6 8"/>',
  morphine: '<path d="M14 4l6 6M17 7L8 16l-3 3M10 10l4 4M5 19l-1 1"/>',
  amphetamine: '<rect x="4" y="9" width="16" height="6" rx="3"/><path d="M12 9v6"/>',
  weed: '<path d="M12 21V11M12 11C12 6 9 3 9 3s3 3 3 8zm0 0c0-5 3-8 3-8s-3 3-3 8zM12 13l-6-3M12 13l6-3"/>',
  cigarette: '<path d="M3 15h14v3H3zM19 15v3M21 15v3M18 12c0-2 2-2 2-4"/>',
};
const WD = ['', 'Withdrawal // mild', 'Withdrawal // heavy', 'Withdrawal // severe'];
const hud = document.getElementById('hud');
const listEl = document.getElementById('list');
const wdEl = document.getElementById('wd');
let items = [], timer = null;

const fmt = s => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

function render() {
  listEl.innerHTML = items.map(i => `
    <div class="item${i.left <= 15 ? ' low' : ''}" data-d="${esc(i.drug)}">
      <div class="row"><svg viewBox="0 0 24 24">${ICONS[i.drug] || '<circle cx="12" cy="12" r="6"/>'}</svg>
        <span class="name">${esc(i.label)}<span class="q ${esc(i.q)}">${esc(i.ql)}</span></span>
        <span class="time">${fmt(i.left)}</span></div>
      <div class="bar"><div class="fill" style="width:${Math.max(0, Math.min(100, i.left / Math.max(1, i.dur) * 100))}%"></div></div>
    </div>`).join('');
}

function tick() {
  items.forEach(i => { i.left = Math.max(0, i.left - 1); });
  items = items.filter(i => i.left > 0);
  // Update in place so the slide-in anim does not replay.
  items.forEach(i => {
    const el = listEl.querySelector(`[data-d="${CSS.escape(i.drug)}"]`);
    if (!el) return;
    el.querySelector('.time').textContent = fmt(i.left);
    el.querySelector('.fill').style.width = `${Math.max(0, i.left / Math.max(1, i.dur) * 100)}%`;
    el.classList.toggle('low', i.left <= 15);
  });
  listEl.querySelectorAll('.item').forEach(el => { if (!items.some(i => i.drug === el.dataset.d)) el.remove(); });
  update();
}

function update() {
  const show = items.length > 0 || !wdEl.classList.contains('hidden');
  hud.classList.toggle('hidden', !show);
  if (items.length && !timer) timer = setInterval(tick, 1000);
  if (!items.length && timer) { clearInterval(timer); timer = null; }
}

window.addEventListener('message', e => {
  const d = e.data;
  if (!d || d.action !== 'drugs') return;
  items = Array.isArray(d.list) ? d.list : [];
  const w = d.withdrawal | 0;
  wdEl.textContent = WD[w] || '';
  wdEl.classList.toggle('hidden', !WD[w]);
  render();
  update();
});

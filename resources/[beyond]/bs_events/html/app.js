// Radio popup: crackle-in, typewriter body, auto tune-out.
(function () {
  const box = document.getElementById('radio');
  const $ = (id) => document.getElementById(id);
  let typing = null, hideT = null, outT = null;

  function garble(ch) {
    return Math.random() < 0.06 ? '#%&*/'[Math.floor(Math.random() * 5)] : ch;
  }

  function type(el, text, speed) {
    clearInterval(typing);
    el.textContent = '';
    let i = 0;
    typing = setInterval(() => {
      if (i >= text.length) { clearInterval(typing); el.textContent = text; return; }
      // a crackly char first, then the real one
      el.textContent = text.slice(0, i) + garble(text[i]);
      i++;
    }, speed);
  }

  function show(m) {
    clearTimeout(hideT); clearTimeout(outT);
    box.className = m.kind || '';
    $('kind').textContent = (m.kind || '').toUpperCase();
    $('title').textContent = m.title || '';
    $('grid').textContent = m.grid ? t('ui.grid', { g: m.grid }) : '';
    type($('body'), m.body || '', 28);
    const secs = Math.max(4, m.seconds || 16);
    const bar = $('bar');
    bar.style.transition = 'none';
    bar.style.transform = 'scaleX(1)';
    void bar.offsetWidth;
    bar.style.transition = 'transform ' + secs + 's linear';
    bar.style.transform = 'scaleX(0)';
    hideT = setTimeout(() => {
      box.classList.add('out');
      outT = setTimeout(() => box.classList.add('hidden'), 500);
    }, secs * 1000);
  }

  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'radio') show(m);
  });
})();

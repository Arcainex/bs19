/* F10 drag handles. UI-only; no server events or existing tab logic changed. */
(() => {
  const menu = document.querySelector('.menu');
  const rail = menu?.querySelector('.rail');
  const divider = document.getElementById('f10Splitter');
  const corner = document.getElementById('f10Resize');
  if (!menu || !rail || !divider || !corner) return;
  const clamp = (n, min, max) => Math.min(Math.max(n, min), max);
  const get = (key) => { try { return localStorage.getItem(key); } catch (_) { return null; } };
  const put = (key, value) => { try { localStorage.setItem(key, String(value)); } catch (_) {} };
  const minMenuWidth = () => Math.min(520, innerWidth * .96);
  const minMenuHeight = () => Math.min(380, innerHeight * .90);
  const limitWidth = (v) => clamp(v, minMenuWidth(), innerWidth * .98);
  const limitHeight = (v) => clamp(v, minMenuHeight(), innerHeight * .98);
  const applySaved = () => {
    const w = Number(get('bs19_f10_width'));
    const h = Number(get('bs19_f10_height'));
    const r = Number(get('bs19_f10_rail'));
    if (w > 0) menu.style.width = `${limitWidth(w)}px`;
    if (h > 0) menu.style.height = `${limitHeight(h)}px`;
    if (r > 0) menu.style.setProperty('--f10-rail-width', `${clamp(r, 110, Math.max(110, menu.getBoundingClientRect().width - 260))}px`);
  };
  applySaved();
  const drag = (handle, onMove, onEnd) => {
    handle.addEventListener('pointerdown', (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      handle.setPointerCapture(event.pointerId);
      handle.classList.add('is-dragging');
      const startX = event.clientX, startY = event.clientY;
      const rect = menu.getBoundingClientRect();
      const startRail = rail.getBoundingClientRect().width;
      const move = (e) => { if (e.pointerId === event.pointerId) onMove(e.clientX - startX, e.clientY - startY, rect, startRail); };
      const end = (e) => {
        if (e.pointerId !== event.pointerId) return;
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', end);
        handle.removeEventListener('pointercancel', end);
        handle.classList.remove('is-dragging');
        onEnd();
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', end);
      handle.addEventListener('pointercancel', end);
    });
  };
  drag(divider, (dx, _dy, rect, initial) => {
    if (menu.classList.contains('is-narrow') || menu.classList.contains('is-simple')) return;
    menu.style.setProperty('--f10-rail-width', `${clamp(initial + dx, 110, Math.max(110, rect.width - 260))}px`);
  }, () => put('bs19_f10_rail', Math.round(rail.getBoundingClientRect().width)));
  drag(corner, (dx, dy, rect) => {
    menu.style.width = `${limitWidth(rect.width + dx)}px`;
    menu.style.height = `${limitHeight(rect.height + dy)}px`;
    const maxRail = Math.max(110, menu.getBoundingClientRect().width - 260);
    const currentRail = parseFloat(getComputedStyle(menu).getPropertyValue('--f10-rail-width')) || 185;
    menu.style.setProperty('--f10-rail-width', `${clamp(currentRail, 110, maxRail)}px`);
  }, () => {
    const rect = menu.getBoundingClientRect();
    put('bs19_f10_width', Math.round(rect.width));
    put('bs19_f10_height', Math.round(rect.height));
    put('bs19_f10_rail', Math.round(rail.getBoundingClientRect().width));
  });
  window.addEventListener('resize', () => {
    const rect = menu.getBoundingClientRect();
    if (rect.width > innerWidth * .98) menu.style.width = `${limitWidth(rect.width)}px`;
    if (rect.height > innerHeight * .98) menu.style.height = `${limitHeight(rect.height)}px`;
  });
})();

// Isolated read-only F10 building diagnostics.
(() => {
  const out = document.getElementById('bsBuildDebugOutput');
  const refresh = document.getElementById('bsBuildRefresh');
  const copy = document.getElementById('bsBuildCopy');
  if (!out || !refresh || !copy) { console.warn('[BS19] F10 snap debugger controls missing'); return; }
  async function update() {
    out.textContent = 'Lese Snap-Diagnose …';
    try {
      const r = await fetch(`https://${GetParentResourceName()}/buildingDebugRead`, {
        method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
      });
      const d = await r.json();
      if (!d.ok) { out.textContent = `FEHLER: ${d.error || 'Unbekannt'}`; return; }
      const data = d.data || {};
      const state = data.state || {};
      const snap = data.snap || {};
      const events = data.events || [];
      const status = (value) => value === true ? 'JA' : value === false ? 'NEIN' : '–';
      out.textContent = [
        '=== F2 BAUSYSTEM · LIVE-DIAGNOSE ===',
        `Platzierung aktiv: ${status(data.active)} | Magnet: ${status(data.magnet)}`,
        `Phase: ${state.phase || '–'}`,
        `Vorschau aktualisiert: ${status(state.preview)} | Snap angewendet: ${status(state.snapped)}`,
        `ENTER erkannt: ${status(state.enter)}`,
        `Letzte Serverantwort: ${state.server || '–'}`,
        `LETZTER FEHLER: ${state.lastError || '–'}`,
        '', '=== SNAP-RESOLVER ===', JSON.stringify(snap, null, 2),
        '', '=== LETZTE EREIGNISSE (NEUE ZUERST) ===',
        ...events.map(e => `[${(e.time / 1000).toFixed(1)}s] ${e.level === 'error' ? 'FEHLER ' : ''}${e.step}: ${e.detail}`)
      ].join('\n');
    } catch (e) { out.textContent = `FEHLER: ${e.message}`; }
  }
  refresh.addEventListener('click', update);
  copy.addEventListener('click', () => {
    const t = document.createElement('textarea'); t.value = out.textContent;
    document.body.appendChild(t); t.select(); document.execCommand('copy'); t.remove();
  });
})();

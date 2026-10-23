// Scrap panel
(function () {
    const $ = (id) => document.getElementById(id);
    let T = {}, parts = [];

    function drawParts(active) {
        $('scParts').innerHTML = parts.map((p, i) => {
            const cls = p.state || (i === active ? 'active' : '');
            return `<li class="${cls}${p.ruined ? ' ruined' : ''}">${T['part_' + p.id] || p.id}</li>`;
        }).join('');
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'scrapShow') {
            T = d.text || {};
            parts = (d.parts || []).map((p) => ({ id: p.id }));
            $('scTitle').textContent = T.title || '';
            const tool = d.tool || T.no_tool || '';
            $('scMeta').textContent = `${T.tool || ''}: ${tool}  |  ${T.skill || ''}: ${d.skill || 0}`;
            $('scHint').textContent = '';
            drawParts(0);
            $('scrap').classList.remove('hidden');
        } else if (d.action === 'scrapCheck') {
            const c = d.challenge;
            drawParts(c.index - 1);
            $('scName').textContent = T['part_' + c.id] || c.id;
            $('scHint').textContent = (c.mode === 'hold' ? T.hint_hold : T.hint_timing) + '  |  ' + (T.cancel || '');
            $('scZone').style.left = ((c.center - c.zone / 2) * 100) + '%';
            $('scZone').style.width = (c.zone * 100) + '%';
            const pw = c.zone * (c.perfect || 0.25);
            $('scPerfect').style.left = ((c.center - pw / 2) * 100) + '%';
            $('scPerfect').style.width = (pw * 100) + '%';
            $('scMarker').style.left = '0%';
        } else if (d.action === 'scrapPos') {
            $('scMarker').style.left = (Math.max(0, Math.min(1, d.pos)) * 100) + '%';
            $('scTime').textContent = Math.ceil((d.left || 0) / 1000) + 's';
        } else if (d.action === 'scrapResult') {
            const p = parts[d.index - 1];
            if (p) { p.state = d.outcome; p.ruined = !d.salvaged; }
            drawParts(-1);
            $('scName').textContent = (T[d.outcome] || '') + ' - ' + (d.salvaged ? T.salvaged : T.ruined);
        } else if (d.action === 'scrapHide') {
            $('scrap').classList.add('hidden');
        }
    });
})();

// Pump panel
(function () {
    const $ = (id) => document.getElementById(id);
    const CX = 100, CY = 105, R = 80;

    // value 0..1 maps to the half circle, left to right
    function point(v, r) {
        const a = Math.PI * (1 - v);
        return [CX + r * Math.cos(a), CY - r * Math.sin(a)];
    }

    function arc(from, to) {
        from = Math.max(0, Math.min(1, from)); to = Math.max(0, Math.min(1, to));
        const [x1, y1] = point(from, R), [x2, y2] = point(to, R);
        return `M${x1.toFixed(1)} ${y1.toFixed(1)} A${R} ${R} 0 0 1 ${x2.toFixed(1)} ${y2.toFixed(1)}`;
    }

    // tick marks, built once
    (function () {
        let html = '';
        for (let i = 0; i <= 12; i++) {
            const v = i / 12, [x1, y1] = point(v, R - 9), [x2, y2] = point(v, R + 7);
            html += `<line class="tick" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;
        }
        $('ticks').innerHTML = html;
    })();

    function bar(el, frac, cls) {
        el.style.width = (Math.max(0, Math.min(1, frac)) * 100).toFixed(1) + '%';
        if (cls !== undefined) el.className = 'fill ' + cls;
    }

    function text(t) {
        if (!t) return;
        const map = { title: 'title', clamps: 'tClamps', red: 'tRed', black: 'tBlack', battery: 'tBattery',
                      liters: 'tLiters', station: 'tStation', progress: 'tProgress' };
        for (const k in map) if (t[k]) $(map[k]).textContent = t[k];
    }

    let strings = {};

    function render(d) {
        if (d.text) { strings = d.text; text(d.text); }
        $('panel').classList.remove('hidden');
        const jump = d.mode === 'jump';
        $('clampBlock').classList.toggle('hidden', !jump);
        $('progBlock').classList.toggle('hidden', !(jump && d.stage === 'crank'));
        $('litersBlock').classList.toggle('hidden', jump);

        // gauge
        const v = jump ? (d.needle || 0) : (d.pumping ? 0.62 + Math.sin(Date.now() / 90) * 0.02 : 0.05);
        const [nx, ny] = point(v, R - 12);
        $('needle').setAttribute('x2', nx.toFixed(1));
        $('needle').setAttribute('y2', ny.toFixed(1));
        if (d.zone) $('zone').setAttribute('d', arc(d.zone.center - d.zone.width / 2, d.zone.center + d.zone.width / 2));
        else $('zone').setAttribute('d', '');
        $('volts').textContent = (jump ? (d.volts || 0) : (d.pumping ? 12.6 : 0)).toFixed(1);

        // state lamp
        const st = $('state');
        let label = strings.off || 'OFF', cls = 'state';
        if (d.mode === 'fuel') { label = d.powered === 'grid' ? (strings.grid || 'GRID') : (strings.powered || 'BATTERY'); cls = 'state on'; }
        else if (d.stage === 'powered') { label = strings.powered || 'POWERED'; cls = 'state on'; }
        else if (d.stage === 'crank') { label = strings.crank || 'CRANK'; cls = 'state warn'; }
        else label = strings.clamps || 'CLAMPS';
        st.textContent = label; st.className = cls;

        $('ledRed').classList.toggle('on', !!d.red);
        $('ledBlack').classList.toggle('on', !!d.black);

        // battery: charge over capacity, the hatched part is capacity already lost
        if (typeof d.charge === 'number') {
            const cap = typeof d.cap === 'number' ? d.cap : 100;
            $('battBlock').classList.remove('hidden');
            $('battTxt').textContent = `${Math.floor(d.charge)}% / ${Math.floor(cap)}%`;
            bar($('battFill'), d.charge / 100, d.charge < 15 ? 'crit' : d.charge < 35 ? 'low' : 'good');
            $('battCap').style.width = (100 - cap).toFixed(1) + '%';
        } else {
            $('battBlock').classList.toggle('hidden', d.mode === 'fuel');
        }

        if (d.station) {
            $('stationTxt').textContent = `${d.station.label}  ${d.station.fuel} / ${d.station.cap} L`;
            bar($('stationFill'), d.station.fuel / Math.max(1, d.station.cap));
        }
        if (typeof d.liters === 'number') $('liters').textContent = d.liters.toFixed(1).padStart(5, '0');
        if (typeof d.progress === 'number') bar($('progFill'), d.progress);
        $('timeLeft').textContent = typeof d.left === 'number' ? d.left + 's' : '';

        const meta = [];
        if (jump && typeof d.pump === 'number') meta.push(`${strings.pump || 'PUMP'} ${d.pump}%`);
        if (jump && typeof d.skill === 'number') meta.push(`${strings.skill || 'SKILL'} ${d.skill}%`);
        if (jump && d.rain) meta.push(strings.rain || 'RAIN');
        $('meta').textContent = meta.join('  ·  ');
        $('hint').textContent = d.hint || '';
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'pump') render(d);
        else if (d.action === 'pumpHide') $('panel').classList.add('hidden');
    });
})();

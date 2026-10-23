// BeyondSurvival - squad/faction side frames.
// partyhud:roster {rows, more} full row list (sent on change)
// partyhud:live {list} per-member {src, hp, dist, down, oor} deltas
// partyhud:visible {visible}
(() => {
    const root = document.getElementById('partyhud');
    if (!root) return;
    const list = root.querySelector('.partyhud__list');
    const els = new Map();   // src -> {row, fill, ghost, bar, state, dist, live}

    const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    function paint(e) {
        const l = e.live || { oor: true };
        const oor = !!l.oor, down = !!l.down;
        e.row.classList.toggle('is-oor', oor && !down);
        e.row.classList.toggle('is-down', down);
        const hp = oor ? 0 : Math.max(0, Math.min(100, l.hp ?? 100));
        e.fill.style.width = (down ? 0 : hp) + '%';
        e.ghost.style.width = (down ? 0 : hp) + '%';
        e.bar.classList.toggle('is-low', !oor && !down && hp <= 25);
        e.state.textContent = down ? t('ui.party_down', { fallback: 'DOWN' }) : oor ? t('ui.party_oor', { fallback: 'OUT OF RANGE' }) : hp + '%';
        e.dist.textContent = oor || l.dist == null ? '' : l.dist + ' m';
    }

    function build(r) {
        const row = document.createElement('div');
        row.className = 'ph-row ph-row--' + (r.kind === 'squad' ? 'squad' : 'faction');
        row.innerHTML =
            `<div class="ph-top"><span class="ph-tag">${esc(r.tag)}</span>` +
            `<span class="ph-name">${esc(r.name)}</span><span class="ph-lvl">${esc(t('ui.party_lv', { n: r.level, fallback: 'LV ' + r.level }))}</span></div>` +
            `<div class="ph-bar"><div class="ph-ghost"></div><div class="ph-fill"></div></div>` +
            `<div class="ph-meta"><span class="ph-state"></span><span class="ph-dist"></span></div>`;
        return {
            row, bar: row.querySelector('.ph-bar'), fill: row.querySelector('.ph-fill'),
            ghost: row.querySelector('.ph-ghost'), state: row.querySelector('.ph-state'),
            dist: row.querySelector('.ph-dist'), live: { oor: true, down: !!r.down },
        };
    }

    BS.on('partyhud:roster', ({ rows = [], more = 0 }) => {
        const keep = new Set(rows.map((r) => r.src));
        for (const [src, e] of els) {
            if (!keep.has(src)) {
                els.delete(src);
                e.row.classList.add('is-leaving');
                setTimeout(() => e.row.remove(), 260);
            }
        }
        list.querySelectorAll('.ph-sep, .ph-more').forEach((n) => n.remove());
        let lastKind = null;
        const frag = [];
        for (const r of rows) {
            if (r.kind !== lastKind) {
                const sep = document.createElement('div');
                sep.className = 'ph-sep';
                sep.textContent = r.kind === 'squad' ? t('ui.party_squad', { fallback: 'SQUAD' }) : t('ui.party_faction', { fallback: 'FACTION' });
                frag.push(sep);
                lastKind = r.kind;
            }
            let e = els.get(r.src);
            if (e && e.kind !== r.kind) { e.row.remove(); els.delete(r.src); e = null; }
            if (!e) { e = build(r); e.kind = r.kind; els.set(r.src, e); }
            else {
                e.row.querySelector('.ph-tag').textContent = r.tag;
                e.row.querySelector('.ph-name').textContent = r.name;
                e.row.querySelector('.ph-lvl').textContent = t('ui.party_lv', { n: r.level, fallback: 'LV ' + r.level });
            }
            const nm = e.row.querySelector('.ph-name');
            if (/^#[0-9a-f]{6}$/i.test(r.hex || '')) nm.style.color = r.hex; else nm.style.removeProperty('color');
            if (r.down) e.live.down = true;
            paint(e);
            frag.push(e.row);
        }
        if (more > 0) {
            const m = document.createElement('div');
            m.className = 'ph-more';
            m.textContent = t('ui.party_more', { n: more, fallback: '+' + more + ' MORE' });
            frag.push(m);
        }
        frag.forEach((n) => list.appendChild(n));   // appendChild moves existing rows into order
    });

    BS.on('partyhud:live', ({ list: changes = [] }) => {
        for (const l of changes) {
            const e = els.get(l.src);
            if (e) { e.live = l; paint(e); }
        }
    });

    BS.on('partyhud:visible', ({ visible }) => {
        root.classList.toggle('is-on', !!visible);
    });
})();

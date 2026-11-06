(() => {
    const $ = id => document.getElementById(id);
    $('openSurvivorLink').onclick=()=>post('survivorLink');
    const number = value => Math.max(0, Number(value) || 0);
    const percent = value => Math.max(0, Math.min(100, number(value)));
    const lang = () => (window.BSI18n && BSI18n.lang()) || 'en';
    const format = value => Math.floor(number(value)).toLocaleString(lang());
    const T = (key, fallback, vars) => {
        const out = window.BSI18n ? BSI18n.t(key, Object.assign({ fallback }, vars || {})) : fallback;
        return vars ? String(out).replace(/\{(\w+)\}/g, (m, n) => (vars[n] !== undefined ? String(vars[n]) : m)) : out;
    };
    let snapshot = null, lastVitals = null, refreshedAt = null;

    async function post(name) {
        try { await fetch(`https://${GetParentResourceName()}/${name}`, { method: 'POST', body: '{}', headers: { 'Content-Type': 'application/json' } }); } catch (_) {}
    }
    const el = (tag, cls, text) => {
        const node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text !== undefined) node.textContent = text;
        return node;
    };
    const empty = text => el('p', 'sv-empty', text);

    // Same icons and colours as the HUD bars (bs_ui nui.js and UI.Bars).
    const ICON = {
        heart: 'M12 20s-7-4.35-7-9a4 4 0 0 1 7-2.65A4 4 0 0 1 19 11c0 4.65-7 9-7 9z',
        shield: 'M12 3l7 3v5c0 4.4-3 8.3-7 10-4-1.7-7-5.6-7-10V6l7-3z',
        bolt: 'M13 2L4 14h6l-1 8 9-12h-6l1-8z',
        food: 'M7 3v8m0 0a3 3 0 0 0 3-3V3M7 11v10M17 3c-1.5 2-2 4-2 6s.5 3 2 3v9',
        drop: 'M12 3s6 6.5 6 10.5A6 6 0 0 1 6 13.5C6 9.5 12 3 12 3z',
        virus: 'M12 6a6 6 0 1 0 0 12 6 6 0 0 0 0-12zM12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5M17.5 17.5 19 19M19 5l-1.5 1.5M6.5 17.5 5 19',
    };
    const svg = (name, color) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color:${color}"><path d="${ICON[name]}"/></svg>`;
    const BARS = [
        { key: 'health', label: 'Health', icon: 'heart', color: '#b4574a', critical: 25 },
        { key: 'armour', label: 'Armour', icon: 'shield', color: '#5b7d9d' },
        { key: 'stamina', label: 'Stamina', icon: 'bolt', color: '#7fd4a2', critical: 15 },
        { key: 'hunger', label: 'Hunger', icon: 'food', color: '#d99b5b', critical: 20 },
        { key: 'thirst', label: 'Thirst', icon: 'drop', color: '#5bc8d9', critical: 20 },
        { key: 'infection', label: 'Infection', icon: 'virus', color: '#8d6bb0', critical: 1, inverted: true },
    ];
    const nodes = {};
    for (const bar of BARS) {
        const row = el('div', 'sv-bar');
        row.innerHTML = `${svg(bar.icon, bar.color)}<span class="sv-bar__label"></span><span class="sv-bar__track"><i style="background-color:${bar.color}"></i></span><span class="sv-bar__value">-</span>`;
        $('vitals').append(row);
        nodes[bar.key] = { row, label: row.querySelector('.sv-bar__label'), fill: row.querySelector('i'), value: row.querySelector('.sv-bar__value') };
    }

    // Skill glyphs from the inventory Skills tab.
    const GLYPH = { combat: 'M6 3l15 15-3 3L3 6zM3 17l4 4m-2-2 6-6M16 3l5 5-6 6', survival: 'M12 2l8 5-2 12-6 3-6-3L4 7zM8 12l3 3 5-7', crafting: 'M14 3a6 6 0 0 0-7 7L3 18l3 3 8-8a6 6 0 0 0 7-7l-4 4-3-3z', medical: 'M9 3h6v6h6v6h-6v6H9v-6H3V9h6z', lockpicking: 'M6 10h12v11H6zM8 10V6a4 4 0 0 1 8 0v4M12 14v3', fishing: 'M17 3v12a5 5 0 0 1-10 0v-3l3 3M4 3h16' };
    const ORDER = ['combat', 'survival', 'crafting', 'medical', 'lockpicking', 'fishing'];

    const EFFECTS = [
        ['weaponDamage', 'Weapon damage'], ['meleeDamage', 'Melee damage'], ['hungerRate', 'Slower hunger'], ['thirstRate', 'Slower thirst'],
        ['stealth', 'Quieter steps'], ['carryWeight', 'Carry'], ['stamina', 'Stamina'], ['staminaDrain', 'Stamina drain'],
    ];

    function setStamp(node, text, tone) {
        node.textContent = text;
        node.className = 'sv-stamp' + (tone ? ' is-' + tone : '');
    }

    function vitals(data) {
        lastVitals = data || {};
        data = lastVitals;
        const alerts = [];
        for (const bar of BARS) {
            const node = nodes[bar.key];
            node.label.textContent = T('sv.bar_' + bar.key, bar.label);
            if (data[bar.key] == null) {
                node.value.textContent = '-'; node.fill.style.width = '0%';
                node.row.className = 'sv-bar is-empty';
                continue;
            }
            const n = Math.round(percent(data[bar.key]));
            const critical = bar.critical != null && (bar.inverted ? n >= bar.critical : n <= bar.critical);
            node.row.className = 'sv-bar' + (critical ? ' is-critical' : '') + (n === 0 && (bar.key === 'armour' || bar.key === 'infection') ? ' is-empty' : '');
            node.value.textContent = `${n}%`;
            node.fill.style.width = `${n}%`;
            if (critical) alerts.push(bar.inverted ? T('sv.warn_infected', 'Infected') : T('sv.warn_low', '{what} low', { what: T('sv.bar_' + bar.key, bar.label) }));
        }
        if (data.dead) setStamp($('stamp'), T('sv.dead', 'Dead'), 'bad');
        else if (data.downed) setStamp($('stamp'), T('sv.downed', 'Downed'), 'bad');
        else if (alerts.length) setStamp($('stamp'), T('sv.attention', 'Needs care'), 'warn');
        else setStamp($('stamp'), T('sv.stable', 'Stable'), 'good');
        $('warning').hidden = !alerts.length && !data.downed;
        $('warning').textContent = data.downed ? T('sv.warn_downed', 'You are down. Someone has to patch you up.') : alerts.join(' · ');

        const effects = data.effects || {};
        $('effects').replaceChildren();
        for (const [key, label] of EFFECTS) {
            const value = Number(effects[key]);
            if (!Number.isFinite(value) || value === 0) continue;
            const chip = el('span', 'sv-effect' + (value < 0 && key !== 'staminaDrain' ? ' is-neg' : ''), T('sv.fx_' + key, label));
            const amount = el('b', '', key === 'carryWeight' ? `+${value.toFixed(1)} kg` : `${value > 0 ? '+' : ''}${Math.round(value * 100)}%`);
            chip.append(amount);
            $('effects').append(chip);
        }
        if (!$('effects').children.length) $('effects').append(empty(T('sv.no_perks', 'No perks learned yet.')));
    }

    function plate(value, label) {
        const span = el('span', '', label);
        span.prepend(el('b', '', value));
        return span;
    }
    function spec(label, value) {
        $('baseline').append(el('dt', '', label), el('dd', '', value));
    }
    function stampUpdated() {
        if (!refreshedAt) return;
        const time = refreshedAt.toLocaleTimeString(lang(), { hour: '2-digit', minute: '2-digit' });
        $('updated').textContent = T('sv.updated', 'Updated {time}', { time });
    }

    function render(data) {
        snapshot = data;
        const c = data.character || {};
        $('name').textContent = c.name || T('sv.title', 'Survivor');
        $('classTag').textContent = c.class || T('sv.unassigned', 'No class');
        $('level').textContent = format(c.level);
        $('points').textContent = format(c.skillPoints);
        $('points').parentElement.classList.toggle('is-zero', number(c.skillPoints) === 0);
        const maxed = number(c.level) >= number(c.maxLevel) && number(c.maxLevel) > 0;
        $('xpbar').style.width = `${maxed ? 100 : percent(number(c.xp) / Math.max(1, number(c.xpToNext)) * 100)}%`;
        $('xp').textContent = maxed ? T('sv.max_level', 'Max level') : T('sv.xp', '{xp} / {next} XP', { xp: format(c.xp), next: format(c.xpToNext) });

        const time = number(c.playtime);
        $('record').replaceChildren(plate(T('sv.hm', '{h}h {m}m', { h: Math.floor(time / 3600), m: Math.floor(time % 3600 / 60) }), T('sv.playtime', 'Time in the world')));
        if (data.record) {
            for (const [key, label] of [['zombie_kills', 'Walkers killed'], ['deaths', 'Deaths'], ['items_crafted', 'Items crafted']]) {
                $('record').append(plate(format(data.record[key]), T('sv.rec_' + key, label)));
            }
        } else $('record').append(empty(T('sv.record_off', 'Kill and craft counts are unavailable right now.')));

        $('baseline').replaceChildren();
        const stats = c.stats || {};
        if (stats.maxHealth != null) spec(T('sv.max_hp', 'Max health'), format(stats.maxHealth));
        if (stats.carryWeight != null) spec(T('sv.carry', 'Carry'), `${number(stats.carryWeight).toFixed(1)} kg`);
        if (stats.meleeDamageMult != null) spec(T('sv.melee', 'Melee'), `${number(stats.meleeDamageMult).toFixed(2)}×`);
        if (stats.staminaMult != null) spec(T('sv.stamina', 'Stamina'), `${number(stats.staminaMult).toFixed(2)}×`);

        $('skills').replaceChildren();
        const rank = id => (ORDER.indexOf(id) < 0 ? 99 : ORDER.indexOf(id));
        const skills = Object.values(data.skills || {}).sort((a, b) => rank(a.id) - rank(b.id) || String(a.label).localeCompare(String(b.label)));
        const learned = skills.reduce((n, s) => n + (Array.isArray(s.perks) ? s.perks.filter(p => p.owned).length : 0), 0);
        $('skillcount').textContent = skills.length ? T('sv.perks_owned', '{n} perks learned', { n: learned }) : '';
        for (const skill of skills) {
            const max = number(skill.level) >= number(skill.maxLevel);
            const card = el('article', 'sv-skill' + (max ? ' is-max' : '') + (number(skill.level) > 0 ? ' has-level' : ''));
            const glyph = el('i', 'sv-glyph');
            glyph.innerHTML = `<svg viewBox="0 0 24 24"><path d="${GLYPH[skill.id] || GLYPH.survival}"/></svg>`;
            const lv = el('span', 'sv-skill__lv', format(skill.level));
            lv.append(el('small', '', ` / ${format(skill.maxLevel)}`));
            const xp = el('div', 'sv-skill__xp');
            const track = el('span'); const fill = el('i');
            fill.style.width = `${max ? 100 : percent(number(skill.xp) / Math.max(1, number(skill.xpToNext)) * 100)}%`;
            track.append(fill);
            xp.append(track, el('span', '', max ? T('sv.mastered', 'Mastered') : `${format(skill.xp)} / ${format(skill.xpToNext)}`));
            card.append(glyph, el('strong', '', skill.label || skill.id), lv, xp);
            $('skills').append(card);
        }
        if (!skills.length) $('skills').append(empty(T('sv.no_skills', 'Skills are unavailable right now.')));
        vitals(data.vitals);
        refreshedAt = new Date();
        stampUpdated();
    }

    // Language switch while open: redraw from what we already have.
    if (window.BSI18n) BSI18n.onChange(() => { if (snapshot) render(Object.assign({}, snapshot, { vitals: lastVitals })); else if (lastVitals) vitals(lastVitals); });

    function setPortrait(url) {
        const img = $('portrait');
        const frame = img.parentElement;
        if (!url) { img.hidden = true; img.removeAttribute('src'); frame.classList.remove('has-photo'); return; }
        img.onload = () => { img.hidden = false; frame.classList.add('has-photo'); };
        img.onerror = () => { img.hidden = true; frame.classList.remove('has-photo'); };
        img.src = url;
    }

    window.addEventListener('message', ({ data }) => {
        if (!data) return;
        if (data.action === 'open') {
            $('screen').hidden = false; $('veil').hidden = false;
            $('updated').textContent = T('sv.loading', 'Reading record…');
        }
        if (data.action === 'close') { $('screen').hidden = true; $('veil').hidden = true; snapshot = null; setPortrait(null); }
        if (data.action === 'snapshot') render(data);
        if (data.action === 'vitals') vitals(data.vitals);
        if (data.action === 'portrait') setPortrait(data.url);
        if (data.action === 'error') $('updated').textContent = T('sv.unavailable', 'Record unavailable. Try again.');
    });
    $('close').onclick = () => post('close');
    $('refresh').onclick = () => post('refresh');
    window.addEventListener('keydown', event => { if (event.key === 'Escape') post('close'); });
})();

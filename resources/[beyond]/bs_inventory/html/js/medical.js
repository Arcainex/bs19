// Medical tab: a clickable body diagram plus a technical readout. Data comes from bs_medical (through cl_main.lua as action 'medical'); clicks go back as post('medical', ...).
// Separate from the Field Medical card on the MYSELF tab, which it never touches.
(function () {
    'use strict';
    const RESN = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_inventory';
    const el = (id) => document.getElementById(id);
    const M = { on: false, t: {}, items: [], view: {}, state: null, part: null, item: null, error: null, names: {}, cfg: {}, hp: null };
    const PARTS = ['head', 'torso', 'rarm', 'larm', 'rleg', 'lleg'];
    const LIMBS = { larm: 1, rarm: 1, lleg: 1, rleg: 1 };
    // Where markers sit on the silhouette (viewBox units).
    const ANCHOR = { head: [100, 34], torso: [100, 150], rarm: [34, 200], larm: [166, 200], rleg: [80, 330], lleg: [120, 330] };
    const BLOOD_ML = 5000; // adult blood volume used for the mL estimate

    function send(data) {
        return fetch(`https://${RESN}/medical`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        }).catch(() => {});
    }
    // T: strings sent by bs_medical. U: bs_inventory locale keys (bs_ui i18n), English fallback.
    const T = (k, f) => (M.t && M.t[k]) || f || k;
    const U = (k, fb, vars) => {
        let s = (typeof window.t === 'function') ? window.t(k, { fallback: fb }) : fb;
        if (s === k) s = fb;
        if (vars) s = String(s).replace(/\{(\w+)\}/g, (m, n) => (vars[n] != null ? vars[n] : m));
        return s;
    };
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const mmss = (s) => { s = Math.max(0, Math.floor(s || 0)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
    const iname = (n) => (M.names && M.names[n]) || ((M.items.find((i) => i.name === n) || {}).label) || n.replace(/_/g, ' ');

    function partIssues(p) {
        const out = [];
        if (!p) return out;
        if (p.bleed === 2) out.push({ cls: 'crit', text: T('cond_bleed_heavy'), k: 'bleed2' });
        else if (p.bleed === 1) out.push({ cls: 'warn', text: T('cond_bleed_light'), k: 'bleed1' });
        if (p.frac && p.splint > 0) out.push({ cls: 'ok', text: `${T('cond_splinted')} ${mmss(p.splint)}`, k: 'splint' });
        else if (p.frac) out.push({ cls: 'crit', text: T('cond_fracture'), k: 'frac' });
        if (p.bullet) out.push({ cls: 'warn', text: T('cond_bullet'), k: 'bullet' });
        if (p.pain > 0) out.push({ cls: 'warn', text: `${T('cond_pain')} ${p.pain}`, k: 'pain' });
        return out;
    }

    function partLevel(p) {
        if (!p) return 0;
        if (p.bleed === 2 || (p.frac && !(p.splint > 0))) return 3;
        if (p.bleed === 1 || p.bullet) return 2;
        if (p.frac) return 1;
        if (p.pain > 0) return 4;
        return 0;
    }

    function itemFits(it) {
        if (M.view.self && !it.self) return false;
        if (it.whole) return true;
        if (!M.part) return false;
        if (it.limbs && !LIMBS[M.part]) return false;
        return true;
    }

    // Blood lost per minute, in percent, from the open wounds.
    function bleedRate(st) {
        let r = 0;
        Object.values(st.parts || {}).forEach((p) => {
            if (p.bleed === 2) r += Number(M.cfg.bleedHeavy) || 7;
            else if (p.bleed === 1) r += Number(M.cfg.bleedLight) || 2;
        });
        return r;
    }

    // ---------------------------------------------------------------- body
    function renderBody() {
        const st = M.state || {};
        document.querySelectorAll('#medBody [data-part]').forEach((n) => {
            const p = st.parts ? st.parts[n.dataset.part] : null;
            n.dataset.level = String(partLevel(p));
            n.classList.toggle('is-sel', M.part === n.dataset.part);
        });
        // small glyphs where the conditions are: B bleed, F fracture, S splint, P projectile
        let marks = '';
        PARTS.forEach((name) => {
            const p = st.parts && st.parts[name];
            if (!p) return;
            const g = [];
            if (p.bleed > 0) g.push({ c: p.bleed === 2 ? 'crit' : 'warn', l: 'B' });
            if (p.frac) g.push({ c: p.splint > 0 ? 'ok' : 'crit', l: p.splint > 0 ? 'S' : 'F' });
            if (p.bullet) g.push({ c: 'warn', l: 'P' });
            const [x, y] = ANCHOR[name];
            const x0 = x - ((g.length - 1) * 13) / 2;
            g.forEach((m, i) => {
                const cx = x0 + i * 13;
                marks += `<g class="med__mk med__mk--${m.c}"><circle cx="${cx}" cy="${y}" r="6"/><text x="${cx}" y="${y + 3}">${m.l}</text></g>`;
            });
            if (p.pain > 0 && !g.length) marks += `<circle class="med__mk-pain" cx="${x}" cy="${y}" r="${4 + Math.min(10, p.pain / 4)}"/>`;
        });
        el('medMarks').innerHTML = marks;
        el('medLegend').innerHTML = [
            ['crit', 'B', U('med.bleed', 'BLEED')], ['crit', 'F', T('cond_fracture')],
            ['ok', 'S', T('cond_splinted')], ['warn', 'P', T('cond_bullet')],
        ].map(([c, l, txt]) => `<span class="med__lg"><i class="med__lgdot med__lgdot--${c}">${l}</i>${esc(txt)}</span>`).join('');
    }

    // ---------------------------------------------------------------- readout
    function vrow(label, value, cls, bar, barCls, sub) {
        return `<span class="med__vlabel">${esc(label)}</span>
            <span class="med__val${cls ? ' med__val--' + cls : ''}">${value}</span>
            <div class="med__track">${bar != null ? `<div class="med__fill${barCls ? ' ' + barCls : ''}" style="width:${Math.max(0, Math.min(100, bar))}%"></div>` : ''}</div>
            <span class="med__vsub">${sub ? esc(sub) : ''}</span>`;
    }

    function renderVitals(st) {
        const c = M.cfg || {};
        const rows = [];
        // health (own ped only)
        if (M.view.self && M.hp) {
            const pct = Math.round(100 * M.hp.cur / Math.max(1, M.hp.max));
            rows.push(vrow(U('med.health', 'HEALTH'), `${M.hp.cur} / ${M.hp.max}`, pct < 30 ? 'crit' : (pct < 60 ? 'warn' : ''), pct, 'med__fill--hp', `${pct}%`));
        } else {
            rows.push(vrow(U('med.health', 'HEALTH'), esc(U('med.na', 'N/A')), 'dim', null));
        }
        // blood volume
        const blood = Number(st.blood ?? 100);
        const lowAt = Number(c.lowAt) || 60, critAt = Number(c.critAt) || 30;
        rows.push(vrow(U('med.blood_vol', 'BLOOD VOLUME'), `${blood.toFixed(1)}% <small>~${Math.round(blood / 100 * BLOOD_ML)} mL</small>`,
            blood < critAt ? 'crit' : (blood < lowAt ? 'warn' : ''), blood,
            blood < critAt ? 'med__fill--crit' : (blood < lowAt ? 'med__fill--warn' : ''),
            blood < critAt ? U('med.critical', 'CRITICAL') : (blood < lowAt ? U('med.low', 'LOW') : U('med.normal', 'NORMAL'))));
        // bleed rate
        const rate = bleedRate(st);
        if (rate > 0) {
            const toCrit = blood > critAt ? ((blood - critAt) / rate) * 60 : 0;
            rows.push(vrow(U('med.bleed_rate', 'BLEED RATE'), `-${rate.toFixed(1)}%/min <small>~${Math.round(rate / 100 * BLOOD_ML)} mL/min</small>`, 'crit',
                Math.min(100, rate * 6), 'med__fill--crit', toCrit > 0 ? U('med.to_critical', 'CRITICAL IN {t}', { t: mmss(toCrit) }) : U('med.critical', 'CRITICAL')));
        } else {
            rows.push(vrow(U('med.bleed_rate', 'BLEED RATE'), esc(U('med.none', 'NONE')), 'ok', null, '', blood < 100 && c.regen ? `+${c.regen}%/min` : ''));
        }
        // pain and painkillers
        const pain = Math.round(st.pain || 0), pk = st.pk || 0;
        rows.push(vrow(T('tab_pain', U('ui.med_pain', 'PAIN')), `${pain} / 100`, pain >= 50 ? 'crit' : (pain > 0 ? 'warn' : ''), pain,
            pk > 0 ? 'med__fill--pain med__fill--masked' : 'med__fill--pain', pk > 0 ? T('cond_pain_masked') : ''));
        rows.push(vrow(U('med.painkiller', 'PAINKILLER'), pk > 0 ? mmss(pk) : esc(U('med.none', 'NONE')), pk > 0 ? 'ok' : 'dim',
            pk > 0 ? 100 * pk / 600 : null, 'med__fill--ok'));
        // infection: stage, percent and time to the next stage at the base rate
        const inf = Number(st.inf || 0), stage = st.stage || 0, rateInf = Number(c.infRate) || 0;
        let next = '';
        if (inf > 0 && rateInf > 0) {
            const nxt = stage === 1 ? Number(c.stage2) : (stage === 2 ? Number(c.stage3) : 100);
            if (nxt > inf) next = U('med.next_stage', 'NEXT STAGE IN {t}', { t: mmss(((nxt - inf) / rateInf) * 60) });
        }
        rows.push(vrow(T('tab_infection', U('ui.med_infection', 'INFECTION')), `${esc(T('stage_' + stage))} <small>${inf.toFixed(1)}%</small>`,
            ['', 'warn', 'warn', 'crit'][stage] || '', inf, stage >= 3 ? 'med__fill--crit' : 'med__fill--inf', next));
        // sickness and temperature
        rows.push(vrow(T('tab_sickness', U('ui.med_sickness', 'SICKNESS')), st.food > 0 ? `${esc(T('cond_food'))} <small>${mmss(st.food)}</small>` : esc(U('med.none', 'NONE')),
            st.food > 0 ? 'warn' : 'dim', null));
        rows.push(vrow(U('med.temperature', 'TEMPERATURE'), st.cold > 0 ? `${esc(U('med.hypothermic', 'HYPOTHERMIC'))} <small>${mmss(st.cold)}</small>` : esc(U('med.normal', 'NORMAL')),
            st.cold > 0 ? 'warn' : 'ok', null, '', st.cold > 0 ? T('cond_cold') : ''));
        el('medVitals').innerHTML = rows.join('');
    }

    function renderParts(st) {
        el('medParts').innerHTML = PARTS.map((name) => {
            const p = st.parts && st.parts[name];
            const iss = partIssues(p).filter((i) => i.k !== 'pain' && i.k !== 'splint');
            const splinted = p && p.frac && p.splint > 0;
            let status = iss.map((i) => `<b class="med__st med__st--${i.cls}">${esc(i.text)}</b>`).join(' ');
            if (splinted) status += ` <b class="med__st med__st--ok">${esc(T('cond_splinted'))}</b>`;
            if (!status) status = `<b class="med__st med__st--dim">${esc(U('med.ok', 'OK'))}</b>`;
            const pain = (p && p.pain) || 0;
            return `<tr data-prow="${name}" class="med__row med__row--l${partLevel(p)}${M.part === name ? ' is-sel' : ''}">
                <td>${esc(T('part_' + name))}</td><td>${status}</td>
                <td><span class="med__pbar"><i style="width:${Math.min(100, pain)}%"></i></span>${pain}</td><td>${splinted ? mmss(p.splint) : '-'}</td></tr>`;
        }).join('');
    }

    // One line per active condition: what it is, where, and which items treat it.
    function renderTips(st) {
        const tips = [];
        const tip = (cls, what, where, items) => tips.push({ cls, what, where, items });
        PARTS.forEach((name) => {
            const p = st.parts && st.parts[name];
            if (!p) return;
            const where = T('part_' + name), limb = !!LIMBS[name];
            if (p.bleed === 2) tip('crit', T('cond_bleed_heavy'), where, limb ? ['tourniquet', 'bandage', 'medkit'] : ['bandage', 'medkit']);
            else if (p.bleed === 1) tip('warn', T('cond_bleed_light'), where, ['rag', 'bandage', 'antiseptic']);
            if (p.frac && !(p.splint > 0)) tip('crit', T('cond_fracture'), where, limb ? ['splint'] : ['medkit']);
            if (p.bullet) tip('warn', T('cond_bullet'), where, ['surgical_kit']);
        });
        const blood = Number(st.blood ?? 100);
        if (blood < (Number(M.cfg.lowAt) || 60)) tip(blood < (Number(M.cfg.critAt) || 30) ? 'crit' : 'warn', T('cond_low_blood'), '', ['saline', 'blood_bag']);
        if ((st.stage || 0) > 0) tip(st.stage >= 3 ? 'crit' : 'warn', T('stage_' + st.stage), '',
            st.stage <= (Number(M.cfg.antiviralMax) || 2) ? ['antiviral', 'antiseptic'] : ['antiseptic']);
        if (st.food > 0) tip('warn', T('cond_food'), '', ['antibiotics']);
        if (st.cold > 0) tip('warn', T('cond_cold'), '', ['antibiotics']);
        if ((st.pain || 0) > 0 && !((st.pk || 0) > 0)) tip('warn', T('cond_pain'), '', ['painkillers']);
        const have = {};
        (M.items || []).forEach((i) => { have[i.name] = i.count; });
        el('medTips').innerHTML = tips.length ? tips.map((x) => `<li class="med__tip med__tip--${x.cls}">
            <span class="med__tipw">${esc(x.what)}${x.where ? ` <small>${esc(x.where)}</small>` : ''}</span>
            <span class="med__tipi">${x.items.map((n) => `<em class="${have[n] ? 'is-have' : ''}">${esc(iname(n))}${have[n] ? ` x${have[n]}` : ''}</em>`).join('')}</span></li>`).join('')
            : `<li class="med__tip med__tip--ok">${esc(U('med.no_issues', 'No active conditions.'))}</li>`;
    }

    function renderSide() {
        const st = M.state || {};
        el('medWho').textContent = M.view.self ? T('tab_self') : `${T('tab_patient')}: ${M.view.name || ('#' + M.view.target)}`;
        el('medBackSelf').classList.toggle('hidden', !!M.view.self);
        el('medSkill').textContent = `${T('tab_skill')} ${M.view.skill || 0}`;
        const d = new Date(), two = (n) => String(n).padStart(2, '0');
        el('medClock').textContent = `${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}`;

        renderVitals(st);
        renderParts(st);
        renderTips(st);

        // selected part
        const p = M.part && st.parts ? st.parts[M.part] : null;
        el('medPartName').textContent = M.part ? T('part_' + M.part) : T('tab_pick_part');
        const issues = partIssues(p);
        el('medPartList').innerHTML = M.part
            ? (issues.length ? issues.map((i) => `<li class="med__iss med__iss--${i.cls}">${esc(i.text)}</li>`).join('')
                : `<li class="med__iss med__iss--ok">${esc(T('tab_healthy'))}</li>`)
            : '';

        // items
        const list = M.items || [];
        el('medItems').innerHTML = list.length ? list.map((it) => {
            const fits = itemFits(it);
            const icon = (typeof BSIcons !== 'undefined') ? BSIcons.get(it.name, 'medical') : '';
            const note = (M.view.self && !it.self) ? T('tab_others_only') : (it.whole ? T('tab_whole') : '');
            return `<button class="med__item${fits ? '' : ' is-off'}${M.item === it.name ? ' is-sel' : ''}" data-item="${esc(it.name)}" ${fits ? '' : 'disabled'}>
                <span class="med__icon">${icon}</span>
                <span class="med__ilabel">${esc(it.label)}<i>x${it.count}</i></span>
                <span class="med__idesc">${esc(it.desc)}${note ? ` <b>${esc(note)}</b>` : ''}</span>
            </button>`;
        }).join('') : `<p class="med__empty">${esc(T('tab_no_items'))}</p>`;

        const chosen = list.find((i) => i.name === M.item);
        el('medApply').disabled = !(chosen && itemFits(chosen));
        el('medApply').textContent = T('tab_apply');
        el('medErr').textContent = M.error || '';
        el('medHint').textContent = T('tab_hint');
    }

    function render() {
        const tab = document.querySelector('.tab[data-tab="medical"]');
        if (tab) tab.classList.toggle('hidden', !M.on);
        el('medOff').classList.toggle('hidden', M.on);
        el('medMain').classList.toggle('hidden', !M.on);
        if (!M.on) {
            el('medOff').textContent = T('tab_off');
            if (tab && tab.classList.contains('is-active')) {
                const carry = document.querySelector('.tab[data-tab="carry"]');
                if (carry) carry.click();
            }
            return;
        }
        el('medTitle').textContent = T('tab_title');
        renderBody();
        renderSide();
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'medical') {
            const sameTarget = M.view && d.view && M.view.target === d.view.target;
            M.on = !!d.on;
            M.t = d.t || M.t;
            M.items = d.items || [];
            M.view = d.view || {};
            M.state = d.state || null;
            M.error = d.error || null;
            M.names = d.names || M.names;
            M.cfg = d.cfg || M.cfg;
            M.hp = d.hp || null;
            if (!sameTarget) { M.part = null; M.item = null; }
            if (d.select) M.item = d.select;
            if (M.item && !M.items.find((i) => i.name === M.item)) M.item = null;
            if (d.focus) {
                const tab = document.querySelector('.tab[data-tab="medical"]');
                if (tab) tab.click();
            }
            render();
        } else if (d.action === 'open') {
            M.error = null;
            send({ op: 'refresh' });
        }
    });
    if (window.BSI18n && typeof window.BSI18n.onChange === 'function') window.BSI18n.onChange(() => { if (M.on) render(); });

    function pick(part) { M.part = part; M.error = null; render(); }
    el('medBody').addEventListener('click', (e) => {
        const n = e.target.closest('[data-part]');
        if (n) pick(n.dataset.part);
    });
    el('medParts').addEventListener('click', (e) => {
        const n = e.target.closest('[data-prow]');
        if (n) pick(n.dataset.prow);
    });
    el('medItems').addEventListener('click', (e) => {
        const n = e.target.closest('[data-item]');
        if (!n || n.disabled) return;
        M.item = n.dataset.item;
        M.error = null;
        render();
    });
    el('medItems').addEventListener('dblclick', (e) => {
        const n = e.target.closest('[data-item]');
        if (n && !n.disabled) el('medApply').click();
    });
    el('medApply').addEventListener('click', () => {
        if (el('medApply').disabled || !M.item) return;
        send({ op: 'apply', part: M.part, item: M.item });
    });
    el('medBackSelf').addEventListener('click', () => send({ op: 'self' }));
    // timers count down while the tab is open
    setInterval(() => {
        if (!M.on || !M.state || el('root').classList.contains('hidden')) return;
        const st = M.state;
        ['food', 'cold', 'pk'].forEach((k) => { if (st[k] > 0) st[k] -= 1; });
        Object.values(st.parts || {}).forEach((p) => { if (p.splint > 0) p.splint -= 1; });
        // readout only; the item buttons are left alone so clicks and scroll survive
        const d = new Date(), two = (n) => String(n).padStart(2, '0');
        el('medClock').textContent = `${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}`;
        renderVitals(st); renderParts(st); renderTips(st);
    }, 1000);
})();

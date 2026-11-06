(() => {
    const root = document.getElementById('skillsRoot');
    const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    let data = null, selected = '', busy = false, error = '', opened = false, pendingConfirm = null;
    let feedback = null, soundEnabled = true;
    try { soundEnabled = localStorage.getItem('bs-skills-sound') !== 'off'; } catch {}
    const post = async (action, body = {}) => {
        const response = await fetch(`https://${GetParentResourceName()}/${action}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
        if (!response.ok) throw new Error('Request failed. Try again.');
        return response.json();
    };
    const glyph = id => {
        const shapes = {fighting:'M7 10V7a1.5 1.5 0 0 1 3 0v2V6a1.5 1.5 0 0 1 3 0v3V7a1.5 1.5 0 0 1 3 0v4a1.5 1.5 0 0 1 3 0v3a6 6 0 0 1-6 6h-1a6 6 0 0 1-6-6z',combat:'M6 3l15 15-3 3L3 6zM3 17l4 4m-2-2 6-6M16 3l5 5-6 6',survival:'M12 2l8 5-2 12-6 3-6-3L4 7zM8 12l3 3 5-7',crafting:'M14 3a6 6 0 0 0-7 7L3 18l3 3 8-8a6 6 0 0 0 7-7l-4 4-3-3z',medical:'M9 3h6v6h6v6h-6v6H9v-6H3V9h6z',lockpicking:'M6 10h12v11H6zM8 10V6a4 4 0 0 1 8 0v4M12 14v3',fishing:'M17 3v12a5 5 0 0 1-10 0v-3l3 3M4 3h16',parkour:'M13 4a2 2 0 1 0 0 .1M9 21l3-6 3 2 2 4M6 12l3-4h5l3 4M12 15l-1-4'};
        return `<i class="skillbook__glyph" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="${shapes[id] || shapes.survival}"/></svg></i>`;
    };
    const text = (key, fallback) => window.BSI18n?.t?.(key, {fallback}) || fallback;
    async function refresh() {
        try {
            const next = await post('skillsList');
            if (!next.ok) throw new Error(next.error || 'Skills are unavailable.');
            data = next; error = '';
        } catch (e) { error = e.message; }
        render();
    }
    function confirmReset() {
        return new Promise(resolve => {
            const dialog = document.createElement('div');
            dialog.className = 'skillbook__confirm';
            dialog.setAttribute('role','alertdialog');
            dialog.setAttribute('aria-label','Reset learned perks');
            dialog.innerHTML = `<p>Reset learned perks for ${Number(data.respec.cost) || 0} XP? Training levels remain.</p><button data-answer="no">Keep perks</button> <button data-answer="yes">Reset perks</button>`;
            pendingConfirm = answer => { dialog.remove(); pendingConfirm = null; resolve(answer); };
            dialog.addEventListener('click', e => {
                e.stopPropagation();
                const answer = e.target.closest('[data-answer]');
                if (answer) pendingConfirm(answer.dataset.answer === 'yes');
            });
            root.append(dialog); dialog.querySelector('button').focus();
        });
    }
    function render() {
        if (pendingConfirm) return;
        root.classList.toggle('is-working',busy);
        if (feedback && Date.now() > feedback.until) feedback = null;
        const order = ['combat','survival','crafting','medical','lockpicking','fishing','parkour','fighting'];
        const trees = Object.entries(data?.skills || {}).sort(([a],[b]) => (order.indexOf(a) < 0 ? 99 : order.indexOf(a)) - (order.indexOf(b) < 0 ? 99 : order.indexOf(b)) || a.localeCompare(b));
        if (!trees.some(([id]) => id === selected)) selected = trees[0]?.[0] || '';
        const tree = data?.skills?.[selected];
        const points = Number(data?.points) || 0;
        root.innerHTML = `<header class="skillbook__head"><div><span class="skillbook__eyebrow">CHARACTER DEVELOPMENT</span><h1>${esc(text('ui.skills','Skills'))}</h1></div><strong>${points} <small>Available points</small></strong><button class="skillbook__sound" data-action="sound" aria-pressed="${soundEnabled}" aria-label="Skill sounds">${soundEnabled ? 'Sound on' : 'Sound off'}</button></header>
            ${error ? `<p class="skillbook__error" role="alert">${esc(error)} <button data-action="refresh">Retry</button></p>` : ''}
            <div class="skillbook__layout"><nav aria-label="Skill categories">${trees.map(([id,t]) => `<button class="skillbook__category ${id === selected ? 'is-active' : ''}" data-tree="${esc(id)}" style="--mastery:${Math.min(100,100*t.level/t.maxLevel)}%">${glyph(id)}<span>${esc(t.label)}</span><b>${t.level}</b></button>`).join('')}</nav>
            <section class="skillbook__detail ${feedback?.action === 'train' ? 'is-trained' : ''}">${tree ? detail(tree, points) : '<p>Loading skills…</p>'}</section></div>`;
    }
    function layoutPerks(perks, columns) {
        const nodes=[], occupied=new Set();
        [...perks].sort((a,b)=>(a.requires||0)-(b.requires||0)||a.id.localeCompare(b.id)).forEach((perk,i)=>{
            const parent=nodes.find(n=>n.id===perk.needsPerk);
            let row=Math.max(Math.floor(i/columns),parent?parent.row+1:0),col=i%columns;
            while(occupied.has(`${row}:${col}`)) { col=(col+1)%columns;if(col===0) row++; }
            occupied.add(`${row}:${col}`);
            nodes.push({...perk,row,x:(columns===3?[17,50,83]:[27,73])[col],y:42+row*200});
        });
        return nodes;
    }
    function detail(tree, points) {
        const pct = tree.xpToNext ? Math.min(100, 100 * tree.xp / tree.xpToNext) : 100;
        const perks = tree.perks || [], training = data.training || {}, respec = data.respec || {};
        const columns=root.clientWidth>=1000?3:2;
        const nodes=layoutPerks(perks,columns);
        const height=Math.max(180,(Math.max(0,...nodes.map(n=>n.row))+1)*200+25);
        const links = nodes.map(p => {
            const parent = nodes.find(n => n.id === p.needsPerk);
            return `<path class="${p.owned ? 'owned' : ''}" d="M ${parent?.x || 50} ${parent ? parent.y + 20 : 0} V ${p.y-30} H ${p.x} V ${p.y}"/>`;
        }).join('');
        return `<header><div class="skillbook__crest">${glyph(selected)}</div><h2>${esc(tree.label)} <small>LEVEL ${tree.level} / ${tree.maxLevel}</small></h2><p>${esc(tree.blurb)}</p><div class="skillbook__xp"><i style="width:${pct}%"></i></div><p>${tree.xpToNext ? `${tree.xp} / ${tree.xpToNext} XP` : 'Maximum level'}</p></header>
            <div class="skillbook__actions"><span class="skillbook__learned">${perks.length ? `${perks.filter(p=>p.owned).length} / ${perks.length} perks learned` : 'Practice improves catches'}</span><button data-action="train" ${busy || !training.enabled || points < training.cost || tree.level >= tree.maxLevel ? 'disabled' : ''}>Train · ${training.cost || 1} point${training.cost === 1 ? '' : 's'}</button><button data-action="respec" ${busy || !respec.enabled ? 'disabled' : ''}>Reset perks · ${respec.cost || 0} XP</button></div>
            <p class="skillbook__hint">${selected === 'fishing' ? 'Land fish to gain XP. Each level widens the timing window, shortens the wait and improves rare-catch odds.' : 'Earn experience through play, or spend a point to train.'}</p>
            <div class="skillbook__tree" style="height:${height}px">${!nodes.length ? `<section class="skillbook__practice">${glyph(selected)}<h3>Learn on the water</h3><p>Land fish to build experience. Every level improves your timing and brings better catches within reach.</p><div><span>Steadier timing</span><span>Shorter waits</span><span>Rarer catches</span></div></section>` : ''}<svg viewBox="0 0 100 ${height}" preserveAspectRatio="none" aria-hidden="true">${links}</svg><i class="skillbook__root" aria-hidden="true"></i>
            ${nodes.map(p => `<article class="skillbook__node ${feedback?.perk === p.id ? 'just-unlocked' : ''} ${p.owned ? 'is-owned' : p.available && points >= p.cost ? 'is-ready' : 'is-locked'}" style="left:${p.x}%;top:${p.y}px;width:${columns===3?29:40}%"><span>${p.owned ? 'LEARNED' : p.available && points >= p.cost ? 'AVAILABLE' : 'LOCKED'} · LV ${p.requires || 0}</span><h3>${esc(p.label)}</h3><p>${esc(p.description)}</p><button data-perk="${esc(p.id)}" ${busy || p.owned || !p.available || points < p.cost || p.pending || p.trainer ? 'disabled' : ''}>${p.pending ? 'Not active yet' : p.owned ? 'Learned' : p.trainer ? 'Learn from a trainer' : `Unlock perk <span aria-hidden="true">↗</span> · ${p.cost} point${p.cost === 1 ? '' : 's'}`}</button></article>`).join('')}</div>`;
    }
    root.addEventListener('click', async e => {
        const category = e.target.closest('[data-tree]');
        if (category) { selected = category.dataset.tree; render(); return; }
        const button = e.target.closest('button');
        if (!button || button.disabled || busy) return;
        const action = button.dataset.action;
        if (action === 'refresh') return refresh();
        if (action === 'sound') { soundEnabled = !soundEnabled; try { localStorage.setItem('bs-skills-sound',soundEnabled ? 'on' : 'off'); } catch {} render(); return; }
        if (!button.dataset.perk && action !== 'train' && action !== 'respec') return;
        if (action === 'respec') {
            busy = true;
            const approved = await confirmReset();
            busy = false;
            if (!approved) { render(); return; }
        }
        busy = true; render();
        try {
            const result = await post(button.dataset.perk ? 'skillsUnlock' : action === 'train' ? 'skillsTrain' : 'skillsRespec', {tree:selected, perk:button.dataset.perk, sound:soundEnabled});
            if (!result.ok) throw new Error(result.error || 'That action could not be completed.');
            feedback = {action, perk:button.dataset.perk, until:Date.now()+1000};
            await refresh();
        } catch (e) { error = e.message; }
        finally { busy = false; render(); }
    });
    const tab = () => document.querySelector('.tab.is-active')?.dataset.tab === 'skills';
    new MutationObserver(() => { if (tab() && !opened) { opened = true; refresh(); } else if (!tab()) opened = false; }).observe(document.querySelector('.tabs'), {attributes:true, subtree:true, attributeFilter:['class']});
    window.addEventListener('message', e => {
        if (e.data?.action === 'close') { pendingConfirm?.(false); busy = false; data = null; opened = false; root.innerHTML = ''; }
        if (e.data?.action === 'skillsChanged' && tab()) refresh();
        if (e.data?.action === 'open') { data = null; opened = false; if (e.data.tab === 'skills') { opened = true; refresh(); } }
    });
    const sheet = document.querySelector('.sheet__head');
    if (sheet) {
        sheet.tabIndex = 0; sheet.setAttribute('role','button'); sheet.setAttribute('aria-label','Open Skills');
        sheet.addEventListener('click', () => document.querySelector('[data-tab="skills"]')?.click());
        sheet.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); sheet.click(); } });
    }
})();

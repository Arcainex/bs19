const $ = (id) => document.getElementById(id);
const tr = (k, f) => (window.BSI18N && window.BSI18N.t) ? window.BSI18N.t(k, { fallback: f }) : f;
function post(name, body) {
    return fetch(`https://bs_fpdebug/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) })
        .then((r) => r.json()).catch(() => ({ ok: false }));
}
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function msg(t, bad) { const e = $('msg'); e.textContent = String(t || '').toUpperCase(); e.classList.toggle('bad', !!bad); }
function btn(label, attrs) { return `<button class="row" ${attrs}><span>${esc(label)}</span></button>`; }
function chip(label, attrs) { return `<button class="row" ${attrs}><span>${esc(label)}</span></button>`; }

function render(d) {
    const f = d.fight || {}, p = d.park || {};
    let h = '';
    for (const st of f.styles || []) {
        h += `<p class="mpane__label"><span>${esc(st.id.toUpperCase())}</span></p><div class="split">`;
        h += btn(tr('fpdbg.learn', 'LEARN'), `data-cmd="fightlearn" data-a="${esc(st.id)}"`);
        h += btn(tr('fpdbg.forget', 'FORGET'), `data-cmd="fightforget" data-a="${esc(st.id)}"`);
        h += btn(tr('fpdbg.use', 'USE'), `data-style="${esc(st.id)}"`) + '</div><div class="chips">';
        for (const s of st.slots) h += `<button class="chip" data-fight="${esc(s[1])}">${esc(s[0])}</button>`;
        h += '</div>';
    }
    h += `<p class="mpane__label"><span>${esc(tr('fpdbg.weapon', 'WEAPON'))}</span></p><div class="chips">`;
    for (const id of f.weapon || []) h += `<button class="chip" data-fight="${esc(id)}">${esc(id)}</button>`;
    h += '</div><div class="split">' + btn(tr('fpdbg.learn_all', 'LEARN ALL'), 'data-cmd="fightlearn" data-a="all"') + btn(tr('fpdbg.reset', 'RESET'), 'data-cmd="fightreset" data-a=""') + '</div>';
    $('pFight').innerHTML = h;

    h = `<p class="mpane__label"><span>${esc(tr('fpdbg.perks', 'PERKS'))}</span></p><div class="split">`;
    for (const k of ['basic', 'advanced', 'all', 'reset']) h += btn(k.toUpperCase(), `data-cmd="parkourperk" data-a="${k}"`);
    h += `</div><p class="mpane__label"><span>${esc(tr('fpdbg.level', 'LEVEL'))}</span></p><div class="chips">`;
    for (const l of [0, 1, 5, 10, 15, 20]) h += `<button class="chip" data-cmd="parkourlevel" data-a="${l}">${l}</button>`;
    h += `</div><p class="mpane__label"><span>${esc(tr('fpdbg.moves', 'MOVES'))}</span></p><div class="chips">`;
    for (const k of p.kinds || []) h += `<button class="chip" data-park="${esc(k)}">${esc(k)}</button>`;
    h += '</div>';
    $('pPark').innerHTML = h;

    const bad = [...(f.failed || []), ...(p.failed || [])];
    $('pFailed').innerHTML = bad.length ? bad.map((b) => `<p class="cost-line">${esc(b)}</p>`).join('') : '<p class="cost-line">0</p>';
}

document.addEventListener('click', async (e) => {
    const t = e.target.closest('[data-cmd],[data-style],[data-fight],[data-park],[data-tab]');
    if (!t) return;
    if (t.dataset.tab) {
        document.querySelectorAll('.mtab').forEach((x) => x.classList.toggle('is-active', x === t));
        document.querySelectorAll('.mpane').forEach((x) => x.classList.toggle('is-active', x.dataset.pane === t.dataset.tab));
        return;
    }
    let r;
    if (t.dataset.cmd) r = await post('do', { name: 'cmd', cmd: t.dataset.cmd, a: t.dataset.a });
    else if (t.dataset.style) r = await post('do', { name: 'style', id: t.dataset.style });
    else if (t.dataset.fight) r = await post('do', { name: 'fight', id: t.dataset.fight });
    else r = await post('do', { name: 'park', id: t.dataset.park });
    msg(r && r.ok ? 'ok' : 'failed', !(r && r.ok));
});

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') { render(m.data || {}); $('root').classList.remove('hidden'); }
    else if (m.action === 'close') $('root').classList.add('hidden');
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close'); });

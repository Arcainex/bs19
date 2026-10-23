// F1 page for bs_pass: tier reward editor and season tools.
(() => {
  'use strict';
  const ui = () => window.BSConfigUI;
  const ext = (action, payload) => ui().rpc('ext', 'bs_pass', action, payload);
  const E = (s) => ui().esc(s);
  const X = (k, fb, v) => ui().T(k, fb, v);
  let R = null, main = null;

  // Rewards as text: item:canned_food:3, cash:500, xp:300, token:1, car:mesa3
  const toText = (list) => (list || []).map(r => r.type === 'item' ? `item:${r.item}:${r.amount}` : r.type === 'car' ? `car:${r.model}` : `${r.type}:${r.amount}`).join(', ');
  const parse = (txt) => String(txt || '').split(',').map(x => x.trim()).filter(Boolean).map(x => {
    const p = x.split(':').map(s => s.trim());
    if (p[0] === 'item') return { type: 'item', item: p[1], amount: Number(p[2]) || 1 };
    if (p[0] === 'car') return { type: 'car', model: p[1] };
    return { type: p[0], amount: Number(p[1]) || 1 };
  });

  function draw() {
    const s = R.season || {};
    main.innerHTML = `<h2 class="cat">${E(X('cfg.t.wasteland_pass', 'Wasteland Pass'))}</h2>
      <p class="shint">${E(X('cfg.x.pass.hint', 'Season {id} ends {date}. XP, odds and caps are under the Wasteland Pass category. Tier edits are live and saved to bs_pass/data/tiers.json.', { id: s.id, date: new Date((s.ends || 0) * 1000).toLocaleString() }))}</p>
      <div class="card"><h4>${E(X('cfg.x.pass.tools', 'Season tools'))}</h4>
        <button class="btn danger" data-xs="end">${E(X('cfg.x.pass.end', 'End season now'))}</button>
        <button class="btn" data-xs="xp">${E(X('cfg.x.pass.xp', 'Give me 1000 pass XP'))}</button></div>
      <div class="card"><h4>${E(X('cfg.x.pass.tiers', 'Tier rewards'))}</h4>
      <p class="shint">${E(X('cfg.x.pass.fmt', 'Format: item:canned_food:3, cash:500, xp:300, token:1, car:mesa3'))}</p>
      <table class="audit"><tr><th>${E(X('cfg.x.pass.th_tier', 'Tier'))}</th><th>${E(X('cfg.x.pass.th_rewards', 'Rewards'))}</th><th></th></tr>
      ${R.tiers.map(t => `<tr><td class="k">${t.tier}</td><td><input type="text" id="xs_${t.tier}" value="${E(toText(t.rewards))}" style="width:100%;box-sizing:border-box"></td>
        <td style="white-space:nowrap"><button class="btn" data-xs="save" data-t="${t.tier}">${E(X('cfg.x.save', 'Save'))}</button>${t.custom ? ` <span class="badge mod">${E(X('cfg.x.pass.edited', 'edited'))}</span> <button class="btn" data-xs="reset" data-t="${t.tier}">&#8634;</button>` : ''}</td></tr>`).join('')}
      </table></div>`;
  }

  async function render(m) {
    main = m;
    const res = await ext('state');
    if (!res || !res.ok) { m.innerHTML = `<div class="empty">${E((res && res.error) || X('cfg.x.pass.notrunning', 'bs_pass is not running.'))}</div>`; return; }
    R = res; draw();
  }

  async function act(action, payload, msg) {
    const res = await ext(action, payload);
    if (!res || !res.ok) return ui().toast((res && res.error) || X('cfg.failed', 'Failed'), true);
    R = res; draw(); if (msg) ui().toast(msg);
  }

  document.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-xs]');
    if (!b) return;
    const t = Number(b.dataset.t);
    if (b.dataset.xs === 'save') return act('saveTier', { tier: t, rewards: parse(document.getElementById('xs_' + t).value) }, X('cfg.x.pass.saved', 'Tier {t} saved', { t }));
    if (b.dataset.xs === 'reset') return act('resetTier', t, X('cfg.x.pass.reset', 'Tier {t} reset', { t }));
    if (b.dataset.xs === 'xp') return act('giveXp', 1000, X('cfg.x.pass.xp_added', 'XP added'));
    if (b.dataset.xs === 'end' && await ui().confirmBox(X('cfg.x.pass.end_title', 'End season'), X('cfg.x.pass.end_msg', 'Unclaimed rewards go to mailboxes, leftover tokens are spun, and a new season starts.'))) return act('endSeason', null, X('cfg.x.pass.new_season', 'New season started'));
  });

  window.BSConfigExt = (window.BSConfigExt || []).concat([{ id: '_ext_pass', get label() { return X('cfg.t.wasteland_pass', 'Wasteland Pass'); }, render }]);
})();

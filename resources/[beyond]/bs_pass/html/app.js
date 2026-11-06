// Wasteland Pass NUI. Draws what the server sends; every action goes back to the server.
(() => {
  'use strict';
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'bs_pass';
  const $ = (id) => document.getElementById(id);
  const GLYPH = { can: '◍', med: '✚', bullet: '▮', gear: '⚙', skull: '☠', crown: '♛' };
  let D = null, STR = {}, spinning = false;

  const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => ({ ok: false }));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const t = (k, v) => { let s = STR[k] || k; if (v) for (const n in v) s = s.split('{' + n + '}').join(v[n]); return s; };

  function toast(msg) { const el = $('toast'); el.textContent = msg; el.classList.add('on'); clearTimeout(toast.h); toast.h = setTimeout(() => el.classList.remove('on'), 2600); }

  function rewardText(r) {
    if (r.type === 'item') return `<i>${esc(r.amount)}x</i> ${esc(t('item.' + r.item) !== 'item.' + r.item ? t('item.' + r.item) : r.item.replace(/_/g, ' '))}`;
    if (r.type === 'cash') return `<i>$${esc(r.amount)}</i>`;
    if (r.type === 'xp') return `<i>${esc(r.amount)}</i> XP`;
    if (r.type === 'token') return `<i>${esc(r.amount)}</i> ${esc(t('pass.token'))}`;
    if (r.type === 'car') return `<i>${esc(t('pass.car'))}</i> ${esc(r.model)}`;
    return '';
  }

  function left(sec) { sec = Math.max(0, sec); const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600); return d > 0 ? `${d}d ${h}h` : `${h}h ${Math.floor(sec % 3600 / 60)}m`; }

  function header() {
    $('tier').textContent = D.tier; $('tokens').textContent = D.tokens; $('dayxp').textContent = `${D.dayXp}/${D.dayCap}`;
    $('seasonInfo').textContent = t('pass.season', { n: D.season, left: left(D.ends - D.now) });
    const inTier = D.tier >= D.maxTier ? D.xpPerTier : D.xp % D.xpPerTier;
    $('xpfill').style.width = (inTier / D.xpPerTier * 100) + '%';
    $('xptext').textContent = D.tier >= D.maxTier ? t('pass.maxed') : `${inTier} / ${D.xpPerTier} XP`;
    $('spin').disabled = D.tokens < 1 || spinning;
  }

  function road() {
    const claimed = (n) => (D.claimed || '').charAt(n - 1) === '1';
    let html = '';
    D.tiersList.forEach((list, i) => {
      const n = i + 1, reached = n <= D.tier, done = claimed(n);
      const cls = ['post', reached ? 'reached' : '', reached && !done ? 'claimable' : '', done ? 'claimed' : '', n % 10 === 0 ? 'big' : '', n === Math.max(1, Math.min(D.tier, D.maxTier)) ? 'me' : ''].join(' ');
      const ic = list[0] ? ({ item: '\u25A3', cash: '$', xp: '\u2605', token: '\u25CE', car: '\u2699' }[list[0].type] || '\u25A0') : '';
      const st = done ? '\u2713' : (reached ? '\u25B6' : '\u2022');
      html += `<div class="${cls}" data-tier="${n}"><div class="card"><div class="hd"><span class="n">${n}</span><span class="st">${st}</span></div><div class="ic">${ic}</div><div class="rw">${list.map(rewardText).join('<br>')}</div></div></div>`;
    });
    $('ladder').innerHTML = html;
    $('cars').innerHTML = (D.cars || []).map(c => `<button class="btn pri" data-car="${c.id}">${esc(t('pass.bring_car', { model: c.model }))}</button>`).join('');
    const me = document.querySelector('.post.me');
    if (me) $('roadWrap').scrollLeft = Math.max(0, me.offsetLeft - 160);
  }

  function chList(list, daily) {
    return (list || []).map((c, i) => `<div class="ch${c.done ? ' done' : ''}"><div class="t">${esc(t('ch.' + c.kind, { n: c.target }))}</div>
      <div class="bar"><div style="width:${Math.min(100, c.p / c.target * 100)}%"></div></div>
      <div class="f"><span>${c.p} / ${c.target}</span><span><b>+${c.xp} XP</b>${!daily && !c.done ? ' +' + esc(t('pass.token')) : ''}
      ${!c.done && c.accepted !== true ? `<button class="btn" data-accept="pass:${daily ? 'd' : 'w'}:${daily ? D.dayKey : D.weekKey}:${i + 1}:${esc(c.id)}">Accept objective</button>` : ''}
      ${daily && !c.done && D.rerollsLeft > 0 ? ` <button class="btn rr" data-reroll="${i + 1}">${esc(t('pass.reroll'))}</button>` : ''}</span></div></div>`).join('');
  }
  function challenges() {
    $('daily').innerHTML = chList(D.dailies, true);
    $('weekly').innerHTML = chList(D.weeklies, false);
    $('hDaily').textContent = `${t('pass.daily')} - ${t('pass.resets', { left: left(D.nextDay - D.now) })}`;
    $('hWeekly').textContent = `${t('pass.weekly')} - ${t('pass.resets', { left: left(D.nextWeek - D.now) })}`;
  }

  // Reel window shows 3 rows; strips always carry one symbol above and below the one on the win line.
  const CELL = 104;
  const rnd = (syms) => syms[Math.floor(Math.random() * syms.length)];
  function strip(el, ids) { el.innerHTML = ids.map(s => `<div class="sym-${s}">${GLYPH[s] || '?'}</div>`).join(''); }
  function rest(el, above, mid, below) { strip(el, [above, mid, below]); el.style.transition = 'none'; el.style.transform = 'translateY(0)'; }
  function slotIdle() {
    const syms = (D.symbols || []).map(s => s.id);
    if (!syms.length) return;
    [0, 1, 2].forEach(i => { const el = $('r' + i); if (!el.dataset.set) { rest(el, rnd(syms), syms[i % syms.length], rnd(syms)); el.dataset.set = '1'; } });
    const tot = (D.symbols || []).reduce((a, s) => a + s.w, 0) || 1;
    $('paytable').innerHTML = (D.symbols || []).map(s => `<span>${GLYPH[s.id]} x3 = ${esc(t('pool.' + s.pool))} (${(Math.pow(s.w / tot, 3) * 100).toFixed(2)}%)</span>`).join('') + `<span>x2 = ${esc(t('pool.pair'))}</span><span>${esc(t('pool.consolation'))}</span>`;
  }

  // Sounds are synthesised with WebAudio, no files to ship.
  let AC = null;
  function tone(freq, dur, type, vol, when) {
    try {
      AC = AC || new (window.AudioContext || window.webkitAudioContext)();
      const t0 = AC.currentTime + (when || 0), o = AC.createOscillator(), g = AC.createGain();
      o.type = type || 'square'; o.frequency.setValueAtTime(freq, t0);
      g.gain.setValueAtTime(vol || 0.06, t0); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      o.connect(g); g.connect(AC.destination); o.start(t0); o.stop(t0 + dur + 0.02);
    } catch (e) { /* no audio, fine */ }
  }
  const sfx = {
    lever: () => { tone(140, .12, 'sawtooth', .08); tone(90, .2, 'triangle', .08, .1); },
    tick: () => tone(900 + Math.random() * 200, .025, 'square', .025),
    stop: () => { tone(220, .08, 'square', .09); tone(110, .1, 'triangle', .08, .03); },
    tease: () => tone(600, .1, 'triangle', .05),
    coin: (k) => tone(1500 + (k % 4) * 180, .09, 'square', .045, k * 0.07),
    jackpot: () => { [523, 659, 784, 1047, 784, 1047, 1319].forEach((f, i) => tone(f, .18, 'square', .07, i * .13)); for (let k = 0; k < 24; k++) sfx.coin(k + 8); },
    lose: () => { tone(300, .15, 'triangle', .05); tone(220, .25, 'triangle', .05, .15); },
  };

  function coins(n) {
    const fx = $('fx');
    for (let i = 0; i < n; i++) {
      const c = document.createElement('div'); c.className = 'coin';
      c.style.left = (Math.random() * 100) + '%'; c.style.animationDuration = (1.2 + Math.random() * 1.6) + 's'; c.style.animationDelay = (Math.random() * .8) + 's';
      fx.appendChild(c); setTimeout(() => c.remove(), 3800);
    }
  }

  // One reel: fast blurred strip, eased stop on the final symbol. Tease = extra slow crawl with a glow.
  function spinReel(i, final, syms, ms, tease, nearSym) {
    return new Promise(done => {
      const el = $('r' + i), reel = el.parentElement, seq = [rnd(syms)];
      const n = Math.round(ms / 55);
      for (let k = 0; k < n; k++) seq.push(rnd(syms));
      if (tease && nearSym) seq.push(nearSym);        // the matching symbol slides past the line just before the stop
      seq.push(final, nearSym && tease ? rnd(syms) : rnd(syms));
      strip(el, seq);
      el.style.transition = 'none'; el.style.transform = 'translateY(0)';
      void el.offsetHeight;
      el.classList.add('blur');
      if (tease) { reel.classList.add('tease'); sfx.tease(); }
      el.style.transition = `transform ${ms}ms cubic-bezier(.12,.6,.25,1.04)`;
      el.style.transform = `translateY(-${(seq.length - 3) * CELL}px)`;
      const ticker = setInterval(sfx.tick, tease ? 140 : 70);
      setTimeout(() => el.classList.remove('blur'), ms * 0.72);
      setTimeout(() => {
        clearInterval(ticker); reel.classList.remove('tease'); sfx.stop();
        rest(el, seq[seq.length - 3], final, seq[seq.length - 1]); done();
      }, ms + 40);
    });
  }

  function pullLever() {
    const l = $('lever'); l.classList.add('pull'); sfx.lever();
    return new Promise(r => setTimeout(() => { l.classList.remove('pull'); r(); }, 260));
  }

  function draw() { header(); road(); challenges(); slotIdle(); }

  async function spin() {
    if (spinning || !D || D.tokens < 1) return;
    spinning = true; $('spin').disabled = true; $('slotResult').className = 'result'; $('slotResult').textContent = '';
    $('cabinet').classList.remove('celebrate'); document.querySelector('.window').classList.remove('win');
    await pullLever();
    const res = await post('spin');
    if (!res || !res.ok) { spinning = false; header(); return toast(t('pass.no_tokens')); }
        const syms = D.symbols.map(s => s.id), R = res.reels;
    // near miss: first two match, third does not -> slow tease on reel 3 with the match sliding past
    const near = R[0] === R[1] && R[2] !== R[0];
    const tease3 = R[0] === R[1];
    await Promise.all([
      spinReel(0, R[0], syms, 1300),
      spinReel(1, R[1], syms, 1900),
      spinReel(2, R[2], syms, tease3 ? 3600 : 2500, tease3, near ? R[0] : null),
    ]);
    const r = $('slotResult');
    r.innerHTML = `${esc(t('pool.' + res.pool))}: ${res.rewards.map(rewardText).join(', ')}${res.mailed ? ' - ' + esc(t('pass.to_mail')) : ''}`;
    const three = R[0] === R[1] && R[1] === R[2];
    if (three || res.pool === 'jackpot') {
      document.querySelector('.window').classList.add('win'); $('cabinet').classList.add('celebrate');
      r.classList.add('jackpot'); sfx.jackpot(); coins(res.pool === 'jackpot' ? 90 : 40);
    } else if (near) {
      r.innerHTML = `<b>${esc(t('pass.so_close'))}</b> ` + r.innerHTML; sfx.lose();
    } else {
      for (let k = 0; k < 4; k++) sfx.coin(k);
    }
    spinning = false; D = res.data; header(); road(); challenges();
  }

  document.addEventListener('click', async (e) => {
    const tab = e.target.closest('[data-tab]');
    if (tab) {
      document.querySelectorAll('nav button').forEach(b => b.classList.toggle('on', b === tab));
      document.querySelectorAll('.tab').forEach(s => s.classList.toggle('on', s.id === tab.dataset.tab));
      if (tab.dataset.tab === 'lb') {
        const res = await post('leaderboard');
        $('board').innerHTML = `<tr><th>#</th><th>${esc(t('pass.name'))}</th><th>${esc(t('pass.tier'))}</th><th>XP</th></tr>` +
          ((res && res.rows) || []).map((r, i) => `<tr><td>${i + 1}</td><td>${esc(r.name)}</td><td>${r.tier}</td><td>${r.xp}</td></tr>`).join('');
      }
      return;
    }
    const tier = e.target.closest('.post.claimable');
    if (tier) { const res = await post('claim', { tier: Number(tier.dataset.tier) }); if (res && res.ok) { D = res.data; draw(); toast(res.mailed ? t('pass.to_mail') : t('pass.claimed')); } return; }
    const accept = e.target.closest('[data-accept]');
    if (accept) { accept.disabled = true; const res = await post('acceptChallenge', { id: accept.dataset.accept }); if (res && res.ok) { D = res.data; challenges(); } else accept.disabled = false; return; }
    const rr = e.target.closest('[data-reroll]');
    if (rr) { const res = await post('reroll', { idx: Number(rr.dataset.reroll) }); if (res && res.ok) { D = res.data; challenges(); } return; }
    const car = e.target.closest('[data-car]');
    if (car) { const res = await post('car', { id: Number(car.dataset.car) }); if (res && res.ok) { D = res.data; road(); toast(t('pass.car_here')); } return; }
    if (e.target.id === 'claimAll') { const res = await post('claim', { tier: 'all' }); if (res && res.ok) { D = res.data; draw(); toast(t('pass.claimed_n', { n: res.claimed }) + (res.mailed ? ' - ' + t('pass.to_mail') : '')); } else toast(t('pass.nothing')); return; }
    if (e.target.id === 'mailbox') return post('mailbox');
    if (e.target.id === 'spin' || e.target.closest('#lever')) return spin();
    if (e.target.id === 'close') return post('close');
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !$('app').classList.contains('hidden')) post('close'); });

  function labels() {
    const set = (id, k) => { $(id).textContent = t(k); };
    set('title', 'pass.title_big'); set('lTier', 'pass.tier'); set('lTokens', 'pass.tokens'); set('lToday', 'pass.today');
    set('tRoad', 'pass.tab_road'); set('tCh', 'pass.tab_ch'); set('tSlot', 'pass.tab_slot'); set('tLb', 'pass.tab_lb');
    set('claimAll', 'pass.claim_all'); set('mailbox', 'pass.mailbox'); set('spin', 'pass.spin'); set('slotTitle', 'pass.slot_title');
  }

  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') { D = m.data; STR = m.strings || {}; labels(); $('app').classList.remove('hidden'); draw(); }
    else if (m.action === 'close') $('app').classList.add('hidden');
    else if (m.action === 'progress' && D) { const old = D.tier; Object.assign(D, m.data); header(); challenges(); if (D.tier !== old) road(); }
  });
})();

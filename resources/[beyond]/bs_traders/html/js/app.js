// bs_traders - trade menu UI. Plain JS and inline SVG, no framework or CDN (has to run offline).

(function () {
    'use strict';

    var root = document.getElementById('root');
    var status = document.getElementById('status');
    var current = null;   // last full payload from traders:open
    var filterText = '';
    var catFilter = 'all';   // selected category tab

    function post(name, body, done) {
        fetch('https://bs_traders/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).then(function (r) { return r.json(); })
          .then(function (d) { if (done) done(d); })
          .catch(function () {});
    }

    function flash(text, bad) {
        status.textContent = text;
        status.className = bad ? 'bad' : 'good';
        clearTimeout(flash.t);
        flash.t = setTimeout(function () {
            status.textContent = 'ready';
            status.className = '';
        }, 2200);
    }

    function money(n) { return '$' + Math.floor(n || 0).toLocaleString('en-US'); }

    // Item icons by category, resolved from the item id. Unknown items fall back to a generic crate.

    var ICONS = {
        water:   '<path d="M12 3s6 6.5 6 10.5A6 6 0 016 13.5C6 9.5 12 3 12 3z"/>',
        food:    '<path d="M5 4v16M5 4c2 0 3 1.5 3 4s-1 4-3 4M14 4c-1.5 1-2.5 3-2.5 5.5S13 14 15 14h4M19 4v16"/>',
        med:     '<path d="M4 8h16v10H4zM9 8V5h6v3M12 11v5M9.5 13.5h5"/>',
        ammo:    '<path d="M9 21h6V10l-3-7-3 7zM9 14h6"/>',
        weapon:  '<path d="M3 9h13l3 3h2v3h-6l-2-2H9v4H6v-4H3z"/>',
        attach:  '<path d="M4 10h11v4H4zM15 12h5M7 10V7h3v3"/>',
        armour:  '<path d="M12 3l7 3v6c0 5-3.5 8-7 9-3.5-1-7-4-7-9V6z"/>',
        material:'<path d="M3 8l9-5 9 5-9 5zM3 8v8l9 5 9-5V8"/>',
        tool:    '<path d="M14.5 3a5 5 0 00-4.6 7L3 16.9 5.1 19l6.9-6.9a5 5 0 006.5-6.4l-3 3-2.2-2.2 3-3A5 5 0 0014.5 3z"/>',
        fuel:    '<path d="M4 20V5a1 1 0 011-1h7a1 1 0 011 1v15zM13 9h3l2 2v7a1.5 1.5 0 01-3 0v-4h-2M6 7h5v3H6z"/>',
        wire:    '<path d="M3 17c4 0 4-10 8-10s4 10 8 10M5 17v3M19 17v3"/>',
        trophy:  '<path d="M7 4h10v5a5 5 0 01-10 0zM7 6H4v2a3 3 0 003 3M17 6h3v2a3 3 0 01-3 3M10 14h4v4h-4zM8 20h8"/>',
        crate:   '<path d="M3 7h18v13H3zM3 7l2-4h14l2 4M12 7v13M8 11h1M15 11h1"/>'
    };

    /* Longest/most specific matches first: 'ammo_rifle' must not be caught by
       a looser 'rifle' weapon rule, and 'repair_kit' must not read as 'kit'. */
    var CATEGORY_RULES = [
        [/^att_/,                                   'attach'],
        [/^ammo_/,                                  'ammo'],
        [/water|drink|canteen/,                     'water'],
        [/food|canned|ration|meat|bread/,           'food'],
        [/bandage|medkit|antiseptic|antibiotic|pill|syringe|splint/, 'med'],
        [/armour|armor|plate|vest|helmet/,          'armour'],
        [/pistol|shotgun|rifle|smg|revolver|gun/,   'weapon'],
        [/knife|machete|axe|bat|crowbar/,           'weapon'],
        [/fuel|petrol|gas_can|jerry/,               'fuel'],
        [/wire|electric|circuit|battery/,           'wire'],
        [/tooth|teeth|trophy|skull/,                'trophy'],
        [/toolbox|repair|shovel|lockpick|hammer|wrench|tool/, 'tool'],
        [/scrap|metal|copper|cloth|wood|plank|stone|rubber|plastic|part|engine/, 'material']
    ];

    function iconFor(itemId) {
        var id = String(itemId || '').toLowerCase();
        for (var i = 0; i < CATEGORY_RULES.length; i++) {
            if (CATEGORY_RULES[i][0].test(id)) { return CATEGORY_RULES[i][1]; }
        }
        return 'crate';
    }

    // Use the shared bs_ui icon set (nui://bs_ui/html/js/icons.js) so items look the same as in the inventory.
    // The local category icons below are the fallback when bs_ui is not running.
    function iconSvg(itemId) {
        if (typeof BSIcons !== 'undefined' && BSIcons && BSIcons.get) {
            try { return BSIcons.get(itemId); } catch (err) { /* fall through */ }
        }
        var key = iconFor(itemId);
        return '<svg viewBox="0 0 24 24" class="ico ico-' + key + '" aria-hidden="true">'
             + ICONS[key] + '</svg>';
    }

    // Render

    function render(data) {
        current = data;

        document.getElementById('npcLabel').textContent = data.label || 'Trader';

        var roleEl = document.getElementById('npcRole');
        var roleText = data.role === 'both' ? t('ui.role_both')
                     : data.role === 'quest' ? t('ui.contracts')
                     : data.role === 'clothing' ? t('ui.clothing') : t('ui.role_trader');
        roleEl.textContent = roleText;

        var hasTrade = !!(data.sells || data.buys);
        var hasMissions = !!data.missions;

        document.getElementById('cashWrap').classList.toggle('hidden', !hasTrade);
        document.getElementById('searchWrap').classList.toggle('hidden', !hasTrade);
        if (hasTrade) { document.getElementById('cashVal').textContent = money(data.cash); }

        var tradeTab = document.querySelector('.tab[data-tab="trade"]');
        var missionTab = document.querySelector('.tab[data-tab="missions"]');
        tradeTab.style.display = hasTrade ? '' : 'none';
        missionTab.style.display = hasMissions ? '' : 'none';
        // A single-purpose NPC gets no tab strip at all - a row of one tab is
        // furniture, not navigation.
        document.getElementById('tabs').classList.toggle('hidden', !(hasTrade && hasMissions));

        if (hasMissions) {
            var open = 0;
            (data.missions || []).forEach(function (m) {
                if (m.status === 'ready' || m.status === 'available') { open++; }
            });
            var badge = missionTab.querySelector('.tabcount');
            badge.textContent = open ? String(open) : '';
            badge.classList.toggle('hidden', !open);
        }

        var active = document.querySelector('.tab.on');
        var want = (active && active.dataset.tab) || 'trade';
        if (want === 'trade' && !hasTrade) { want = 'missions'; }
        if (want === 'missions' && !hasMissions) { want = 'trade'; }
        switchTab(want);

        var oN = document.getElementById('outsiderNote');
        oN.textContent = data.outsider ? t('ui.outsider_note', { n: data.surchargePct || 25 }) : '';
        oN.classList.toggle('hidden', !data.outsider);

        renderTrade(data);
        renderMissions(data);
    }

    function catLabel(c) {
        return (c && c.label) ? c.label : t('ui.cat_' + (c && c.id));
    }

    // Shop state: 'buy' (they sell) or 'sell' (they buy), the chosen item and the chosen quantity.
    var mode = 'buy';
    var picked = null;
    var pickedQty = 1;

    function sellable(data) {
        return (data.buys || []).filter(function (e) { return (e.have || 0) > 0; });
    }

    function modeList(data) {
        return mode === 'buy' ? (data.sells || []) : sellable(data);
    }

    // Tabs for the categories that have at least one row in the current list, plus All.
    function renderCatTabs(data) {
        var box = document.getElementById('catTabs');
        var used = {};
        modeList(data).forEach(function (e) { used[e.category || 'misc'] = true; });
        var cats = (data.categories || []).filter(function (c) { return used[c.id]; });
        if (catFilter !== 'all' && !used[catFilter]) { catFilter = 'all'; }
        box.innerHTML = '';
        box.classList.toggle('hidden', cats.length < 2);
        if (cats.length < 2) { catFilter = 'all'; return; }
        function add(id, label) {
            var b = document.createElement('button');
            b.type = 'button';
            b.className = 'cattab' + (catFilter === id ? ' on' : '');
            b.textContent = label;
            b.addEventListener('click', function () { catFilter = id; renderTrade(current); });
            box.appendChild(b);
        }
        add('all', t('ui.cat_all'));
        cats.forEach(function (c) { add(c.id, catLabel(c)); });
    }

    function matchesFilter(row) {
        if (catFilter !== 'all' && (row.category || 'misc') !== catFilter) { return false; }
        if (!filterText) { return true; }
        var hay = ((row.label || '') + ' ' + (row.item || '')).toLowerCase();
        return hay.indexOf(filterText) !== -1;
    }

    function renderTrade(data) {
        var hasSell = (data.sells || []).length > 0;
        var hasBuy = (data.buys || []).length > 0;
        if (mode === 'buy' && !hasSell && hasBuy) { mode = 'sell'; }
        if (mode === 'sell' && !hasBuy && hasSell) { mode = 'buy'; }

        document.getElementById('buyModeCount').textContent = (data.sells || []).length;
        document.getElementById('sellModeCount').textContent = sellable(data).length;
        document.querySelectorAll('.modebtn').forEach(function (b) {
            b.classList.toggle('on', b.dataset.mode === mode);
            b.classList.toggle('hidden', (b.dataset.mode === 'buy' && !hasSell) || (b.dataset.mode === 'sell' && !hasBuy));
        });
        document.getElementById('lhStock').textContent = mode === 'buy' ? t('ui.col_stock') : t('ui.col_carry');

        renderCatTabs(data);

        var list = document.getElementById('shopList');
        list.innerHTML = '';
        var rows = modeList(data).filter(matchesFilter);

        if (!rows.some(function (e) { return e.item === picked; })) {
            picked = rows.length ? rows[0].item : null;
            pickedQty = 1;
        }

        rows.forEach(function (e) { list.appendChild(shopRow(e, data)); });

        if (!rows.length) {
            var p = document.createElement('div');
            p.className = 'colEmpty';
            p.textContent = filterText ? t('ui.no_match', { q: filterText })
                : (mode === 'buy' ? t('ui.nothing_sale') : t('ui.nothing_to_sell'));
            list.appendChild(p);
        }

        renderDetail(data);
    }

    function shopRow(e, data) {
        var row = document.createElement('div');
        row.className = 'shoprow' + (e.item === picked ? ' on' : '') + (e.locked ? ' locked' : '');
        row.dataset.item = e.item;

        var ic = document.createElement('div');
        ic.className = 'ricon';
        ic.innerHTML = iconSvg(e.item);

        var name = document.createElement('div');
        name.className = 'sr-name';
        name.textContent = e.label || e.item;
        if (e.locked) {
            var lk = document.createElement('span');
            lk.className = 'rlock';
            lk.textContent = t('ui.rank_needed', { n: e.minRank || 1 });
            name.appendChild(lk);
        }

        var price = document.createElement('div');
        price.className = 'sr-price';
        price.textContent = money(e.price);
        if (mode === 'buy' && data.outsider) {
            var tag = document.createElement('small');
            tag.className = 'ptag up';
            tag.textContent = '+' + (data.surchargePct || 25) + '%';
            price.appendChild(tag);
        } else if (mode === 'buy' && data.discount && data.discount.total > 0) {
            var tg = document.createElement('small');
            tg.className = 'ptag down';
            tg.textContent = '-' + data.discount.total + '%';
            price.appendChild(tg);
        }

        var stock = document.createElement('div');
        stock.className = 'sr-stock';
        if (mode === 'buy') {
            stock.textContent = e.stock == null ? '∞' : String(e.stock);
            if (e.stock != null && e.stock < 1) { stock.classList.add('out'); }
            else if (e.stock != null && e.stock <= 3) { stock.classList.add('low'); }
        } else {
            stock.textContent = String(e.have || 0);
        }

        row.appendChild(ic);
        row.appendChild(name);
        row.appendChild(price);
        row.appendChild(stock);
        row.addEventListener('click', function () {
            picked = e.item;
            pickedQty = 1;
            renderTrade(current);
        });
        return row;
    }

    function priceLine(label, value, cls) {
        var d = document.createElement('div');
        d.className = 'pl' + (cls ? ' ' + cls : '');
        var a = document.createElement('span'); a.textContent = label;
        var b = document.createElement('b'); b.textContent = value;
        d.appendChild(a); d.appendChild(b);
        return d;
    }

    function renderDetail(data) {
        var entry = null;
        modeList(data).forEach(function (e) { if (e.item === picked) { entry = e; } });
        document.getElementById('dEmpty').classList.toggle('hidden', !!entry);
        document.getElementById('dBody').classList.toggle('hidden', !entry);
        if (!entry) { return; }

        var e = entry;
        document.getElementById('dIcon').innerHTML = iconSvg(e.item);
        document.getElementById('dName').textContent = e.label || e.item;
        document.getElementById('dCat').textContent = catLabel({ id: e.category || 'misc',
            label: ((data.categories || []).filter(function (c) { return c.id === (e.category || 'misc'); })[0] || {}).label });

        var lock = document.getElementById('dLock');
        lock.classList.toggle('hidden', !e.locked);
        lock.textContent = e.locked ? t('ui.rank_needed', { n: e.minRank || 1 }) : '';

        // Price breakdown
        var box = document.getElementById('dPrices');
        var cmp = document.getElementById('dCompare');
        box.innerHTML = '';
        cmp.textContent = '';
        if (mode === 'buy') {
            var info = e.info;
            if (info) { box.appendChild(priceLine(t('ui.base_price'), money(info.base))); }
            if (data.outsider) {
                box.appendChild(priceLine(t('ui.outsider_markup'), '+' + (data.surchargePct || 25) + '%', 'up'));
            } else if (data.discount) {
                if (data.discount.rank > 0) { box.appendChild(priceLine(t('ui.rank_discount'), '-' + data.discount.rank + '%', 'down')); }
                if (data.discount.skill > 0) { box.appendChild(priceLine(t('ui.skill_discount'), '-' + data.discount.skill + '%', 'down')); }
            }
            box.appendChild(priceLine(t('ui.your_price'), money(e.price), 'main'));
            if (info) { cmp.textContent = t('ui.price_compare', { m: money(info.member), o: money(info.outsider) }); }
        } else {
            box.appendChild(priceLine(t('ui.payout_each'), money(e.price), 'main'));
            box.appendChild(priceLine(t('ui.you_carry', { n: e.have || 0 }), ''));
        }

        // Cart: capped by stock and cash when buying, by what is carried when selling.
        var max;
        if (e.locked) { max = 0; }
        else if (mode === 'buy') {
            var byCash = e.price > 0 ? Math.floor((data.cash || 0) / e.price) : 99;
            var byStock = e.stock == null ? 99 : e.stock;
            max = Math.max(0, Math.min(99, byCash, byStock));
        } else { max = Math.max(0, Math.min(999, e.have || 0)); }

        var input = document.getElementById('dQty');
        var action = document.getElementById('dAction');
        input.max = max;
        pickedQty = Math.max(max > 0 ? 1 : 0, Math.min(pickedQty, max));
        input.value = pickedQty;

        function qty() { return Math.max(0, Math.min(parseInt(input.value, 10) || 0, max)); }

        function sync() {
            var q = qty();
            pickedQty = q;
            input.value = q;
            var total = q * e.price;
            document.getElementById('dTotalLbl').textContent = mode === 'buy' ? t('ui.total') : t('ui.you_receive');
            document.getElementById('dTotal').textContent = money(total);
            var after = (data.cash || 0) + (mode === 'buy' ? -total : total);
            var afterEl = document.getElementById('dAfter');
            afterEl.textContent = money(after);
            afterEl.className = after < (data.cash || 0) ? 'down' : (after > (data.cash || 0) ? 'up' : '');
            action.disabled = q < 1;
            action.textContent = (mode === 'buy' ? t('ui.buy') : t('ui.sell')) + ' · ' + money(total);
            if (e.locked) {
                action.textContent = t('ui.locked');
            } else if (max < 1) {
                action.textContent = mode === 'buy'
                    ? ((e.stock != null && e.stock < 1) ? t('ui.out_of_stock') : t('ui.too_expensive'))
                    : t('ui.none_to_sell');
            }
        }

        // Fresh listeners each render: replace the nodes' handlers via cloneNode.
        ['dMinus', 'dPlus', 'dMax', 'dAction', 'dQty'].forEach(function (id) {
            var old = document.getElementById(id);
            var fresh = old.cloneNode(true);
            old.parentNode.replaceChild(fresh, old);
        });
        input = document.getElementById('dQty');
        action = document.getElementById('dAction');
        input.value = pickedQty;
        document.getElementById('dMinus').addEventListener('click', function () { input.value = qty() - 1; sync(); });
        document.getElementById('dPlus').addEventListener('click', function () { input.value = qty() + 1; sync(); });
        document.getElementById('dMax').addEventListener('click', function () { input.value = max; sync(); });
        input.addEventListener('input', sync);
        action.addEventListener('click', function () {
            var q = qty();
            if (q < 1) { return; }
            action.disabled = true;
            post(mode, { item: e.item, qty: q }, function (r) {
                if (r && r.ok) {
                    flash(t(mode === 'buy' ? 'ui.bought' : 'ui.sold', { n: q, item: e.label || e.item }));
                    pickedQty = 1;
                    refresh();
                } else {
                    flash((r && r.reason) || 'failed', true);
                    sync();
                }
            });
        });
        sync();
    }

    function renderMissions(data) {
        var list = document.getElementById('missionList');
        var empty = document.getElementById('noMissions');
        list.innerHTML = '';

        var missions = data.missions || [];
        empty.classList.toggle('hidden', missions.length > 0);

        // Sort actionable first: ready to hand in, then available, then in progress, then on cooldown.
        var rank = { ready: 0, available: 1, active: 2, cooldown: 3 };
        missions.slice().sort(function (a, b) {
            return (rank[a.status] == null ? 9 : rank[a.status])
                 - (rank[b.status] == null ? 9 : rank[b.status]);
        }).forEach(function (m) {
            var tpl = document.getElementById('tplMission');
            var node = tpl.content.firstElementChild.cloneNode(true);
            node.classList.add(m.status);

            node.querySelector('.mname').textContent = m.label;

            var pill = node.querySelector('.mstatus');
            pill.textContent = m.status === 'ready' ? t('ui.ready')
                             : m.status === 'active' ? t('ui.in_progress')
                             : m.status === 'cooldown' ? fmtTime(m.cooldown)
                             : t('ui.available');

            node.querySelector('.mdesc').textContent = m.desc || '';
            node.querySelector('.mxp').textContent = (m.reward.xp || 0) + ' XP';
            node.querySelector('.mcash').textContent = money(m.reward.money);

            var pct = m.target ? Math.min(100, Math.floor(100 * m.progress / m.target)) : 0;
            node.querySelector('.mfill').style.width = pct + '%';
            node.querySelector('.mtext').textContent = m.progress + ' / ' + m.target;

            // A mission not yet taken has no progress worth drawing - an empty
            // bar reading 0/50 looks like a mission you have started and failed.
            node.querySelector('.mprogress').classList.toggle(
                'hidden', m.status === 'available' || m.status === 'cooldown');

            var buttons = node.querySelector('.mbuttons');

            if (m.status === 'available') {
                buttons.appendChild(btn('btn-accept', t('ui.accept'), function () {
                    post('missionAccept', { missionId: m.id }, done('Accepted: ' + m.label));
                }));
            } else if (m.status !== 'cooldown') {
                if (m.status === 'ready') {
                    buttons.appendChild(btn('btn-turnin', t('ui.turn_in'), function () {
                        post('missionTurnIn', { missionId: m.id }, done('Completed: ' + m.label));
                    }));
                }
                buttons.appendChild(btn('btn-abandon', t('ui.abandon'), function () {
                    post('missionAbandon', { missionId: m.id }, done('Abandoned: ' + m.label));
                }));
            }

            list.appendChild(node);
        });
    }

    function btn(cls, text, fn) {
        var b = document.createElement('button');
        b.className = cls;
        b.textContent = text;
        b.addEventListener('click', fn);
        return b;
    }

    function done(msg) {
        return function (r) {
            if (r && r.ok) { flash(msg); refresh(); }
            else { flash((r && r.reason) || 'failed', true); }
        };
    }

    function fmtTime(s) {
        s = s || 0;
        if (s < 60) { return s + 's'; }
        if (s < 3600) { return Math.ceil(s / 60) + 'm'; }
        return Math.ceil(s / 3600) + 'h';
    }

    function refresh() {
        post('refresh', {}, function (r) { if (r && r.ok) { render(r); } });
    }

    // Wiring

    function switchTab(name) {
        document.querySelectorAll('.tab').forEach(function (t) {
            t.classList.toggle('on', t.dataset.tab === name);
        });
        document.querySelectorAll('main section').forEach(function (s) {
            s.classList.toggle('on', s.dataset.page === name);
        });
    }

    // js/debug.js sets this while /traderdebug is open. The two menus share one
    // NUI page and both listen document-wide, so without this a debug-form
    // Escape or click would also fire this menu's own close/tab handlers.
    function debugIsOpen() { return !!window.__bsNpcsDebugOpen; }

    document.addEventListener('click', function (e) {
        if (debugIsOpen()) return;
        var t = e.target;
        var tab = t.closest ? t.closest('.tab') : null;
        if (tab) { switchTab(tab.dataset.tab); return; }
        if (t.id === 'close') { post('close', {}); }
    });

    document.addEventListener('keyup', function (e) {
        if (debugIsOpen()) return;
        if (e.key === 'Escape') { post('close', {}); }
    });

    // Drag / resize via the shared helper; the grip doubles as the corner handle and resets on double-click.
    var panel = document.getElementById('panel');
    if (window.BSWindow) {
        BSWindow.make(panel, { id: 'bs_traders', handle: panel.querySelector('header'), grip: '#grip', minW: 720, minH: 460 });
        var dbgPanel = document.getElementById('dbgPanel');
        if (dbgPanel) BSWindow.make(dbgPanel, { id: 'bs_traders_debug', handle: dbgPanel.querySelector('header'), minW: 640, minH: 420 });
    }

    document.querySelectorAll('.modebtn').forEach(function (b) {
        b.addEventListener('click', function () {
            mode = b.dataset.mode;
            picked = null;
            pickedQty = 1;
            catFilter = 'all';
            if (current) { renderTrade(current); }
        });
    });

    var search = document.getElementById('search');
    search.addEventListener('input', function () {
        filterText = search.value.trim().toLowerCase();
        if (current) { renderTrade(current); }
    });

    // Objective tracker. Driven by pushTracker() in cl_main.lua, which sends the full list on every change. No state is kept here so it cannot disagree with the server.

    var tracker = document.getElementById('tracker');
    var tkList = document.getElementById('tkList');

    // Rows are keyed by mission id and updated in place instead of rebuilt, so running animations survive. Animations fire on the change in count.
    var tkRows = {};   // [missionId] = { el, name, what, count, fill, done, prev, wasReady }

    function buildRow(m) {
        var row = document.createElement('div');
        row.className = 'tkrow tkenter';

        var name = document.createElement('div');
        name.className = 'tkname';

        var obj = document.createElement('div');
        obj.className = 'tkobj';
        var what = document.createElement('span');
        var count = document.createElement('span');
        count.className = 'tkcount';
        obj.appendChild(what);
        obj.appendChild(count);

        var bar = document.createElement('div');
        bar.className = 'tkbar';
        var fill = document.createElement('div');
        fill.className = 'tkfill';
        bar.appendChild(fill);

        var done = document.createElement('div');
        done.className = 'tkdone';
        done.textContent = t('ui.return_hand_in');

        // The floating "+N". Lives in the row so it can be positioned against
        // it, and is only ever made visible for the length of one animation.
        var pop = document.createElement('div');
        pop.className = 'tkpop';

        row.appendChild(name);
        row.appendChild(obj);
        row.appendChild(bar);
        row.appendChild(done);
        row.appendChild(pop);

        tkList.appendChild(row);

        // Let the enter animation run once, then take the class back off so a
        // later re-order does not replay it.
        setTimeout(function () { row.classList.remove('tkenter'); }, 450);

        return { el: row, name: name, what: what, count: count,
                 fill: fill, done: done, pop: pop, prev: null, wasReady: false };
    }

    // Restart a CSS animation: remove the class, force a layout, add it back.
    function replay(el, cls) {
        el.classList.remove(cls);
        void el.offsetWidth;
        el.classList.add(cls);
    }

    function renderTracker(missions, hidden) {
        missions = missions || [];

        if (hidden || !missions.length) {
            tracker.classList.add('hidden');
            if (!missions.length) { tkRows = {}; tkList.innerHTML = ''; }
            return;
        }

        var seen = {};

        // Finished missions first. Order uses flex `order` instead of moving nodes, which would restart animations.
        missions.slice().sort(function (a, b) {
            var ar = a.progress >= a.target ? 0 : 1;
            var br = b.progress >= b.target ? 0 : 1;
            return ar - br;
        }).forEach(function (m, index) {
            seen[m.id] = true;

            var r = tkRows[m.id] || (tkRows[m.id] = buildRow(m));
            r.el.style.order = index;

            var progress = Math.max(0, Math.min(m.progress || 0, m.target));
            var ready = progress >= m.target;
            var first = r.prev === null;
            var gained = !first && progress > r.prev;

            r.name.textContent = m.label || m.id;
            r.what.textContent = m.kind === 'gather'
                ? t('ui.collect', { item: m.itemLabel || m.item || t('ui.items') })
                : t('ui.eliminate');
            r.count.textContent = progress + ' / ' + m.target;
            r.fill.style.width = (m.target ? (100 * progress / m.target) : 0) + '%';
            r.el.classList.toggle('ready', ready);

            if (gained) {
                // The three beats of the same event: the row registers the
                // hit, the number punches, and the amount floats off it.
                replay(r.el, 'tkhit');
                replay(r.count, 'tkbump');

                r.pop.textContent = '+' + (progress - r.prev);
                replay(r.pop, 'tkfloat');
            }

            // Completion is its own, louder beat - and only on the frame it
            // actually completes, never every push thereafter.
            if (ready && !r.wasReady && !first) { replay(r.el, 'tkcomplete'); }

            r.prev = progress;
            r.wasReady = ready;
        });

        // Anything no longer in the list (turned in, abandoned) leaves.
        Object.keys(tkRows).forEach(function (id) {
            if (seen[id]) { return; }
            var r = tkRows[id];
            delete tkRows[id];
            r.el.classList.add('tkexit');
            setTimeout(function () {
                if (r.el.parentNode) { r.el.parentNode.removeChild(r.el); }
            }, 320);
        });

        tracker.classList.remove('hidden');
    }

    window.addEventListener('message', function (event) {
        var msg = event.data || {};

        if (msg.action === 'tracker') {
            renderTracker(msg.missions, msg.hidden);
            return;
        }

        if (msg.action === 'open') {
            filterText = '';
            search.value = '';
            render(msg.data);
            root.classList.remove('hidden');
        } else if (msg.action === 'close') {
            root.classList.add('hidden');
        } else if (msg.action === 'progress' && current) {
            // A kill ticked a mission forward while the menu is open - refresh
            // from the server rather than guessing the new state locally.
            refresh();
        }
    });
})();

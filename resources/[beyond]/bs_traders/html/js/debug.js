// bs_traders - trader editor (admin). Opened by /traderdebug, F10 or the bs:traders:openEditor event.
// Separate script, root (#dbgRoot) and `debug*` action namespace from app.js; both share one NUI page and must not answer each other's messages. Lua side: client/cl_debug.lua; the link between them is window.__bsNpcsDebugOpen in app.js.
// Nothing here is trusted: the server validates and re-checks admin on every save.

(function () {
    'use strict';

    var root = document.getElementById('dbgRoot');
    var statusEl = document.getElementById('dbgStatus');

    var npcs = {};       // [id] = effective npc from the server
    var missions = {};   // [id] = effective mission from the server
    var zones = [];      // { id, label, x, y, z }
    var factions = [];   // vanilla faction ids
    var defaultCats = [];
    var listMode = 'npcs';       // 'npcs' | 'missions'
    var selected = null;         // id of whatever is loaded in a form, or null
    var isNew = false;           // true while the id field is still editable
    var dirty = false;

    // Clipboard: copy/paste moves a trader's settings, not the trader. Paste only fills the form until Save and never carries id or position. Duplicate makes a real second trader (see dbgDuplicate).
    var clipboard = null;

    function tr(key, vars, fallback) {
        try {
            var v = (typeof t === 'function') ? t(key, vars) : null;
            if (v && v !== key) return v;
        } catch (e) { /* fall through */ }
        return fallback || key;
    }

    function $(id) { return document.getElementById(id); }

    function post(name, body, done) {
        fetch('https://bs_traders/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).then(function (r) { return r.json(); })
          .then(function (d) { if (done) done(d); })
          .catch(function () { if (done) done({ ok: false, reason: tr('trd.timeout') }); });
    }

    function flash(text, bad) {
        statusEl.textContent = text;
        statusEl.style.color = bad ? 'var(--blood)' : 'var(--good)';
        clearTimeout(flash.t);
        flash.t = setTimeout(function () { statusEl.textContent = tr('ui.ready', null, 'ready'); statusEl.style.color = ''; }, 2600);
    }

    function setDirty(v) {
        dirty = v;
        $('dbgDirty').classList.toggle('hidden', !v);
    }

    // Open/close

    window.addEventListener('message', function (event) {
        var msg = event.data || {};

        if (msg.action === 'debugOpen') {
            npcs = {}; (msg.npcs || []).forEach(function (n) { npcs[n.id] = n; });
            missions = {}; (msg.missions || []).forEach(function (m) { missions[m.id] = m; });
            zones = msg.zones || [];
            factions = msg.factions || [];
            defaultCats = msg.defaultCategories || [];
            selected = null;
            window.__bsNpcsDebugOpen = true;
            root.classList.remove('hidden');
            buildStaticSelects();
            renderList();
            showEmpty();
        } else if (msg.action === 'debugClose') {
            window.__bsNpcsDebugOpen = false;
            root.classList.add('hidden');
        }
    });

    document.addEventListener('keyup', function (e) {
        if (!window.__bsNpcsDebugOpen) return;
        if (e.key === 'Escape') post('debugClose', {});
    });

    $('dbgClose').addEventListener('click', function () { post('debugClose', {}); });

    // Static selects

    function opt(value, text) {
        var o = document.createElement('option');
        o.value = value; o.textContent = text;
        return o;
    }

    function pad2(n) { return (n < 10 ? '0' : '') + n + ':00'; }

    function buildStaticSelects() {
        var fac = $('fFaction'); fac.innerHTML = '';
        fac.appendChild(opt('', tr('ui.fac_none', null, 'None / neutral')));
        factions.forEach(function (f) { fac.appendChild(opt(f, tr('ui.fac_' + f, null, f))); });

        var zn = $('fZone'); zn.innerHTML = '';
        zn.appendChild(opt('', tr('ui.zone_none', null, '(none)')));
        zones.forEach(function (z) { zn.appendChild(opt(z.id, z.label + ' (' + z.id + ')')); });

        ['fFrom', 'fTo'].forEach(function (id) {
            var sel = $(id); sel.innerHTML = '';
            sel.appendChild(opt('-1', tr('ui.dbg_always', null, 'always open')));
            for (var h = 0; h < 24; h++) sel.appendChild(opt(String(h), pad2(h)));
        });

        var ff = $('dbgFilterFaction'); ff.innerHTML = '';
        ff.appendChild(opt('*', tr('ui.dbg_all_factions', null, 'All factions')));
        ff.appendChild(opt('', tr('ui.fac_none', null, 'None / neutral')));
        factions.forEach(function (f) { ff.appendChild(opt(f, tr('ui.fac_' + f, null, f))); });

        var fz = $('dbgFilterZone'); fz.innerHTML = '';
        fz.appendChild(opt('*', tr('ui.dbg_all_zones', null, 'All zones')));
        zones.forEach(function (z) { fz.appendChild(opt(z.id, z.label)); });
    }

    // Zone ids in config may omit the faction_ prefix; map to the list entry.
    function zoneKey(id) {
        if (!id) return '';
        for (var i = 0; i < zones.length; i++) if (zones[i].id === id) return id;
        for (var j = 0; j < zones.length; j++) if (zones[j].id === 'faction_' + id) return zones[j].id;
        return id;
    }

    // Sidebar

    function passesFilter(n) {
        var q = $('dbgSearch').value.trim().toLowerCase();
        if (q && ((n.label || '') + ' ' + n.id).toLowerCase().indexOf(q) === -1) return false;
        var ff = $('dbgFilterFaction').value;
        if (ff !== '*' && (n.faction || '') !== ff) return false;
        var fz = $('dbgFilterZone').value;
        if (fz !== '*' && zoneKey(n.safezone) !== fz) return false;
        return true;
    }

    function renderList() {
        var box = $('dbgList');
        box.innerHTML = '';
        $('dbgFilters').style.display = listMode === 'npcs' ? '' : 'none';

        var ids, source;
        if (listMode === 'npcs') { source = npcs; ids = Object.keys(npcs); }
        else { source = missions; ids = Object.keys(missions); }
        ids.sort();

        ids.forEach(function (id) {
            var row = source[id];
            if (listMode === 'npcs' && !passesFilter(row)) return;
            var el = document.createElement('div');
            el.className = 'dbgListItem' + (id === selected ? ' on' : '')
                + (row.disabled ? ' disabled' : '') + (!row.hasConfig ? ' custom' : '');
            el.innerHTML = '<span></span><span class="tag"></span>';
            el.children[0].textContent = row.label || id;
            el.children[1].textContent = (listMode === 'npcs' && row.faction)
                ? tr('ui.fac_' + row.faction, null, row.faction).slice(0, 8)
                : (row.hasConfig ? 'cfg' : 'custom');
            el.addEventListener('click', function () {
                if (listMode === 'npcs') selectNpc(id); else selectMission(id);
            });
            box.appendChild(el);
        });
    }

    ['input', 'change'].forEach(function (ev) {
        ['dbgSearch', 'dbgFilterFaction', 'dbgFilterZone'].forEach(function (id) { $(id).addEventListener(ev, renderList); });
    });

    document.querySelectorAll('.dbgSideTab').forEach(function (btn) {
        btn.addEventListener('click', function () {
            listMode = btn.dataset.list;
            document.querySelectorAll('.dbgSideTab').forEach(function (b) {
                b.classList.toggle('on', b === btn);
            });
            selected = null;
            renderList();
            showEmpty();
        });
    });

    $('dbgNew').addEventListener('click', function () {
        selected = null;
        isNew = true;
        if (listMode === 'npcs') loadNpcForm(null); else loadMissionForm(null);
    });

    function showEmpty() {
        post('debugPreviewClear', {});
        setDirty(false);
        $('dbgEmpty').classList.remove('hidden');
        $('dbgNpcForm').classList.add('hidden');
        $('dbgMissionForm').classList.add('hidden');
    }

    // Categories

    function catText(c) { return c.label || tr('ui.cat_' + c.id, null, c.id); }

    function readCats() {
        var out = [];
        document.querySelectorAll('#fCats .dbgRow').forEach(function (row) {
            var id = row.querySelector('.cId').value.trim().toLowerCase();
            if (!id) return;
            out.push({ id: id, label: row.querySelector('.cLabel').value.trim() });
        });
        return out;
    }

    function addCatRow(c, editableId) {
        var node = $('dbgTplCatRow').content.firstElementChild.cloneNode(true);
        var idEl = node.querySelector('.cId');
        idEl.value = c ? c.id : '';
        idEl.readOnly = !editableId;
        var lb = node.querySelector('.cLabel');
        lb.value = c ? (c.label || '') : '';
        lb.placeholder = c ? tr('ui.cat_' + c.id, null, c.id) : tr('ui.dbg_label_lc', null, 'label');
        node.querySelector('.dRemove').addEventListener('click', function () { node.remove(); refreshCatSelects(); onEdit(); });
        $('fCats').appendChild(node);
    }

    function fillCatSelect(sel, value) {
        var cats = readCats();
        sel.innerHTML = '';
        cats.forEach(function (c) { sel.appendChild(opt(c.id, catText(c))); });
        if (value && !cats.some(function (c) { return c.id === value; })) sel.appendChild(opt(value, value));
        sel.value = value || (cats.length ? cats[cats.length - 1].id : '');
    }

    function refreshCatSelects() {
        document.querySelectorAll('#fSells .dCat, #fBuys .dCat').forEach(function (sel) { fillCatSelect(sel, sel.value); });
    }

    $('fCats').addEventListener('input', function (e) {
        if (e.target.classList.contains('cId') && !e.target.readOnly) {
            e.target.value = e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '');
        }
        refreshCatSelects();
    });

    // Trade rows

    function addRow(containerId, tplId, fill) {
        var tpl = $(tplId);
        var node = tpl.content.firstElementChild.cloneNode(true);
        if (fill) fill(node);
        node.querySelector('.dRemove').addEventListener('click', function () { node.remove(); onEdit(); });
        $(containerId).appendChild(node);
        return node;
    }

    function addTradeRow(containerId, e) {
        var buying = containerId === 'fBuys';
        addRow(containerId, 'dbgTplTradeRow', function (node) {
            node.classList.toggle('hideStock', buying);
            node.querySelector('.dItem').value = (e && e.item) || '';
            node.querySelector('.dPrice').value = (e && e.price != null) ? e.price : '';
            node.querySelector('.dStock').value = (e && e.stock != null) ? e.stock : '';
            node.querySelector('.dRestockAmt').value = (e && e.restockAmount) ? e.restockAmount : '';
            node.querySelector('.dRank').value = (e && e.minRank) ? e.minRank : '';
            fillCatSelect(node.querySelector('.dCat'), e && e.category);
        });
    }

    document.querySelectorAll('.dbgAddRow').forEach(function (el) {
        el.addEventListener('click', function () {
            var which = el.dataset.add;
            if (which === 'sells') addTradeRow('fSells');
            else if (which === 'buys') addTradeRow('fBuys');
            else if (which === 'cats') addCatRow(null, true);
            else if (which === 'filter') addRow('mFilter', 'dbgTplFilterRow');
            onEdit();
        });
    });

    function tradeRows(containerId, list) {
        $(containerId).innerHTML = '';
        (list || []).forEach(function (e) { addTradeRow(containerId, e); });
    }

    function numOrNull(v) { var n = parseFloat(v); return isNaN(n) ? null : n; }

    function readTradeRows(containerId) {
        var out = [], nodes = [];
        document.querySelectorAll('#' + containerId + ' .dbgRow').forEach(function (row) {
            var item = row.querySelector('.dItem').value.trim();
            if (!item) return;
            var entry = { item: item, price: numOrNull(row.querySelector('.dPrice').value) };
            if (entry.price === null) entry.price = 0;
            var st = row.querySelector('.dStock').value;
            if (st !== '') entry.stock = parseInt(st, 10);
            var ra = row.querySelector('.dRestockAmt').value;
            if (ra !== '') entry.restockAmount = parseInt(ra, 10);
            var rk = row.querySelector('.dRank').value;
            if (rk !== '') entry.minRank = parseInt(rk, 10);
            entry.category = row.querySelector('.dCat').value;
            out.push(entry); nodes.push(row);
        });
        out._nodes = nodes;
        return out;
    }

    function filterRows(list) {
        $('mFilter').innerHTML = '';
        (list || []).forEach(function (v) {
            addRow('mFilter', 'dbgTplFilterRow', function (node) { node.querySelector('.dFilter').value = v; });
        });
    }

    function readFilterRows() {
        var out = [];
        document.querySelectorAll('#mFilter .dFilter').forEach(function (input) {
            var v = input.value.trim();
            if (v) out.push(v);
        });
        return out;
    }

    // Reading and validating the form

    function readForm() {
        var links = [];
        document.querySelectorAll('#fMissionLinks input:checked').forEach(function (b) { links.push(b.value); });
        return {
            label: $('fLabel').value.trim(),
            role: $('fRole').value,
            model: $('fModel').value.trim(),
            scenario: $('fScenario').value.trim(),
            heading: numOrNull($('fHeading').value),
            x: numOrNull($('fX').value), y: numOrNull($('fY').value), z: numOrNull($('fZ').value),
            clothing: $('fNpcClothing').checked,
            disabled: $('fNpcDisabled').checked,
            faction: $('fFaction').value,
            safezone: $('fZone').value,
            categories: readCats(),
            openFrom: parseInt($('fFrom').value, 10), openTo: parseInt($('fTo').value, 10),
            priceMult: numOrNull($('fMult').value),
            rankDiscount: numOrNull($('fRankDisc').value) || 0,
            restock: parseInt($('fRestock').value, 10) || 0,
            blipOn: $('fBlip').checked,
            blipSprite: parseInt($('fBlipSprite').value, 10),
            blipColor: parseInt($('fBlipColor').value, 10),
            notes: $('fNotes').value,
            sells: readTradeRows('fSells'),
            buys: readTradeRows('fBuys'),
            missions: links
        };
    }

    function clearErrors() {
        document.querySelectorAll('#dbgNpcForm [data-err]').forEach(function (el) { el.textContent = ''; });
        document.querySelectorAll('#dbgNpcForm .bad').forEach(function (el) { el.classList.remove('bad'); });
    }

    // errs: [{ field, key, vars, row }] - row is 1-based among non-empty rows.
    function showErrors(errs, form) {
        clearErrors();
        var lists = { sells: form && form.sells, buys: form && form.buys };
        errs.forEach(function (e) {
            var holder = document.querySelector('#dbgNpcForm [data-err="' + e.field + '"]');
            var msg = tr(e.key, e.vars, e.key);
            if (e.row) {
                msg = tr('ui.v_row_n', { n: e.row }, 'Row ' + e.row) + ': ' + msg;
                var nodes = lists[e.field] && lists[e.field]._nodes;
                if (nodes && nodes[e.row - 1]) nodes[e.row - 1].classList.add('bad');
            }
            if (holder) holder.textContent = holder.textContent ? holder.textContent + ' | ' + msg : msg;
            var input = holder && holder.previousElementSibling;
            if (input && input.tagName !== 'EM' && !e.row) input.classList.add('bad');
        });
    }

    // Mirrors the server rules so most mistakes show before a round trip.
    function validateLocal(id, f) {
        var errs = [];
        function add(field, key, vars, row) { errs.push({ field: field, key: key, vars: vars, row: row }); }
        if (!/^[A-Za-z0-9_\-]{2,48}$/.test(id)) add('id', 'ui.v_id');
        if (!f.label || f.label.length > 48) add('label', 'ui.v_label');
        if (!/^[A-Za-z0-9_]{1,64}$/.test(f.model)) add('model', 'ui.v_model');
        if (f.heading === null) add('heading', 'ui.v_heading');
        if (f.x === null || f.y === null || f.z === null) add('xyz', 'ui.v_coords');
        var catIds = {};
        f.categories.forEach(function (c) {
            if (!/^[a-z0-9_]{1,16}$/.test(c.id) || catIds[c.id]) add('categories', 'ui.v_category_id', { id: c.id });
            catIds[c.id] = true;
        });
        if ((f.openFrom >= 0) !== (f.openTo >= 0) || (f.openFrom >= 0 && f.openFrom === f.openTo)) add('hours', 'ui.v_hours');
        if (f.priceMult === null || f.priceMult < 0.1 || f.priceMult > 10) add('priceMult', 'ui.v_price_mult');
        if (f.rankDiscount < 0 || f.rankDiscount > 15) add('rankDiscount', 'ui.v_rank_disc');
        if (f.restock !== 0 && (f.restock < 30 || f.restock > 604800)) add('restock', 'ui.v_restock');
        if (!(f.blipSprite >= 1 && f.blipSprite <= 900)) add('blipSprite', 'ui.v_blip_sprite');
        if (!(f.blipColor >= 0 && f.blipColor <= 85)) add('blipColor', 'ui.v_blip_color');
        ['sells', 'buys'].forEach(function (k) {
            var seen = {};
            f[k].forEach(function (r, i) {
                var n = i + 1;
                if (!/^[A-Za-z0-9_\-]{1,48}$/.test(r.item)) add(k, 'ui.v_item', null, n);
                if (seen[r.item]) add(k, 'ui.v_dup_item', { item: r.item }, n);
                seen[r.item] = true;
                if (!(r.price > 0)) add(k, 'ui.v_price', null, n);
                if (r.stock !== undefined && !(r.stock >= 0)) add(k, 'ui.v_stock', null, n);
                if (r.restockAmount !== undefined && !(r.restockAmount > 0)) add(k, 'ui.v_restock_amt', null, n);
                if (r.minRank !== undefined && !(r.minRank >= 0 && r.minRank <= 10)) add(k, 'ui.v_min_rank', null, n);
                if (r.category && !catIds[r.category]) add(k, 'ui.v_cat_unknown', { cat: r.category }, n);
            });
        });
        return errs;
    }

    // Live preview of the player shop (tabs, prices after the multiplier, hours).
    function refreshPreview() {
        var f = readForm();
        var box = $('fShopPreview');
        box.innerHTML = '';
        var meta = document.createElement('div');
        meta.className = 'pvMeta';
        var parts = [];
        parts.push(f.faction ? tr('ui.fac_' + f.faction, null, f.faction) : tr('ui.fac_none', null, 'None / neutral'));
        parts.push(f.openFrom >= 0 ? pad2(f.openFrom) + ' - ' + pad2(f.openTo) : tr('ui.dbg_always', null, 'always open'));
        parts.push('x' + (f.priceMult === null ? '?' : f.priceMult));
        if (f.disabled) parts.push(tr('ui.dbg_disabled', null, 'disabled'));
        meta.textContent = f.label + ' - ' + parts.join(' | ');
        box.appendChild(meta);

        var used = {};
        f.sells.concat(f.buys).forEach(function (r) { used[r.category] = true; });
        var tabs = document.createElement('div');
        tabs.className = 'pvTabs';
        f.categories.forEach(function (c) {
            if (!used[c.id]) return;
            var tb = document.createElement('span');
            tb.className = 'pvTab'; tb.textContent = catText(c);
            tabs.appendChild(tb);
        });
        box.appendChild(tabs);

        f.sells.slice(0, 8).forEach(function (r) {
            var line = document.createElement('div');
            line.className = 'pvRow';
            var a = document.createElement('span'); a.textContent = r.item + (r.minRank ? '  [R' + r.minRank + ']' : '');
            var b = document.createElement('span');
            b.textContent = '$' + Math.max(1, Math.round((r.price || 0) * (f.priceMult || 1)));
            line.appendChild(a); line.appendChild(b);
            box.appendChild(line);
        });
    }

    function onEdit() {
        if ($('dbgNpcForm').classList.contains('hidden')) return;
        setDirty(true);
        refreshPreview();
    }

    $('dbgNpcForm').addEventListener('input', onEdit);
    $('dbgNpcForm').addEventListener('change', onEdit);

    // NPC

    function fillForm(n) {
        $('fNpcDisabled').checked = !!(n && n.disabled);
        $('fNpcClothing').checked = !!(n && n.clothing);
        $('fLabel').value = n ? n.label : '';
        $('fRole').value = n ? n.role : 'trader';
        $('fModel').value = n ? n.model : 'a_m_m_farmer_01';
        $('fScenario').value = (n && n.scenario) || '';
        $('fHeading').value = n ? n.heading : 0;
        $('fX').value = n && n.coords ? n.coords.x.toFixed(2) : '';
        $('fY').value = n && n.coords ? n.coords.y.toFixed(2) : '';
        $('fZ').value = n && n.coords ? n.coords.z.toFixed(2) : '';

        $('fFaction').value = (n && n.faction) || '';
        $('fZone').value = zoneKey(n && n.safezone);
        $('fFrom').value = String(n && n.openFrom != null ? n.openFrom : -1);
        $('fTo').value = String(n && n.openTo != null ? n.openTo : -1);
        $('fMult').value = n && n.priceMult != null ? n.priceMult : 1;
        $('fRankDisc').value = n && n.rankDiscount != null ? n.rankDiscount : 0;
        $('fRestock').value = n && n.restock != null ? n.restock : 0;
        $('fBlip').checked = !!(n && n.blipOn);
        $('fBlipSprite').value = n && n.blipSprite != null ? n.blipSprite : 52;
        $('fBlipColor').value = n && n.blipColor != null ? n.blipColor : 2;
        $('fNotes').value = (n && n.notes) || '';

        $('fCats').innerHTML = '';
        var cats = (n && n.categories && n.categories.length) ? n.categories
            : defaultCats.map(function (id) { return { id: id, label: '' }; });
        cats.forEach(function (c) { addCatRow(c, false); });

        tradeRows('fSells', n ? n.sells : []);
        tradeRows('fBuys', n ? n.buys : []);

        var linksBox = $('fMissionLinks');
        linksBox.innerHTML = '';
        var have = (n && n.missions) || [];
        Object.keys(missions).sort().forEach(function (mid) {
            var label = document.createElement('label');
            var box = document.createElement('input');
            box.type = 'checkbox';
            box.value = mid;
            box.checked = have.indexOf(mid) !== -1;
            label.appendChild(box);
            label.appendChild(document.createTextNode(missions[mid].label || mid));
            linksBox.appendChild(label);
        });
    }

    function loadNpcForm(id) {
        selected = id;
        isNew = !id;
        var n = id ? npcs[id] : null;

        // Clear any model preview left from the previous form so it does not look like the selected NPC.
        post('debugPreviewClear', {});
        $('fPreviewHint').textContent = '';

        $('dbgEmpty').classList.add('hidden');
        $('dbgMissionForm').classList.add('hidden');
        $('dbgNpcForm').classList.remove('hidden');

        var idInput = $('fNpcId');
        idInput.value = id || '';
        idInput.readOnly = !isNew;

        $('dbgPaste').disabled = !clipboard;
        $('dbgDuplicate').style.visibility = isNew ? 'hidden' : 'visible';
        $('dbgDuplicate').textContent = tr('ui.duplicate', null, 'duplicate');
        $('dbgDupId').classList.add('hidden');

        fillForm(n);
        clearErrors();

        $('fZoneHint').textContent = isNew
            ? tr('ui.dbg_hint_new', null, 'New NPCs have no safe zone to anchor to - click "use my position" or type coordinates by hand.')
            : (n && n.hasConfig ? tr('ui.dbg_hint_abs', null, 'Saving writes an absolute position override, even if you do not touch these fields.') : '');

        var resetBtn = $('dbgResetOrDelete');
        resetBtn.textContent = isNew ? '' : ((n && n.hasConfig) ? tr('ui.dbg_reset', null, 'Reset to default') : tr('ui.dbg_delete', null, 'Delete'));
        resetBtn.style.visibility = isNew ? 'hidden' : 'visible';
        resetBtn.dataset.armed = '0';

        // A not-yet-saved NPC has no server id, so 'teleport to NPC' has nowhere to go until it has been saved once.
        $('dbgTeleport').style.visibility = isNew ? 'hidden' : 'visible';

        setDirty(false);
        refreshPreview();
        renderList();
    }

    function selectNpc(id) { isNew = false; loadNpcForm(id); }

    $('dbgDiscard').addEventListener('click', function () {
        loadNpcForm(selected);
        flash(tr('ui.dbg_discarded', null, 'Changes discarded'));
    });

    $('dbgTeleport').addEventListener('click', function () {
        if (!selected) return;
        post('debugTeleport', { npcId: selected }, function (r) {
            if (!r || !r.ok) { flash((r && r.reason) || tr('ui.dbg_tp_failed', null, 'Teleport failed'), true); return; }
            flash(tr('ui.dbg_teleported', null, 'Teleported'));
        });
    });

    $('dbgPreviewModel').addEventListener('click', function () {
        var model = $('fModel').value.trim();
        var hint = $('fPreviewHint');
        if (!model) { flash(tr('ui.dbg_type_model', null, 'Type a model name first'), true); return; }

        post('debugPreviewModel', { model: model }, function (r) {
            if (!r || !r.ok) {
                flash((r && r.reason) || tr('ui.dbg_prev_failed', null, 'Could not preview that model'), true);
                hint.textContent = '';
                return;
            }
            // No HTML thumbnail (see cl_debug.lua).
            hint.textContent = tr('ui.dbg_prev_hint', null, 'Standing beside you until you pick something else or close this menu.');
        });
    });

    $('dbgUseHere').addEventListener('click', function () {
        post('debugHere', {}, function (r) {
            if (!r || !r.ok) { flash(tr('ui.dbg_pos_failed', null, 'Could not get your position'), true); return; }
            $('fX').value = r.x.toFixed(2);
            $('fY').value = r.y.toFixed(2);
            $('fZ').value = r.z.toFixed(2);
            $('fHeading').value = r.heading.toFixed(1);
            onEdit();
        });
    });

    $('dbgSave').addEventListener('click', function () {
        var id = $('fNpcId').value.trim();
        var f = readForm();
        var errs = validateLocal(id, f);
        if (errs.length) {
            showErrors(errs, f);
            flash(tr('ui.dbg_fix_errors', { n: errs.length }, 'Fix the highlighted fields'), true);
            return;
        }
        clearErrors();

        post('debugSaveNpc', { npcId: id, patch: f }, function (r) {
            if (!r || !r.ok) {
                if (r && r.errors) {
                    showErrors(r.errors, f);
                    flash(tr('ui.dbg_fix_errors', { n: r.errors.length }, 'Fix the highlighted fields'), true);
                } else {
                    flash((r && r.reason) || tr('ui.dbg_save_failed', null, 'save failed'), true);
                }
                return;
            }
            npcs[id] = r.npc;
            flash(tr('ui.dbg_saved', null, 'Saved'));
            selectNpc(id);
        });
    });

    // Copy / paste / clone

    $('dbgCopy').addEventListener('click', function () {
        // Read from the form, not npcs[selected], so unsaved edits are copied.
        var f = readForm();
        ['x', 'y', 'z', 'heading', 'disabled'].forEach(function (k) { delete f[k]; });
        clipboard = f;
        $('dbgPaste').disabled = false;
        flash(tr('ui.dbg_copied', null, 'Copied settings') + (f.label ? ' - ' + f.label : ''));
    });

    $('dbgPaste').addEventListener('click', function () {
        if (!clipboard) { flash(tr('ui.dbg_nothing_copied', null, 'Nothing copied yet'), true); return; }

        // Everything EXCEPT id, position and heading - see the note on `clipboard`. Nothing is written until Save.
        var keep = { x: $('fX').value, y: $('fY').value, z: $('fZ').value, h: $('fHeading').value, d: $('fNpcDisabled').checked };
        var c = clipboard;
        fillForm({
            label: c.label, role: c.role, model: c.model, scenario: c.scenario, clothing: c.clothing,
            faction: c.faction, safezone: c.safezone, categories: c.categories,
            openFrom: c.openFrom, openTo: c.openTo, priceMult: c.priceMult, rankDiscount: c.rankDiscount,
            restock: c.restock, blipOn: c.blipOn, blipSprite: c.blipSprite, blipColor: c.blipColor, notes: c.notes,
            sells: c.sells, buys: c.buys, missions: c.missions
        });
        $('fX').value = keep.x; $('fY').value = keep.y; $('fZ').value = keep.z; $('fHeading').value = keep.h;
        $('fNpcDisabled').checked = keep.d;
        onEdit();
        flash(tr('ui.dbg_pasted', null, 'Pasted - not saved yet'));
    });

    // Two clicks instead of a dialog: the first shows a field with a suggested id, the second creates. window.prompt is not used because CEF blocks JS dialogs.
    $('dbgDuplicate').addEventListener('click', function (e) {
        var btn = e.currentTarget;
        var field = $('dbgDupId');

        if (!selected) { flash(tr('ui.dbg_save_first', null, 'Save this one first'), true); return; }

        if (field.classList.contains('hidden')) {
            // Suggested id the user can edit; bumps the suffix until free locally. The server also refuses collisions.
            var base = selected.replace(/_copy\d*$/, '');
            var candidate = base + '_copy';
            var n = 2;
            while (npcs[candidate]) { candidate = base + '_copy' + n; n++; }

            field.value = candidate;
            field.classList.remove('hidden');
            field.focus();
            field.select();
            btn.textContent = tr('ui.dbg_create', null, 'create');
            return;
        }

        var newId = field.value.trim();
        if (!newId) { flash(tr('ui.v_id', null, 'Invalid id'), true); field.focus(); return; }

        post('debugDuplicateNpc', { npcId: selected, newId: newId }, function (r) {
            if (!r || !r.ok) { flash((r && r.reason) || tr('ui.dbg_save_failed', null, 'failed'), true); return; }
            npcs[r.npc.id] = r.npc;
            field.classList.add('hidden');
            btn.textContent = tr('ui.duplicate', null, 'duplicate');
            flash(tr('ui.dbg_dup_done', null, 'Copied - it is disabled and standing where you are'));
            selectNpc(r.npc.id);
        });
    });

    $('dbgDupId').addEventListener('keydown', function (e) {
        e.stopPropagation();
        if (e.key === 'Enter') { e.preventDefault(); $('dbgDuplicate').click(); }
        if (e.key === 'Escape') {
            e.stopPropagation();
            this.classList.add('hidden');
            $('dbgDuplicate').textContent = tr('ui.duplicate', null, 'duplicate');
        }
    });

    $('dbgResetOrDelete').addEventListener('click', function (e) {
        var btn = e.currentTarget;
        if (!selected) return;

        if (btn.dataset.armed !== '1') {
            btn.dataset.armed = '1';
            var original = btn.textContent;
            btn.textContent = tr('ui.dbg_confirm', null, 'Click again to confirm');
            setTimeout(function () { btn.dataset.armed = '0'; btn.textContent = original; }, 4000);
            return;
        }

        post('debugResetNpc', { npcId: selected }, function (r) {
            if (!r || !r.ok) { flash(tr('ui.dbg_save_failed', null, 'failed'), true); return; }
            // A config trader comes back with its defaults: refresh the list.
            post('debugRefresh', {}, function (d) {
                if (d && d.ok) { npcs = {}; (d.npcs || []).forEach(function (n) { npcs[n.id] = n; }); }
                else { delete npcs[selected]; }
                flash(tr('ui.dbg_done', null, 'Done'));
                selected = null;
                renderList();
                showEmpty();
            });
        });
    });

    // Mission

    function refreshGiverOptions() {
        var sel = document.getElementById('mGiver');
        var current = sel.value;
        sel.innerHTML = '';
        Object.keys(npcs).sort().forEach(function (id) {
            var n = npcs[id];
            if (n.role === 'quest' || n.role === 'both') {
                var opt = document.createElement('option');
                opt.value = id;
                opt.textContent = n.label || id;
                sel.appendChild(opt);
            }
        });
        if (current) sel.value = current;
    }

    function toggleMissionKind() {
        var kind = document.getElementById('mKind').value;
        document.getElementById('mKindKill').classList.toggle('hidden', kind !== 'kill');
        document.getElementById('mKindGather').classList.toggle('hidden', kind !== 'gather');
    }
    document.getElementById('mKind').addEventListener('change', toggleMissionKind);

    function loadMissionForm(id) {
        selected = id;
        isNew = !id;
        var m = id ? missions[id] : null;

        // Clear the model preview: it belongs to the NPC form.
        post('debugPreviewClear', {});

        document.getElementById('dbgEmpty').classList.add('hidden');
        document.getElementById('dbgNpcForm').classList.add('hidden');
        document.getElementById('dbgMissionForm').classList.remove('hidden');

        var idInput = document.getElementById('mId');
        idInput.value = id || '';
        idInput.readOnly = !isNew;

        refreshGiverOptions();

        document.getElementById('mLabel').value = m ? m.label : '';
        document.getElementById('mGiver').value = m ? m.giver : (document.getElementById('mGiver').options[0] || {}).value || '';
        document.getElementById('mKind').value = m ? m.kind : 'kill';
        document.getElementById('mTarget').value = m ? m.target : 1;
        document.getElementById('mItem').value = (m && m.item) || '';
        document.getElementById('mConsume').checked = !!(m && m.consume);
        document.getElementById('mDesc').value = (m && m.desc) || '';
        document.getElementById('mXp').value = m && m.reward ? m.reward.xp || 0 : 0;
        document.getElementById('mMoney').value = m && m.reward ? m.reward.money || 0 : 0;
        document.getElementById('mCooldown').value = m ? m.cooldown : 1800;

        filterRows(m ? m.filter : []);
        toggleMissionKind();

        var resetBtn = document.getElementById('dbgResetOrDeleteMission');
        resetBtn.textContent = isNew ? '' : ((m && m.hasConfig) ? tr('ui.dbg_reset', null, 'Reset to default') : tr('ui.dbg_delete', null, 'Delete'));
        resetBtn.style.visibility = isNew ? 'hidden' : 'visible';
        resetBtn.dataset.armed = '0';

        renderList();
    }

    function selectMission(id) { isNew = false; loadMissionForm(id); }

    document.getElementById('dbgSaveMission').addEventListener('click', function () {
        var id = document.getElementById('mId').value.trim();
        if (!id) { flash(tr('ui.v_id', null, 'Invalid id'), true); return; }

        var giver = document.getElementById('mGiver').value;
        if (!giver) { flash(tr('ui.dbg_need_giver', null, 'Mission needs a giver'), true); return; }

        var kind = document.getElementById('mKind').value;
        var patch = {
            label: document.getElementById('mLabel').value.trim() || id,
            giver: giver,
            kind: kind,
            target: parseInt(document.getElementById('mTarget').value, 10) || 1,
            desc: document.getElementById('mDesc').value,
            reward: {
                xp: parseInt(document.getElementById('mXp').value, 10) || 0,
                money: parseInt(document.getElementById('mMoney').value, 10) || 0,
            },
            cooldown: parseInt(document.getElementById('mCooldown').value, 10) || 0,
        };

        if (kind === 'kill') {
            patch.filter = readFilterRows();
            if (patch.filter.length === 0) { flash(tr('ui.dbg_need_action', null, 'Kill missions need an action id'), true); return; }
        } else {
            patch.item = document.getElementById('mItem').value.trim();
            if (!patch.item) { flash(tr('ui.dbg_need_item', null, 'Gather missions need an item key'), true); return; }
            patch.consume = document.getElementById('mConsume').checked;
        }

        post('debugSaveMission', { missionId: id, patch: patch }, function (r) {
            if (!r || !r.ok) { flash((r && r.reason) || tr('ui.dbg_save_failed', null, 'save failed'), true); return; }
            missions[id] = r.mission;
            flash(tr('ui.dbg_saved', null, 'Saved'));
            selectMission(id);
        });
    });

    document.getElementById('dbgResetOrDeleteMission').addEventListener('click', function (e) {
        var btn = e.currentTarget;
        if (!selected) return;

        if (btn.dataset.armed !== '1') {
            btn.dataset.armed = '1';
            var original = btn.textContent;
            btn.textContent = tr('ui.dbg_confirm', null, 'Click again to confirm');
            setTimeout(function () { btn.dataset.armed = '0'; btn.textContent = original; }, 4000);
            return;
        }

        post('debugResetMission', { missionId: selected }, function (r) {
            if (!r || !r.ok) { flash(tr('ui.dbg_save_failed', null, 'failed'), true); return; }
            delete missions[selected];
            flash(tr('ui.dbg_done', null, 'Done'));
            selected = null;
            renderList();
            showEmpty();
        });
    });
})();

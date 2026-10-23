// bs_traders - clothing shop panel. Kept separate from app.js so the trade menu and wardrobe do not share document-wide key listeners.

(function () {
    'use strict';

    var root = document.getElementById('wardrobe');
    if (!root) { return; }

    var OUTFITS = '__outfits';   // the pseudo-category the Outfits tab uses

    var state = {
        open: false,
        cats: [],
        rules: [],
        owned: {},           // "category:drawable" -> true
        outfits: [],
        maxOutfits: 0,
        gender: 'm',
        basePrice: 0,
        cash: 0,
        vip: false,
        level: 0,
        autoArms: true,
        poses: [],
        pose: null,          // which pose is being held, or null for standing
        active: null,        // selected category id, or OUTFITS
        cursor: 0,           // keyboard position within the drawn list
        original: {},        // [catId] = { drawable, texture }  as opened
        current: {},         // [catId] = { drawable, texture }  as previewed
        rows: [],            // what the keyboard is stepping through
    };

    function post(name, body, done) {
        fetch('https://bs_traders/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        }).then(function (r) { return r.json(); })
          .then(function (d) { if (done) done(d); })
          .catch(function () {});
    }

    function money(n) { return '$' + Math.floor(n || 0).toLocaleString('en-US'); }
    function catOf(id) { return state.cats.filter(function (c) { return c.id === id; })[0]; }
    function ownKey(catId, drawable) { return catId + ':' + drawable; }
    function owns(catId, drawable) { return !!state.owned[ownKey(catId, drawable)]; }

    // Garment names come from js/clothingnames.js (dump of the game's text tables). An entry is a plain string when every colour of a garment shares a name, otherwise a per-texture list.

    function garmentName(cat, drawable, texture) {
        var table = window.BS_CLOTHING_NAMES || {};
        var byCat = table[state.gender] || {};
        var entry = (byCat[cat.id] || {})[drawable];

        if (typeof entry === 'string') { return entry; }
        if (Array.isArray(entry)) {
            var pick = entry[texture || 0];
            if (pick) { return pick; }
            // Fall back to the first named texture rather than a number.
            for (var i = 0; i < entry.length; i++) { if (entry[i]) { return entry[i]; } }
        }

        return cat.label.replace(/s$/, '') + ' #' + drawable;
    }

    // Rules: mirrors Wardrobe.RuleFor / PriceFor / Allowed in config_wardrobe.lua, with the same precedence (exact drawable, then range, then bare category rule), so the panel agrees with the server about what is locked.

    function ruleFor(catId, drawable) {
        var best = null, bestScore = -1;

        state.rules.forEach(function (rule) {
            if (rule.category !== catId) { return; }
            var score = -1;

            if (rule.drawable !== undefined && rule.drawable === drawable) { score = 3; }
            else if (rule.from !== undefined && rule.to !== undefined
                     && drawable >= rule.from && drawable <= rule.to) { score = 2; }
            else if (rule.drawable === undefined && rule.from === undefined) { score = 1; }

            if (score > bestScore) { best = rule; bestScore = score; }
        });

        return best;
    }

    // Price for this player right now: free if already owned or if it is the bare body.
    function priceFor(catId, drawable) {
        var cat = catOf(catId);
        if (cat && cat.bare !== undefined && cat.bare !== null && drawable === cat.bare) { return 0; }
        if (owns(catId, drawable)) { return 0; }

        var rule = ruleFor(catId, drawable);
        if (rule && typeof rule.price === 'number') { return rule.price; }
        if (cat && typeof cat.price === 'number') { return cat.price; }
        return state.basePrice;
    }

    // Returns null when wearable, otherwise {tag, why}.
    function lockFor(catId, drawable) {
        var rule = ruleFor(catId, drawable);
        if (!rule) { return null; }
        if (rule.hidden) { return { tag: 'hidden', why: t('ui.not_for_sale') }; }
        if (rule.vip && !state.vip) { return { tag: 'vip', why: 'VIP' }; }
        if (rule.minLevel && state.level < rule.minLevel) {
            return { tag: 'level', why: t('ui.lv', { n: rule.minLevel }) };
        }
        return null;
    }

    // The bill: only what differs from the outfit the player arrived in, and only what is not already owned.

    function changes() {
        var out = [];

        Object.keys(state.current).forEach(function (catId) {
            var now = state.current[catId];
            var was = state.original[catId] || {};
            if (now.drawable === was.drawable && now.texture === was.texture) { return; }
            out.push({ category: catId, drawable: now.drawable, texture: now.texture });
        });

        return out;
    }

    function bill() {
        var sum = changes().reduce(function (acc, c) {
            return acc + (c.drawable < 0 ? 0 : priceFor(c.category, c.drawable));
        }, 0);
        // VIP tailor discount - the server applies the same rule
        if (sum > 0 && state.discount > 0) { sum = Math.floor(sum * (100 - state.discount) / 100); }
        return sum;
    }

    function renderBill() {
        var list = changes();
        var total = bill();
        var el = document.getElementById('wdBill');
        var confirm = document.getElementById('wdConfirm');

        if (!list.length) {
            el.textContent = t('ui.no_changes');
            el.classList.remove('is-over');
            confirm.disabled = true;
            confirm.textContent = t('ui.confirm');
            return;
        }

        var over = total > state.cash;
        el.textContent = t('ui.n_changes', { n: list.length })
            + ' · ' + (total > 0 ? money(total) : t('ui.free'))
            + (state.discount > 0 && total > 0 ? ' (VIP -' + state.discount + '%)' : '');
        el.classList.toggle('is-over', over);

        confirm.disabled = over;
        confirm.textContent = over ? t('ui.not_enough_cash')
            : (total > 0 ? t('ui.confirm') + ' · ' + money(total) : t('ui.confirm_free'));
    }

    // Render

    function renderCats() {
        var nav = document.getElementById('wdCats');
        nav.innerHTML = '';

        // Outfits sits at the top of the rail so it is easy to find.
        var outfitsBtn = document.createElement('button');
        outfitsBtn.className = 'wdcat wdcat--outfits' + (state.active === OUTFITS ? ' on' : '');
        outfitsBtn.textContent = t('ui.outfits');
        if (state.outfits.length) {
            var n = document.createElement('span');
            n.className = 'wdcat__n';
            n.textContent = state.outfits.length;
            outfitsBtn.appendChild(n);
        }
        outfitsBtn.addEventListener('click', function () { select(OUTFITS); });
        nav.appendChild(outfitsBtn);

        state.cats.forEach(function (cat) {
            var b = document.createElement('button');
            b.className = 'wdcat' + (cat.id === state.active ? ' on' : '');
            b.textContent = cat.label;

            // A dot marks a category that was changed in this fitting.
            var cur = state.current[cat.id] || {};
            var was = state.original[cat.id] || {};
            if (cur.drawable !== was.drawable || cur.texture !== was.texture) {
                b.classList.add('changed');
            }

            b.addEventListener('click', function () { select(cat.id); });
            nav.appendChild(b);
        });
    }

    function select(catId) {
        state.active = catId;
        state.cursor = -1;
        renderCats();
        renderPanel();
        // Move the camera to the part of the body this category is about.
        if (catId !== OUTFITS) { post('wardrobeFocus', { category: catId }); }
    }

    function renderPanel() {
        if (state.active === OUTFITS) { renderOutfits(); } else { renderList(); }
    }

    // Garments

    function renderList() {
        var cat = catOf(state.active);
        var list = document.getElementById('wdList');
        list.innerHTML = '';
        state.rows = [];

        if (!cat) { return; }

        document.getElementById('wdCatLabel').textContent = cat.label;
        document.getElementById('wdCatCount').textContent = cat.count + ' available';

        var cur = state.current[cat.id] || { drawable: 0, texture: 0 };
        var hasBare = cat.bare !== undefined && cat.bare !== null;

        // Remove row: props have a real empty state (-1), components do not, so `bare` is the drawable that is the bare body on this model. It is drawn as a normal row and skipped in the loop below. Categories with no bare value get no Remove row.
        if (cat.kind === 'prop' || hasBare) {
            var bareValue = cat.kind === 'prop' ? -1 : cat.bare;
            list.appendChild(row(cat, bareValue, cur, true));
        }

        var first = cat.kind === 'prop' ? 0 : 0;
        for (var d = first; d < cat.count; d++) {
            if (hasBare && d === cat.bare) { continue; }
            list.appendChild(row(cat, d, cur, false));
        }

        // Start the keyboard cursor on whatever is currently worn.
        state.rows.forEach(function (r, i) { if (r.node.classList.contains('on')) { state.cursor = i; } });
    }

    function row(cat, drawable, cur, isRemove) {
        var node = document.createElement('div');
        var lock = isRemove ? null : lockFor(cat.id, drawable);
        var selected = cur.drawable === drawable;

        node.className = 'wdrow' + (selected ? ' on' : '') + (lock ? ' locked' : '')
            + (isRemove ? ' wdrow--none' : '');

        // Hidden rows are not drawn. The server refuses them too, so this is not the enforcement.
        if (lock && lock.tag === 'hidden') { node.className = 'wdrow hidden'; return node; }

        var name = document.createElement('span');
        name.className = 'wdrow__name';

        if (isRemove) {
            name.textContent = cat.kind === 'prop' ? t('ui.none') : t('ui.none_bare');
        } else {
            name.textContent = garmentName(cat, drawable, selected ? cur.texture : 0);
            var idx = document.createElement('span');
            idx.className = 'wdrow__idx';
            idx.textContent = '#' + drawable;
            name.appendChild(idx);
        }

        var tag = document.createElement('span');
        tag.className = 'wdrow__tag';
        if (lock) {
            tag.textContent = lock.why; tag.classList.add('is-lock');
        } else if (isRemove) {
            tag.textContent = '';
        } else if (owns(cat.id, drawable)) {
            // Bought once, owned for good.
            tag.textContent = 'Owned'; tag.classList.add('is-owned');
        } else {
            tag.textContent = money(priceFor(cat.id, drawable));
        }

        node.appendChild(name);
        node.appendChild(tag);

        // The texture stepper only exists on the worn row, to avoid enumerating textures for every drawable on each render.
        if (selected && !isRemove && cat.textures > 1) {
            node.appendChild(stepper(cat, drawable, cur));
        }

        if (!lock) {
            node.addEventListener('click', function () {
                if (isRemove) { wear(cat, null, 0, true); } else { wear(cat, drawable, 0); }
            });
        }

        if (!lock) { state.rows.push({ node: node, cat: cat, drawable: drawable, remove: !!isRemove }); }
        return node;
    }

    function stepper(cat, drawable, cur) {
        var tex = document.createElement('div');
        tex.className = 'wdtex';

        var minus = document.createElement('button');
        minus.textContent = '−';
        var label = document.createElement('span');
        label.textContent = (cur.texture + 1) + ' / ' + cat.textures;
        var plus = document.createElement('button');
        plus.textContent = '+';

        minus.addEventListener('click', function (e) {
            e.stopPropagation();
            wear(cat, drawable, Math.max(0, cur.texture - 1));
        });
        plus.addEventListener('click', function (e) {
            e.stopPropagation();
            wear(cat, drawable, Math.min(cat.textures - 1, cur.texture + 1));
        });

        tex.appendChild(minus);
        tex.appendChild(label);
        tex.appendChild(plus);
        return tex;
    }

    // Put it on the ped and use the ped's answer for what happened.
    function wear(cat, drawable, texture, remove) {
        post('wardrobeWear',
            { category: cat.id, drawable: drawable, texture: texture, remove: !!remove },
            function (r) {
                if (!r || !r.ok) { return; }

                // The client clamps against the real model; trust that over what was requested.
                state.current[cat.id] = { drawable: r.drawable, texture: r.texture };
                cat.textures = r.textures;
                state.autoArms = !!r.autoArms;

                // A top that pulled the arms with it changed two categories; absorb both so the Arms tab and the bill stay correct.
                if (r.also) { absorb(r.also); }

                renderCats();
                renderPanel();
                renderBill();
                renderArmsMode();
            });
    }

    // Fold a { catId: {drawable, texture, textures} } answer into the panel.
    function absorb(map) {
        Object.keys(map || {}).forEach(function (catId) {
            var r = map[catId];
            if (!r || !r.ok) { return; }
            state.current[catId] = { drawable: r.drawable, texture: r.texture };
            var c = catOf(catId);
            if (c) { c.textures = r.textures; }
        });
    }

    // Arms: a normal category plus a toggle back to AUTO, since picking sleeves by hand stops the shop pairing them with the top.

    function renderArmsMode() {
        var el = document.getElementById('wdArms');
        if (!el) { return; }

        var show = state.active === 'arms';
        el.classList.toggle('hidden', !show);
        if (!show) { return; }

        el.querySelector('.wdarms__state').textContent = state.autoArms
            ? t('ui.following_your_top')
            : t('ui.chosen_by_hand');
        el.querySelector('#wdArmsAuto').disabled = state.autoArms;
    }

    // Outfits

    function renderOutfits() {
        var list = document.getElementById('wdList');
        list.innerHTML = '';
        state.rows = [];

        document.getElementById('wdCatLabel').textContent = 'Outfits';
        document.getElementById('wdCatCount').textContent = state.maxOutfits
            ? state.outfits.length + ' / ' + state.maxOutfits : '';

        if (!state.outfits.length) {
            var empty = document.createElement('div');
            empty.className = 'wdempty';
            empty.textContent = t('ui.no_outfits');
            list.appendChild(empty);
        }

        state.outfits.forEach(function (outfit) {
            var node = document.createElement('div');
            node.className = 'wdrow wdrow--outfit';

            var name = document.createElement('span');
            name.className = 'wdrow__name';
            name.textContent = outfit.name;

            var count = document.createElement('span');
            count.className = 'wdrow__idx';
            count.textContent = t('ui.n_pieces', { n: Object.keys(outfit.parts || {}).length });
            name.appendChild(count);

            var del = document.createElement('button');
            del.className = 'wdx';
            del.textContent = '×';
            del.title = t('ui.delete_outfit');
            del.addEventListener('click', function (e) {
                e.stopPropagation();
                post('wardrobeOutfitDelete', { id: outfit.id }, function (r) {
                    if (r && r.ok) { state.outfits = r.outfits || []; renderCats(); renderOutfits(); }
                });
            });

            node.appendChild(name);
            node.appendChild(del);
            node.addEventListener('click', function () { wearOutfit(outfit); });

            list.appendChild(node);
            state.rows.push({ node: node, outfit: outfit });
        });
    }

    function wearOutfit(outfit) {
        post('wardrobeOutfitWear', { parts: outfit.parts }, function (r) {
            if (!r || !r.ok) { return; }
            absorb(r.applied);
            state.autoArms = !!r.autoArms;
            renderCats();
            renderBill();
            renderOutfits();
        });
    }

    function saveOutfit() {
        var input = document.getElementById('wdOutfitName');
        var status = document.getElementById('wdStatus');
        var name = (input.value || '').trim();
        if (!name) { status.textContent = t('ui.name_it'); input.focus(); return; }

        // Saved from what is on the ped right now, not from the diff: an outfit is the whole look.
        post('wardrobeOutfitSave', { name: name, parts: state.current }, function (r) {
            if (!r || !r.ok) { status.textContent = (r && r.reason) || 'failed'; return; }
            status.textContent = t(r.replaced ? 'ui.replaced' : 'ui.saved', { name: name });
            input.value = '';
            state.outfits = r.outfits || [];
            renderCats();
            renderOutfits();
        });
    }

    // Poses: a latching toggle group. Clicking the current pose stands back up (the Lua side treats re-selecting the held pose as a clear). A pose whose clip does not resolve removes its own button. See cl_wardrobe.lua.

    function renderPoses() {
        var box = document.getElementById('wdPoses');
        box.innerHTML = '';

        state.poses.forEach(function (pose) {
            var b = document.createElement('button');
            b.className = 'wdpose' + (state.pose === pose.id ? ' on' : '');
            b.textContent = pose.label;
            b.title = t('ui.hold_pose');

            b.addEventListener('click', function () {
                post('wardrobePose', { pose: pose.id }, function (r) {
                    if (!r) { return; }
                    if (r.missing) { b.remove(); return; }
                    state.pose = r.pose || null;
                    renderPoses();
                });
            });

            box.appendChild(b);
        });
    }

    // Wiring

    document.getElementById('wdCancel').addEventListener('click', function () {
        post('wardrobeCancel', {});
    });

    document.getElementById('wdConfirm').addEventListener('click', function () {
        var list = changes();
        if (!list.length) { return; }

        var status = document.getElementById('wdStatus');
        status.textContent = '';
        document.getElementById('wdConfirm').disabled = true;

        post('wardrobeBuy', { changes: list }, function (r) {
            if (r && r.ok) { return; }            // the client closes the shop
            status.textContent = (r && r.reason) || 'failed';
            renderBill();
        });
    });

    // Arrows turn the character; dragging orbits the camera. See shop.orbit in cl_wardrobe.lua.
    document.getElementById('wdLeft').addEventListener('click', function () {
        post('wardrobeTurn', { by: -25, mode: 'ped' });
    });
    document.getElementById('wdRight').addEventListener('click', function () {
        post('wardrobeTurn', { by: 25, mode: 'ped' });
    });
    document.getElementById('wdBack').addEventListener('click', function () {
        post('wardrobeTurn', { by: 180, mode: 'orbit' });
    });

    var armsAuto = document.getElementById('wdArmsAuto');
    if (armsAuto) {
        armsAuto.addEventListener('click', function () {
            post('wardrobeAutoArms', {}, function (r) {
                if (!r || !r.ok) { return; }
                state.autoArms = true;
                if (r.arms) { absorb({ arms: r.arms }); }
                renderCats(); renderPanel(); renderBill(); renderArmsMode();
            });
        });
    }

    document.getElementById('wdOutfitSave').addEventListener('click', saveOutfit);
    document.getElementById('wdOutfitName').addEventListener('keydown', function (e) {
        e.stopPropagation();                       // do not let arrows leak out
        if (e.key === 'Enter') { saveOutfit(); }
    });

    // Drag anywhere that is not a panel to orbit the camera around the player.
    var dragging = false, lastX = 0;
    root.addEventListener('mousedown', function (e) {
        if (e.target.closest('#wdPanel') || e.target.closest('#wdCats')
            || e.target.closest('#wdFoot') || e.target.closest('#wdHead')) { return; }
        dragging = true; lastX = e.clientX;
    });
    window.addEventListener('mouseup', function () { dragging = false; });
    window.addEventListener('mousemove', function (e) {
        if (!dragging) { return; }
        var dx = e.clientX - lastX;
        if (Math.abs(dx) < 3) { return; }
        lastX = e.clientX;
        post('wardrobeTurn', { by: dx * 0.55, mode: 'orbit' });
    });

    root.addEventListener('wheel', function (e) {
        if (!state.open) { return; }
        if (e.target.closest('#wdList') || e.target.closest('#wdCats')) { return; }
        post('wardrobeZoom', { by: e.deltaY > 0 ? 0.08 : -0.08 });
    });

    // Keyboard: Up/Down walks the list and puts the row on, Left/Right steps the colour, Tab changes category, Enter confirms, Escape leaves. Uses keydown with preventDefault on arrows so the list does not scroll under the cursor.

    function step(delta) {
        if (!state.rows.length) { return; }

        var next = state.cursor + delta;
        if (next < 0) { next = 0; }
        if (next > state.rows.length - 1) { next = state.rows.length - 1; }
        if (next === state.cursor) { return; }
        state.cursor = next;

        var target = state.rows[next];
        target.node.scrollIntoView({ block: 'nearest' });

        if (target.outfit) { wearOutfit(target.outfit); return; }
        if (target.remove) { wear(target.cat, null, 0, true); return; }
        wear(target.cat, target.drawable, 0);
    }

    function stepTexture(delta) {
        var cat = catOf(state.active);
        if (!cat || !cat.textures || cat.textures < 2) { return; }
        var cur = state.current[cat.id];
        if (!cur || cur.drawable < 0) { return; }
        var t = Math.max(0, Math.min(cat.textures - 1, cur.texture + delta));
        if (t === cur.texture) { return; }
        wear(cat, cur.drawable, t);
    }

    function stepCategory(delta) {
        var ids = [OUTFITS].concat(state.cats.map(function (c) { return c.id; }));
        var at = ids.indexOf(state.active);
        var next = (at + delta + ids.length) % ids.length;
        select(ids[next]);
    }

    document.addEventListener('keydown', function (e) {
        if (!state.open) { return; }

        switch (e.key) {
            case 'ArrowDown':  e.preventDefault(); step(1); break;
            case 'ArrowUp':    e.preventDefault(); step(-1); break;
            case 'ArrowRight': e.preventDefault(); stepTexture(1); break;
            case 'ArrowLeft':  e.preventDefault(); stepTexture(-1); break;
            case 'PageDown':   e.preventDefault(); step(8); break;
            case 'PageUp':     e.preventDefault(); step(-8); break;
            case 'Tab':
                e.preventDefault();
                stepCategory(e.shiftKey ? -1 : 1);
                break;
            case 'Enter': {
                var confirm = document.getElementById('wdConfirm');
                if (!confirm.disabled) { e.preventDefault(); confirm.click(); }
                break;
            }
            case 'Escape': e.preventDefault(); post('wardrobeCancel', {}); break;
            default: break;
        }
    });

    // Payload

    window.addEventListener('message', function (event) {
        var msg = event.data || {};
        if (msg.action !== 'wardrobe') { return; }

        if (msg.state === 'open') {
            state.open = true;
            state.cats = msg.categories || [];
            state.rules = msg.rules || [];
            state.basePrice = msg.basePrice || 0;
            state.cash = msg.cash || 0;
            state.vip = !!msg.vip;
            state.level = msg.level || 0;
            state.gender = msg.gender === 'female' ? 'f' : 'm';
            state.outfits = msg.outfits || [];
            state.poses = msg.poses || [];
            state.pose = null;
            state.maxOutfits = msg.maxOutfits || 0;
            state.discount = msg.discount || 0;
            state.autoArms = true;

            state.owned = {};
            (msg.owned || []).forEach(function (key) { state.owned[key] = true; });

            state.original = {};
            state.current = {};
            state.cats.forEach(function (c) {
                state.original[c.id] = { drawable: c.current, texture: c.texture };
                state.current[c.id] = { drawable: c.current, texture: c.texture };
            });

            document.getElementById('wdLabel').textContent = msg.label || 'Clothing';
            document.getElementById('wdCash').textContent = money(msg.cash);
            document.getElementById('wdStatus').textContent = '';
            document.getElementById('wdOutfitName').value = '';

            state.active = state.cats.length ? state.cats[0].id : OUTFITS;
            state.cursor = -1;
            renderCats();
            renderPanel();
            renderBill();
            renderArmsMode();
            renderPoses();
            if (state.active !== OUTFITS) { post('wardrobeFocus', { category: state.active }); }

            root.classList.remove('hidden');

            // Tell the client the panel is really open. Until this lands it does not freeze the player, move the camera or take the mouse (see cl_wardrobe.lua). Sent after the class is removed.
            post('wardrobeReady', {});
        } else if (msg.state === 'cash') {
            // Balance changed while the shop is open: re-render the bill, since affordability and the Confirm button depend on it. See cl_wardrobe.lua.
            state.cash = msg.cash || 0;
            document.getElementById('wdCash').textContent = money(state.cash);
            renderBill();
        } else if (msg.state === 'close') {
            state.open = false;
            root.classList.add('hidden');
        }
    });
})();

// bs_cinecam menu - no framework, no CDN, so it works on a server with no internet.

(function () {
    'use strict';

    // Translations from nui://bs_ui/html/js/i18n.js (t is used for other things in here).
    var tr = function (k, v) { return window.BSI18n ? window.BSI18n.t(k, v) : k; };

    var root   = document.getElementById('root');
    var status = document.getElementById('status');

    var settings = {};
    var pathState = { count: 0, playing: false, duration: 12, ease: 0.25, loop: false };

    // post

    function post(name, body, done) {
        fetch('https://bs_cinecam/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).then(function (r) { return r.json(); })
          .then(function (data) { if (done) done(data); })
          .catch(function () { /* resource stopping mid-click: nothing useful to say */ });
    }

    function flash(text) {
        status.textContent = text;
        clearTimeout(flash.timer);
        flash.timer = setTimeout(function () { status.textContent = 'ready'; }, 1400);
    }

    // sliders

    // Sliders are built from markup: <div class="slider" data-key data-min data-max data-step>. Adding a setting is one line of HTML.
    function buildSliders() {
        var nodes = document.querySelectorAll('.slider');

        Array.prototype.forEach.call(nodes, function (box) {
            var label = box.querySelector('label');
            var head = document.createElement('div');
            head.className = 'head';

            var val = document.createElement('span');
            val.className = 'val';

            head.appendChild(label);
            head.appendChild(val);
            box.insertBefore(head, box.firstChild);

            var input = document.createElement('input');
            input.type = 'range';
            input.min = box.dataset.min;
            input.max = box.dataset.max;
            input.step = box.dataset.step;
            box.appendChild(input);

            box._val = val;
            box._input = input;

            var unit = box.dataset.unit || '';
            var step = parseFloat(box.dataset.step);
            var places = step < 0.1 ? 2 : (step < 1 ? 1 : 0);

            function show(v) { val.innerHTML = parseFloat(v).toFixed(places) + unit; }

            // 'input' fires while dragging so the camera updates live. The save is debounced, last value wins.
            input.addEventListener('input', function () {
                show(input.value);
                schedule(box, parseFloat(input.value));
            });

            box._show = show;
        });
    }

    var pending = null, pendingPath = null, timer = null;

    function schedule(box, value) {
        if (box.dataset.key) {
            pending = pending || {};
            pending[box.dataset.key] = value;
        } else if (box.dataset.pathKey) {
            pendingPath = pendingPath || {};
            pendingPath[box.dataset.pathKey] = value;
        }

        clearTimeout(timer);
        timer = setTimeout(commit, 90);
    }

    function commit() {
        if (pending) {
            post('apply', { patch: pending }, function (r) {
                if (r && r.settings) { settings = r.settings; }
            });
            pending = null;
        }
        if (pendingPath) {
            var body = { op: 'set' };
            for (var k in pendingPath) { body[k] = pendingPath[k]; }
            post('path', body, applyPath);
            pendingPath = null;
        }
    }

    // rendering

    // grade
    // Built from bs_ui's look list (sent in the open payload). 'Mine' is the empty string: camera keeps your own filter. 'off' strips it for a clean plate.

    var gradesBuilt = false;

    function buildGrades(list) {
        var box = document.getElementById('grades');
        var wrap = document.getElementById('gradeBox');
        if (!box || !wrap) { return; }

        // No bs_ui, no looks: hide the control rather than show an empty row.
        if (!list || !list.length) { wrap.classList.add('hidden'); return; }
        wrap.classList.remove('hidden');
        if (gradesBuilt) { return; }

        box.innerHTML = '';

        var entries = [{ id: '', label: tr('ui.mine'), note: tr('ui.mine_note') }]
            .concat(list);

        entries.forEach(function (preset) {
            var b = document.createElement('button');
            b.dataset.value = preset.id;
            b.textContent = String(preset.label || preset.id);
            if (preset.note) { b.title = preset.note; }
            b.addEventListener('click', function () {
                post('apply', { patch: { filter: preset.id } }, function (r) {
                    applySettings(r && r.settings);
                });
            });
            box.appendChild(b);
        });

        gradesBuilt = true;
    }

    function paintGrades(s) {
        var box = document.getElementById('grades');
        if (!box) { return; }
        var current = (s && s.filter) || '';
        Array.prototype.forEach.call(box.querySelectorAll('button'), function (b) {
            b.classList.toggle('on', b.dataset.value === current);
        });
    }

    function applySettings(s) {
        if (!s) { return; }
        settings = s;
        paintGrades(s);

        Array.prototype.forEach.call(document.querySelectorAll('.slider[data-key]'), function (box) {
            var v = s[box.dataset.key];
            if (typeof v !== 'number') { return; }
            box._input.value = v;
            box._show(v);
        });

        Array.prototype.forEach.call(document.querySelectorAll('.check input[data-key]'), function (input) {
            input.checked = !!s[input.dataset.key];
        });
    }

    // countOnly is used by the 200ms live push so it does not reset the duration/ease sliders while you drag them.
    function applyPath(r, countOnly) {
        var p = (r && r.path) || r;
        if (!p) { return; }
        pathState = p;

        document.getElementById('pathCount').textContent = p.count;
        document.getElementById('pathPlaying').textContent = p.playing ? '· ' + tr('ui.playing') : '';
        if (countOnly) { return; }

        Array.prototype.forEach.call(document.querySelectorAll('.slider[data-path-key]'), function (box) {
            var v = p[box.dataset.pathKey];
            if (typeof v !== 'number') { return; }
            box._input.value = v;
            box._show(v);
        });

        var loop = document.querySelector('.check input[data-path-key="loop"]');
        if (loop) { loop.checked = !!p.loop; }
    }

    function applyCamera(c) {
        if (!c) { return; }
        var btn = document.getElementById('toggleCam');
        btn.classList.toggle('active', !!c.active);
        btn.textContent = c.active
            ? tr('ui.leave_mode')
            : tr('ui.enter_mode');
    }

    function buildPresets(list) {
        var box = document.getElementById('presets');
        box.innerHTML = '';

        (list || []).forEach(function (preset, i) {
            var b = document.createElement('button');
            b.textContent = preset.label;
            b.addEventListener('click', function () {
                /* Lua tables are 1-indexed and this list came straight from
                   one, so the index sent back has to be too. */
                post('preset', { index: i + 1 }, function (r) {
                    applySettings(r && r.settings);
                    flash(preset.label);
                });
            });
            box.appendChild(b);
        });
    }

    // wiring

    document.addEventListener('click', function (e) {
        var t = e.target;

        if (t.classList.contains('tab')) {
            Array.prototype.forEach.call(document.querySelectorAll('.tab'), function (x) {
                x.classList.toggle('on', x === t);
            });
            Array.prototype.forEach.call(document.querySelectorAll('section'), function (x) {
                x.classList.toggle('on', x.dataset.page === t.dataset.tab);
            });
            return;
        }

        if (t.dataset && t.dataset.path) {
            post('path', { op: t.dataset.path }, applyPath);
            flash(tr('ui.path_' + t.dataset.path));
            return;
        }

        if (t.id === 'close') { post('close', {}); return; }

        if (t.id === 'toggleCam') {
            post('camera', {}, function (r) {
                applyCamera(r && r.camera);
                flash(r && r.camera && r.camera.active ? tr('ui.camera_on') : tr('ui.camera_off'));
            });
            return;
        }

        if (t.id === 'reset') {
            post('reset', {}, function (r) {
                applySettings(r && r.settings);
                flash(tr('ui.reset_done'));
            });
        }
    });

    document.addEventListener('change', function (e) {
        var input = e.target;
        if (input.type !== 'checkbox') { return; }

        if (input.dataset.key) {
            var patch = {};
            patch[input.dataset.key] = input.checked;
            post('apply', { patch: patch }, function (r) { applySettings(r && r.settings); });
        } else if (input.dataset.pathKey) {
            var body = { op: 'set' };
            body[input.dataset.pathKey] = input.checked;
            post('path', body, applyPath);
        }
    });

    /* ESC closes. F3 does too - but only as a courtesy, because while the
       page has focus the game never sees the key at all, so the Lua side
       cannot be the one to handle it. */
    document.addEventListener('keyup', function (e) {
        if (e.key === 'Escape' || e.key === 'F3') { post('close', {}); }
    });

    // from client

    window.addEventListener('message', function (event) {
        var msg = event.data || {};

        if (msg.action === 'open') {
            var d = msg.data || {};
            buildPresets(d.presets);
            // Before applySettings: paintGrades needs the buttons to exist.
            buildGrades(d.filters);
            applySettings(d.settings);
            applyPath(d.path);
            applyCamera(d.camera);
            root.classList.remove('hidden');

        } else if (msg.action === 'close') {
            root.classList.add('hidden');

        } else if (msg.action === 'live') {
            var l = msg.data || {};
            var r = document.getElementById('readout');
            r.querySelector('[data-k="pos"]').textContent =
                l.x.toFixed(0) + ', ' + l.y.toFixed(0) + ', ' + l.z.toFixed(0);
            r.querySelector('[data-k="fov"]').textContent = l.fov.toFixed(1) + '°';
            r.querySelector('[data-k="spd"]').textContent = l.speed.toFixed(1) + ' m/s';
            applyCamera(l.camera);
            applyPath(l.path, true);
        }
    });

    buildSliders();
})();

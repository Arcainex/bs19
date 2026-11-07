// bs - 3D sound engine in the NUI page.
// GTA cannot easily play custom .ogg files (needs dat54/.awc authoring, and replacing vanilla banks is unreliable), so audio is played from the browser with Web Audio instead.

(() => {
    const RES = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName() : 'bs_ui';

    // Tunables, overridable from Lua (config_ui.lua -> UI.Audio -> 'audiocfg'). These defaults match the config and are only used if Lua has not pushed values yet (e.g. after a resource restart).
    const CFG = {
        panningModel:   'HRTF',
        distanceModel:  'inverse',
        refDistance:    3.0,
        rolloffFactor:  1.1,
        maxDistance:    45.0,
        coneInnerAngle: 360,     /* omnidirectional: a groan is not a torch */
        maxVoices:      12,      /* positional (world) voices */
        maxUiVoices:    6,       /* hitmarkers and friends, counted apart */
        defaultFadeMs:  120,
        listenerSmooth: 0.0,     /* 0 = snap. See updateListener(). */
    };

    // Audio context. Created lazily and resumed on every use: a context built before user interaction can start suspended in some CEF builds and play nothing.
    let ctx = null;

    function context() {
        if (ctx) {
            if (ctx.state === 'suspended') ctx.resume().catch(() => {});
            return ctx;
        }
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) {
            warnOnce('nocontext', 'this CEF build has no Web Audio API - all custom sound is off');
            return null;
        }
        try {
            ctx = new AC();
            if (ctx.state === 'suspended') ctx.resume().catch(() => {});
        } catch (e) {
            ctx = null;
            warnOnce('nocontext', `could not create an AudioContext: ${e}`);
        }
        return ctx;
    }

    // Master gain in front of the destination. Unused for now, but it is where a global mute would go.
    let master = null;
    function destination() {
        const c = context();
        if (!c) return null;
        if (!master) {
            master = c.createGain();
            master.gain.value = 1.0;
            master.connect(c.destination);
        }
        return master;
    }

    // Log each message only once, so a missing file in a horde does not flood the F8 console.
    const said = new Set();
    function warnOnce(key, msg) {
        if (said.has(key)) return;
        said.add(key);
        console.log(`[bs_ui/sound] ${msg}`);
    }

    // Buffer cache: each file is fetched and decoded once, on first use (no preloading). A failed load is cached as null so a typo does not become a fetch storm.
    const buffers = new Map();   /* file -> AudioBuffer | null */
    const pending = new Map();   /* file -> Promise */

    // Report missing files back to Lua once, so they also show in the server console, not only in F8.
    function reportMissing(file) {
        try {
            fetch(`https://${RES}/soundMissing`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ file }),
            }).catch(() => {});
        } catch (e) { /* not running inside NUI; nothing to report to */ }
    }

    async function load(file) {
        if (buffers.has(file)) return buffers.get(file);
        if (pending.has(file)) return pending.get(file);

        const c = context();
        if (!c) return null;

        const job = (async () => {
            try {
                const res = await fetch(`https://cfx-nui-${RES}/html/sound/${file}`);
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                const bytes = await res.arrayBuffer();

                // The promise form of decodeAudioData is not on every CEF build, so use the callback form.
                const buf = await new Promise((resolve, reject) => {
                    let settled = false;
                    const ok = (b) => { if (!settled) { settled = true; resolve(b); } };
                    const no = (e) => { if (!settled) { settled = true; reject(e || new Error('decode failed')); } };
                    try {
                        const maybe = c.decodeAudioData(bytes, ok, no);
                        if (maybe && typeof maybe.then === 'function') maybe.then(ok, no);
                    } catch (e) { no(e); }
                });

                buffers.set(file, buf);
                return buf;
            } catch (e) {
                // Say a missing or unreadable file out loud once, then carry on.
                buffers.set(file, null);
                warnOnce(`missing:${file}`, `could not load "${file}": ${e} - that sound is off, everything else still works`);
                reportMissing(file);
                return null;
            } finally {
                pending.delete(file);
            }
        })();

        pending.set(file, job);
        return job;
    }

    // The listener follows the camera, not the ped, so sounds stay on the correct side of the screen in third person. Supports both the AudioParam API (positionX/forwardX...) and the legacy setPosition/setOrientation.
    let listenerMode = null;    /* 'param' | 'legacy' | 'none' */

    function listenerModeFor(l) {
        if (listenerMode) return listenerMode;
        if (l && l.positionX && typeof l.positionX.setValueAtTime === 'function') {
            listenerMode = 'param';
        } else if (l && typeof l.setPosition === 'function') {
            listenerMode = 'legacy';
            warnOnce('listener-legacy', 'using the deprecated listener API - spatialisation is fine, just older');
        } else {
            listenerMode = 'none';
            warnOnce('listener-none', 'no usable AudioListener - sounds will play flat (no direction)');
        }
        return listenerMode;
    }

    // Last listener position, so a panner created between updates starts at the right place instead of the origin.
    let ear = { x: 0, y: 0, z: 0 };

    function updateListener(m) {
        const c = context();
        if (!c) return;
        const l = c.listener;
        const mode = listenerModeFor(l);
        if (mode === 'none') return;

        // Axes: GTA is Z-up, Web Audio is Y-up. Instead of remapping, both listener and panners get raw game coordinates and the game's up vector. Web Audio only uses relative geometry, so this stays consistent and keeps handedness correct.
        const px = m.x || 0, py = m.y || 0, pz = m.z || 0;
        const fx = m.fx || 0, fy = m.fy || 1, fz = m.fz || 0;
        const ux = m.ux || 0, uy = m.uy || 0, uz = m.uz || 1;

        ear = { x: px, y: py, z: pz };

        if (mode === 'param') {
            const t = c.currentTime;
            l.positionX.setValueAtTime(px, t);
            l.positionY.setValueAtTime(py, t);
            l.positionZ.setValueAtTime(pz, t);
            l.forwardX.setValueAtTime(fx, t);
            l.forwardY.setValueAtTime(fy, t);
            l.forwardZ.setValueAtTime(fz, t);
            l.upX.setValueAtTime(ux, t);
            l.upY.setValueAtTime(uy, t);
            l.upZ.setValueAtTime(uz, t);
        } else {
            l.setPosition(px, py, pz);
            l.setOrientation(fx, fy, fz, ux, uy, uz);
        }
    }

    // Live sources by id. A world sound may carry an id (for zombies, the walker id) so everything one creature says moves and stops together.
    // Race: loading is async, so a stop can arrive before the source starts. A per-id epoch counter is bumped on every stop and checked after loading.
    const live = new Map();     /* id -> Set of voice records */
    const epochs = new Map();   /* id -> counter, bumped on every stop */

    let worldVoices = 0;
    let uiVoices = 0;

    function voiceCount() { return worldVoices; }

    // Farthest-first eviction: when the cap is reached, a closer sound replaces a distant one. Lua does this too, but the page guards itself.
    function evictFarthest(thanDistance) {
        let worst = null, worstD = -1;
        for (const set of live.values()) {
            for (const v of set) {
                if (!v.spatial) continue;
                const d = distanceFromEar(v.pos);
                if (d > worstD) { worstD = d; worst = v; }
            }
        }
        if (!worst || worstD <= thanDistance) return false;
        fade(worst, CFG.defaultFadeMs);
        return true;
    }

    function distanceFromEar(p) {
        if (!p) return Infinity;
        const dx = p.x - ear.x, dy = p.y - ear.y, dz = p.z - ear.z;
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    // Stopping with a ramp: a hard stop mid-waveform clicks, and a death should fade rather than cut. Every stop is a gain ramp followed by a real stop scheduled just after it ends.
    function fade(v, ms) {
        if (!v || v.stopping) return;
        v.stopping = true;

        const c = ctx;
        if (!c) return;

        const t = c.currentTime;
        const seconds = Math.max(0.01, (typeof ms === 'number' ? ms : CFG.defaultFadeMs) / 1000);

        try {
            const g = v.gain.gain;
            const from = Math.max(0.0001, g.value);
            g.cancelScheduledValues(t);
            g.setValueAtTime(from, t);
            g.exponentialRampToValueAtTime(0.0001, t + seconds * 0.9);
            g.linearRampToValueAtTime(0.0, t + seconds);
        } catch (e) { /* a context that went away mid-ramp; the stop below still runs */ }

        try { v.src.stop(t + seconds + 0.02); } catch (e) { /* already ended */ }
    }

    function stopId(id, ms) {
        if (id === null || id === undefined || id === '') return;
        id = String(id);
        epochs.set(id, (epochs.get(id) || 0) + 1);

        const set = live.get(id);
        if (!set) return;
        for (const v of set) fade(v, ms);
        // Do not delete the set here. onended removes each voice when it really finishes, which keeps the voice counter right during the ramp.
    }

    function stopAll(ms) {
        for (const id of Array.from(live.keys())) stopId(id, ms);
    }

    // Moving a playing sound. Lua sends a position for any id it thinks is still making noise; if nothing is playing under that id this is a no-op. The panner position is ramped over a short window instead of snapped, where AudioParams are available.
    function moveId(id, x, y, z, overMs) {
        if (id === null || id === undefined) return;
        const set = live.get(String(id));
        if (!set || set.size === 0) return;

        const c = ctx;
        if (!c) return;
        const t = c.currentTime;
        const ramp = Math.max(0.0, (typeof overMs === 'number' ? overMs : 150) / 1000);

        for (const v of set) {
            if (!v.spatial || !v.panner || v.stopping) continue;
            v.pos = { x, y, z };
            try {
                if (v.panner.positionX && typeof v.panner.positionX.linearRampToValueAtTime === 'function') {
                    v.panner.positionX.linearRampToValueAtTime(x, t + ramp);
                    v.panner.positionY.linearRampToValueAtTime(y, t + ramp);
                    v.panner.positionZ.linearRampToValueAtTime(z, t + ramp);
                } else if (typeof v.panner.setPosition === 'function') {
                    v.panner.setPosition(x, y, z);
                }
            } catch (e) { /* a panner whose source already ended */ }
        }
    }

    // Playing
    let pannerMode = null;   /* 'param' | 'legacy' */

    function makePanner(c, pos, opts) {
        const p = c.createPanner();

        // HRTF is not on every build; an unsupported panningModel either throws or stays equalpower. Probed once.
        try { p.panningModel = CFG.panningModel; }
        catch (e) {
            try { p.panningModel = 'equalpower'; } catch (e2) { /* keep default */ }
            warnOnce('nohrtf', 'HRTF panning is unavailable here - falling back to equal-power (left/right only)');
        }
        if (p.panningModel !== CFG.panningModel) {
            warnOnce('nohrtf', `HRTF panning was refused (model is "${p.panningModel}") - direction will be left/right only`);
        }

        try { p.distanceModel = CFG.distanceModel; } catch (e) { /* default is inverse anyway */ }

        p.refDistance   = Math.max(0.1, opts.refDistance || CFG.refDistance);
        p.rolloffFactor = Math.max(0.0, opts.rolloffFactor || CFG.rolloffFactor);
        p.maxDistance   = Math.max(1.0, opts.maxDistance || CFG.maxDistance);

        // Omnidirectional: a cone would make zombies facing away quieter, which is noise rather than information. A 360 inner angle disables the cone maths.
        p.coneInnerAngle = CFG.coneInnerAngle;
        p.coneOuterAngle = 360;
        p.coneOuterGain  = 1.0;

        if (!pannerMode) {
            pannerMode = (p.positionX && typeof p.positionX.setValueAtTime === 'function')
                ? 'param' : 'legacy';
        }
        try {
            if (pannerMode === 'param') {
                const t = c.currentTime;
                p.positionX.setValueAtTime(pos.x, t);
                p.positionY.setValueAtTime(pos.y, t);
                p.positionZ.setValueAtTime(pos.z, t);
            } else {
                p.setPosition(pos.x, pos.y, pos.z);
            }
        } catch (e) { /* positioned at the origin; still audible */ }

        return p;
    }

    async function play(d) {
        const file = d.file;
        if (!file) return;

        // A world sound carries coordinates; a UI sound does not and is not spatialised. This test is the whole 2D/3D split (PlaySound2D sends no pos).
        const spatial = !!(d.pos && typeof d.pos.x === 'number');
        const id = (d.id !== undefined && d.id !== null && d.id !== '')
            ? String(d.id) : (d.tag ? String(d.tag) : null);

        if (spatial) {
            if (worldVoices >= CFG.maxVoices) {
                const mine = distanceFromEar(d.pos);
                if (!evictFarthest(mine)) return;   /* everything live is closer; this one waits its turn */
            }
        } else if (uiVoices >= CFG.maxUiVoices) {
            return;
        }

        const epochAtStart = id ? (epochs.get(id) || 0) : 0;

        const c = context();
        if (!c) return;
        const out = destination();
        if (!out) return;

        const buf = await load(file);
        if (!buf) return;   /* missing file: already reported, nothing else breaks */

        // Stop was requested for this id while the file was loading.
        if (id && (epochs.get(id) || 0) !== epochAtStart) return;

        // Loading is async, so re-check the caps after the await; a whole horde may have spoken in between.
        if (spatial ? worldVoices >= CFG.maxVoices : uiVoices >= CFG.maxUiVoices) return;

        try {
            const src = c.createBufferSource();
            src.buffer = buf;
            src.loop = !!d.loop;
            src.playbackRate.value = Math.max(0.25, Math.min(4.0, Number(d.rate) || 1.0));

            const gain = c.createGain();
            const target = Math.max(0.0, Math.min(1.0, Number(d.volume) === 0 ? 0 : (Number(d.volume) || 1.0)));

            // Short fade-in too, since a buffer starting mid-waveform clicks. 10ms is inaudible and removes the click.
            const t0 = c.currentTime;
            gain.gain.setValueAtTime(0.0001, t0);
            gain.gain.linearRampToValueAtTime(target, t0 + 0.01);

            const v = {
                src, gain, panner: null, spatial,
                pos: spatial ? { x: d.pos.x, y: d.pos.y, z: d.pos.z } : null,
                stopping: false, id,
            };

            src.connect(gain);
            if (spatial) {
                v.panner = makePanner(c, v.pos, d);
                gain.connect(v.panner);
                v.panner.connect(out);
                worldVoices += 1;
            } else {
                gain.connect(out);
                uiVoices += 1;
            }

            src.onended = () => {
                if (spatial) worldVoices = Math.max(0, worldVoices - 1);
                else uiVoices = Math.max(0, uiVoices - 1);

                try { gain.disconnect(); } catch (e) {}
                if (v.panner) { try { v.panner.disconnect(); } catch (e) {} }

                if (id) {
                    const set = live.get(id);
                    if (set) {
                        set.delete(v);
                        if (set.size === 0) {
                            live.delete(id);
                            // Tell Lua the emitter has gone quiet so it can stop sending position updates, instead of polling every walker or guessing clip lengths.
                            notifyEnded(id);
                        }
                    }
                }
            };

            if (id) {
                let set = live.get(id);
                if (!set) { set = new Set(); live.set(id, set); }
                set.add(v);
            }

            src.start(0);
        } catch (e) {
            console.log(`[bs_ui/sound] could not play "${file}": ${e}`);
        }
    }

    function notifyEnded(id) {
        try {
            fetch(`https://${RES}/soundEnded`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ id }),
            }).catch(() => {});
        } catch (e) { /* not inside NUI */ }
    }

    // Messages from Lua. `sound` and `soundstop` keep their old names and payloads, so older senders (a tag, a pan, no pos) still work as 2D sounds.
    window.addEventListener('message', (event) => {
        const d = event.data || {};
        switch (d.action) {
            case 'sound':      play(d); break;
            case 'soundstop':  stopId(d.id !== undefined ? d.id : d.tag, d.fadeMs); break;
            case 'soundmove':  moveId(d.id, d.x, d.y, d.z, d.overMs); break;
            case 'soundlistener': updateListener(d); break;
            case 'soundstopall': stopAll(d.fadeMs); break;
            case 'audiocfg':
                if (d.cfg && typeof d.cfg === 'object') Object.assign(CFG, d.cfg);
                break;
            default: break;
        }
    });

    // Exposed for the F8 console and /soundtest. Useful for checking whether the voice cap is silencing something.
    window.bsSound = {
        voices: voiceCount,
        ui: () => uiVoices,
        ids: () => Array.from(live.keys()),
        cfg: () => Object.assign({}, CFG),
    };
})();

(function (global) {
    'use strict';
    const host = document.getElementById('pickupVisual');
    const grid = document.getElementById('pickupGrid');
    let queue = [], current = null, timer = null, phase = 'idle', due = 0;
    let progress = false, hidden = false;
    let config = {enabled:true,duration:2500,mergeWindow:400,maxQueue:20,showReceived:true,showRemoved:false,showAmount:true};
    const seen = new Set();
    const number = (v, fallback, low, high) => Number.isFinite(Number(v)) ? Math.max(low, Math.min(high, Math.floor(Number(v)))) : fallback;
    const blocked = () => progress || hidden || !config.enabled;
    function configure(value = {}) {
        config = {enabled:value.enabled!==false,duration:number(value.duration,2500,100,30000),
            mergeWindow:number(value.mergeWindow,400,0,5000),maxQueue:number(value.maxQueue,20,1,100),
            showReceived:value.showReceived!==false,showRemoved:value.showRemoved===true,showAmount:value.showAmount!==false};
        while (queue.length > config.maxQueue) queue.shift();
        if (!config.enabled) reset();
    }
    function clearTimer() { if (timer !== null) clearTimeout(timer); timer = null; }
    function reset() {
        clearTimer(); queue = []; current = null; phase = 'idle'; seen.clear();
        host.hidden = true; host.classList.remove('is-fading'); grid.replaceChildren();
    }
    function draw() {
        grid.replaceChildren();
        if (!current) return;
        const entry = current.entry;
        const w = number(entry.w,1,1,12), h = number(entry.h,1,1,16);
        grid.style.setProperty('--cols', w); grid.style.setProperty('--rows', h);
        global.BSInventorySlots.cells(grid,w,h);
        const plate = global.BSInventorySlots.create(entry, {name:false,countOnly:true,amount:config.showAmount});
        plate.style.gridColumn = `1 / span ${w}`; plate.style.gridRow = `1 / span ${h}`;
        grid.appendChild(plate);
    }
    function finish() {
        clearTimer(); host.hidden = true; host.classList.remove('is-fading');
        current = null; phase = 'idle'; grid.replaceChildren(); pump();
    }
    function fade() {
        clearTimer(); phase = 'fade'; host.classList.add('is-fading');
        timer = setTimeout(finish,180);
    }
    function pump() {
        if (blocked() || phase !== 'idle') return;
        if (!current) current = queue.shift() || null;
        if (!current) return;
        draw(); phase = 'show'; host.classList.remove('is-fading'); host.hidden = false;
        const duration = current.remaining ?? config.duration;
        due = performance.now() + duration; timer = setTimeout(fade,duration);
    }
    function pause() {
        if (phase === 'show') {
            current.remaining = Math.max(0,due-performance.now());
            clearTimer(); phase = 'idle'; host.hidden = true;
        } else if (phase === 'fade') finish();
    }
    function setProgress(state = {}) {
        progress = state.active === true;
        if (typeof state.bottom === 'string' && /^\d+(?:\.\d+)?px$/.test(state.bottom)) host.style.bottom = state.bottom;
        if (blocked()) pause(); else pump();
    }
    function receive(packet) {
        if (!config.enabled || !packet || !Array.isArray(packet.changes)) return;
        const id = `${packet.epoch}:${packet.sequence}`;
        if (seen.has(id)) return;
        seen.add(id); if (seen.size > 128) seen.delete(seen.values().next().value);
        const now = performance.now();
        for (const raw of packet.changes.slice(0,128)) {
            if (!raw || typeof raw.item !== 'string' || raw.item.length > 100 || !/^[\w:.-]+$/.test(raw.item)
                || !Number.isSafeInteger(raw.amount) || raw.amount < 1) continue;
            const kind = raw.kind === 'removed' ? 'removed' : 'received';
            if ((kind === 'removed' && !config.showRemoved) || (kind !== 'removed' && !config.showReceived)) continue;
            const entry = {item:raw.item,amount:raw.amount,category:typeof raw.category==='string'?raw.category:'misc',
                rarity:typeof raw.rarity==='string'?raw.rarity:undefined,w:raw.w,h:raw.h};
            const key = `${kind}:${entry.item}:${entry.rarity || ''}`;
            const target = config.mergeWindow>0 ? (phase==='fade'?queue:[current,...queue]).find(x => x && x.key===key && now-x.at<=config.mergeWindow
                && Number.isSafeInteger(x.entry.amount+entry.amount)) : undefined;
            if (target) {
                target.entry.amount += entry.amount;
                if (target === current) draw();
            } else {
                if (queue.length >= config.maxQueue) queue.shift(); // preserve active slot, discard oldest waiting visual
                queue.push({entry,key,at:now});
            }
        }
        pump();
    }
    global.addEventListener('message', event => {
        const data = event.data || {};
        if (data.action === 'pickups') { configure(data.settings); receive(data.packet); }
        else if (data.action === 'pickupReset') reset();
        else if (data.action === 'pickupProgress') setProgress(data.state);
        else if (data.action === 'bsHideAll') { hidden=data.hidden===true; if(blocked())pause();else pump(); }
    });
    if (typeof GetParentResourceName === 'function') {
        fetch(`https://${GetParentResourceName()}/pickupReady`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
    }
})(window);

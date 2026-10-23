// BeyondSurvival - interactions NUI. Presentation only; decisions are made in Lua.

const dotEl  = document.getElementById('dot');
const optsEl = document.getElementById('options');
const progEl = document.getElementById('progress');
const fillEl = document.getElementById('progress-fill');

const ICONS = {
    search:  'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zm5 12 4 4',
    medical: 'M12 6v12M6 12h12',
    tool:    'M14 6a4 4 0 0 1-5.5 5.3L4 16v4h4l4.7-4.5A4 4 0 0 1 18 10',
    lock:    'M7 11V8a5 5 0 0 1 10 0v3M5 11h14v9H5z',
    food:    'M7 3v8a3 3 0 0 0 3-3V3M7 11v10M17 3c-1.5 2-2 4-2 6s.5 3 2 3v9',
    drop:    'M12 3s6 6.5 6 10.5A6 6 0 0 1 6 13.5C6 9.5 12 3 12 3z',
    bag:     'M6 8h12l-1 12H7L6 8zm3 0V6a3 3 0 0 1 6 0v2',
    recycle: 'M7 17H4l3-5m6-6 2 3m-2-3-3 5m9 6-2 4h-4m-3 0H7l2-4M20 12l-3-5-3 2',
    hand:    'M8 11V5a1.5 1.5 0 0 1 3 0v6m0-1V4a1.5 1.5 0 0 1 3 0v7m0-2a1.5 1.5 0 0 1 3 0v6a6 6 0 0 1-6 6H10l-4-5',
    wire:    'M3 8h5l2 3m4 2 2 3h5M8 6v4m8 4v4M10 11l4 2',
    crowbar: 'M5 20 16 7m0 0 3-3 2 2-3 3m-2-2-3-3M5 20l-2-2',
    fridge:  'M6 3h12v18H6zM6 11h12M9 6v2m0 6v3',
    barrel:  'M5 4h14l-1 16H6L5 4zm1 3h12M6 17h12',
    npc:     'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 20c0-4 3-7 8-7 2 0 4 1 5 2m2-8h3v5h-3l-2 2V7z',
    hanger:  'M9 6a3 3 0 0 1 6 0c0 2-3 2-3 5m0 0L3 17v2h18v-2l-9-6',
    dig:     'M3 19h18M7 17l4-5m1-8 7 7-4 4-7-7zM8 19l-2-2',
    fill:    'M3 20h18M5 18l4-4m1-9 7 7-3 3-7-7zM16 17l2 2',
    pickaxe: 'M4 21l9-11m-3-3c4-4 8-4 11-1l-6 2-3 4-2-5z',
    axe:     'M5 20 14 5m0 0 6 2-2 6-6-2 2-6zM4 21h17',
    flag:    'M5 21V3m0 1c5-2 9 2 14 0v10c-5 2-9-2-14 0',
    warning: 'M12 3 2 21h20L12 3zm0 6v5m0 3v1',
};

function icon(name) {
    const d = ICONS[name] || ICONS.hand;
    return `<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor"
             stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${d}"/></svg>`;
}

let options = [];
let index = 1;

function renderOptions() {
    if (!options.length) {
        optsEl.classList.add('hidden');
        optsEl.innerHTML = '';
        return;
    }

    optsEl.innerHTML = options.map((o, i) => `
        <div class="opt ${i + 1 === index ? 'is-active' : ''}">
            <span class="opt__key">${i + 1 === index ? 'E' : i + 1}</span>
            ${icon(o.icon)}
            <span>${String(o.label || '').toUpperCase()}</span>
            ${o.hint ? `<span class="opt__hint">${o.hint}</span>` : ''}
        </div>`).join('');
    optsEl.classList.remove('hidden');
}

window.addEventListener('message', (e) => {
    const d = e.data || {};

    if (d.action === 'dot') {
        if (d.settings) {
            const s = document.documentElement.style;
            s.setProperty('--dot-size', `${d.settings.size ?? 6}px`);
            s.setProperty('--ring-size', `${d.settings.ring ?? 26}px`);
            s.setProperty('--dot-alpha', String(d.settings.idle ?? 0.35));
        }
        if (typeof d.visible === 'boolean') dotEl.classList.toggle('hidden', !d.visible);
    }

    if (d.action === 'target') {
        if (d.state === 'live') {
            options = d.options || [];
            index = d.index || 1;
            dotEl.classList.add('is-live');
            renderOptions();
        } else {
            options = [];
            dotEl.classList.remove('is-live');
            renderOptions();
        }
    }

    if (d.action === 'index') {
        index = d.index || 1;
        renderOptions();
    }

    if (d.action === 'progress') {
        if (d.cancel) {
            progEl.classList.add('hidden');
            fillEl.style.transition = 'none';
            fillEl.style.width = '0%';
            return;
        }
        document.getElementById('progress-label').textContent =
            String(d.label || t('ui.searching')).toUpperCase();
        progEl.classList.remove('hidden');

        // Restart the progress bar transition by forcing a reflow between the two width changes; requestAnimationFrame alone can coalesce them and the bar never moves.
        fillEl.style.transition = 'none';
        fillEl.style.width = '0%';
        void fillEl.offsetWidth;
        fillEl.style.transition = `width ${d.duration || 4000}ms linear`;
        fillEl.style.width = '100%';
    }
});

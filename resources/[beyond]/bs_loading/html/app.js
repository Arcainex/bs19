// BeyondSurvival loading screen. Driven by real FiveM load events, so the bar shows actual progress.

// log

const BROADCAST = [
    { stamp: '04:12', text: 'Relay is live. If anyone is receiving this, you are not the last.' },
    { stamp: '04:19', text: 'Blaine County shelter is past capacity. They are turning people away at the fence.' },
    { stamp: '05:02', text: 'Do not follow the highway south. Whatever came through it is still there.', alert: true },
    { stamp: '05:44', text: 'Water at the reservoir tested clean. Boil it anyway.' },
    { stamp: '06:30', text: 'We lost the eastern checkpoint overnight. No survivors accounted for.' },
    { stamp: '07:15', text: 'They move slow until they hear you. Then they do not.', alert: true },
    { stamp: '08:03', text: 'Trading post at the camp is still standing. Bring something worth having.' },
    { stamp: '09:21', text: 'Four of us left from a group of twenty. We keep going anyway.' },
];

const NOTES_EN = [
    'Sound carries further than you think. A gunshot brings the whole street.',
    'A crowded room is a dead end. Always know where the second door is.',
    'Bandages before bullets. You cannot shoot what you cannot stand up for.',
    'Scrap is worth more than money. Money stopped meaning anything years ago.',
    'Night doubles their numbers. Whatever you need, get it before dark.',
    'Nobody survives alone out here. Not for long.',
    'Check the bodies. Check them again. People hide things.',
    'If it is quiet, something already cleared the area. Ask yourself what.',
];
const NOTES = (LANG && LANG.notes) || NOTES_EN;
if (LANG && LANG.log) BROADCAST.forEach((b, i) => { if (LANG.log[i]) b.text = LANG.log[i]; });


const logEl    = document.getElementById('log');
const tipEl    = document.getElementById('tip');
const barEl    = document.getElementById('bar');
const pctEl    = document.getElementById('pct');
const statusEl = document.getElementById('status');
const dayEl    = document.getElementById('day');

// Day counter drifts so the world feels like it kept going.
dayEl.textContent = LT('day', null, 'DAY') + ' ' + (1380 + Math.floor(Math.random() * 90)).toLocaleString('en-US');

// Types one broadcast line out character by character.
function typeLine({ stamp, text, alert }, done) {
    const el = document.createElement('div');
    el.className = 'line line--now' + (alert ? ' line--alert' : '');
    el.dataset.stamp = stamp;

    const body = document.createElement('span');
    const caret = document.createElement('span');
    caret.className = 'line__caret';
    el.append(body, caret);
    logEl.appendChild(el);

    // Keep the log to a readable window; older lines fade.
    const lines = logEl.querySelectorAll('.line');
    if (lines.length > 6) lines[0].remove();
    lines.forEach((l, i) => {
        if (i < lines.length - 1) l.classList.remove('line--now');
    });

    let i = 0;
    (function tick() {
        if (i >= text.length) {
            caret.remove();
            return done && done();
        }
        // Uneven cadence reads like typing.
        body.textContent += text[i++];
        setTimeout(tick, 14 + Math.random() * 34);
    })();
}

let entry = 0;
(function nextLine() {
    typeLine(BROADCAST[entry % BROADCAST.length], () => {
        entry++;
        setTimeout(nextLine, 2600);
    });
})();

// notes

let note = Math.floor(Math.random() * NOTES.length);
function rotateNote() {
    tipEl.classList.add('fading');
    setTimeout(() => {
        tipEl.textContent = NOTES[note++ % NOTES.length];
        tipEl.classList.remove('fading');
    }, 500);
}
tipEl.textContent = NOTES[note++ % NOTES.length];
setInterval(rotateNote, 7000);

// progress

let shown = 0;

function setProgress(fraction) {
    const target = Math.max(0, Math.min(100, Math.round(fraction * 100)));
    // Never let the bar go backwards - each FiveM phase reports its own 0-1.
    if (target < shown) return;
    shown = target;
    barEl.style.width = shown + '%';
    pctEl.textContent = shown + '%';
}

function setStatus(text) {
    if (!text) return;
    statusEl.textContent = String(text).toUpperCase().slice(0, 90);
}

// FiveM loading-screen events.
window.addEventListener('message', (event) => {
    const d = event.data || {};
    switch (d.eventName) {
        case 'loadProgress':
            setProgress(d.loadFraction ?? 0);
            break;
        case 'startInitFunction':
            setStatus(LT('init', { x: d.type || LT('systems', null, 'systems') }, 'initialising {x}'));
            break;
        case 'startDataFileEntries':
            setStatus(LT('reading', { n: d.count || 0 }, 'reading {n} data files'));
            break;
        case 'onDataFileEntry':
            setStatus(LT('mounting', { x: d.name || LT('archive', null, 'archive') }, 'mounting {x}'));
            break;
        case 'performMapLoadFunction':
            setStatus(LT('rebuild', null, 'rebuilding the world'));
            break;
        case 'onLogLine':
            setStatus(d.message);
            break;
        case 'startInitFunctionOrder':
        case 'initFunctionInvoking':
            setStatus(LT('loading', { x: d.type || '' }, 'loading {x}'));
            break;
        case 'endLoadingScreen':
            setProgress(1);
            setStatus(LT('welcome', null, 'welcome to what is left'));
            break;
    }
});

// Nothing reported yet - creep forward so it never looks frozen.
let idle = 0;
const creep = setInterval(() => {
    idle += 1;
    if (shown === 0 && idle > 2) setProgress(Math.min(0.08, idle * 0.01));
    if (shown >= 100) clearInterval(creep);
}, 1000);

// ambience

const canvas = document.getElementById('spores');
const ctx = canvas.getContext('2d');
let spores = [];

function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    const count = Math.round((canvas.width * canvas.height) / 26000);
    spores = Array.from({ length: count }, () => ({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        r: Math.random() * 1.6 + 0.3,
        vy: -(Math.random() * 0.22 + 0.05),
        vx: (Math.random() - 0.5) * 0.18,
        a: Math.random() * 0.4 + 0.1,
        drift: Math.random() * Math.PI * 2,
    }));
}

function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const s of spores) {
        s.drift += 0.01;
        s.x += s.vx + Math.sin(s.drift) * 0.16;
        s.y += s.vy;
        if (s.y < -5) { s.y = canvas.height + 5; s.x = Math.random() * canvas.width; }
        if (s.x < -5) s.x = canvas.width + 5;
        if (s.x > canvas.width + 5) s.x = -5;

        ctx.beginPath();
        ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(216, 210, 194, ${s.a})`;
        ctx.fill();
    }
    requestAnimationFrame(draw);
}

window.addEventListener('resize', resize);
resize();
draw();

// Static labels.
document.querySelector('.head__since').textContent = LT('since', null, 'SINCE THE OUTBREAK');
document.querySelector('.tip__label').textContent = LT('note', null, 'FIELD NOTE');
if (statusEl.textContent === 'ESTABLISHING UPLINK') statusEl.textContent = LT('uplink', null, 'ESTABLISHING UPLINK');

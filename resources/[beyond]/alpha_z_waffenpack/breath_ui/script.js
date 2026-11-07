const effect = document.getElementById('breathEffect');

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'alphaZBreath') {
        const active = data.active === true;
        effect.classList.toggle('active', active);
        if (!active) {
            effect.style.setProperty('--breath-progress', '0');
        }
        return;
    }

    if (data.action === 'alphaZBreathProgress') {
        const raw = Number(data.progress);
        const progress = Number.isFinite(raw) ? Math.max(0, Math.min(1, raw)) : 0;
        effect.style.setProperty('--breath-progress', progress.toFixed(4));
    }
});

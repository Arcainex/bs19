(() => {
    const panel = document.createElement('section');
    panel.className = 'fishing-game hidden';
    panel.setAttribute('aria-label','Fishing');
    panel.innerHTML = '<header><span>FISHING</span><b id="fishScore">0 / 3</b></header><p id="fishHint">Tap E while the marker crosses the amber zone.</p><div class="fishing-game__track"><i id="fishTarget"></i><b id="fishCursor"></b></div><footer>E · REEL &nbsp; BACKSPACE · CANCEL</footer>';
    document.body.append(panel);
    const cursor = panel.querySelector('#fishCursor'), target = panel.querySelector('#fishTarget');
    window.addEventListener('message', ({data:d}) => {
        if (d.action === 'fishingOpen') {
            panel.classList.remove('hidden');
            panel.querySelector('#fishScore').textContent = '0 / 3';
            panel.querySelector('#fishHint').textContent = 'Tap E while the marker crosses the amber zone.';
        }
        if (d.action === 'fishingClose') panel.classList.add('hidden');
        if (d.action === 'fishingTick') {
            cursor.style.left = `${Math.max(0,Math.min(1,d.cursor))*100}%`;
            target.style.left = `${(d.target-d.width/2)*100}%`;
            target.style.width = `${d.width*100}%`;
            panel.querySelector('#fishScore').textContent = `${d.score} / 3`;
            panel.querySelector('#fishHint').textContent = d.ready ? 'Fish hooked. Bringing it in…' : 'Tap E while the marker crosses the amber zone.';
        }
    });
})();

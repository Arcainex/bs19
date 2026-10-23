/* BeyondSurvival | announce.js - staff broadcast banner, one at a time, newest wins. */

(function () {
    let root = null;
    let timer = null;

    function build() {
        root = document.createElement('div');
        root.id = 'announce';
        root.className = 'announce hidden';
        root.innerHTML = '<div class="announce__band">' +
            '<span class="announce__kicker"></span>' +
            '<h2 class="announce__title"></h2>' +
            '<p class="announce__text"></p>' +
            '<i class="announce__timer"></i>' +
            '</div>';
        document.body.appendChild(root);
    }

    function hide() {
        if (!root) return;
        root.classList.add('announce--out');
        setTimeout(() => { root.classList.add('hidden'); root.classList.remove('announce--out'); }, 420);
    }

    BS.on('announce', (d) => {
        if (!root) build();
        clearTimeout(timer);
        const ms = Math.max(3000, Math.min(30000, Number(d.duration) || 10000));

        root.querySelector('.announce__kicker').textContent = d.by ? '// ' + d.by : '//';
        root.querySelector('.announce__title').textContent = d.title || '';
        root.querySelector('.announce__text').textContent = d.text || '';

        const bar = root.querySelector('.announce__timer');
        bar.style.animation = 'none';
        void bar.offsetWidth;
        bar.style.animation = `announce-drain ${ms}ms linear forwards`;

        // restart the entry animation when one replaces another
        root.classList.remove('hidden', 'announce--out', 'announce--in');
        void root.offsetWidth;
        root.classList.add('announce--in');

        timer = setTimeout(hide, ms);
    });
})();

// Theme pack loader. Include in any NUI page: sets <html data-theme> and loads nui://bs_ui/html/themes/<pack>.css.
// The active pack is asked from bs_ui (callback themeGet); a refresh from F1 bumps rev and every open page reloads the sheet.
(function () {
    if (window.__bsTheme) return;
    window.__bsTheme = true;
    var BASE = 'nui://bs_ui/html/themes/', KEY = 'bs_theme_pack', cur = '', loadedPack = '', link = null, skin = null;
    function apply(pack, rev) {
        if (!/^[a-z0-9_]{1,24}$/.test(pack || '')) pack = 'classic';
        document.documentElement.setAttribute('data-theme', pack);
        if (!link) {
            // skin first, then the pack, so pack tokens win over the skin defaults
            skin = document.createElement('link');
            skin.rel = 'stylesheet';
            skin.id = 'bs-theme-skin';
            link = document.createElement('link');
            link.rel = 'stylesheet';
            link.id = 'bs-theme-css';
            (document.head || document.documentElement).appendChild(skin);
            (document.head || document.documentElement).appendChild(link);
        }
        var nextSkin=BASE+'skin.css?r='+(rev||0);if(skin.getAttribute('href')!==nextSkin)skin.setAttribute('href',nextSkin);
        var signature=pack+':'+(rev||0);if(loadedPack!==signature){link.href=BASE+pack+'.css?r='+(rev||0);loadedPack=signature;}
    }
    // The server/profile is authoritative; stale browser storage must not flash another pack.
    apply('classic', 0);
    function poll() {
        fetch('https://bs_ui/themeGet', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
            .then(function (r) { return r.json(); })
            .then(function (t) {
                if (!t || !t.theme) return;
                var sig = t.theme + ':' + t.rev;
                if (sig === cur) return;
                cur = sig;
                apply(t.theme, t.rev);
                try { localStorage.setItem(KEY, t.theme); } catch (e) {}
            })
            .catch(function () {});
    }
    poll();
    setInterval(poll, 4000);
})();

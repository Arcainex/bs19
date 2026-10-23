// bs_ui - personal screen filter, page side. Receives already-resolved values (cl_filter.lua applies master strength) and just sets four numbers.

(function () {
    'use strict';

    var root = document.getElementById('filter');
    if (!root) { return; }

    var tint = root.querySelector('.filter__tint');
    var vignette = root.querySelector('.filter__vignette');
    var grain = root.querySelector('.filter__grain');
    var scanlines = root.querySelector('.filter__scanlines');

    function clamp(n) { return Math.max(0, Math.min(1, Number(n) || 0)); }

    function apply(filter) {
        if (!filter) {
            // Remove the class and leave the layers alone so the #filter opacity transition fades everything as one piece.
            root.classList.remove('on');
            return;
        }

        vignette.style.opacity = clamp(filter.vignette);
        scanlines.style.opacity = clamp(filter.scanlines);

        // Grain is capped well under 1: full opacity washes the game out.
        grain.style.opacity = clamp(filter.grain) * 0.35;

        if (filter.tint && filter.tint.a > 0) {
            tint.style.background = 'rgba(' + [
                Math.round(filter.tint.r || 0),
                Math.round(filter.tint.g || 0),
                Math.round(filter.tint.b || 0),
                clamp(filter.tint.a).toFixed(3),
            ].join(',') + ')';
        } else {
            tint.style.background = 'transparent';
        }

        root.classList.add('on');
    }

    window.addEventListener('message', function (event) {
        var msg = event.data || {};
        if (msg.action !== 'filter') { return; }
        apply(msg.filter);
    });
})();

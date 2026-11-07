// BeyondSurvival phone item icon override. Only item id `phone` is changed.
(() => {
    if (typeof BSIcons === 'undefined' || !BSIcons || typeof BSIcons.get !== 'function') return;
    const originalGet = BSIcons.get.bind(BSIcons);
    BSIcons.get = function(item, category) {
        if (String(item || '').toLowerCase() === 'phone') {
            return '<img src="img/phone.png?v=20261031-phone-item" alt="Handy" draggable="false">';
        }
        return originalGet(item, category);
    };
})();

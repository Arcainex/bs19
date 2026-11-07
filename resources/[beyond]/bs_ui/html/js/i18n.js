// Shared NUI translations. Load with <script src="nui://bs_ui/html/js/i18n.js"></script> before the page script.
// The Lua side (@bs_core/shared/sh_locale.lua) sends { action: 'bs_i18n', lang, dict } and answers the bs_i18n callback.
// Markup: data-i18n="key" sets textContent, data-i18n-html="key" sets innerHTML, data-i18n-attr="placeholder:key;title:key2".
// Script: t('key', { name: 'x' }). BSI18n.onChange(fn) re-renders dynamic text when the language changes.
(function () {
    const res = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : null;
    let dict = {};
    let lang = 'en';
    const listeners = [];

    function t(key, vars) {
        let s = Object.prototype.hasOwnProperty.call(dict, key) ? dict[key] : null;
        if (s === null || s === undefined) {
            // fall back to the English text already in the markup, then the key
            return vars && vars.fallback !== undefined ? vars.fallback : key;
        }
        s = String(s);
        if (vars) s = s.replace(/\{(\w+)\}/g, (m, n) => (vars[n] !== undefined ? String(vars[n]) : m));
        return s;
    }

    function apply(root) {
        root = root || document;
        root.querySelectorAll('[data-i18n]').forEach((el) => {
            const k = el.getAttribute('data-i18n');
            if (el.dataset.i18nOrig === undefined) el.dataset.i18nOrig = el.textContent;
            // page script rewrote it since (live value), leave it alone
            const last = el.dataset.i18nLast !== undefined ? el.dataset.i18nLast : el.dataset.i18nOrig;
            if (el.textContent !== last) return;
            el.textContent = t(k, { fallback: el.dataset.i18nOrig });
            el.dataset.i18nLast = el.textContent;
        });
        root.querySelectorAll('[data-i18n-html]').forEach((el) => {
            const k = el.getAttribute('data-i18n-html');
            if (el.dataset.i18nOrig === undefined) el.dataset.i18nOrig = el.innerHTML;
            const last = el.dataset.i18nLast !== undefined ? el.dataset.i18nLast : el.dataset.i18nOrig;
            if (el.innerHTML !== last) return;
            el.innerHTML = t(k, { fallback: el.dataset.i18nOrig });
            el.dataset.i18nLast = el.innerHTML;
        });
        root.querySelectorAll('[data-i18n-attr]').forEach((el) => {
            el.getAttribute('data-i18n-attr').split(';').forEach((pair) => {
                const [attr, k] = pair.split(':').map((x) => x && x.trim());
                if (!attr || !k) return;
                const store = 'i18nOrig_' + attr;
                if (el.dataset[store] === undefined) el.dataset[store] = el.getAttribute(attr) || '';
                el.setAttribute(attr, t(k, { fallback: el.dataset[store] }));
            });
        });
        if (document.documentElement) document.documentElement.lang = lang;
    }

    function set(newLang, newDict) {
        if (newDict && typeof newDict === 'object') dict = newDict;
        if (newLang) lang = newLang;
        apply(document);
        listeners.forEach((fn) => { try { fn(lang); } catch (e) { /* keep going */ } });
    }

    window.addEventListener('message', (e) => {
        const d = e.data;
        if (d && d.action === 'bs_i18n') set(d.lang, d.dict);
    });

    function request() {
        if (!res) return;
        fetch(`https://${res}/bs_i18n`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: '{}',
        }).then((r) => r.json()).then((d) => { if (d) set(d.lang, d.dict); }).catch(() => {});
    }

    window.BSI18n = {
        t, apply, request,
        lang: () => lang,
        onChange: (fn) => listeners.push(fn),
    };
    window.t = window.t || t;

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', request);
    else request();
})();

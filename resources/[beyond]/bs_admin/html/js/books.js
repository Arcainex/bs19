// BeyondSurvival BS19 — F10 book administration.
// Uses the existing HTML IDs, admin callback and notification UI.
(() => {
    'use strict';

    const $ = (id) => document.getElementById(id);
    if (!$('bkList')) return;

    const PAGE_DEFAULTS = Object.freeze({
        text: '',
        image: '',
        font: 'normal',
        fontFamily: 'georgia',
        fontSize: 17,
        align: 'left',
        color: '#352719',
        layout: 'standard',
        background: ''
    });

    let book = null;
    let pageIndex = 0;
    let books = [];
    let busy = false;
    const debugLines = [];
    function debug(stage, detail = '') {
        const line = `[${new Date().toLocaleTimeString()}] ${stage}${detail ? ' | ' + detail : ''}`;
        debugLines.push(line);
        if (debugLines.length > 100) debugLines.shift();
        console.log('[BS19 BOOKS]', line);
        const out = $('bkDebugLog');
        if (out) { out.textContent = debugLines.join('\n'); out.scrollTop = out.scrollHeight; }
    }
    const debugBox = document.createElement('details');
    debugBox.className = 'bk-section';
    debugBox.innerHTML = '<summary>🛠 DEBUG / PROTOKOLL</summary><div class="bk-section__content"><button type="button" id="bkDebugCopy" class="row">LOG KOPIEREN</button><pre id="bkDebugLog" style="max-height:200px;overflow:auto;white-space:pre-wrap;user-select:text;font-size:11px"></pre></div>';
    $('bsBooksPane').appendChild(debugBox);
    $('bkDebugCopy').onclick = () => { const t = debugLines.join('\n'); navigator.clipboard?.writeText(t).then(() => showStatus('Debug-Log kopiert')).catch(() => showStatus('Debug-Log unten markieren und kopieren.')); };
    window.addEventListener('error', e => debug('JS ERROR', `${e.message} @ ${e.filename}:${e.lineno}`));
    window.addEventListener('unhandledrejection', e => debug('PROMISE ERROR', String(e.reason)));
    debug('Editor gestartet');

    function newPage() {
        return { ...PAGE_DEFAULTS };
    }

    function newBook() {
        return {
            id: '',
            title: '',
            author: '',
            description: '',
            cover: '',
            layout: 'standard',
            background: '',
            pages: [newPage()]
        };
    }

    async function request(action, args = {}) {
        debug('REQUEST', action);
        try {
            const response = await fetch(`https://${GetParentResourceName()}/booksAdmin`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action, args })
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const result = await response.json();
            debug('RESPONSE', `${action}: ${result?.ok ? 'OK' : String(result?.error || 'FEHLER')}`);
            return result;
        } catch (error) {
            debug('REQUEST ERROR', `${action}: ${String(error)}`);
            return { ok: false, error: String(error) };
        }
    }

    function showStatus(message, isError = false, toast = true) {
        const text = String(message || '');
        const element = $('bkStatus');
        if (element) element.textContent = text;
        debug(isError ? 'ERROR' : 'STATUS', text);

        // The existing F10 message widget (defined in app.js).
        if (toast && typeof msg === 'function') {
            msg(text, isError);
        }
    }

    function setBusy(value) {
        busy = value;
        for (const id of ['bkSave', 'bkDelete', 'bkGive']) {
            const button = $(id);
            if (button) button.disabled = value;
        }
    }

    function safeImageUrl(value) {
        return (/^https:\/\/[^\s"'<>]+$/i.test(value || '') || /^data:image\/(?:png|jpeg|webp);base64,[a-z0-9+/=]+$/i.test(value || '')) ? value : '';
    }

    function saveCurrentPage() {
        if (!book || !book.pages[pageIndex]) return;
        const page = book.pages[pageIndex];
        page.text = $('bkText').value;
        page.image = $('bkImage').value;
        page.font = $('bkFont').value;
        page.fontFamily = $('bkFontFamily').value;
        page.fontSize = Math.max(12, Math.min(24, Number($('bkFontSize').value) || 17));
        page.align = $('bkAlign').value;
        page.color = $('bkColor').value;
        page.layout = $('bkLayout').value;
        page.background = pageIndex === 0 ? $('bkBackground').value : '';
    }

    function readBookDetails() {
        if (!book) return;
        book.id = $('bkId').value.trim();
        book.title = $('bkTitle').value.trim();
        book.author = $('bkAuthor').value.trim();
        book.description = $('bkDescription').value.trim();
        book.cover = $('bkCover').value.trim();
        book.layout = $('bkLayout').value;
        book.background = $('bkBackground').value;
        book.pages.forEach((p, i) => { p.layout = book.layout; p.background = i === 0 ? book.background : ''; });
    }

    function fontStack(key) {
        return ({ georgia: 'Georgia, serif', arial: 'Arial, sans-serif', courier: '"Courier New", monospace', caveat: 'Caveat, cursive', kalam: 'Kalam, cursive', cinzel: 'Cinzel, serif' })[key] || 'Georgia, serif';
    }

    function updatePreview() {
        const text = $('bkPreviewText');
        const image = $('bkPreviewImage');

        text.textContent = $('bkText').value;
        text.style.fontSize = `${Math.max(12, Math.min(24, Number($('bkFontSize').value) || 17))}px`;
        text.style.fontFamily = fontStack($('bkFontFamily').value);
        text.style.textAlign = $('bkAlign').value;
        text.style.color = $('bkColor').value;

        const preview = $('bkPreview');
        preview.classList.remove('bk-theme-standard','bk-theme-clean','bk-theme-rusty','bk-theme-torn');
        preview.classList.add('bk-theme-' + $('bkLayout').value);
        const binding = ['standard','clean','rusty','torn'].includes($('bkLayout').value) ? $('bkLayout').value : 'standard';
        const coverPreview = document.querySelector('#bsBooksPane .bk-cover-preview');
        if (coverPreview) coverPreview.style.backgroundImage = `url("img/book_themes/${binding}_binding.png")`;
        preview.style.backgroundImage = safeImageUrl($('bkBackground').value) ? `url("${$('bkBackground').value}")` : '';
        const url = safeImageUrl($('bkImage').value.trim());
        image.hidden = !url;
        if (url) image.src = url;
        else image.removeAttribute('src');
    }

    // Pagination uses the same page dimensions, font and image as the visible preview.
    // A hidden measurement page prevents overflowing text from being saved.
    const pageMeasure = document.createElement('div');
    pageMeasure.className = 'bk-page';
    pageMeasure.style.cssText = 'position:fixed!important;left:-10000px!important;top:0!important;visibility:hidden!important;pointer-events:none!important;width:340px!important;height:425px!important;aspect-ratio:auto!important;overflow:hidden!important;';
    const measureText = document.createElement('div');
    measureText.className = 'bk-page__text';
    const measureImage = document.createElement('img');
    measureImage.hidden = true;
    pageMeasure.append(measureText, measureImage);
    document.body.appendChild(pageMeasure);
    function textFits(value) {
        const visible = $('bkPreview');
        const width = visible.getBoundingClientRect().width || 340;
        pageMeasure.style.width = `${width}px`;
        pageMeasure.style.height = `${width * 1.25}px`;
        const computed = getComputedStyle($('bkPreviewText'));
        measureText.style.fontFamily = computed.fontFamily;
        measureText.style.fontSize = computed.fontSize;
        measureText.style.lineHeight = computed.lineHeight;
        measureText.style.textAlign = computed.textAlign;
        measureText.textContent = value || ' ';
        const image = $('bkPreviewImage');
        measureImage.hidden = image.hidden;
        if (!image.hidden) {
            measureImage.src = image.src;
            measureImage.style.width = `${image.getBoundingClientRect().width || width * .65}px`;
            measureImage.style.height = `${image.getBoundingClientRect().height || width * .4}px`;
        }
        const padding = parseFloat(getComputedStyle(pageMeasure).paddingTop) + parseFloat(getComputedStyle(pageMeasure).paddingBottom);
        return measureText.scrollHeight + (measureImage.hidden ? 0 : measureImage.height + 12) <= pageMeasure.clientHeight - padding - 3;
    }
    let paginating = false;
    function paginateTyping() {
        if (paginating || !book) return;
        const field = $('bkText');
        const cursor = field.selectionStart;
        // Only split when typing/pasting at the end. Editing older text stays on its page.
        if (cursor < field.value.length || textFits(field.value)) return;
        paginating = true;
        try {
            while (!textFits(field.value)) {
                if (book.pages.length >= 80) {
                    showStatus('Maximal 80 Seiten – bitte Text kürzen.', true);
                    break;
                }
                const content = field.value;
                let lo = 0, hi = content.length;
                while (lo < hi) {
                    const mid = Math.ceil((lo + hi) / 2);
                    if (textFits(content.slice(0, mid))) lo = mid;
                    else hi = mid - 1;
                }
                let cut = lo;
                const word = content.lastIndexOf(' ', lo);
                const newline = content.lastIndexOf('\n', lo);
                const boundary = Math.max(word, newline);
                if (boundary > Math.max(0, lo - 90)) cut = boundary + 1;
                if (cut <= 0) break;
                const remainder = content.slice(cut);
                field.value = content.slice(0, cut).trimEnd();
                saveCurrentPage();
                const next = { ...book.pages[pageIndex], text: remainder, image: '', background: '' };
                book.pages.splice(pageIndex + 1, 0, next);
                pageIndex++;
                renderBook();
                field.focus();
                field.setSelectionRange(field.value.length, field.value.length);
            }
        } finally { paginating = false; updatePreview(); }
    }
    $('bkText').addEventListener('input', paginateTyping);
    $('bkFontSize').addEventListener('change', paginateTyping);
    $('bkFontFamily').addEventListener('change', paginateTyping);

    // Custom font picker: native <select> popup menus can fail in FiveM NUI.
    function syncFontPicker() {
        const select = $('bkFontFamily');
        const selected = select.options[select.selectedIndex];
        $('bkFontToggle').firstChild.textContent = `${selected ? selected.textContent : 'Georgia · Buchdruck'} `;
    }
    function closeFontPicker() {
        $('bkFontOptions').hidden = true;
        $('bkFontToggle').setAttribute('aria-expanded', 'false');
    }
    $('bkFontToggle').addEventListener('click', () => {
        const panel = $('bkFontOptions');
        panel.hidden = !panel.hidden;
        $('bkFontToggle').setAttribute('aria-expanded', String(!panel.hidden));
    });
    document.querySelectorAll('[data-bk-font]').forEach(button => {
        button.addEventListener('click', () => {
            $('bkFontFamily').value = button.dataset.bkFont;
            syncFontPicker();
            closeFontPicker();
            $('bkFontFamily').dispatchEvent(new Event('input', { bubbles: true }));
        });
    });
    document.addEventListener('click', event => {
        if (!$('bkFontPicker').contains(event.target)) closeFontPicker();
    });

    // Both sources write to the existing bkImage field so persistence remains unchanged.
    const imageUrlField = $('bkImageUrl');
    imageUrlField.addEventListener('input', () => {
        const value = imageUrlField.value.trim();
        if (!value) {
            if (!$('bkImage').value.startsWith('data:')) $('bkImage').value = '';
        } else if (/^https:\/\/[^\s"'<>]+$/i.test(value)) {
            $('bkImage').value = value;
            $('bkImageInfo').textContent = 'Bild über HTTPS-URL';
        } else {
            $('bkImage').value = '';
            $('bkImageInfo').textContent = 'Bitte eine gültige HTTPS-URL eingeben';
        }
        updatePreview();
    });

    // Desktop files are resized proportionally, max 1024px, and JPEG-compressed for DB storage.
    $('bkChooseImage').addEventListener('click', () => $('bkImageFile').click());
    $('bkRemoveImage').addEventListener('click', () => {
        $('bkImage').value = '';
        imageUrlField.value = '';
        $('bkImageFile').value = '';
        $('bkImageInfo').textContent = 'Kein Bild ausgewählt';
        updatePreview();
    });
    $('bkImageFile').addEventListener('change', async (event) => {
        const file = event.target.files?.[0];
        if (!file) return;
        if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 8 * 1024 * 1024) {
            showStatus('Bitte PNG, JPG oder WebP unter 8 MB wählen.', true); return;
        }
        try {
            const objectUrl = URL.createObjectURL(file);
            const bitmap = new Image();
            try {
                await new Promise((resolve, reject) => { bitmap.onload = resolve; bitmap.onerror = reject; bitmap.src = objectUrl; });
                const scale = Math.min(1, 1024 / bitmap.naturalWidth, 1024 / bitmap.naturalHeight);
                const canvas = document.createElement('canvas');
                canvas.width = Math.max(1, Math.round(bitmap.naturalWidth * scale));
                canvas.height = Math.max(1, Math.round(bitmap.naturalHeight * scale));
                canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
                // Keep 1024px as the maximum, not a mandatory upscale size.
                // Reduce quality first; if necessary reduce dimensions until it fits the DB limit.
                let data = '';
                let quality = .86;
                for (let pass = 0; pass < 8; pass++) {
                    data = canvas.toDataURL('image/jpeg', quality);
                    if (data.length <= 650000) break;
                    if (quality > .46) quality -= .12;
                    else {
                        const resized = document.createElement('canvas');
                        resized.width = Math.max(1, Math.round(canvas.width * .8));
                        resized.height = Math.max(1, Math.round(canvas.height * .8));
                        resized.getContext('2d').drawImage(canvas, 0, 0, resized.width, resized.height);
                        canvas.width = resized.width;
                        canvas.height = resized.height;
                        canvas.getContext('2d').drawImage(resized, 0, 0);
                    }
                }
                if (data.length > 650000) throw new Error('Bild ist nach Komprimierung zu groß.');
                $('bkImage').value = data;
                imageUrlField.value = '';
                $('bkImageInfo').textContent = `${canvas.width} × ${canvas.height} px · ${Math.round(data.length * .75 / 1024)} KB`;
                updatePreview();
                showStatus('Seitenbild bereit – mit BUCH SPEICHERN dauerhaft übernehmen.');
            } finally { URL.revokeObjectURL(objectUrl); }
        } catch (error) { showStatus('Bild konnte nicht geladen werden: ' + error.message, true); }
    });

    // Book cover and paper background: independent, optional, URL or local file.
    async function imageFileData(file) {
        if (!file || !['image/png','image/jpeg','image/webp'].includes(file.type) || file.size > 8*1024*1024) throw Error('PNG, JPG oder WebP unter 8 MB wählen.');
        const objectUrl = URL.createObjectURL(file);
        try {
            const img = new Image();
            await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=objectUrl;});
            let scale = Math.min(1,1024/img.naturalWidth,1024/img.naturalHeight);
            let w=Math.max(1,Math.round(img.naturalWidth*scale)),h=Math.max(1,Math.round(img.naturalHeight*scale));
            for(let pass=0;pass<12;pass++) {
                const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;
                canvas.getContext('2d').drawImage(img,0,0,w,h);
                for(const quality of [.86,.7,.55,.4]) {
                    const data=canvas.toDataURL('image/jpeg',quality);
                    if(data.length<=650000) return data;
                }
                w=Math.max(1,Math.round(w*.8));h=Math.max(1,Math.round(h*.8));
            }
            throw Error('Bild konnte nicht ausreichend komprimiert werden.');
        } finally { URL.revokeObjectURL(objectUrl); }
    }
    function syncMedia(name) {
        const val=$(name==='Cover'?'bkCover':'bkBackground').value;
        const mode=$('bk'+name+'Mode');
        mode.value = !val ? (mode.value==='url'||mode.value==='file'?mode.value:(name==='Cover'?'none':'default')) : val.startsWith('https://')?'url':'file';
        $('bk'+name+'UrlWrap').hidden=mode.value!=='url';
        $('bk'+name+'FileWrap').hidden=mode.value!=='file';
        $('bk'+name+'Url').value=val.startsWith('https://')?val:'';
        $('bk'+name+'Info').textContent=!val?(name==='Cover'?'Kein Cover ausgewählt':'Hintergrund des Buchlayouts'):(val.startsWith('data:')?'Bild vom Computer gespeichert':'HTTPS-Bild ausgewählt');
        if(name==='Cover') {
            $('bkCoverPreview').hidden=!safeImageUrl(val);
            if(safeImageUrl(val)) $('bkCoverPreview').src=val;else $('bkCoverPreview').removeAttribute('src');
        }
    }
    for(const name of ['Cover','Background']) {
        const hidden=$(name==='Cover'?'bkCover':'bkBackground');
        $('bk'+name+'Mode').addEventListener('change',()=>{
            const mode=$('bk'+name+'Mode').value;
            hidden.value=mode==='url'?$('bk'+name+'Url').value.trim():'';
            syncMedia(name);updatePreview();
        });
        $('bk'+name+'Url').addEventListener('input',()=>{
            hidden.value=safeImageUrl($('bk'+name+'Url').value.trim());
            $('bk'+name+'Info').textContent=hidden.value?'HTTPS-Bild ausgewählt':'Bitte einen gültigen HTTPS-Bildlink eingeben';
            if(name==='Cover'){ $('bkCoverPreview').hidden=!hidden.value;if(hidden.value)$('bkCoverPreview').src=hidden.value; }
            updatePreview();
        });
        $('bk'+name+'Choose').addEventListener('click',()=>$('bk'+name+'File').click());
        $('bk'+name+'File').addEventListener('change',async e=>{
            try {if(!e.target.files?.[0])return;hidden.value=await imageFileData(e.target.files[0]);syncMedia(name);updatePreview();showStatus(name==='Cover'?'Cover bereit – Buch speichern.':'Hintergrund bereit – Buch speichern.');}
            catch(err){showStatus(err.message,true);}
        });
    }
    $('bkLayout').addEventListener('change',updatePreview);

    function renderBook() {
        if (!book) return;
        const page = book.pages[pageIndex] || newPage();

        $('bkId').value = book.id || '';
        $('bkTitle').value = book.title || '';
        $('bkAuthor').value = book.author || '';
        $('bkDescription').value = book.description || '';
        $('bkCover').value = book.cover || '';
        $('bkLayout').value = book.layout || book.pages[0]?.layout || 'standard';
        $('bkBackground').value = book.background || book.pages[0]?.background || '';
        syncMedia('Cover'); syncMedia('Background');

        $('bkText').value = page.text || '';
        $('bkImage').value = page.image || '';
        imageUrlField.value = (page.image || '').startsWith('https://') ? page.image : '';
        $('bkImageInfo').textContent = page.image ? (page.image.startsWith('data:') ? 'Bild vom Desktop gespeichert' : 'Bild über HTTPS-URL') : 'Kein Bild ausgewählt';
        $('bkFont').value = page.font || 'normal';
        $('bkFontFamily').value = page.fontFamily || 'georgia';
        syncFontPicker();
        closeFontPicker();
        $('bkFontSize').value = page.fontSize || ({ small: 13, normal: 17, large: 23 }[page.font] || 17);
        $('bkAlign').value = page.align || 'left';
        $('bkColor').value = page.color || '#352719';
        $('bkPageNum').textContent = `${pageIndex + 1} / ${book.pages.length}`;
        updatePreview();
    }

    function changePage(index) {
        if (!book) return;
        saveCurrentPage();
        pageIndex = Math.max(0, Math.min(book.pages.length - 1, index));
        renderBook();
    }

    function movePage(direction) {
        if (!book) return;
        const nextIndex = pageIndex + direction;
        if (nextIndex < 0 || nextIndex >= book.pages.length) return;

        saveCurrentPage();
        [book.pages[pageIndex], book.pages[nextIndex]] =
            [book.pages[nextIndex], book.pages[pageIndex]];
        pageIndex = nextIndex;
        renderBook();
    }

    async function loadBooks({ silent = false, selectId = null } = {}) {
        const result = await request('list');
        if (!result.ok) {
            showStatus(result.error || 'Bücher konnten nicht geladen werden.', true);
            return false;
        }

        books = result.books || [];
        const list = $('bkList');
        list.replaceChildren();
        for (const entry of books) {
            const option = document.createElement('option');
            option.value = entry.id;
            option.textContent = `${entry.title} (${entry.id})`;
            list.appendChild(option);
        }
        if (selectId && books.some((entry) => entry.id === selectId)) {
            list.value = selectId;
        }
        if (!silent) {
            showStatus(`${books.length} Bücher geladen. Klassische PNG-Bücher bleiben separat.`, false, false);
        }
        return true;
    }

    function validateBeforeSave() {
        if (!book) return 'Kein Buch ausgewählt.';
        if (!/^[a-z0-9_]{1,60}$/.test(book.id)) {
            return 'Buch-ID: nur Kleinbuchstaben, Zahlen und Unterstriche (max. 60).';
        }
        if (!book.title) return 'Bitte einen Buchtitel eingeben.';
        if (!book.pages.length || book.pages.length > 80) {
            return 'Ein Buch benötigt 1 bis 80 Seiten.';
        }
        const urls = [book.cover, book.background, ...book.pages.map((page) => page.image)];
        if (urls.some((url) => url && !safeImageUrl(url))) {
            return 'Bitte gültige HTTPS-Links oder hochgeladene Bilder verwenden.';
        }
        return null;
    }

    async function saveBook() {
        if (busy || !book) return;
        saveCurrentPage();
        readBookDetails();

        const error = validateBeforeSave();
        if (error) return showStatus(error, true);

        debug('SAVE START', book.id);
        setBusy(true);
        showStatus('Buch wird gespeichert …', false, false);
        try {
            const result = await request('save', { book });
            if (!result.ok) {
                return showStatus(result.error || 'Buch konnte nicht gespeichert werden.', true);
            }
            // Refresh the list, but do not overwrite the success message.
            const loaded = await loadBooks({ silent: true, selectId: book.id });
            if (loaded) showStatus('Buch erfolgreich gespeichert!');
        } finally {
            setBusy(false);
        }
    }

    // No native confirm(): FiveM NUI/CEF can freeze or behave unexpectedly with browser dialogs.
    let deleteArmedId = null;
    let deleteTimer = null;
    async function deleteBook() {
        if (busy || !book || !book.id) return showStatus('Bitte zuerst ein gespeichertes Buch auswählen.', true);
        const id = book.id;
        if (deleteArmedId !== id) {
            deleteArmedId = id;
            const button = $('bkDelete');
            button.textContent = '⚠ WIRKLICH LÖSCHEN? (NOCHMAL KLICKEN)';
            button.classList.add('is-armed');
            clearTimeout(deleteTimer);
            deleteTimer = setTimeout(() => {
                deleteArmedId = null;
                button.textContent = 'BUCH LÖSCHEN';
                button.classList.remove('is-armed');
                debug('DELETE', 'Bestätigung abgelaufen');
            }, 8000);
            debug('DELETE CONFIRM', id);
            return showStatus(`Buch ${id} löschen? Innerhalb von 8 Sekunden erneut klicken.`, true);
        }
        clearTimeout(deleteTimer);
        deleteArmedId = null;
        $('bkDelete').textContent = 'BUCH LÖSCHEN';
        $('bkDelete').classList.remove('is-armed');
        debug('DELETE START', id);
        setBusy(true);
        try {
            const result = await request('delete', { id });
            if (!result.ok) return showStatus(result.error || 'Löschen fehlgeschlagen.', true);
            book = newBook();
            pageIndex = 0;
            renderBook();
            await loadBooks({ silent: true });
            showStatus(`Buch ${id} erfolgreich gelöscht!`);
            debug('DELETE SUCCESS', id);
        } catch (error) {
            debug('DELETE EXCEPTION', String(error));
            showStatus('Löschen fehlgeschlagen: ' + String(error), true);
        } finally {
            setBusy(false);
        }
    }

    // Uses bs_admin's existing admin:players callback; no new server endpoint.
    async function refreshBookPlayers() {
        const select = $('bkPlayer');
        if (!select) return;
        const previous = select.value;
        debug('PLAYERS REFRESH', 'loading connected players');
        try {
            const response = await fetch(`https://${GetParentResourceName()}/refreshPlayers`, {
                method: 'POST', headers: {'Content-Type':'application/json'}, body: '{}'
            });
            const players = await response.json();
            if (!Array.isArray(players)) throw new Error('Unerwartete Spielerliste');
            select.replaceChildren();
            const empty = document.createElement('option');
            empty.value = ''; empty.textContent = '— Spieler auswählen —';
            select.appendChild(empty);
            players.sort((a,b) => String(a.name || '').localeCompare(String(b.name || '')));
            for (const player of players) {
                const id = Number(player.source);
                if (!Number.isInteger(id) || id <= 0) continue;
                const option = document.createElement('option');
                option.value = String(id);
                option.textContent = player.character && player.character !== player.name
                    ? `${player.character} (${player.name})` : (player.name || `Spieler ${id}`);
                select.appendChild(option);
            }
            if ([...select.options].some(option => option.value === previous)) select.value = previous;
            debug('PLAYERS REFRESH', `${players.length} players`);
        } catch (error) {
            debug('PLAYERS ERROR', String(error));
            showStatus('Spielerliste konnte nicht geladen werden: ' + String(error), true);
        }
    }

    async function giveBook() {
        if (busy || !book || !book.id) return showStatus('Bitte ein gespeichertes Buch auswählen.', true);
        const target = Number($('bkPlayer').value);
        if (!Number.isInteger(target) || target <= 0) {
            return showStatus('Bitte einen Spieler aus der Liste auswählen.', true);
        }

        setBusy(true);
        try {
            const result = await request('give', { id: book.id, target });
            showStatus(
                result.ok ? 'Buch erfolgreich vergeben!' : result.error || 'Vergabe fehlgeschlagen.',
                !result.ok
            );
        } finally {
            setBusy(false);
        }
    }

    // Book list and editor actions.
    $('bkNew').addEventListener('click', () => {
        book = newBook();
        pageIndex = 0;
        renderBook();
        showStatus('Neues Buch – bitte Titel und Buch-ID eingeben.', false, false);
    });
    $('bkReload').addEventListener('click', () => loadBooks());
    $('bkList').addEventListener('change', async () => {
        const result = await request('get', { id: $('bkList').value });
        if (!result.ok) return showStatus(result.error || 'Buch konnte nicht geladen werden.', true);
        book = result.book;
        pageIndex = 0;
        renderBook();
    });

    // Page editing and live preview.
    for (const id of ['bkText', 'bkImage', 'bkFont', 'bkFontFamily', 'bkFontSize', 'bkAlign', 'bkColor']) {
        $(id).addEventListener('input', updatePreview);
    }
    $('bkAddPage').addEventListener('click', () => {
        if (!book) return;
        if (book.pages.length >= 80) return showStatus('Maximal 80 Seiten erlaubt.', true);
        saveCurrentPage();
        book.pages.splice(pageIndex + 1, 0, newPage());
        pageIndex++;
        renderBook();
    });
    $('bkRemovePage').addEventListener('click', () => {
        if (!book || book.pages.length === 1) return;
        book.pages.splice(pageIndex, 1);
        pageIndex = Math.min(pageIndex, book.pages.length - 1);
        renderBook();
    });
    $('bkPagePrev').addEventListener('click', () => changePage(pageIndex - 1));
    $('bkPageNext').addEventListener('click', () => changePage(pageIndex + 1));
    $('bkMoveLeft').addEventListener('click', () => movePage(-1));
    $('bkMoveRight').addEventListener('click', () => movePage(1));

    // Server actions.
    $('bkSave').addEventListener('click', saveBook);
    $('bkDelete').addEventListener('click', deleteBook);
    $('bkGive').addEventListener('click', giveBook);
    $('bkRefreshPlayers').addEventListener('click', refreshBookPlayers);
    debug('HANDLERS', 'Save/Delete/Give registered');

    const booksTab = document.querySelector('.mtab[data-tab="books"]');
    if (booksTab) booksTab.addEventListener('click', () => loadBooks());

    // Sidebar submenu: each action opens a focused, separate book view.
    const railSub = $('bkRailSub');
    const pane = $('bsBooksPane');
    const railButtons = railSub ? [...railSub.querySelectorAll('[data-bk-view]')] : [];
    const viewNames = {new:'NEUES BUCH', edit:'BUCH BEARBEITEN', list:'BÜCHERÜBERSICHT', give:'BUCH VERGEBEN', delete:'BUCH LÖSCHEN'};
    function setBookView(view) {
        if (!pane || !viewNames[view]) return;
        pane.dataset.bkView = view;
        railButtons.forEach(b => b.classList.toggle('is-active', b.dataset.bkView === view));
        const heading = pane.querySelector('.bk-heading h2');
        if (heading) heading.textContent = '📚 ' + viewNames[view];
        const sections = [...pane.querySelectorAll('[data-bk-section]')];
        sections.forEach(s => { s.open = true; });
        if (view === 'new') {
            book = newBook(); pageIndex = 0; renderBook();
            showStatus('Neues Buch: ID und Titel eingeben, Seiten schreiben und speichern.', false, false);
        }
        if (view === 'edit') showStatus('Buch aus der Liste wählen, bearbeiten und speichern.', false, false);
        if (view === 'give') {
            showStatus('Gespeichertes Buch und verbundenen Spieler auswählen.', false, false);
            refreshBookPlayers();
        }
        if (view === 'delete') showStatus('Gespeichertes Buch auswählen und Löschung im Menü bestätigen.', false, false);
    }
    if (booksTab && railSub) {
        booksTab.setAttribute('aria-expanded', 'false');
        booksTab.addEventListener('click', () => {
            const opening = railSub.hidden;
            railSub.hidden = !opening;
            booksTab.setAttribute('aria-expanded', String(opening));
            if (opening && !pane.dataset.bkView) setBookView('list');
        });
        railButtons.forEach(button => button.addEventListener('click', async () => {
            if (!booksTab.classList.contains('is-active')) booksTab.click();
            const view = button.dataset.bkView;
            if (view !== 'new') await loadBooks({silent:true});
            setBookView(view);
        }));
        setBookView('list');
    }

    book = newBook();
    renderBook();

    // FiveM NUI: custom clickable menus, while retaining original select IDs/events.
    function initBookSelects() {
        const pane = $('bsBooksPane');
        if (!pane) return;
        const selects = [...pane.querySelectorAll('select')].filter(s => !s.hidden && !s.hasAttribute('multiple') && Number(s.getAttribute('size') || 1) <= 1);
        let active = null;
        const close = () => {
            if (!active) return;
            active.list.hidden = true;
            active.button.setAttribute('aria-expanded', 'false');
            active = null;
        };
        for (const select of selects) {
            const wrap = document.createElement('div');
            wrap.className = 'bk-nui-select';
            select.parentNode.insertBefore(wrap, select);
            wrap.appendChild(select);
            select.classList.add('bk-nui-select__native');
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'bk-nui-select__button';
            button.setAttribute('aria-haspopup', 'listbox');
            button.setAttribute('aria-expanded', 'false');
            const list = document.createElement('div');
            list.className = 'bk-nui-select__options';
            list.setAttribute('role', 'listbox');
            list.hidden = true;
            wrap.append(button, list);
            const sync = () => {
                const option = select.selectedOptions[0];
                button.textContent = (option ? option.textContent : 'Bitte auswählen') + '  ▾';
                button.disabled = select.disabled;
            };
            const populate = () => {
                list.replaceChildren();
                for (const option of select.options) {
                    const item = document.createElement('button');
                    item.type = 'button';
                    item.className = 'bk-nui-select__option';
                    item.setAttribute('role', 'option');
                    item.setAttribute('aria-selected', String(option.selected));
                    item.textContent = option.textContent;
                    item.disabled = option.disabled;
                    item.addEventListener('click', event => {
                        event.stopPropagation();
                        select.value = option.value;
                        select.dispatchEvent(new Event('change', { bubbles: true }));
                        select.dispatchEvent(new Event('input', { bubbles: true }));
                        sync();
                        close();
                    });
                    list.appendChild(item);
                }
            };
            button.addEventListener('click', event => {
                event.stopPropagation();
                if (active && active.button === button) { close(); return; }
                close();
                populate();
                sync();
                list.hidden = false;
                button.setAttribute('aria-expanded', 'true');
                active = { button, list };
            });
            select.addEventListener('change', sync);
            new MutationObserver(sync).observe(select, { childList: true, subtree: true, attributes: true, attributeFilter: ['selected', 'disabled'] });
            // Existing editor code changes select.value programmatically on render.
            // Refresh the displayed label when the editor is revisited.
            wrap.addEventListener('mouseenter', sync);
            wrap.addEventListener('focusin', sync);
            sync();
        }
        document.addEventListener('click', event => {
            if (active && !active.button.parentNode.contains(event.target)) close();
        });
        document.addEventListener('keydown', event => { if (event.key === 'Escape') close(); });
        pane.addEventListener('scroll', close, true);
    }
    initBookSelects();
})();

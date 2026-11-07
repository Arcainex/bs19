/* ALPHA-Z V17 – Performanceoptimierte 3D-Modellvorschau.
 * Die Kenney-Modelle wurden offline mit echter Modellgeometrie und Holztextur
 * aus 20 Ansichten pro Bauteil als animierte WebP-Vorschauen vorgerendert.
 * Keine WebGL-Session, keine Echtzeit-3D-Rechenlast, kein dauerhaft laufender JS-Timer.
 * Nur das unter dem Mauszeiger ausgewählte Modell wird bei Bedarf geladen.
 */
(() => {
    'use strict';
    const img = document.getElementById('wheelPreviewImage');
    const title = document.getElementById('wheelPreviewTitle');
    const dims = document.getElementById('wheelPreviewDims');
    const state = document.getElementById('wheelPreviewState');
    if (!img || !title || !dims || !state) return;
    let visible = false;
    let current = '';
    let currentPiece = null;
    let generation = 0;
    let hoverDelay = 0;
    const namePattern = /^bs_k_[a-z0-9_]+$/;
    const stop = () => {
        if (hoverDelay) {clearTimeout(hoverDelay);hoverDelay=0;}
        img.onload = null;
        img.onerror = null;
        img.hidden = true;
        img.removeAttribute('src'); // beendet animierte Dekodierung beim Schliessen
    };
    function select(piece) {
        if (!visible) return;
        const id = piece && typeof piece.id==='string' ? piece.id : '';
        if (id===current) return;
        current = id;
        currentPiece=piece || null;
        generation++;
        stop();
        title.textContent = piece && piece.label || '3D-Vorschau';
        const size=piece && piece.size;
        dims.textContent=Array.isArray(size) && size.length>=3 ? size.slice(0,3).map(n=>Number(n).toFixed(2).replace('.',',')).join(' × ')+' m' : '';
        state.classList.remove('is-error');
        if (!namePattern.test(id)) {
            state.textContent='Bauteil auswählen, um es anzusehen';
            return;
        }
        state.textContent='Vorschau wird geladen …';
        const ticket=generation;
        // Winzige Entprellung verhindert 79 nutzlose Bild-Ladevorgänge bei
        // schnellen Mausbewegungen über der Bauteilliste.
        hoverDelay=setTimeout(()=>{
            hoverDelay=0;
            if (!visible || ticket!==generation || document.hidden) return;
            img.onload=()=>{
                if (!visible || ticket!==generation) return;
                img.hidden=false;
                state.textContent='Langsam rotierende Modellansicht';
            };
            img.onerror=()=>{
                if (!visible || ticket!==generation) return;
                img.hidden=true;
                state.textContent='Vorschau für dieses Modell nicht verfügbar';
                state.classList.add('is-error');
            };
            img.src=`previews/${id}.webp`;
        },90);
    }
    function open() {
        visible=true;current='';currentPiece=null;generation++;
        stop();
        title.textContent='3D-Vorschau';dims.textContent='';
        state.classList.remove('is-error');
        state.textContent='Bauteil auswählen, um es anzusehen';
    }
    function close() {
        visible=false;current='';currentPiece=null;generation++;
        stop();
    }
    document.addEventListener('visibilitychange',()=>{
        if (!visible) return;
        if(document.hidden) {
            stop();
        } else if(namePattern.test(current)) {
            // Nach Alt-Tab nur die zuvor ausgewählte Animation wieder laden.
            const next=currentPiece;
            current='';
            select(next);
        }
    });
    window.AZPreview={select,open,close};
})();

// Part icons for the O menu and the workbench.
// Order: bs_ui icon registry -> img/items/<item>.png -> img/custom_attachments/<item>.png (and _03) -> mount glyph.
(() => {
'use strict';
const BASE='nui://bs_ui/html/img/';
const G={
 muzzle:'<rect x="6" y="18" width="30" height="12" rx="2"/><path d="M36 21h6v6h-6M12 18v12M18 18v12M24 18v12"/>',
 optic:'<rect x="8" y="16" width="32" height="10" rx="5"/><circle cx="12" cy="21" r="3"/><circle cx="36" cy="21" r="3"/><path d="M18 26v6h12v-6M14 32h20"/>',
 grip:'<path d="M8 14h32v6H8z"/><path d="M20 20l-2 18a3 3 0 0 0 3 3h4a3 3 0 0 0 3-3l2-18"/><path d="M21 27h7M21 33h6"/>',
 light:'<rect x="6" y="18" width="20" height="12" rx="2"/><path d="M26 16l6 4v8l-6 4z"/><path d="M36 18l7-4M37 24h7M36 30l7 4"/>',
 laser:'<rect x="6" y="17" width="20" height="14" rx="2"/><circle cx="21" cy="24" r="2.5"/><path d="M28 24h3M34 24h3M40 24h3"/>',
 mag:'<path d="M17 8h13l-2 16c-1 8 1 13 4 16H18c-3-4-4-9-3-16z"/><path d="M18 14h11M17 20h11"/>',
 stock:'<path d="M6 18h18l16-4v16l-6 4h-6l-4-8H6z"/><path d="M14 22h6"/>',
 rail:'<path d="M6 20h36v8H6z"/><path d="M10 20v-4M16 20v-4M22 20v-4M28 20v-4M34 20v-4M40 20v-4"/>',
 bipod:'<path d="M8 12h32v6H8z"/><path d="M20 18l-8 22M28 18l8 22M10 40h4M34 40h4"/>',
 piece:'<path d="M28 8a8 8 0 0 0-8 10L8 30l6 6 12-12a8 8 0 0 0 10-8l-5 3-4-4z"/>',
 sticker:'<path d="M10 8h28v20L28 40H10z"/><path d="M38 28H28v12"/><path d="M17 18h14M17 24h8"/>',
};
function kind(slot,item){
 const s=String(slot||''),i=String(item||'').toLowerCase();
 if(s==='scope'||/optic|sight|scope|holo|reflex|prism/.test(i))return'optic';
 if(s==='muzzle'||/supp|brake|hider|compensator|muzzle/.test(i))return'muzzle';
 if(s==='grip'||/grip|handstop/.test(i))return'grip';
 if(s==='light'||/light|flash/.test(i))return'light';
 if(s==='laser'||/laser/.test(i))return'laser';
 if(s==='mag'||/mag|clip/.test(i))return'mag';
 if(/stock|brace/.test(i))return'stock';
 if(/rail|handguard|shroud/.test(i))return'rail';
 if(/bipod/.test(i))return'bipod';
 if(s==='sticker')return'sticker';
 return'piece';
}
const glyph=k=>`<svg class="bs-part-glyph" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${G[k]||G.piece}</svg>`;
const safe=v=>String(v||'').replace(/[^a-z0-9_]/gi,'');
function html(item,slot){
 const k=kind(slot,item),id=safe(item);
 if(id&&window.BSIcons&&BSIcons.has&&BSIcons.has(id))return BSIcons.get(id,'attachment');
 if(!id)return glyph(k);
 const list=[`items/${id}.png`,`custom_attachments/${id}.png`,`custom_attachments/${id}_03.png`].map(p=>BASE+p);
 return `<img class="bs-part-img" alt="" draggable="false" src="${list[0]}" data-next="${list.slice(1).join('|')}" data-kind="${k}" onerror="BSPartIcon.next(this)">`;
}
function next(img){
 const rest=(img.dataset.next||'').split('|').filter(Boolean);
 if(rest.length){img.dataset.next=rest.slice(1).join('|');img.src=rest[0];return}
 const span=document.createElement('span');span.className='bs-part-fallback';span.innerHTML=glyph(img.dataset.kind);img.replaceWith(span);
}
window.BSPartIcon={html,next,kind,glyph};
})();

(()=>{
'use strict';
// Weapon workbench (cosmetics). The Lua side owns the scene, validation and the save; this page is the draft.
const $=id=>document.getElementById(id),clone=v=>JSON.parse(JSON.stringify(v)),clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const axes=['x','y','z'],colours={x:'#e87265',y:'#83bc7a',z:'#79a9e7',uniform:'#eee5d1'};
// Approximate swatch colours of the factory tint palettes, used for the swatches and to pick the nearest finish.
const PALETTE8=[['Factory','#1E1E1C'],['Green','#3F5B2A'],['Gold','#C9A33A'],['Pink','#D9759F'],['Army','#6B6A45'],['Police','#2D3F63'],['Orange','#D0702A'],['Platinum','#C7C9C8']];
const PALETTE32=[['Classic black','#1E1E1C'],['Classic grey','#6A6A68'],['Two-tone','#3C3C3A'],['Classic white','#D8D6D0'],['Classic beige','#B8A27A'],['Classic green','#4E5B33'],['Classic blue','#34465E'],['Classic earth','#6E5B3E'],['Brown & black','#4A3828'],['Red contrast','#9A2B22'],['Blue contrast','#2A4C8C'],['Yellow contrast','#C8A82A'],['Orange contrast','#C7642A'],['Bold pink','#D45B95'],['Purple & yellow','#6A3D8C'],['Bold orange','#E07A1F'],['Green & purple','#4D8A3A'],['Red features','#B5302A'],['Green features','#3E9A45'],['Cyan features','#2AA5B5'],['Yellow features','#D8C232'],['Red & white','#C8504A'],['Blue & white','#5A7AC0'],['Metallic gold','#C9A33A'],['Metallic platinum','#C7C9C8'],['Grey & lilac','#8A84A0'],['Purple & lime','#7A4A9A'],['Metallic red','#A0242A'],['Metallic green','#2E7A3E'],['Metallic blue','#2A4FA0'],['White & aqua','#7FC8C8'],['Red & yellow','#C8642A']];
let state=null,mounts=[],stickers=[],selected=null,tool='appearance',mode='move',busy=false,session=0,saved=null,savedSig='',deferredShow=null,stickerDesign=null,category='';
let gizmoBusy=false,drag=null,dragBusy=false,dragPending=null,dragFrame=null,previewBusy=false,previewPending={},previewTimer,keySeq=0;
document.documentElement.style.visibility='hidden';

async function post(route,body={}){try{const r=await fetch(`https://${GetParentResourceName()}/${route}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});return await r.json()}catch(_){return{ok:false,error:'No response from the workbench.'}}}
const status=(text,kind='')=>{const s=$('status');s.textContent=text||'';s.className=kind?'is-'+kind:''};
const newKey=()=>'p'+Date.now().toString(36)+(keySeq++).toString(36);
const stickerPayload=()=>stickers.map(({_k,...rest})=>rest);
const mountBody=()=>({serial:state.profile.serial,mounts:clone(mounts)});
const stickerBody=()=>({serial:state.profile.serial,entries:stickerPayload()});
const signature=()=>JSON.stringify([state.profile.name||'',Number(state.profile.tint),mounts,stickerPayload(),paintPayload()]);
const isDirty=()=>!!state&&signature()!==savedSig;
function refreshDirty(){const d=isDirty();const tag=$('dirty');tag.textContent=d?'Draft · unsaved':'Applied';tag.className='k-stamp '+(d?'is-draft':'is-dim');$('apply').disabled=!d||busy;$('revert').disabled=!d||busy;$('inspector').classList.toggle('is-dirty',d);renderLayers();}
function changed(){refreshDirty();historyNote()}

/* ---------- undo / redo: every draft change is snapshotted; quick edits and drags merge into one step ---------- */
let history={undo:[],redo:[],base:null,timer:null,applying:false};
const snap=()=>JSON.stringify({name:state.profile.name||'',tint:Number(state.profile.tint),mounts,stickers,paint});
function historyReset(){clearTimeout(history.timer);history={undo:[],redo:[],base:state?snap():null,timer:null,applying:false}}
function historyNote(){if(history.applying||!state)return;clearTimeout(history.timer);history.timer=setTimeout(historyCommit,350)}
function historyCommit(){clearTimeout(history.timer);history.timer=null;if(!state||history.base==null)return;if(drag){history.timer=setTimeout(historyCommit,200);return}
 const now=snap();if(now===history.base)return;history.undo.push(history.base);if(history.undo.length>100)history.undo.shift();history.redo=[];history.base=now}
function historyApply(text){const d=JSON.parse(text);history.applying=true;
 try{state.profile.name=d.name;state.profile.tint=d.tint;mounts=d.mounts;stickers=d.stickers;paint=d.paint||null;if(state.paint?.enabled)preview('paintPreview',{serial:state.profile.serial,paint:paintPayload()});renderPaint();$('name').value=d.name||'';setTitle(d.name||state.weapon);
  preview('previewFinish',{tint:d.tint});if(state.cosmetics?.enabled||mounts.length||saved?.mounts?.length)preview('cosmeticPreview',mountBody());if(state.stickers?.enabled||stickers.length||saved?.stickers?.length)preview('stickerPreview',stickerBody());
  if(selected&&!entry())selected=null;$('gizmo').replaceChildren();renderLibrary();renderEditor();syncFinishWheel();refreshDirty()}
 finally{history.applying=false}}
function undo(){historyCommit();if(!history.undo.length)return status('Nothing to undo.');history.redo.push(history.base);history.base=history.undo.pop();historyApply(history.base);status(`Undone. ${history.undo.length} more step${history.undo.length===1?'':'s'} back.`)}
function redo(){historyCommit();if(!history.redo.length)return status('Nothing to redo.');history.undo.push(history.base);history.base=history.redo.pop();historyApply(history.base);status('Redone.')}

function preview(route,body){previewPending[route]=body;if(!previewTimer&&!previewBusy)previewTimer=setTimeout(flushPreview,30)}
async function flushPreview(){clearTimeout(previewTimer);previewTimer=null;if(previewBusy)return;previewBusy=true;const version=session;try{while(Object.keys(previewPending).length&&version===session){const route=Object.keys(previewPending)[0],body=previewPending[route];delete previewPending[route];const result=await post(route,body);if(!result.ok&&version===session)status(result.error||'Preview unavailable.','bad')}}finally{previewBusy=false;if(Object.keys(previewPending).length)previewTimer=setTimeout(flushPreview,30)}}
function previewMounts(){changed();preview('cosmeticPreview',mountBody())}
function previewStickers(){changed();preview('stickerPreview',stickerBody())}

function entry(){return selected?.type==='mount'?mounts.find(m=>m.key===selected.key):selected?.type==='sticker'?stickers.find(s=>s._k===selected.key):null}
const partOption=m=>state.cosmetics?.options?.find(p=>p.id===m.id);
const partName=m=>partOption(m)?.label||m.id;
const designOf=s=>state.stickers?.designs?.find(d=>d.id===s.design);
const designName=s=>designOf(s)?.label||'Sticker';
const maxMounts=()=>Number(state.cosmetics?.maxMounts||state.cosmetics?.maxCount||10);
const maxStickers=()=>Number(state.stickers?.maxCount||5);
function designArt(design){return (design.art||design.emblem)&&window.BSStickerArt?BSStickerArt.uri(design):(design.image||`stickers/${design.id}.png`).replace(/^html\//,'')}
function partArt(part){if(part.icon||part.image)return`<img src="${part.icon||part.image}" alt="">`;return window.BSPartIcon?BSPartIcon.html(part.item||part.id,part.slot||'piece'):''}
function el(tag,cls,html){const n=document.createElement(tag);if(cls)n.className=cls;if(html!=null)n.innerHTML=html;return n}
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function setTitle(text){const t=$('weapon');t.textContent=text||'';window.BSFitTitle&&BSFitTitle(t,38,20)}
function select(value){selected=value;if(value?.type==='sticker')mode='move';renderLayers();renderEditor();$('gizmo').replaceChildren()}
function setTool(value){tool=value;document.querySelectorAll('[data-tool]').forEach(b=>b.classList.toggle('active',b.dataset.tool===value));document.querySelectorAll('[data-pane]').forEach(p=>p.hidden=p.dataset.pane!==value)}

/* ---------- finish ---------- */
function palette(){const count=(state.tintOptions||PALETTE8).length;const base=count>8?PALETTE32:PALETTE8;return (state.tintOptions||PALETTE8.map((_,id)=>({id}))).map(({id})=>({id,label:(base[id]||['Finish '+String(id+1).padStart(2,'0'),'#555555'])[0],hex:(base[id]||[0,'#555555'])[1]}))}
function setFinish(index,fromWheel=false){state.profile.tint=index;preview('previewFinish',{tint:index});const p=palette().find(f=>f.id===index);if(!fromWheel&&p)finishWheel.set(p.hex);finishWheel.note(p?p.label:'');changed();renderFinishes()}
function renderFinishes(){const box=$('finishLibrary');box.replaceChildren();for(const f of palette()){const b=el('button','wb-swatch'+(Number(state.profile.tint)===f.id?' is-on':''),`<i style="background:${f.hex}"></i><span>${esc(f.label)}</span>`);b.onclick=()=>setFinish(f.id);box.append(b)}}
const finishWheel=BSColourWheel.create($('finishWheel'),{size:184,note:true,onInput:hex=>{if(!state)return;if(paintActive()){paintWheel(hex);return}let best=null,bd=Infinity;for(const f of palette()){const d=BSColourWheel.distance(hex,f.hex);if(d<bd){bd=d;best=f}}if(best&&best.id!==Number(state.profile.tint))setFinish(best.id,true);else if(best)finishWheel.note(best.label)}});

/* ---------- custom paint (experimental): RGB colour per texture part, pattern, wear and hand painting ---------- */
let paint=null,activePart=null,paintTarget='base',brushMode='paint',brushColour='#E5DDC5',stroke=null,paintSendAt=0;
const paintParts=()=>state?.paint?.enabled?state.paint.parts||[]:[];
const paintActive=()=>!!(paint&&paintParts().length);
const part=()=>paint&&activePart?paint.parts[activePart]:null;
// Lua turns empty lists into {}: rebuild the exact draft shape so nothing is lost or re-defaulted.
function normalPaint(raw){if(!raw||typeof raw!=='object'||!raw.parts)return null;const out={v:1,parts:{}};for(const[id,p]of Object.entries(raw.parts)){if(!p||!p.base)continue;out.parts[id]={base:p.base,pattern:p.pattern||'solid',colour2:p.colour2||'#1E1E1C',wear:Number(p.wear??.35),strokes:(Array.isArray(p.strokes)?p.strokes:Object.values(p.strokes||{})).map(s=>({c:s.c,s:s.s,p:Array.isArray(s.p)?s.p:Object.values(s.p||{}),...(s.e?{e:true}:{})}))}}return Object.keys(out.parts).length?out:null}
const paintPayload=()=>paint&&Object.keys(paint.parts).length?clone(paint):null;
function ensurePart(id){if(!paint.parts[id]){const from=part();paint.parts[id]=from?{...clone(from),strokes:[]}:{base:finishWheel.get(),pattern:'solid',colour2:'#1E1E1C',wear:.35,strokes:[]}}activePart=id}
function paintChanged(){changed();preview('paintPreview',{serial:state.profile.serial,paint:paintPayload()});renderPaint()}
function drawPaintCanvas(extra){const c=$('paintCanvas'),ctx=c.getContext&&c.getContext('2d');if(!ctx||!window.BSPaintRender)return;const p=part();
 const view=p?{...p,strokes:extra?[...p.strokes,extra]:p.strokes}:null;BSPaintRender.draw(ctx,c.width,view,(state?.weapon||'')+':'+activePart)}
function renderPaint(){
 const box=$('paintBox');if(!state?.paint?.enabled){box.hidden=true;return}box.hidden=false;
 const parts=paintParts();
 $('paintHint').textContent=parts.length?'Swaps the weapon texture for your paint. Everyone near you sees it, unless someone close by holds the same model with a different look.':'This weapon model has no paintable texture mapped yet. An admin can run /weaponpaintprobe while holding it.';
 $('paintOn').disabled=!parts.length;$('paintOn').checked=!!paint;$('paintControls').hidden=!paintActive();
 if(!paintActive())return;
 if(!activePart||!parts.some(p=>p.id===activePart))activePart=Object.keys(paint.parts)[0]||parts[0].id;
 const chips=$('paintParts');chips.replaceChildren();
 for(const p of parts){const b=el('button',(paint.parts[p.id]?'is-painted':'')+(p.id===activePart?' active':''),esc(p.label));b.title=paint.parts[p.id]?'Painted':'Factory: click to paint';b.onclick=()=>{ensurePart(p.id);paintChanged()};chips.append(b)}
 if(part()){const u=el('button','',"Leave factory");u.title='This part goes back to the factory look';u.onclick=()=>{delete paint.parts[activePart];activePart=Object.keys(paint.parts)[0]||null;paintChanged()};chips.append(u)}
 const p=part();
 $('paintTarget').querySelectorAll('button').forEach(b=>b.classList.toggle('active',b.dataset.target===paintTarget));
 $('paintPattern').querySelectorAll('button').forEach(b=>{b.classList.toggle('active',p?.pattern===b.dataset.pattern);b.disabled=!p});
 $('paintBaseSw').style.background=p?.base||'transparent';$('paintSecondSw').style.background=p?.colour2||'transparent';$('paintBrushSw').style.background=brushColour;
 $('paintWear').value=Math.round((p?.wear??.35)*100);$('paintWear').disabled=!p;
 $('paintStrokes').textContent=p?`${p.strokes.length}/${state.paint.maxStrokes||40} strokes`:'Pick a part';
 document.querySelectorAll('[data-brush]').forEach(b=>b.classList.toggle('active',b.dataset.brush===brushMode));
 drawPaintCanvas();
}
function paintWheel(hex){
 if(paintTarget==='brush'){brushColour=hex;$('paintBrushSw').style.background=hex;return}
 const p=part();if(!p)return;if(paintTarget==='second')p.colour2=hex;else p.base=hex;
 changed();const now=Date.now();if(now-paintSendAt>90){paintSendAt=now;preview('paintPreview',{serial:state.profile.serial,paint:paintPayload()})}
 $('paintBaseSw').style.background=p.base;$('paintSecondSw').style.background=p.colour2;drawPaintCanvas();
}
$('paintOn').onchange=()=>{if($('paintOn').checked){paint={v:1,parts:{}};ensurePart(paintParts()[0].id)}else paint=null;paintChanged()};
$('paintTarget').onclick=e=>{const b=e.target.closest('[data-target]');if(!b)return;paintTarget=b.dataset.target;const p=part();finishWheel.set(paintTarget==='brush'?brushColour:paintTarget==='second'?p?.colour2||'#1E1E1C':p?.base||'#FFFFFF');renderPaint()};
$('paintPattern').onclick=e=>{const b=e.target.closest('[data-pattern]');const p=part();if(!b||!p)return;p.pattern=b.dataset.pattern;paintChanged()};
$('paintWear').oninput=()=>{const p=part();if(!p)return;p.wear=clamp(Number($('paintWear').value)/100,0,1);paintChanged()};
document.querySelectorAll('[data-brush]').forEach(b=>b.onclick=()=>{brushMode=b.dataset.brush;renderPaint()});
$('paintClear').onclick=()=>{const p=part();if(!p||!p.strokes.length)return;p.strokes=[];paintChanged()};
const canvas=$('paintCanvas');
const uv=e=>{const r=canvas.getBoundingClientRect();return[Math.round(clamp((e.clientX-r.left)/r.width,0,1)*1000),Math.round(clamp((e.clientY-r.top)/r.height,0,1)*1000)]};
canvas.addEventListener('pointerdown',e=>{const p=part();if(e.button!==0||!p)return;if(p.strokes.length>=(state.paint.maxStrokes||40))return status('This part has the maximum number of strokes. Clear or undo some first.','bad');
 stroke={c:brushColour,s:Number($('paintSize').value),p:uv(e)};if(brushMode==='erase')stroke.e=true;canvas.setPointerCapture(e.pointerId);drawPaintCanvas(stroke)});
canvas.addEventListener('pointermove',e=>{if(!stroke)return;const[x,y]=uv(e),p=stroke.p,lx=p[p.length-2],ly=p[p.length-1];if(Math.hypot(x-lx,y-ly)<6)return;
 if(p.length>=238){const pp=part();pp.strokes.push(stroke);stroke={c:stroke.c,s:stroke.s,p:[lx,ly],e:stroke.e};if(pp.strokes.length>=(state.paint.maxStrokes||40)){stroke=null;paintChanged();return}}
 stroke.p.push(x,y);drawPaintCanvas(stroke);const now=Date.now();if(now-paintSendAt>120){paintSendAt=now;const pl=paintPayload();if(pl){pl.parts[activePart].strokes.push(clone(stroke));preview('paintPreview',{serial:state.profile.serial,paint:pl})}}});
const endStroke=()=>{if(!stroke)return;const p=part();if(p)p.strokes.push(stroke);stroke=null;paintChanged()};
canvas.addEventListener('pointerup',endStroke);canvas.addEventListener('pointercancel',endStroke);

/* ---------- libraries ---------- */
function renderLibrary(){
 renderFinishes();
 const cosmetics=state.cosmetics,box=$('equipmentLibrary');box.replaceChildren();
 $('cosmeticAvailability').textContent=cosmetics?.enabled?(cosmetics.removeOnly?'Pieces are switched off on this server. You can still take saved ones off.':`Visual only, weapon performance stays the same. Up to ${maxMounts()} pieces.`):'Cosmetic pieces are switched off or not set up for this weapon.';
 for(const part of cosmetics?.enabled?cosmetics.options||[]:[]){
  const used=mounts.filter(m=>m.id===part.id).length,original=(saved?.mounts||[]).filter(m=>m.id===part.id).length,available=Math.max(0,Number(part.count||0)+original-used);
  const b=el('button','wb-tile',`<span class="wb-tile__art">${partArt(part)}</span><strong>${esc(part.label)}</strong><small>${part.available===false?'Model missing':available?`×${available} in bag`:'None in bag'}</small>`);
  b.disabled=part.available===false||available<1||mounts.length>=maxMounts()||!!cosmetics.removeOnly;b.onclick=()=>addMount(part);box.append(b)}
 const config=state.stickers,lib=$('stickerLibrary');lib.replaceChildren();
 $('stickerAvailability').textContent=config?.enabled?(config.removeOnly?'Stickers are switched off on this server. Saved ones can be cleared.':`Click a design or drag it onto the weapon. Up to ${maxStickers()} stickers.`):'Stickers are switched off or this weapon has no supported surfaces.';
 const query=$('stickerSearch').value.toLowerCase();
 for(const design of config?.enabled?config.designs||[]:[]){
  if(query&&!design.label.toLowerCase().includes(query))continue;if(category&&(design.category||'Marks')!==category)continue;
  const b=el('button','wb-tile is-sticker',`<span class="wb-tile__art"><img src="${designArt(design)}" alt="" onerror="this.remove()"></span><strong>${esc(design.label)}</strong>`);
  b.disabled=!!config.removeOnly||stickers.length>=maxStickers();b.draggable=!b.disabled;b.onclick=()=>addSticker(design.id);
  b.ondragstart=e=>{stickerDesign=design.id;e.dataTransfer.setData('text/plain',design.id);$('dropHint').hidden=false};b.ondragend=()=>{$('dropHint').hidden=true};lib.append(b)}
}
function addMount(part){if(mounts.length>=maxMounts())return status(`This weapon already carries ${maxMounts()} pieces.`,'bad');const key=newKey();mounts.push({key,id:part.id,position:clone(part.position||{x:0,y:0,z:0}),rotation:clone(part.rotation||{x:0,y:0,z:0}),scale:Number(part.scale||1)});select({type:'mount',key});previewMounts();renderLibrary();status(`${part.label} added to the draft. Drag the handles to place it.`)}
function addSticker(design,focus=true){const cfg=state.stickers;if(!cfg?.enabled||cfg.removeOnly)return;if(stickers.length>=maxStickers())return status(`No room for more than ${maxStickers()} stickers.`,'bad');const surface=(cfg.surfaces||[]).find(s=>s.id==='receiver_left')||cfg.surfaces?.[0];if(!surface)return status('This weapon has no supported sticker surfaces.','bad');const key=newKey();stickers.push({_k:key,design,surface:surface.id,u:0,v:0,size:.03,rotation:0,colour:'#FFFFFF',opacity:1});select({type:'sticker',key});previewStickers();renderLibrary();if(focus)post('stickerFocus',{serial:state.profile.serial,surface:surface.id});return key}

/* ---------- pieces on the weapon ---------- */
function pieceState(kind,item){const list=kind==='mount'?saved?.mounts:saved?.stickers,key=kind==='mount'?item.key:item._k,old=(list||[]).find(x=>(kind==='mount'?x.key:x._k)===key);if(!old)return['New','is-new'];return JSON.stringify(old)===JSON.stringify(item)?['Saved','is-saved']:['Edited','is-edit']}
function removePiece(kind,key){
 const item=kind==='mount'?mounts.find(m=>m.key===key):stickers.find(s=>s._k===key);if(!item)return;
 const [label]=pieceState(kind,item),name=kind==='mount'?partName(item):designName(item);
 if(kind==='mount'){mounts=mounts.filter(m=>m.key!==key);previewMounts()}else{stickers=stickers.filter(s=>s._k!==key);previewStickers()}
 if(selected?.key===key)select(null);renderLibrary();renderLayers();
 status(label==='New'?`${name} taken out of the draft.`:kind==='mount'?`${name} comes off and goes back to your bag when you apply.`:`${name} is cleared when you apply.`);
}
function renderLayers(){
 if(!state)return;const box=$('layers');box.replaceChildren();
 $('pieceCount').textContent=`PIECES ${mounts.length}/${maxMounts()} · STICKERS ${stickers.length}/${maxStickers()}`;
 const removed=(saved?.mounts||[]).filter(o=>!mounts.some(m=>m.key===o.key)).length+(saved?.stickers||[]).filter(o=>!stickers.some(s=>s._k===o._k)).length;
 if(!mounts.length&&!stickers.length)box.append(el('p','wb-hint','Nothing on this weapon yet. Add pieces or stickers from the left.'));
 const row=(kind,item,name,art)=>{const key=kind==='mount'?item.key:item._k,[label,cls]=pieceState(kind,item);
  const r=el('div','wb-piece'+(selected?.key===key?' is-on':''),`<span class="wb-piece__art">${art}</span><button class="wb-piece__name">${esc(name)}<small class="${cls}">${label}</small></button><button class="wb-x" title="Take it off" aria-label="Remove ${esc(name)}">✕</button>`);
  r.querySelector('.wb-piece__name').onclick=()=>{setTool(kind==='mount'?'equipment':'stickers');select({type:kind,key})};
  r.querySelector('.wb-x').onclick=e=>{e.stopPropagation();removePiece(kind,key)};box.append(r)};
 mounts.forEach(m=>{const o=partOption(m);row('mount',m,partName(m),o?partArt(o):'')});
 stickers.forEach(s=>{const d=designOf(s);row('sticker',s,designName(s),d?`<img src="${designArt(d)}" alt="">${s.colour&&s.colour!=='#FFFFFF'?`<i class="wb-dot" style="background:${s.colour}"></i>`:''}`:'')});
 if(removed)box.append(el('p','wb-hint is-small is-warn',`${removed} saved piece${removed>1?'s':''} will come off on apply.`));
}

/* ---------- selected piece ---------- */
function numeric(label,value,onchange,step='.001'){const f=el('label','wb-num');f.append(document.createTextNode(label));const i=document.createElement('input');i.type='number';i.step=step;i.value=Number(value||0).toFixed(step==='1'?0:3);i.onchange=()=>{if(Number.isFinite(Number(i.value)))onchange(Number(i.value))};f.append(i);$('numeric').append(f)}
const stickerWheel=BSColourWheel.create($('stickerWheel'),{size:150,onInput:hex=>stickerColour(hex)});
function renderEditor(){
 const value=entry();$('pieceEditor').hidden=!value;$('numeric').replaceChildren();if(!value)return;
 $('selectionName').textContent=selected.type==='mount'?partName(value):designName(value);
 $('mountTools').hidden=selected.type!=='mount';$('stickerSurfaceRow').hidden=selected.type!=='sticker';
 document.querySelectorAll('[data-mode]').forEach(b=>b.classList.toggle('active',b.dataset.mode===mode));
 $('stickerQuickTools').replaceChildren();
 if(selected.type==='sticker'){
  stickerWheel.set(value.colour||'#FFFFFF');$('stickerOpacity').value=Math.round((value.opacity??1)*100);
  for(const[label,rotation,size]of[['⟲ 15°',-15,0],['⟳ 15°',15,0],['Smaller',0,-.003],['Larger',0,.003]]){const b=el('button','wb-btn is-small',label);b.onclick=()=>adjustSticker(rotation,size);$('stickerQuickTools').append(b)}
  const c=el('button','wb-btn is-small','Centre');c.onclick=()=>{value.u=value.v=0;previewStickers();renderEditor()};$('stickerQuickTools').append(c);
  const surfaces=$('stickerSurface');surfaces.replaceChildren();for(const s of state.stickers.surfaces||[]){const o=document.createElement('option');o.value=s.id;o.textContent=s.label;surfaces.append(o)}surfaces.value=value.surface;
  for(const key of['u','v','rotation','size'])numeric(key==='size'?'Size':key==='rotation'?'Turn':key.toUpperCase(),value[key],v=>{value[key]=v;constrainSticker(value);previewStickers()},key==='rotation'?'1':'.001');
 }else{
  for(const group of['position','rotation'])for(const axis of axes)numeric(`${group==='position'?'Move':'Turn'} ${axis.toUpperCase()}`,value[group][axis],v=>{value[group][axis]=v;previewMounts()},group==='rotation'?'1':'.001');
  const option=partOption(value);numeric('Scale',value.scale,v=>{value.scale=clamp(v,option?.scaleMin||state.cosmetics.minScale||.5,option?.scaleMax||state.cosmetics.maxScale||1.5);previewMounts()},'.01');
 }
}
function constrainSticker(value){const plane=state.stickers.surfaces.find(p=>p.id===value.surface);if(!plane)return;value.rotation=clamp(value.rotation,-180,180);const factor=Math.abs(Math.cos(value.rotation*Math.PI/180))+Math.abs(Math.sin(value.rotation*Math.PI/180));value.size=clamp(value.size,.015,Math.min(.06,2*Math.min(plane.halfWidth,plane.halfHeight)/Math.max(1,factor)));const extent=value.size*.5*factor;value.u=clamp(value.u,-Math.max(0,1-extent/plane.halfWidth),Math.max(0,1-extent/plane.halfWidth));value.v=clamp(value.v,-Math.max(0,1-extent/plane.halfHeight),Math.max(0,1-extent/plane.halfHeight))}
function adjustSticker(rotation=0,size=0){const value=entry();if(selected?.type!=='sticker'||!value)return;value.rotation=(value.rotation+rotation+540)%360-180;value.size+=size;constrainSticker(value);previewStickers();renderEditor()}
function stickerColour(hex){const v=entry();if(selected?.type!=='sticker'||!v||!/^#[0-9a-f]{6}$/i.test(hex))return;v.colour=hex.toUpperCase();previewStickers()}
$('stickerOpacity').oninput=()=>{const v=entry();if(selected?.type==='sticker'&&v){v.opacity=clamp(Number($('stickerOpacity').value)/100,.1,1);previewStickers()}};
$('stickerOriginal').onclick=()=>{const v=entry();if(selected?.type==='sticker'&&v){v.colour='#FFFFFF';v.opacity=1;previewStickers();renderEditor()}};
$('stickerFace').onclick=()=>{const v=entry();if(selected?.type==='sticker'&&v)post('stickerFocus',{serial:state.profile.serial,surface:v.surface})};
$('stickerSearch').oninput=renderLibrary;
$('stickerCategory').onclick=e=>{const b=e.target.closest('[data-cat]');if(!b)return;category=b.dataset.cat;$('stickerCategory').querySelectorAll('button').forEach(x=>x.classList.toggle('active',x===b));renderLibrary()};
$('stickerSurface').onchange=()=>{const v=entry();if(selected?.type==='sticker'&&v){v.surface=$('stickerSurface').value;constrainSticker(v);previewStickers();post('stickerFocus',{serial:state.profile.serial,surface:v.surface})}};

/* ---------- gizmo ---------- */
function drawGizmo(handles,center){
 const svg=$('gizmo');svg.replaceChildren();svg.setAttribute('viewBox',`0 0 ${innerWidth} ${innerHeight}`);svg.setAttribute('preserveAspectRatio','none');
 const make=(type,attrs)=>{const n=document.createElementNS(svg.namespaceURI,type);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,v);return n};
 for(const handle of handles||[]){
  const axis=String(handle.axis||'uniform').toLowerCase(),group=make('g',{'data-axis':axis});
  const colour=drag?.axis===axis?'#f4ce69':(colours[axis]||colours[axis[0]]||colours.uniform);
  group.style.color=colour;const x=handle.x*innerWidth,y=handle.y*innerHeight,points=handle.points||[];
  if(points.length>1){const geometry=points.map(p=>`${p.x*innerWidth},${p.y*innerHeight}`).join(' '),plane=handle.type==='plane';
   group.append(make(plane?'polygon':'polyline',{points:geometry,fill:plane?colour:'none','fill-opacity':plane?.18:1,stroke:colour,'stroke-width':plane?2:3}));
   group.append(make(plane?'polygon':'polyline',{points:geometry,fill:plane?'transparent':'none',stroke:'transparent','stroke-width':14,'pointer-events':'all'}));
  }else{
   if(center){const cx=center.x*innerWidth,cy=center.y*innerHeight;group.append(make('line',{x1:cx,y1:cy,x2:x,y2:y,stroke:colour,'stroke-width':3}));group.append(make('line',{x1:cx,y1:cy,x2:x,y2:y,stroke:'transparent','stroke-width':16,'pointer-events':'stroke'}));
    if(handle.type==='move'){const dx=x-cx,dy=y-cy,l=Math.hypot(dx,dy)||1,ux=dx/l,uy=dy/l;group.append(make('polygon',{points:`${x},${y} ${x-ux*12-uy*5},${y-uy*12+ux*5} ${x-ux*12+uy*5},${y-uy*12-ux*5}`,fill:colour}))}}
   group.append(make(handle.type==='scale'?'rect':'circle',handle.type==='scale'?{x:x-6,y:y-6,width:12,height:12,fill:colour,'pointer-events':'all'}:{cx:x,cy:y,r:handle.type==='move'?10:6,fill:handle.type==='move'?'transparent':colour,'pointer-events':'all'}));
  }
  const text=make('text',{x:x+10,y:y-10,fill:colour});text.textContent=axis.toUpperCase();group.append(text);svg.append(group);
 }
}
setInterval(async()=>{const value=entry();if(!state||$('inspector').hidden||!value||selected.type!=='mount'||gizmoBusy||dragBusy||drag||dragPending||dragFrame)return;gizmoBusy=true;const version=session,key=selected.key;try{const result=await post('gizmoState',{serial:state.profile.serial,mode,transform:clone(value)});if(version===session&&!drag&&!dragPending&&!dragBusy&&selected?.key===key)drawGizmo(result.handles||[],result.center)}finally{gizmoBusy=false}},50);

/* ---------- pointer on the weapon ---------- */
const orbit=$('orbitArea');orbit.addEventListener('contextmenu',e=>e.preventDefault());
orbit.addEventListener('pointerdown',e=>{if(busy||![0,2].includes(e.button))return;const axis=e.target.closest('[data-axis]')?.dataset.axis;const value=entry();
 drag={x:e.clientX,y:e.clientY,startX:e.clientX,startY:e.clientY,baseline:value?clone(value):null,fine:e.shiftKey,editMode:mode,right:e.button===2,axis,key:selected?.key,type:value?selected.type:null};
 if(!drag.right&&drag.type==='mount'&&!axis)drag.type=null;
 orbit.setPointerCapture(e.pointerId);orbit.classList.toggle('is-orbit',drag.right||!drag.type);
 if(!drag.right&&drag.type==='sticker'&&mode==='move')queueDrag({dx:0,dy:0,totalX:0,totalY:0,x:e.clientX/innerWidth,y:e.clientY/innerHeight,drag:{...drag}})});
orbit.addEventListener('pointermove',e=>{if(!drag)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;drag.x=e.clientX;drag.y=e.clientY;queueDrag({dx,dy,totalX:e.clientX-drag.startX,totalY:e.clientY-drag.startY,x:e.clientX/innerWidth,y:e.clientY/innerHeight,fine:drag.fine,snap:$('snap').checked,drag:{...drag}})});
function queueDrag(next){if(dragPending&&dragPending.drag.key===next.drag.key&&dragPending.drag.axis===next.drag.axis){dragPending.dx+=next.dx;dragPending.dy+=next.dy;dragPending.fine=next.fine;dragPending.x=next.x;dragPending.y=next.y;dragPending.totalX=next.totalX;dragPending.totalY=next.totalY}else dragPending=next;if(!dragBusy&&!dragFrame)dragFrame=requestAnimationFrame(()=>{dragFrame=null;flushDrag()})}
async function flushDrag(){if(!dragPending)return;dragBusy=true;const next=dragPending;dragPending=null;const version=session;
 try{
  if(next.drag.right||!next.drag.type){const result=await post('previewCamera',{dx:next.dx,dy:next.dy,zoom:0,serial:state.profile.serial,mode,transform:selected?.type==='mount'?clone(entry()):undefined});if(result.gizmo&&version===session)drawGizmo(result.gizmo.handles,result.gizmo.center);return}
  if(next.drag.type==='mount'){const value=mounts.find(m=>m.key===next.drag.key);if(!value||!next.drag.axis)return;
   const result=await post('gizmoDrag',{serial:state.profile.serial,mode:next.drag.editMode,axis:next.drag.axis,mounts:clone(mounts),dx:next.totalX,dy:next.totalY,x:next.x,y:next.y,height:innerHeight,transform:clone(next.drag.baseline||value),snap:next.snap,fine:next.fine});
   if(version!==session)return;const t=result.transform||result;
   if(result.ok!==false&&t.position){Object.assign(value,{position:clone(t.position),rotation:clone(t.rotation||value.rotation),scale:Number(t.scale||value.scale)});if(result.previewed)changed();else previewMounts();if(result.gizmo&&selected?.key===next.drag.key)drawGizmo(result.gizmo.handles,result.gizmo.center);if(!drag)renderEditor()}
  }else{const index=stickers.findIndex(s=>s._k===next.drag.key),value=stickers[index];if(!value)return;
   if(next.drag.editMode==='move'){const result=await post('stickerPlace',{...stickerBody(),index:index+1,x:next.x,y:next.y});if(version===session&&result.ok&&result.entries){mergeStickers(result.entries);changed();if(!drag)renderEditor()}}
   else{const f=next.fine?.1:1;if(next.drag.editMode==='rotate')value.rotation+=next.dx*.5*f;else value.size+=next.dx*.0002*f;constrainSticker(value);previewStickers()}}
 }finally{dragBusy=false;if(dragPending&&!dragFrame)dragFrame=requestAnimationFrame(()=>{dragFrame=null;flushDrag()})}}
function mergeStickers(entries){entries.forEach((e,i)=>{const s=stickers[i];if(s){s.u=e.u;s.v=e.v;s.surface=e.surface}})}
for(const ev of['pointerup','pointercancel','lostpointercapture'])orbit.addEventListener(ev,()=>{if(drag){drag=null;orbit.classList.remove('is-orbit');renderEditor();renderLayers()}});
orbit.addEventListener('wheel',e=>{e.preventDefault();if(selected?.type==='sticker'&&(e.shiftKey||e.altKey)){adjustSticker(e.altKey?-Math.sign(e.deltaY)*5:0,e.shiftKey?-Math.sign(e.deltaY)*.002:0);return}post('previewCamera',{dx:0,dy:0,zoom:Math.sign(e.deltaY)})},{passive:false});
orbit.addEventListener('dragover',e=>{if(stickerDesign){e.preventDefault();$('dropHint').hidden=false}});
orbit.addEventListener('drop',e=>{e.preventDefault();const design=e.dataTransfer.getData('text/plain')||stickerDesign;stickerDesign=null;$('dropHint').hidden=true;
 if(design&&state.stickers.designs.some(d=>d.id===design)){const key=addSticker(design,false);if(!key)return;const index=stickers.findIndex(s=>s._k===key);
  post('stickerPlace',{...stickerBody(),index:index+1,x:e.clientX/innerWidth,y:e.clientY/innerHeight}).then(r=>{if(r.ok&&r.entries){mergeStickers(r.entries);changed();renderEditor()}else status(r.error||'Drop it onto a supported surface of the weapon.','bad')})}});

$('resetCamera').onclick=()=>post('previewCamera',{reset:true});
document.querySelectorAll('[data-tool]').forEach(b=>b.onclick=()=>setTool(b.dataset.tool));
document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;renderEditor();$('gizmo').replaceChildren()});
$('name').oninput=()=>{state.profile.name=$('name').value;setTitle($('name').value||state.weapon);changed()};

/* ---------- draft / apply ---------- */
function remember(){saved={profile:clone(state.profile),mounts:clone(mounts),stickers:clone(stickers),paint:paint?clone(paint):null};savedSig=signature()}
function syncFinishWheel(){const p=palette().find(f=>f.id===Number(state.profile.tint));if(p){finishWheel.set(p.hex);finishWheel.note(p.label)}}
function restore(){if(!saved)return;state.profile=clone(saved.profile);mounts=clone(saved.mounts);stickers=clone(saved.stickers);paint=saved.paint?clone(saved.paint):null;if(state.paint?.enabled)preview('paintPreview',{serial:state.profile.serial,paint:paintPayload()});renderPaint();$('name').value=state.profile.name||'';setTitle(state.profile.name||state.weapon);
 preview('previewFinish',{tint:state.profile.tint});if(state.cosmetics?.enabled||mounts.length)preview('cosmeticPreview',mountBody());if(state.stickers?.enabled||stickers.length)preview('stickerPreview',stickerBody());
 select(null);renderLibrary();syncFinishWheel();refreshDirty()}
$('revert').onclick=()=>{restore();status('Draft thrown away. Back to the applied look.')};
$('apply').onclick=async()=>{if(busy||!state||!isDirty())return;const version=session;busy=true;refreshDirty();status('Applying…','busy');
 try{while(previewBusy||dragBusy||dragPending)await new Promise(r=>setTimeout(r,20));clearTimeout(previewTimer);previewTimer=null;previewPending={};
  const paintChanged=!!state.paint?.enabled&&JSON.stringify(paintPayload())!==JSON.stringify(saved?.paint?normalPaint(saved.paint):null);
  const result=await post('applyWorkshop',{serial:state.profile.serial,name:state.profile.name,tint:Number(state.profile.tint),mounts:clone(mounts),entries:stickerPayload(),paintChanged,paint:paintPayload()});
  if(version!==session)return;if(!result.ok)throw new Error(result.error||'Could not apply changes.');
  remember();status('Applied. Pieces taken off are back in your bag.','ok');
 }catch(error){status(error.message,'bad')}finally{if(version===session){busy=false;refreshDirty();if(!isDirty()&&deferredShow){const u=deferredShow;deferredShow=null;receive(u)}}}};
function requestClose(){if(busy)return;if(isDirty()){$('confirmClose').hidden=false;return}post('close')}
$('close').onclick=requestClose;$('keepEditing').onclick=()=>{$('confirmClose').hidden=true};$('discard').onclick=()=>{restore();$('confirmClose').hidden=true;post('close')};
window.addEventListener('keydown',e=>{
 if(!state||$('inspector').hidden)return;const typing=e.target.closest&&e.target.closest('input,select,textarea');
 if(!typing&&(e.ctrlKey||e.metaKey)&&['KeyZ','KeyX','KeyY'].includes(e.code)){e.preventDefault();if(e.code==='KeyZ'&&!e.shiftKey)undo();else redo();return}
 if(!typing&&['KeyW','KeyE','KeyR'].includes(e.code)&&selected){e.preventDefault();mode={KeyW:'move',KeyE:'rotate',KeyR:'scale'}[e.code];renderEditor();$('gizmo').replaceChildren();return}
 if(!typing&&selected&&e.key==='Delete'){e.preventDefault();removePiece(selected.type,selected.key);return}
 if(!typing&&selected?.type==='sticker'&&['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();const v=entry(),step=e.shiftKey?.002:.02;if(e.key==='ArrowLeft')v.u-=step;if(e.key==='ArrowRight')v.u+=step;if(e.key==='ArrowUp')v.v+=step;if(e.key==='ArrowDown')v.v-=step;constrainSticker(v);previewStickers();renderEditor();return}
 if(e.key==='Escape'){if(!$('confirmClose').hidden)$('confirmClose').hidden=true;else if(selected&&!typing)select(null);else requestClose()}});

function receive(data){
 if(data.action==='close'){if(dragFrame)cancelAnimationFrame(dragFrame);dragFrame=null;session++;state=null;deferredShow=null;busy=false;previewPending={};dragPending=null;drag=null;clearTimeout(previewTimer);previewTimer=null;$('gizmo').replaceChildren();$('inspector').hidden=true;document.documentElement.style.visibility='hidden';return}
 if(data.action!=='show')return;if(busy){deferredShow=data;return}
 session++;state=clone(data);
 mounts=clone(data.cosmetics?.mounts||(data.cosmetics?.mount?[{...data.cosmetics.mount,key:'legacy'}]:[])).map((m,i)=>({...m,key:m.key||'mount-'+i,scale:Number(m.scale||1)}));
 stickers=clone(data.stickers?.entries||[]).map((s,i)=>({_k:'s'+i,colour:'#FFFFFF',opacity:1,...s}));
 paint=normalPaint(data.paint?.data);activePart=paint?Object.keys(paint.parts)[0]:null;stroke=null;
 selected=null;remember();
 setTitle(data.profile.name||data.weapon);$('serial').textContent='SERIAL '+data.profile.serial;$('name').value=data.profile.name||'';
 for(const key of['damage','magazine','ammo'])$(key).textContent=data[key]??'—';
 $('confirmClose').hidden=true;$('inspector').hidden=false;document.documentElement.style.visibility='visible';status('');
 setTool(tool||'appearance');renderLibrary();syncFinishWheel();renderEditor();renderPaint();renderBackdrops();refreshDirty();historyReset();
}
function renderBackdrops(){const sel=$('backdropSel'),b=state?.backdrops;if(!b?.list?.length){sel.parentElement.hidden=true;return}sel.parentElement.hidden=false;
 if(sel.options.length!==b.list.length){sel.replaceChildren();for(const o of b.list){const opt=document.createElement('option');opt.value=o.id;opt.textContent=o.label;sel.append(opt)}}sel.value=b.current||b.list[0].id}
$('backdropSel').onchange=async()=>{if(!state)return;const id=$('backdropSel').value;const r=await post('studioBackdrop',{id});if(r.ok&&state?.backdrops){state.backdrops.current=r.current||id;status('Backdrop changed.')}else status('That backdrop is not available.','bad');$('backdropSel').blur()};
window.addEventListener('message',({data})=>receive(data));
})();

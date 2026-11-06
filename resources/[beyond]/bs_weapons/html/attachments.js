(() => {
'use strict';
const $=id=>document.getElementById(id),root=$('attachments');
const state={open:false,data:null,slots:[],serial:null,busy:false,focus:null,preview:null,points:{}};
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const post=async(name,data={})=>{try{return await fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).then(r=>r.json());}catch(_){return{ok:false,error:'The weapon did not respond.'};}};
const slotOf=id=>state.slots.find(s=>s.id===id);
const partOf=(slotId,id)=>slotOf(slotId)?.options.find(p=>p.id===id);
const art=(item,slot)=>window.BSPartIcon?BSPartIcon.html(item,slot):'';
const pad=n=>String(n).padStart(2,'0');
const STATS=[['damage','Damage'],['accuracy','Accuracy'],['range','Range'],['speed','Fire rate']];

/* ---------- stats: the game's HUD numbers plus what the framework config really does ---------- */
function build(change){
 const d=state.data,base=d?.base;let stats=null;
 if(base){stats={...base};for(const s of state.slots){let comp=s.currentStats;if(change&&change.slot===s.id)comp=change.remove?null:partOf(s.id,change.id)?.stats;for(const k of Object.keys(stats))stats[k]+=Number(comp?.[k]||0);}}
 let noise=1,silent=false;
 for(const s of state.slots){let scale=s.currentNoise;if(change&&change.slot===s.id)scale=change.remove?null:partOf(s.id,change.id)?.noise;if(typeof scale==='number'){noise*=scale;if(d.noise.silent&&scale<=d.noise.silentAt)silent=true;}}
 const mag=d?.magazine||{};let rounds=mag.current??null;const magSlot=slotOf('mag');
 if(mag.base!=null){const fitted=!!magSlot?.current,ext=change&&change.slot==='mag'?!change.remove:fitted;rounds=ext&&mag.ext!=null?mag.ext:mag.base;}
 return{stats,noise:silent?0:noise,silent,rounds};
}
function delta(now,next,unit=''){const diff=Math.round((next-now)*10)/10;if(!diff)return'';return ` <i class="${diff>0?'up':'down'}">${diff>0?'+':''}${diff}${unit}</i>`;}
function bar(now,next,max=100){
 const a=Math.max(0,Math.min(100,now/max*100)),b=Math.max(0,Math.min(100,next/max*100));
 if(b>a)return`<i style="width:${a}%"></i><em class="up" style="left:${a}%;width:${b-a}%"></em>`;
 if(b<a)return`<i style="width:${b}%"></i><em class="down" style="left:${b}%;width:${a-b}%"></em>`;
 return`<i style="width:${a}%"></i>`;
}
function renderCard(){
 const change=state.preview,now=build(null),next=build(change),part=change&&!change.remove?partOf(change.slot,change.id):null,slot=change&&slotOf(change.slot);
 $('atCardTitle').textContent=part?part.label:change?.remove?'Remove '+(slot?.currentLabel||'part'):'Current build';
 $('atCardSub').textContent=part?(slot.current?`Replaces ${slot.currentLabel} on the ${slot.label.toLowerCase()} mount`:`On the ${slot.label.toLowerCase()} mount`):change?.remove?`${slot.label} goes back to factory`:'Hover a part to compare it with what is fitted.';
 let html='';
 if(now.stats)for(const[k,label]of STATS)html+=`<div class="at-stat"><span>${label}</span><div class="at-bar">${bar(now.stats[k],next.stats[k])}</div><b>${Math.round(next.stats[k])}${delta(now.stats[k],next.stats[k])}</b></div>`;
 const loud=v=>Math.round(v*100);
 html+=`<div class="at-stat"><span>Noise</span><div class="at-bar is-noise">${bar(loud(now.noise),loud(next.noise))}</div><b>${next.silent?'SILENT':loud(next.noise)+'%'}</b></div>`;
 $('atStats').innerHTML=html;
 const r0=now.rounds,r1=next.rounds;
 $('atFacts').innerHTML=`<div class="at-fact"><span>Magazine</span><b>${r1??'—'}${r0!=null&&r1!=null&&r1!==r0?` <i class="${r1>r0?'up':'down'}">${r1>r0?'+':''}${r1-r0}</i>`:''}</b></div><div class="at-fact"><span>Walkers</span><b>${next.silent?'Not drawn':next.noise<1?'Less drawn':'Drawn in'}</b></div>`;
 $('atBlurb').textContent=part?.blurb||'';
 $('atNote').hidden=!!now.stats;
}

/* ---------- left rail ---------- */
function partTile(slot,p){
 const owned=p.count>0,can=owned&&!p.installed&&!state.busy;
 const label=p.installed?'Fitted':owned?`<span class="at-count">×${p.count}</span> in bag`:'None carried';
 return`<button class="at-part${p.installed?' is-fitted':''}${owned?'':' is-none'}${can?' is-grab':''}" data-slot="${esc(slot.id)}" data-part="${esc(p.id)}" ${can?'':'aria-disabled="true"'} title="${esc(p.blurb||'')}"><span class="at-part__art">${art(p.item,slot.id)}</span><strong>${esc(p.label)}</strong><small>${label}</small></button>`;
}
function renderRail(){
 const list=state.slots.filter(s=>s.options.length||s.current);
 $('atRail').innerHTML=list.length?list.map(s=>{const n=state.slots.indexOf(s)+1;return`<section class="at-mount${state.focus===s.id?' is-focus':''}" data-mount="${esc(s.id)}"><div class="at-mount__head"><span class="at-mount__no">${pad(n)}</span><div class="at-mount__name">${esc(s.label)}<span class="at-mount__fit${s.current?'':' is-factory'}">${esc(s.currentLabel||'Factory')}</span></div>${s.current?`<button class="at-x" data-remove="${esc(s.id)}" ${state.busy?'disabled':''} title="Return ${esc(s.currentLabel)} to your bag"><b>✕</b>Remove</button>`:''}</div><div class="at-parts">${s.options.map(p=>partTile(s,p)).join('')}</div></section>`;}).join(''):'<p class="at-empty">This weapon takes no attachments.</p>';
 const hidden=state.data?.unsupported||0;$('atRailFoot').textContent=hidden?`${hidden} mount${hidden>1?'s':''} not supported on this weapon.`:'Every mount on this weapon is listed.';
}
function render(){renderRail();renderCard();renderPoints();}

/* ---------- hotspots ---------- */
let blocked=[];
function measure(){blocked=['atRailPanel','atCard','atKeys'].map(id=>$(id)?.getBoundingClientRect()).filter(Boolean);}
window.addEventListener('resize',measure);
function renderPoints(){
 const box=$('atPoints'),seen=new Set();
 for(const[id,p]of Object.entries(state.points)){
  const slot=slotOf(id);if(!slot)continue;seen.add(id);
  let el=box.querySelector(`.hs[data-slot="${id}"]`);
  if(!el){el=document.createElement('div');el.className='hs';el.dataset.slot=id;box.appendChild(el);}
  const n=state.slots.indexOf(slot)+1,sig=[slot.current,slot.currentLabel,state.busy].join('|');
  if(el.dataset.sig!==sig){el.dataset.sig=sig;el.innerHTML=`<span class="hs__ring">${n}</span><span class="hs__tag">${esc(slot.label)}<em>${esc(slot.currentLabel||'Factory')}</em>${slot.current?`<button class="at-x" data-remove="${esc(id)}" ${state.busy?'disabled':''} title="Remove"><b>✕</b></button>`:''}</span>`;}
  // hide under the panels, flip the tag on the right half
  const x=p.x*innerWidth,y=p.y*innerHeight,covered=blocked.some(r=>x>r.left-24&&x<r.right+24&&y>r.top-24&&y<r.bottom+24);
  el.hidden=!p.visible||covered;el.style.left=p.x*100+'%';el.style.top=p.y*100+'%';
  el.classList.toggle('is-left',p.x>.62);el.classList.toggle('is-fitted',!!slot.current);el.classList.toggle('is-bounds',p.source==='bounds');
  el.classList.toggle('is-focus',state.focus===id);el.classList.toggle('is-ghost',state.preview?.slot===id&&!state.preview.remove);
  el.classList.toggle('is-match',!!drag.active&&drag.slot===id);el.classList.toggle('is-hot',!!drag.active&&drag.slot===id&&drag.hot);
 }
 box.querySelectorAll('.hs').forEach(el=>{if(!seen.has(el.dataset.slot))el.remove();});
}
function focusMount(id){
 state.focus=id;renderRail();renderPoints();
 root.querySelector(`.at-mount[data-mount="${id}"]`)?.scrollIntoView({block:'nearest',behavior:'smooth'});
}
function flash(id){const el=$('atPoints').querySelector(`.hs[data-slot="${id}"]`);if(!el)return;el.classList.remove('is-flash');void el.offsetWidth;el.classList.add('is-flash');}

/* ---------- status line ---------- */
function status(text,kind='',stamp=''){const s=$('atStatus');s.className=kind?'is-'+kind:'';s.innerHTML=esc(text)+(stamp?`<span class="k-stamp at-stampfx ${kind==='ok'?'is-ok':''}">${esc(stamp)}</span>`:'');}

/* ---------- ghost preview (the real component, held until the pointer leaves) ---------- */
let ghostWant=null,ghostSent=null,ghostTimer=null,ghostBusy=false;
function wantGhost(slot,id,delay=160){
 ghostWant=slot&&id?{slot,id}:null;
 state.preview=ghostWant?{slot,id}:state.preview?.remove?state.preview:null;renderCard();renderPoints();
 clearTimeout(ghostTimer);ghostTimer=setTimeout(flushGhost,ghostWant?delay:90);
}
async function flushGhost(){
 if(ghostBusy||!state.open)return;const want=ghostWant,key=want?want.slot+':'+want.id:'';
 if(key===ghostSent)return;ghostBusy=true;ghostSent=key;
 const p=want&&partOf(want.slot,want.id);
 await post('attachmentGhost',{serial:state.serial,slot:want?.slot,id:p&&p.ghost?want.id:null});
 ghostBusy=false;const now=ghostWant?ghostWant.slot+':'+ghostWant.id:'';if(now!==ghostSent)flushGhost();
}
function previewRemove(slot){ghostWant=null;state.preview=slot?{slot,remove:true}:null;renderCard();clearTimeout(ghostTimer);ghostTimer=setTimeout(flushGhost,60);}

/* ---------- fit / remove ---------- */
async function apply(slotId,id,remove=false){
 if(state.busy||!state.open)return;
 const slot=slotOf(slotId),part=partOf(slotId,id);
 if(!slot||(!remove&&(!part||part.count<1||part.installed)))return;
 ghostWant=null;ghostSent='';state.preview=null;state.busy=true;render();
 status(remove?`Taking off ${slot.currentLabel}…`:`Fitting ${part.label}…`,'busy');
 const result=await post('attachmentPart',{serial:state.serial,slot:slotId,id,remove});
 state.busy=false;if(!state.open)return;
 if(result.ok){flash(slotId);status(remove?`${slot.currentLabel||'Part'} is back in your bag.`:`${part.label} fitted and saved to this weapon.`,'ok',remove?'Removed':'Fitted');}
 else status(result.error||'The change could not be saved.','bad');
 render();
}

/* ---------- drag a part onto its mount (pointer based) ---------- */
const drag={pending:null,active:false,slot:null,id:null,hot:false,el:null};
function pointNear(slot,x,y){
 const el=$('atPoints').querySelector(`.hs[data-slot="${slot}"]`);if(!el||el.hidden)return false;
 const r=el.querySelector('.hs__ring').getBoundingClientRect();return Math.hypot(x-(r.left+r.width/2),y-(r.top+r.height/2))<70*(window.innerHeight/1080);
}
function endDrag(){drag.pending=null;drag.active=false;drag.hot=false;drag.el?.remove();drag.el=null;root.classList.remove('is-dragging');root.querySelectorAll('.at-mount.is-match').forEach(m=>m.classList.remove('is-match'));renderPoints();}
$('atRail').addEventListener('pointerdown',e=>{
 if(e.button!==0||!state.open)return;
 const x=e.target.closest('[data-remove]');if(x){return;}
 const b=e.target.closest('[data-part]');if(!b)return;
 const p=partOf(b.dataset.slot,b.dataset.part);if(!p)return;
 if(state.busy||p.count<1||p.installed){post('attachmentCue',{cue:'cancel'});status(p.installed?`${p.label} is already fitted.`:`You are not carrying a ${p.label}.`,'bad');return;}
 drag.pending={slot:b.dataset.slot,id:b.dataset.part,x:e.clientX,y:e.clientY,item:p.item};
});
window.addEventListener('pointermove',e=>{
 if(drag.pending&&!drag.active&&Math.hypot(e.clientX-drag.pending.x,e.clientY-drag.pending.y)>6){
  drag.active=true;drag.slot=drag.pending.slot;drag.id=drag.pending.id;
  drag.el=document.createElement('div');drag.el.className='at-drag';drag.el.innerHTML=art(drag.pending.item,drag.pending.slot);root.appendChild(drag.el);
  root.classList.add('is-dragging');root.querySelector(`.at-mount[data-mount="${drag.slot}"]`)?.classList.add('is-match');
  post('attachmentCue',{cue:'pick'});wantGhost(drag.slot,drag.id,0);
  status('Drop it on the glowing mount.','busy');
 }
 if(!drag.active)return;
 const box=root.getBoundingClientRect(),k=box.width/(root.offsetWidth||box.width)||1;
 drag.el.style.left=(e.clientX-box.left)/k+'px';drag.el.style.top=(e.clientY-box.top)/k+'px';
 const hot=pointNear(drag.slot,e.clientX,e.clientY);
 if(hot!==drag.hot){drag.hot=hot;drag.el.classList.toggle('is-hot',hot);if(hot)post('attachmentCue',{cue:'match'});renderPoints();}
});
window.addEventListener('pointerup',e=>{
 if(drag.active){const{slot,id,hot}=drag;endDrag();if(hot)apply(slot,id);else{wantGhost(null);status('Drop the part on its glowing mount, or click it to fit.');}return;}
 if(drag.pending){const{slot,id}=drag.pending;drag.pending=null;const b=e.target.closest?.('[data-part]');if(b&&b.dataset.part===id)apply(slot,id);}
});
window.addEventListener('pointercancel',()=>{if(drag.active)wantGhost(null);endDrag();});

/* hover = ghost preview / removal compare */
root.addEventListener('pointerover',e=>{
 if(drag.active||state.busy)return;
 const b=e.target.closest('[data-part]');if(b){const p=partOf(b.dataset.slot,b.dataset.part);if(p&&!p.installed)wantGhost(b.dataset.slot,b.dataset.part);return;}
 const x=e.target.closest('[data-remove]');if(x){previewRemove(x.dataset.remove);return;}
 const m=e.target.closest('.hs');if(m){state.focus=m.dataset.slot;renderPoints();}
});
root.addEventListener('pointerout',e=>{
 if(drag.active)return;
 const from=e.target.closest('[data-part],[data-remove]'),to=e.relatedTarget?.closest?.('[data-part],[data-remove]');
 if(from&&from!==to){if(from.dataset.remove)previewRemove(null);else wantGhost(null);}
});
root.addEventListener('click',e=>{
 const x=e.target.closest('[data-remove]');if(x&&!x.disabled){e.stopPropagation();const s=slotOf(x.dataset.remove);if(s?.current)apply(s.id,null,true);return;}
 const ring=e.target.closest('.hs__ring');if(ring)focusMount(ring.closest('.hs').dataset.slot);
});

/* ---------- orbit / zoom ---------- */
let orbit=false,lastX=0,lastY=0,queued={x:0,y:0},orbitFrame=false;
const stage=$('atStage');
stage.addEventListener('pointerdown',e=>{if(e.button!==2||!state.open)return;orbit=true;lastX=e.clientX;lastY=e.clientY;stage.classList.add('is-orbit');stage.setPointerCapture(e.pointerId);});
stage.addEventListener('pointermove',e=>{if(!orbit)return;queued.x+=e.clientX-lastX;queued.y+=e.clientY-lastY;lastX=e.clientX;lastY=e.clientY;if(!orbitFrame){orbitFrame=true;requestAnimationFrame(()=>{orbitFrame=false;if(state.open)post('attachmentOrbit',queued);queued={x:0,y:0};});}});
const stopOrbit=()=>{orbit=false;stage.classList.remove('is-orbit');};
stage.addEventListener('pointerup',stopOrbit);stage.addEventListener('pointercancel',stopOrbit);
stage.addEventListener('wheel',e=>{if(state.open){e.preventDefault();post('attachmentOrbit',{zoom:Math.sign(e.deltaY)});}},{passive:false});
$('atReset').onclick=()=>post('attachmentOrbit',{reset:true});
$('atClose').onclick=()=>post('attachmentClose');
root.addEventListener('contextmenu',e=>e.preventDefault());
document.addEventListener('keydown',e=>{
 if(!state.open)return;
 if(e.key==='Escape'||e.key.toLowerCase()==='o'){e.preventDefault();if(drag.active){endDrag();wantGhost(null);return;}post('attachmentClose');}
 else if(/^[1-6]$/.test(e.key)){const s=state.slots[Number(e.key)-1];if(s&&(s.options.length||s.current))focusMount(s.id);}
});

/* ---------- messages ---------- */
window.addEventListener('message',({data:d})=>{
 if(!String(d?.action||'').startsWith('attachments:'))return;
 if(d.action==='attachments:state'){
  state.data=d.data;state.slots=d.data.slots||[];state.serial=d.data.serial;
  $('atWeapon').textContent=d.data.weapon;window.BSFitTitle&&BSFitTitle($('atWeapon'),34,18);$('atSerial').textContent=`SERIAL ${d.data.serial}`;$('atRounds').textContent=`${d.data.rounds} RDS`;
  if(state.focus&&!slotOf(state.focus))state.focus=null;
  render();measure();renderPoints();
 }
 if(d.action==='attachments:open'){
  document.documentElement.style.visibility='visible';state.open=true;state.busy=false;state.preview=null;ghostSent='';root.hidden=false;
  post('attachmentReady');status('Drag a part onto its mount, or click it to fit.');render();
  requestAnimationFrame(()=>{measure();renderPoints();});
 }
 if(d.action==='attachments:close'){state.open=false;state.busy=false;endDrag();clearTimeout(ghostTimer);ghostWant=null;ghostSent='';root.hidden=true;state.points={};$('atPoints').replaceChildren();}
 if(d.action==='attachments:points'&&state.open){state.points={};for(const p of d.data||[])state.points[p.id]=p;renderPoints();}
});
})();

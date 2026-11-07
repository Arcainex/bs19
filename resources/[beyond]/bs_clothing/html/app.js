const app=document.getElementById('app');
const cats=document.getElementById('cats');
const dEl=document.getElementById('drawable');
const tEl=document.getElementById('texture');
const dMax=document.getElementById('drawableMax');
const tMax=document.getElementById('textureMax');
const meta=document.getElementById('meta');
const tools=document.getElementById('adminTools');
const modelStatus=document.getElementById('modelStatus');
const textureStatus=document.getElementById('textureStatus');
const disableBtn=document.getElementById('disable');
const disableTextureBtn=document.getElementById('disableTexture');
const favoriteBtn=document.getElementById('favorite');
const torsoPanel=document.getElementById('torsoPanel');
const torsoStatus=document.getElementById('torsoStatus');
const torsoDEl=document.getElementById('torsoDrawable');
const torsoTEl=document.getElementById('torsoTexture');
const torsoDMax=document.getElementById('torsoDrawableMax');
const torsoTMax=document.getElementById('torsoTextureMax');
let S={drawable:0,texture:0,drawableCount:1,modelPosition:1,modelCount:1,textureCount:1,selected:'top',isProp:false,editorMode:false};
let freeMove=false;
const post=(name,data={})=>fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
const apply=(d,t,drawableStep=0,textureStep=0)=>post('change',{drawable:Number(d),texture:Number(t),drawableStep,textureStep});
function tag(el,text,off=false){el.textContent=text;el.classList.toggle('off',off)}
function render(m){
  S=m;
  cats.innerHTML=m.categories.map(c=>`<button class="${c.key===m.selected?'active':''}" data-key="${c.key}">${c.label}</button>`).join('');
  const current=m.categories.find(c=>c.key===m.selected); document.getElementById('categoryName').textContent=current?current.label:'—';
  // Spieler: Position in der aktiven, gueltigen Modell-Liste (1..N).
  // Editor: Position in allen belegten Modellen, auch deaktivierte.
  // GTA-Global-IDs werden nie als sichtbare Spieler-Modellnummer verwendet.
  const modelCount=Math.max(0,Number(m.modelCount||0));
  const modelPos=(m.isProp && m.drawable<0) || modelCount===0 ? 0 : Math.min(modelCount,Math.max(1,Number(m.modelPosition||1)));
  dEl.value=modelPos; dEl.min=(m.isProp||modelCount===0)?0:1; dEl.max=modelCount; dMax.textContent=`/ ${modelCount}`;
  dEl.classList.toggle('disabledValue', !!m.editorMode && !!m.disabled);
  // Spieler sehen nur freigegebene Texturen als fortlaufende Liste 0..N-1.
  // Der Editor zeigt weiterhin die echten GTA-Texture-IDs, damit einzelne
  // Varianten gezielt deaktiviert/reaktiviert werden können.
  const textureDisplay=m.editorMode ? m.texture : (m.activeTextureIndex ?? 0);
  const textureDisplayMax=m.editorMode ? Math.max(0,m.textureCount-1) : Math.max(0,(m.activeTextureCount||1)-1);
  tEl.value=textureDisplay; tEl.min=0; tEl.max=textureDisplayMax; tMax.textContent=`/ ${textureDisplayMax}`;
  tEl.classList.toggle('disabledValue', !!m.editorMode && !!m.textureDisabled);
  tools.classList.toggle('hidden',!m.editorMode); meta.classList.toggle('hidden',!m.editorMode);
  const showTorso=m.editorMode && m.selected==='top'; torsoPanel.classList.toggle('hidden',!showTorso);
  if(showTorso){
    torsoDEl.value=m.torsoDrawable; torsoDEl.max=Math.max(0,m.torsoDrawableCount-1); torsoDMax.textContent=`/ ${Math.max(0,m.torsoDrawableCount-1)}`;
    torsoTEl.value=m.torsoTexture; torsoTEl.max=Math.max(0,m.torsoTextureCount-1); torsoTMax.textContent=`/ ${Math.max(0,m.torsoTextureCount-1)}`;
    torsoStatus.textContent=m.torsoRuleActive?`FIX ${m.savedTorsoDrawable} / ${m.savedTorsoTexture}`:'NICHT GESETZT'; torsoStatus.classList.toggle('active',m.torsoRuleActive);
    document.getElementById('clearTorso').disabled=!m.torsoRuleActive;
  }
  document.getElementById('modePill').textContent=m.editorMode?'EDITOR':'SPIELER'; document.getElementById('modePill').classList.toggle('editor',m.editorMode);
  tag(modelStatus,m.disabled?'DEAKTIVIERT':(m.favorite?'FAVORIT':'AKTIV'),m.disabled); modelStatus.classList.toggle('fav',!m.disabled&&m.favorite);
  tag(textureStatus,m.textureDisabled?'DEAKTIVIERT':'AKTIV',m.textureDisabled);
  if(m.editorMode){
    const collection=m.collection||'(GTA V Basis)';
    meta.innerHTML=`<div><span>GESCHLECHT</span><br><b>${m.gender.toUpperCase()}</b></div><div><span>TYP</span><br><b>${m.kind} ${m.componentId}</b></div><div class="wide"><span>COLLECTION</span><br><code>${collection}</code></div><div><span>LOCAL ID</span><br><b>${m.localIndex}</b></div><div><span>GLOBAL ID</span><br><b>${m.drawable}</b></div>`;
    disableBtn.textContent=m.disabled?'✓ MODELL AKTIVIEREN':'✕ MODELL DEAKTIVIEREN'; disableBtn.classList.toggle('active',m.disabled);
    disableTextureBtn.textContent=m.textureDisabled?'✓ TEXTUR AKTIVIEREN':'✕ TEXTUR DEAKTIVIEREN'; disableTextureBtn.classList.toggle('active',m.textureDisabled); disableTextureBtn.disabled=!m.canTextureRule;
    favoriteBtn.textContent=m.favorite?'★ FAVORIT MARKIERT':'☆ ALS FAVORIT MARKIEREN'; favoriteBtn.classList.toggle('active',m.favorite);
  }
}
window.addEventListener('message',e=>{const m=e.data;if(m.action==='open'){app.classList.remove('hidden');document.getElementById('title').textContent=m.editorMode?'KLEIDUNGS-EDITOR':'UMKLEIDE';document.getElementById('subtitle').textContent=m.editorMode?'GTA-, DLC- und Alpha-Z-Kleidung verwalten':'Kleidung auswählen und anpassen'}if(m.action==='close'){freeMove=false;app.classList.add('hidden')}if(m.action==='state')render(m);if(m.action==='freeMove'){freeMove=!!m.active;const hint=document.getElementById('freeMoveHint');if(hint)hint.classList.toggle('active',freeMove);const panel=document.querySelector('.panel');if(panel)panel.classList.toggle('freeMoveActive',freeMove);if(freeMove&&document.activeElement&&document.activeElement.blur)document.activeElement.blur();}});
cats.onclick=e=>{const b=e.target.closest('[data-key]');if(b)post('select',{key:b.dataset.key})};
document.querySelectorAll('.step .arrow').forEach(b=>b.onclick=()=>{
  if(b.dataset.k==='d'){
    const st=Number(b.dataset.v);
    // Lua navigiert durch die collection-basierte Liste tatsächlich belegter Modelle.
    apply(S.drawable,0,st,0);
  }else{
    const st=Number(b.dataset.v);
    // Immer von der echten GTA-Texture-ID weiterblättern. Der Client überspringt
    // deaktivierte Varianten automatisch.
    apply(S.drawable,S.texture+st,0,st);
  }
});
function manual(el){
  let enteredModel=Number(dEl.value);
  if(!Number.isFinite(enteredModel)) enteredModel=Number(S.modelPosition||1);

  let enteredTexture=Number(tEl.value);
  let t=S.texture;
  if(Number.isFinite(enteredTexture)){
    enteredTexture=Math.trunc(enteredTexture);
    if(S.editorMode){
      t=enteredTexture;
    }else{
      const allowed=Array.isArray(S.allowedTextures)?S.allowedTextures:[];
      if(allowed.length){
        const idx=Math.max(0,Math.min(enteredTexture,allowed.length-1));
        t=Number(allowed[idx]);
      }
    }
  }

  post('change',{
    modelPosition:Math.trunc(enteredModel),
    texture:Math.trunc(t),
    drawableStep:0,
    textureStep:0
  });
  el.blur();
}
dEl.addEventListener('keydown',e=>{if(e.key==='Enter')manual(dEl)}); tEl.addEventListener('keydown',e=>{if(e.key==='Enter')manual(tEl)}); dEl.addEventListener('change',()=>manual(dEl)); tEl.addEventListener('change',()=>manual(tEl));
disableBtn.onclick=()=>post('toggleDisabled'); disableTextureBtn.onclick=()=>post('toggleTextureDisabled'); favoriteBtn.onclick=()=>post('toggleFavorite');
document.getElementById('left').onclick=()=>post('rotate',{delta:-15}); document.getElementById('right').onclick=()=>post('rotate',{delta:15}); document.getElementById('save').onclick=()=>post('save'); document.getElementById('cancel').onclick=()=>post('cancel'); document.addEventListener('keydown',e=>{if(freeMove){e.preventDefault();e.stopImmediatePropagation();return}if(e.key==='Escape')post('cancel')},true);

const applyTorso=(d,t,drawableStep=0,textureStep=0)=>post('changeTorso',{drawable:Number(d),texture:Number(t),drawableStep,textureStep});
document.querySelectorAll('.torsoArrow').forEach(b=>b.onclick=()=>{let d=Number(torsoDEl.value),t=Number(torsoTEl.value);if(b.dataset.k==='d'){const st=Number(b.dataset.v);d+=st;t=0;applyTorso(d,t,st,0)}else{const st=Number(b.dataset.v);t+=st;applyTorso(d,t,0,st)}});
function manualTorso(el){let d=Number(torsoDEl.value),t=Number(torsoTEl.value);if(!Number.isFinite(d))d=S.torsoDrawable||0;if(!Number.isFinite(t))t=S.torsoTexture||0;applyTorso(Math.trunc(d),Math.trunc(t),0,0);el.blur()}
torsoDEl.addEventListener('keydown',e=>{if(e.key==='Enter')manualTorso(torsoDEl)}); torsoTEl.addEventListener('keydown',e=>{if(e.key==='Enter')manualTorso(torsoTEl)}); torsoDEl.addEventListener('change',()=>manualTorso(torsoDEl)); torsoTEl.addEventListener('change',()=>manualTorso(torsoTEl));
document.getElementById('saveTorso').onclick=()=>post('saveTorso'); document.getElementById('clearTorso').onclick=()=>post('clearTorso');

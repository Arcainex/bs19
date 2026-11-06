(() => {
  'use strict';
  const hud=document.createElement('div');hud.id='voiceRadioHud';
  hud.innerHTML=`<div class="vr-chip" id="voiceChip"><svg class="vr-icon" viewBox="0 0 20 24" aria-hidden="true"><rect x="6" y="2" width="8" height="13" rx="4"/><path d="M3 10v2a7 7 0 0 0 14 0v-2M10 19v4M6 23h8"/></svg><div><span class="vr-caption">VOICE</span><span class="vr-value" id="voiceValue">Normal · 15 m</span></div><i class="vr-dot" id="voiceConnection"></i></div><div class="vr-chip" id="radioChip"><svg class="vr-icon" viewBox="0 0 20 24" aria-hidden="true"><path d="M14 8V1M4 8h12v15H4zM7 12h6M7 16h6M7 19h6"/></svg><div><span class="vr-caption">RADIO</span><span class="vr-value" id="radioValue">Off</span></div></div>`;
  const panel=document.createElement('section');panel.id='voiceRadioSettings';
  panel.innerHTML=`<h3>Voice & radio display</h3><p>Drag the indicator to a comfortable position. Its size and safe margin adapt to your screen.</p><label><input type="checkbox" id="vrEnabled">Show voice indicator</label><label><input type="checkbox" id="vrRadio">Show radio indicator</label><label>Size <output id="vrScaleOut"></output><input id="vrScale" type="range" min=".65" max="2" step=".05"></label><label>Opacity <output id="vrOpacityOut"></output><input id="vrOpacity" type="range" min=".3" max="1" step=".05"></label><label>Screen margin <output id="vrMarginOut"></output><input id="vrMargin" type="range" min="8" max="96" step="4"></label><button id="vrReset">Reset position</button><button id="vrDone">Done</button>`;
  document.body.append(hud,panel);
  let prefs={enabled:true,radio:true,scale:1,opacity:.9,margin:24,x:.94,y:.80},editing=false,visible=false,voice={},radio={},drag;
  const $=id=>document.getElementById(id),post=(name,data={})=>BS.post(name,data);
  function place(){
    if (!editing) { document.getElementById("hud")?.append(hud); hud.classList.add("vr-docked"); hud.style.cssText=""; return; }
    document.body.append(hud); hud.classList.remove("vr-docked");
    const scale=Number(prefs.scale)||1,margin=Number(prefs.margin)||24;
    hud.style.transform=`translate(-100%,-50%) scale(${scale})`;
    const width=hud.offsetWidth*scale,height=hud.offsetHeight*scale;
    const maxX=Math.max(margin+width,innerWidth-margin),minX=Math.min(maxX,margin+width);
    const x=Math.max(minX,Math.min(maxX,prefs.x*innerWidth)),y=Math.max(margin+height/2,Math.min(innerHeight-margin-height/2,prefs.y*innerHeight));
    hud.style.left=x+'px';hud.style.top=y+'px';hud.style.opacity=prefs.opacity;
  }
  function draw(){
    hud.style.display=(visible||editing)?'flex':'none';$('voiceChip').style.display=prefs.enabled||editing?'flex':'none';$('radioChip').style.display=prefs.radio&&(radio.channel||editing)?'flex':'none';
    $('voiceValue').textContent=voice.connected===false?'Connecting…':`${voice.mode||'Normal'} · ${voice.range||15} m`;
    $('radioValue').textContent=radio.channel?`${radio.transmitting?'TX':'CH'} ${radio.channel}`:'Off';
    $('voiceChip').classList.toggle('is-speaking',!!voice.talking);$('radioChip').classList.toggle('is-speaking',!!radio.transmitting);$('voiceConnection').classList.toggle('online',voice.connected!==false);
    place();
  }
  function controls(){for(const [key,id] of [['enabled','vrEnabled'],['radio','vrRadio']])$(id).checked=prefs[key];for(const [key,id] of [['scale','vrScale'],['opacity','vrOpacity'],['margin','vrMargin']]){$(id).value=prefs[key];$(id+'Out').textContent=key==='margin'?prefs[key]+' px':Math.round(prefs[key]*100)+'%';}}
  const save=()=>post('voiceRadioSave',prefs);
  panel.addEventListener('input',()=>{prefs.enabled=$('vrEnabled').checked;prefs.radio=$('vrRadio').checked;prefs.scale=Number($('vrScale').value);prefs.opacity=Number($('vrOpacity').value);prefs.margin=Number($('vrMargin').value);controls();draw();});
  panel.addEventListener('change',save);
  $('vrReset').onclick=()=>{prefs.x=.94;prefs.y=.80;draw();save();};$('vrDone').onclick=()=>post('voiceRadioClose');
  hud.addEventListener('pointerdown',e=>{if(!editing)return;drag={x:e.clientX,y:e.clientY,px:parseFloat(hud.style.left),py:parseFloat(hud.style.top)};hud.setPointerCapture(e.pointerId);});
  hud.addEventListener('pointermove',e=>{if(!drag)return;prefs.x=Math.max(0,Math.min(1,(drag.px+e.clientX-drag.x)/innerWidth));prefs.y=Math.max(0,Math.min(1,(drag.py+e.clientY-drag.y)/innerHeight));place();});
  hud.addEventListener('pointerup',()=>{if(drag){drag=null;save();}});
  document.addEventListener('keydown',e=>{if(editing&&e.key==='Escape')post('voiceRadioClose');});
  window.addEventListener('resize',place);
  BS.on('voiceRadioState',d=>{if(d.voice)voice=d.voice;if(d.radio)radio=d.radio;draw();});
  BS.on('voiceRadioPrefs',d=>{prefs={...prefs,...d.settings};controls();draw();});
  BS.on('voiceRadioEdit',d=>{editing=!!d.on;if(d.settings)prefs={...prefs,...d.settings};panel.style.display=editing?'block':'none';hud.classList.toggle('vr-editable',editing);controls();draw();});
  BS.on('hud',d=>{visible=!!d.visible;draw();});
  controls();draw();
})();

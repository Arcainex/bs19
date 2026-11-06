(() => {
  'use strict';
  const ui=()=>window.BSConfigUI, E=v=>ui().esc(String(v??''));
  const rpc=(action,payload)=>ui().rpc('ext','bs_radio',action,payload);
  let main,data;
  const number=(id)=>Number(main.querySelector('#'+id).value);
  const field=(label,id,value,min,max,step=1)=>`<label style="display:grid;gap:6px;min-width:140px;flex:1">${E(label)}<input id="${id}" type="number" value="${E(value)}" min="${min}" max="${max}" step="${step}"></label>`;
  async function act(action,payload){
    const r=await rpc(action,payload);
    if(!r?.ok){ui().toast(r?.error||'Could not save radio settings.',true);return false;}
    data=r.data;draw();ui().toast('Radio network updated.');return true;
  }
  function draw(){
    const ranges=data.voiceRanges||[3,15,35];
    main.innerHTML=`<h2 class="cat">Voice & radio network</h2><p class="shint">Relay coverage follows the map. Radios need a connected route; private faction frequencies require membership.</p>
      <section class="card"><h4>Speaking distance</h4><div style="display:flex;gap:16px;flex-wrap:wrap">${ranges.map((v,i)=>field(['Whisper · metres','Normal · metres','Shout · metres'][i],'vr'+i,v,1,100,.5)).join('')}</div><p><button class="btn" data-radio="voice">Save voice ranges</button></p></section>
      <section class="card"><h4>Radio & portable relays</h4><div style="display:flex;gap:16px;flex-wrap:wrap">${field('Direct radio range · m','direct',data.directRange,1,20000)}${field('Portable coverage · m','portable',data.portableRange,1,20000)}${field('Battery life · seconds','life',data.portableLife,1,86400)}</div><h4>Relay links by radio tier</h4><p class="shint">Two links allow three antennas along the route. 999 allows any connected chain in this network.</p><div style="display:flex;gap:16px;flex-wrap:wrap">${data.tiers.map((t,i)=>field(t.label,'tier'+i,t.hops,0,999)).join('')}</div><p><button class="btn" data-radio="settings">Save radio settings</button> <button class="btn" data-radio="debug">Show relay coverage on map</button></p></section>
      <section class="card"><h4>Antenna sites</h4><p class="shint">Fixed sites are shared across the world. Portable relays retain their owner's battery and routing bucket.</p><div style="overflow-x:auto"><table class="audit"><thead><tr><th>Site</th><th>Coverage</th><th>Link range</th><th>Status</th><th></th></tr></thead><tbody>${data.antennas.map(n=>`<tr><td>${E(n.label)}<div class="shint">${E(n.id)}</div></td><td>${E(Math.round(n.range))} m</td><td>${E(Math.round(n.linkRange))} m</td><td>${n.disrupted?'Disrupted':n.enabled?'Online':'Disabled'}${n.owner?' · portable':''}</td><td>${!n.owner?`<button class="btn" data-radio="edit" data-id="${E(n.id)}">Edit site</button>`:''}</td></tr>`).join('')}</tbody></table></div><p><button class="btn" data-radio="create">Add fixed relay</button></p></section>
      <section class="card"><h4>Faction frequencies</h4><p class="shint">Reserved channels are locked to faction members. Player faction managers can also reserve a frequency from their radio.</p><table class="audit"><tr><th>Channel</th><th>Faction</th></tr>${Object.entries(data.channels||{}).map(([c,f])=>`<tr><td>${E(c)}</td><td>${E(f.faction)}</td></tr>`).join('')}</table><div style="display:flex;gap:12px;flex-wrap:wrap"><label>Faction ID <input id="radioFaction" maxlength="64"></label><label>Channel <input id="radioChannel" type="number" min="1" max="9999"></label><button class="btn" data-radio="faction">Reserve frequency</button></div></section>`;
  }
  function editor(node){
    const creating=!node,n=node||{id:'',label:'New relay',x:0,y:0,z:0,range:1500,linkRange:3000,enabled:true};
    const content=`<div id="relayForm"><label>Site ID <input id="relayId" value="${E(n.id)}" ${creating?'':'disabled'} pattern="[A-Za-z0-9_-]+"></label><label>Display name <input id="relayLabel" maxlength="60" value="${E(n.label)}"></label><div style="display:flex;gap:12px;flex-wrap:wrap">${['x','y','z'].map(k=>field(k.toUpperCase(),'relay'+k,n[k],-20000,20000,.1)).join('')}</div><div style="display:flex;gap:12px">${field('Coverage · m','relayrange',n.range,1,20000)}${field('Link range · m','relaylinkRange',n.linkRange,1,20000)}</div><p><label><input id="relayEnabled" type="checkbox" ${n.enabled?'checked':''}> Enabled</label></p></div>`;
    const save=async()=>{
      const f=document.getElementById('relayForm'),v=id=>f.querySelector('#'+id).value;
      const patch={id:v('relayId'),label:v('relayLabel'),enabled:f.querySelector('#relayEnabled').checked};
      for(const k of ['x','y','z','range','linkRange'])patch[k]=Number(v('relay'+k));
      if(!/^[\w-]+$/.test(patch.id)||!patch.label||['x','y','z','range','linkRange'].some(k=>!Number.isFinite(patch[k]))){ui().toast('Enter a valid site ID and coordinates.',true);return;}
      if(await act(creating?'antenna.create':'antenna.update',patch))ui().closeModal();
    };
    const buttons=[{label:'Cancel',fn:()=>ui().closeModal()},{label:'Save site',primary:true,fn:save}];
    if(!creating)buttons.unshift({label:'Delete site',danger:true,fn:async()=>{if(await ui().confirmBox('Delete relay',`Remove ${n.label} from the network?`)){if(await act('antenna.delete',{id:n.id}))ui().closeModal();}}});
    ui().modal(creating?'Add relay site':'Edit relay site',content,buttons);
  }
  document.addEventListener('click',async e=>{
    const b=e.target.closest('[data-radio]');if(!b||!main?.contains(b))return;
    const action=b.dataset.radio;
    if(action==='settings')return act('settings',{directRange:number('direct'),portableRange:number('portable'),portableLife:number('life'),tiers:data.tiers.map((_,i)=>({hops:number('tier'+i)}))});
    if(action==='voice')return act('voice.ranges',{ranges:[0,1,2].map(i=>number('vr'+i))});
    if(action==='faction')return act('faction.channel',{faction:main.querySelector('#radioFaction').value.trim(),channel:number('radioChannel')});
    if(action==='debug')return act('debug',{});
    if(action==='edit')return editor(data.antennas.find(n=>n.id===b.dataset.id));
    if(action==='create')return editor();
  });
  async function render(m){main=m;const r=await rpc('get');if(!r?.ok){m.innerHTML=`<div class="empty">${E(r?.error||'Radio service is unavailable.')}</div>`;return;}data=r.data;draw();}
  window.BSConfigExt=(window.BSConfigExt||[]).concat([{id:'_ext_radio',label:'Voice & radio',render}]);
})();

(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const prefix = 'bs_multichar:Multichar.';
  const clone = v => JSON.parse(JSON.stringify(v || {}));
  let draft, selected, tab;
  const ui = () => window.BSConfigUI;
  const E = v => ui().esc(v == null ? '' : v);
  const number = (key, label, value, min = -12000, max = 12000) => `<label>${E(label)}<input type="number" data-scene="${E(key)}" value="${E(value ?? 0)}" step="0.01" min="${min}" max="${max}"></label>`;
  const text = (key, label, value) => `<label>${E(label)}<input type="text" data-scene="${E(key)}" value="${E(value)}"></label>`;
  const check = (key, label, value) => `<label><input type="checkbox" data-scene="${E(key)}" ${value ? 'checked' : ''}> ${E(label)}</label>`;
  const paths = ['Selection.presets','Selection.preset','Selection.factions','Selection.weather','Selection.hour','Selection.minute','Selection.lineup','Selection.props','Scene.lights','Settings.focus'];
  function root() { return tab === 'shots' ? draft['Settings.focus'] : tab === 'lights' ? draft['Scene.lights'] : draft['Selection.presets'][selected]; }
  function fields(object, base = '') {
    return Object.entries(object).map(([key, value]) => {
      const path = base ? base + '.' + key : key;
      if (typeof value === 'number') return number(path, key, value);
      if (typeof value === 'boolean') return check(path, key, value);
      if (value && typeof value === 'object' && !Array.isArray(value)) return `<fieldset><legend>${E(key)}</legend>${fields(value, path)}</fieldset>`;
      return '';
    }).join('');
  }
  function render() {
    const scene = draft['Selection.presets'][selected];
    const names = Object.keys(draft['Selection.presets']);
    let body = `<div class="selection-editor"><p>Changes are staged in this F1 profile. Apply them after closing this editor. The selection scene updates on the next connection.</p><nav>${[['scene','Location'],['props','Props'],['factions','Factions'],['shots','Cameras'],['lights','Lighting']].map(([id,label])=>`<button class="btn ${tab===id?'primary':''}" data-scene-tab="${id}">${label}</button>`).join('')}</nav>`;
    if (tab === 'scene' || tab === 'props') body += `<label>Location<select id="sceneLocation">${names.map(name=>`<option value="${E(name)}" ${name===selected?'selected':''}>${E(draft['Selection.presets'][name].label || name)}</option>`).join('')}</select></label>`;
    if (tab === 'scene') {
      body += `<div class="scene-grid">${text('label','Location name',scene.label)}${number('ped.x','X',scene.ped.x)}${number('ped.y','Y',scene.ped.y)}${number('ped.z','Z — standing position',scene.ped.z)}${number('ped.h','Character heading',scene.ped.h,0,360)}${number('cameraHeading','Camera heading',scene.cameraHeading,0,360)}${check('outdoor','Outdoor ground check',scene.outdoor)}</div><button class="btn" id="sceneUsePosition">Use my current position</button> <button class="btn" id="sceneDuplicate">Duplicate location</button><hr><label>Default location<select id="sceneDefault">${names.map(name=>`<option value="${E(name)}" ${name===draft['Selection.preset']?'selected':''}>${E(name)}</option>`).join('')}</select></label><div class="scene-grid">${text('@Selection.weather','Fixed weather',draft['Selection.weather'])}${number('@Selection.hour','Hour',draft['Selection.hour'],0,23)}${number('@Selection.minute','Minute',draft['Selection.minute'],0,59)}${check('@Selection.lineup','Show other survivors',draft['Selection.lineup'])}</div>`;
    } else if (tab === 'props') {
      body += '<p>World coordinates. These objects exist only in selection. Maximum 32 per scene including shared props.</p>';
      const props = Array.isArray(scene.props) ? scene.props : (scene.props=[]);
      body += props.map((prop,i)=>`<fieldset><legend>Prop ${i+1}</legend><div class="scene-grid">${text(`props.${i}.model`,'Model',prop.model)}${['x','y','z','h'].map(k=>number(`props.${i}.${k}`,k.toUpperCase(),prop[k])).join('')}</div><button class="btn" data-remove-prop="${i}">Remove</button></fieldset>`).join('')+'<button class="btn" id="sceneAddProp">Add prop at my position</button>';
    } else if (tab === 'factions') {
      body += '<p>Faction ID selects its own location. Other factions use the default location.</p>';
      body += Object.entries(draft['Selection.factions']).map(([id,name])=>`<div class="scene-grid"><span>${E(id)}</span><select data-faction="${E(id)}">${names.map(n=>`<option value="${E(n)}" ${n===name?'selected':''}>${E(n)}</option>`).join('')}</select><button class="btn" data-remove-faction="${E(id)}">Remove</button></div>`).join('');
      body += '<label>Faction ID<input id="sceneFactionId" type="text"></label><button class="btn" id="sceneAddFaction">Add faction</button>';
    } else body += `<div class="scene-grid">${fields(root())}</div>`;
    body += '</div>';
    ui().modal('Character selection scene',body,[{label:'Cancel',fn:ui().closeModal},{label:'Stage changes',primary:true,fn:()=>{
      if (!draft['Selection.presets'][draft['Selection.preset']]) return ui().toast('Choose an existing default location.',true);
      const weather = String(draft['Selection.weather']).toUpperCase();
      if (!['CLEAR','EXTRASUNNY','CLOUDS','OVERCAST','SMOG','FOGGY','RAIN','THUNDER','CLEARING','NEUTRAL','SNOW','BLIZZARD','SNOWLIGHT','XMAS','HALLOWEEN'].includes(weather)) return ui().toast('Enter a valid GTA weather name, such as OVERCAST.',true);
      draft['Selection.weather']=weather;
      paths.forEach(path=>ui().setValue(prefix+path,draft[path]));ui().closeModal();ui().toast('Scene changes staged. Use Apply to save the profile.');
    }}]);
    const host=$('mBody');
    host.onchange=event=>{
      const t=event.target;
      if(t.id==='sceneLocation'){selected=t.value;return render();}
      if(t.id==='sceneDefault'){draft['Selection.preset']=t.value;return;}
      if(t.dataset.faction){draft['Selection.factions'][t.dataset.faction]=t.value;return;}
      const path=t.dataset.scene;if(!path)return;
      let value=t.type==='checkbox'?t.checked:t.type==='number'?Number(t.value):t.value;
      if(t.type==='number'&&(!Number.isFinite(value)||!t.checkValidity())){t.reportValidity();return;}
      if(path[0]==='@'){draft[path.slice(1)]=value;return;}
      const parts=path.split('.');let obj=root();for(const part of parts.slice(0,-1))obj=obj[part];obj[parts.at(-1)]=value;
    };
    host.onclick=async event=>{
      const t=event.target.closest('button');if(!t)return;
      if(t.dataset.sceneTab){tab=t.dataset.sceneTab;return render();}
      if(t.dataset.removeProp!==undefined){scene.props.splice(Number(t.dataset.removeProp),1);return render();}
      if(t.dataset.removeFaction){delete draft['Selection.factions'][t.dataset.removeFaction];return render();}
      if(t.id==='sceneAddFaction'){const id=$('sceneFactionId').value.trim();if(!/^[a-zA-Z0-9_-]{1,64}$/.test(id)||['__proto__','constructor','prototype'].includes(id))return ui().toast('Enter a valid faction ID.',true);draft['Selection.factions'][id]=selected;return render();}
      if(t.id==='sceneDuplicate'){let name=selected+'_copy';while(draft['Selection.presets'][name])name+='_copy';draft['Selection.presets'][name]=clone(scene);selected=name;return render();}
      if(t.id==='sceneUsePosition'||t.id==='sceneAddProp'){
        const result=await fetch(`https://${GetParentResourceName()}/selectionPosition`,{method:'POST',body:'{}',headers:{'Content-Type':'application/json'}}).then(r=>r.json()).catch(()=>({}));
        if(!result.ok)return ui().toast('Position unavailable.',true);
        if(t.id==='sceneUsePosition')scene.ped={x:result.x,y:result.y,z:result.z,h:result.h};
        else {if(scene.props.length+(draft['Selection.props']||[]).length>=32)return ui().toast('32 props per scene maximum.',true);scene.props.push({model:'prop_barrel_02a',x:result.x,y:result.y,z:result.z,h:result.h});}render();
      }
    };
  }
  $('btnSelectionScene').onclick=()=>{
    if(!ui().schema().some(e=>e.id===prefix+'Selection.presets'))return ui().toast('Selection scene settings are unavailable.',true);
    draft={};paths.forEach(path=>draft[path]=clone(ui().value(prefix+path)));
    for(const path of ['Selection.preset','Selection.weather','Selection.hour','Selection.minute','Selection.lineup'])draft[path]=ui().value(prefix+path);
    selected=draft['Selection.preset'];if(!draft['Selection.presets'][selected])selected=Object.keys(draft['Selection.presets'])[0];
    if(!selected)return ui().toast('No selection locations configured.',true);
    tab='scene';render();
  };
})();

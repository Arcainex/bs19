(() => {
  'use strict';
  const ID='bs_zombies:Zombies.Archetypes',MODE='bs_zombies:Zombies.Mode';
  const ui=()=>window.BSConfigUI,E=value=>ui().esc(String(value??'')),copy=value=>JSON.parse(JSON.stringify(value));
  const gaits=[['move_m@drunk@verydrunk','Drunk walker'],['move_f@drunk@a','Female drunk walk'],['clipset@anim@ingame@move_m@zombie@core','Zombie locomotion']];
  const paces=[['walk','Walking'],['jog','Jogging'],['run','Running'],['sprint','Sprinting']];
  let main;
  const recipes=()=>{const value=ui().value(ID);return Array.isArray(value)?value:[];};
  function draw(){
    const list=recipes(),mode=ui().value(MODE),total=list.reduce((n,a)=>n+Number(a.weight||0),0);
    main.innerHTML=`<h2 class="cat">Networked+ population</h2><p class="shint">Create named population recipes with ped models, movement and optional map circles. Changes stay pending until you use F1 Apply, following the selected profile and audit history.</p>
      <section class="card"><h4>Current mode: ${E({networked:'Networked',networked_plus:'Networked+',legacy:'Legacy'}[mode]||mode||'Unknown')}</h4><p class="shint">The framework ships with the existing drunk walking style only. Recipes affect <b>Networked+</b>; editing this page never switches your zombie mode. Select Networked+ explicitly in the normal zombie settings when you want to use these recipes.</p></section>
      <section class="card"><h4>Population recipes</h4><p class="shint">Weights are relative within overlapping circles. An empty model list uses the existing zombie model pool; no circles means anywhere. Local custom ped assets must also be installed for every player.</p><div style="overflow-x:auto"><table class="audit"><thead><tr><th>Recipe</th><th>Movement</th><th>Models</th><th>Area</th><th>Weight</th><th></th></tr></thead><tbody>${list.map((a,i)=>`<tr><td>${E(a.label||a.id)}<div class="shint">${E(a.id)}</div></td><td>${E(paces.find(p=>p[0]===a.speed)?.[1]||a.speed)}</td><td>${a.models?.length?E(a.models.length)+' custom':'Default pool'}</td><td>${a.regions?.length?E(a.regions.length)+' circles':'Anywhere'}</td><td>${E(a.weight)}</td><td style="white-space:nowrap"><button class="btn" data-zrecipe="edit" data-index="${i}">Edit</button> <button class="btn danger" data-zrecipe="remove" data-index="${i}">Remove</button></td></tr>`).join('')}</tbody></table></div>${!list.length?'<p class="shint">No custom recipes. The existing population remains the fallback.</p>':''}<p><button class="btn" data-zrecipe="add">Add population recipe</button></p></section>`;
  }
  async function stage(list){
    const models=[...new Set(list.flatMap(a=>a.models||[]))];
    let check;
    try{check=await ui().rpc('zombieModels',models);}catch{ui().toast('Model validation is unavailable. Nothing was staged.',true);return false;}
    if(!check?.ok){ui().toast(check?.invalid?.length?'Unavailable ped models: '+check.invalid.join(', '):(check?.error||'Model validation failed. Nothing was staged.'),true);return false;}
    const result=await ui().setValue(ID,copy(list));
    if(result===false||result?.ok===false){ui().toast(result?.error||'The population recipe could not be staged.',true);return false;}
    draw();ui().toast('Population changes staged. Use Apply when ready.');return true;
  }
  function editor(index){
    const list=recipes(),existing=Number.isInteger(index),a=existing?copy(list[index]):{id:'',label:'',models:[],gait:gaits[0][0],speed:'walk',weight:100,regions:[]};
    let regions=copy(a.regions||[]),busy=false;
    const choices=gaits.some(g=>g[0]===a.gait)?gaits:[...gaits,[a.gait,'Existing custom gait · '+a.gait]];
    const field=(label,id,value,min,max)=>`<label style="display:grid;gap:5px;flex:1;min-width:110px">${E(label)}<input id="${id}" type="number" value="${E(value)}" min="${min}" max="${max}" step="1"></label>`;
    const body=`<div id="zrecipeForm"><label>Recipe ID <input id="zrId" maxlength="48" value="${E(a.id)}" placeholder="industrial_walkers"></label><label>Display name <input id="zrLabel" maxlength="64" value="${E(a.label)}" placeholder="Industrial walkers"></label><p class="shint">The ID must be unique. Use letters, numbers, underscores or hyphens.</p><label>Ped models <textarea id="zrModels" rows="4" style="width:100%;box-sizing:border-box" placeholder="One model per line; leave empty for the default pool">${E((a.models||[]).join('\n'))}</textarea></label><p class="shint">Separate model names with new lines or commas. They are checked against the running game before any change is staged.</p><div style="display:flex;gap:12px;flex-wrap:wrap"><label>Walk style <select id="zrGait">${choices.map(g=>`<option value="${E(g[0])}" ${g[0]===a.gait?'selected':''}>${E(g[1])}</option>`).join('')}</select></label><label>Pace <select id="zrSpeed">${paces.map(p=>`<option value="${p[0]}" ${p[0]===a.speed?'selected':''}>${p[1]}</option>`).join('')}</select></label>${field('Relative weight','zrWeight',a.weight,1,100)}</div><h4>Map circles</h4><p class="shint">A recipe can appear inside any of its circles. With no circles it can appear anywhere. Coordinates use map X/Y; radius is metres.</p><div id="zrRegions"></div><button class="btn" id="zrAddRegion">Add circle</button></div>`;
    const readRegions=()=>[...document.querySelectorAll('#zrRegions [data-zcircle]')].map(row=>({x:Number(row.querySelector('[data-coordinate="x"]').value),y:Number(row.querySelector('[data-coordinate="y"]').value),radius:Number(row.querySelector('[data-coordinate="radius"]').value)}));
    function circles(){
      const box=document.getElementById('zrRegions');
      box.innerHTML=regions.map((r,i)=>`<div data-zcircle style="display:flex;gap:9px;align-items:end;flex-wrap:wrap;margin-bottom:12px">${[['x','Map X',-20000,20000],['y','Map Y',-20000,20000],['radius','Radius · m',1,10000]].map(([k,label,min,max])=>`<label style="flex:1;min-width:100px">${label}<input data-coordinate="${k}" type="number" value="${E(r[k])}" min="${min}" max="${max}" step="1" style="width:100%;box-sizing:border-box"></label>`).join('')}<button class="btn danger" data-remove-circle="${i}">Remove</button></div>`).join('');
      box.querySelectorAll('[data-remove-circle]').forEach(b=>b.onclick=()=>{regions=readRegions();regions.splice(Number(b.dataset.removeCircle),1);circles();});
    }
    async function save(){
      if(busy)return;
      const v=id=>document.getElementById(id).value.trim();
      const next={id:v('zrId'),label:v('zrLabel'),models:[...new Set(v('zrModels').split(/[\n,]+/).map(x=>x.trim()).filter(Boolean))],gait:v('zrGait'),speed:v('zrSpeed'),weight:Number(v('zrWeight')),regions:readRegions()};
      if(!/^[A-Za-z0-9_-]{1,48}$/.test(next.id)||!next.label||list.some((r,i)=>i!==index&&r.id===next.id)){ui().toast('Enter a unique recipe ID and a display name.',true);return;}
      if(next.models.length>64||next.models.some(m=>!/^[A-Za-z0-9_]{1,99}$/.test(m))){ui().toast('Use up to 64 valid ped model names.',true);return;}
      if(!Number.isInteger(next.weight)||next.weight<1||next.weight>100||!paces.some(p=>p[0]===next.speed)||!choices.some(g=>g[0]===next.gait)){ui().toast('Choose a movement style, pace and weight from 1 to 100.',true);return;}
      if(next.regions.length>32||next.regions.some(r=>![r.x,r.y,r.radius].every(Number.isFinite)||Math.abs(r.x)>20000||Math.abs(r.y)>20000||r.radius<1||r.radius>10000)){ui().toast('Check circle coordinates and radii (1–10000 metres).',true);return;}
      if(existing)list[index]=next;else list.push(next);
      busy=true;try{if(await stage(list))ui().closeModal();}finally{busy=false;}
    }
    ui().modal(existing?'Edit population recipe':'New population recipe',body,[{label:'Cancel',fn:()=>ui().closeModal()},{label:'Stage recipe',primary:true,fn:save}]);
    circles();document.getElementById('zrAddRegion').onclick=()=>{regions=readRegions();if(regions.length>=32)return ui().toast('Use at most 32 circles per recipe.',true);regions.push({x:0,y:0,radius:250});circles();};
  }
  document.addEventListener('click',async e=>{
    const b=e.target.closest('[data-zrecipe]');if(!b||!main?.contains(b))return;
    const list=recipes(),index=Number(b.dataset.index);
    if(b.dataset.zrecipe==='add'){if(list.length>=32)return ui().toast('Use at most 32 population recipes.',true);return editor();}
    if(!Number.isInteger(index)||!list[index])return;
    if(b.dataset.zrecipe==='edit')return editor(index);
    if(b.dataset.zrecipe==='remove'&&await ui().confirmBox('Remove population recipe',`Stage removal of ${list[index].label||list[index].id}? Existing zombies are not replaced immediately.`)){list.splice(index,1);await stage(list);}
  });
  function render(m){main=m;if(typeof ui().value!=='function'||typeof ui().setValue!=='function'||!ui().schema().some(s=>s.id===ID)){m.innerHTML='<div class="empty">The population schema is unavailable. Start bs_zombies and refresh F1.</div>';return;}draw();}
  window.BSConfigExt=(window.BSConfigExt||[]).concat([{id:'_ext_zombies',label:'Networked+ population',render}]);
})();

// Staff loot workbench: tables, furniture rules and bounded ground supplies.
(() => {
  'use strict';
  const ui = () => window.BSConfigUI;
  const esc = value => ui().esc(String(value ?? ''));
  const rpc = (res, action, data) => ui().rpc('ext', res, action, data);
  let root, state, tables, filter = '', section = 'tables';
  const collection = () => section==='models' ? state.rules.modelRules : state.rules[section] || state.rules.ground[section];
  const field = (id, label, value, type = 'text') => `<label>${esc(label)}</label><input id="${id}" type="${type}" value="${esc(value)}">`;
  const categoryOptions = selected => Object.keys(state.rules.categories).map(id => `<option${id === selected ? ' selected' : ''}>${esc(id)}</option>`).join('');
  const feedback = result => ui().toast(result?.ok ? 'Loot settings saved' : result?.error || 'Could not save', !result?.ok);
  async function saveRules() { const result = await rpc('bs_interactions', 'save', state.rules); feedback(result); if (result?.ok) draw(); }
  function draw() {
    if (!root || !state) return;
    root.innerHTML = `<h2 class="cat">Scavenging & supplies</h2><p class="shint">Control what each place contains. Furniture and ground supplies share depletion across players; ground supplies appear only in the main world.</p>
      <div class="card" style="padding:12px;display:flex;gap:8px;flex-wrap:wrap">${[['tables','Loot tables'],['categories','Location categories'],['models','Prop rules'],['locations','Furniture zones'],['points','Ground points'],['zones','Procedural areas']].map(([id,title]) => `<button class="btn${section===id?' primary':''}" data-loot-tab="${id}">${title}</button>`).join('')}</div>
      <div class="card" style="padding:14px"><div style="display:flex;gap:8px;align-items:center"><input id="loot-filter" placeholder="Find a table, place or prop" value="${esc(filter)}" style="flex:1"><button class="btn primary" data-loot="new">Add ${esc(section==='tables'?'table':section==='categories'?'category':section==='models'?'prop rule':section==='locations'?'furniture zone':section==='points'?'ground point':'procedural area')}</button></div><div id="loot-cards" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px;margin-top:14px"></div></div>
      <div class="card" style="padding:14px"><h4>Visible ground supplies</h4><p class="shint">Authored points and deterministic scatter inside staff-defined areas. Models are local and capped; loot ownership and refill times remain on the server.</p><label><input type="checkbox" id="loot-enabled"${state.rules.ground.enabled?' checked':''}> Enable ground supplies</label><div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px">${field('loot-cap','Maximum visible props',state.rules.ground.maxVisible,'number')}${field('loot-distance','Draw distance (m)',state.rules.ground.streamDistance,'number')}${field('loot-respawn','Refill delay (seconds)',state.rules.ground.respawn,'number')}</div><button class="btn primary" data-loot="ground">Save ground settings</button></div>`;
    const list = section==='tables' ? tables.tables : section==='categories' ? Object.entries(state.rules.categories).map(([id,table])=>({id,table})) : section==='models' ? Object.entries(state.rules.modelRules).map(([id,category])=>({id,category})) : state.rules[section] || state.rules.ground[section];
    root.querySelector('#loot-cards').innerHTML = list.filter(x=>JSON.stringify(x).toLowerCase().includes(filter.toLowerCase())).map(x=>`<div style="background:rgba(18,19,16,.7);border:1px solid #514632;padding:14px"><h4 style="margin:0 0 8px">${esc(x.id)}</h4><div class="shint">${section==='tables'?`${x.entries.length} entries · ${x.rolls.min}–${x.rolls.max} draws`:esc(x.table||x.category||'')}${x.x!==undefined?`<br>${x.x.toFixed(1)}, ${x.y.toFixed(1)}, ${x.z.toFixed(1)}`:''}</div><button class="btn" data-loot="edit" data-id="${esc(x.id)}">Edit</button>${section!=='tables'?` <button class="btn danger" data-loot="remove" data-id="${esc(x.id)}">Remove</button>`:''}</div>`).join('') || '<p class="shint">No entries yet. Add a rule to this section.</p>';
  }
  function edit(id) {
    if (section==='tables') return editTable(id);
    const list=collection();
    const current=section==='categories'?{id,table:list[id]}:section==='models'?{id,category:list[id]}:list.find(x=>x.id===id)||{};
    let form=field('loot-id',section==='models'?'GTA prop model':'Stable id',id||'');
    if(section==='categories') form+=`<label>Loot table</label><select id="loot-table">${tables.tables.map(t=>`<option${t.id===current.table?' selected':''}>${esc(t.id)}</option>`).join('')}</select>`;
    else form+=`<label>Category</label><select id="loot-category">${categoryOptions(current.category)}</select>`;
    if(!['categories','models'].includes(section)) {
      form+=`<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">${['x','y','z'].map(k=>field('loot-'+k,k.toUpperCase(),current[k]??0,'number')).join('')}</div>`;
      if(section!=='points') form+=field('loot-radius','Radius (m)',current.radius||2,'number');
      if(section==='zones') form+=field('loot-count','Number of supplies (1–16)',current.count||4,'number');
    }
    ui().modal(id?'Edit '+id:'Add '+section,form,[{label:'Cancel',fn:()=>ui().closeModal()},{label:'Save',primary:true,fn:async()=>{
      const v=k=>document.getElementById('loot-'+k).value;
      const nextId=v('id').trim();
      if(!/^[\w-]{1,64}$/.test(nextId)) return ui().toast('Use a short id with letters, numbers and underscores',true);
      if(section==='categories') {if(id&&id!==nextId) delete list[id];list[nextId]=v('table');}
      else if(section==='models'){if(id&&id!==nextId) delete list[id];list[nextId]=v('category');}
      else {const p={id:nextId,category:v('category'),x:Number(v('x')),y:Number(v('y')),z:Number(v('z'))};if(section!=='points')p.radius=Number(v('radius'));if(section==='zones')p.count=Number(v('count'));const index=list.findIndex(p=>p.id===id);if(index<0)list.push(p);else list[index]=p;}
      ui().closeModal();await saveRules();
    }}]);
  }
  function editTable(id) {
    const t=tables.tables.find(t=>t.id===id)||{rolls:{min:0,max:2},entries:[]};
    ui().modal(id?'Edit '+id:'New loot table',`${field('loot-tableid','Table id',id||'')}<div style="display:flex;gap:10px">${field('loot-min','Minimum draws',t.rolls.min,'number')}${field('loot-max','Maximum draws',t.rolls.max,'number')}</div><label>Entries</label><p class="shint">One item per line: item, minimum amount, maximum amount, weight. Larger weights appear more often.</p><textarea id="loot-entries" style="width:100%;min-height:240px">${esc(t.entries.map(e=>[e.item,...e.amount,e.weight].join(', ')).join('\n'))}</textarea><p class="shint">Existing item names only. Maximum 20 draws and 128 entries.</p>`,[{label:'Cancel',fn:()=>ui().closeModal()},{label:'Save table',primary:true,fn:async()=>{
      const value=k=>document.getElementById('loot-'+k).value;
      const entries=value('entries').split('\n').map(x=>x.trim()).filter(Boolean).map(line=>{const [item,min,max,weight]=line.split(',').map(x=>x.trim());return{item,amount:[Number(min),Number(max)],weight:Number(weight)};});
      const result=await rpc('bs_economy','save',{id:value('tableid'),table:{rolls:{min:Number(value('min')),max:Number(value('max'))},entries}});feedback(result);
      if(result?.ok){ui().closeModal();tables=await rpc('bs_economy','get');draw();}
    }}]);
  }
  document.addEventListener('click',async event=>{
    if(!root?.contains(event.target)) return;
    const tab=event.target.closest('[data-loot-tab]');if(tab){section=tab.dataset.lootTab;filter='';draw();return;}
    const button=event.target.closest('[data-loot]');if(!button)return;
    const action=button.dataset.loot,id=button.dataset.id;
    if(action==='edit'||action==='new')edit(action==='edit'?id:undefined);
    if(action==='remove') {const list=collection();if(['models','categories'].includes(section))delete list[id];else list.splice(list.findIndex(x=>x.id===id),1);await saveRules();}
    if(action==='ground'){const g=state.rules.ground;g.enabled=document.getElementById('loot-enabled').checked;g.maxVisible=Number(document.getElementById('loot-cap').value);g.streamDistance=Number(document.getElementById('loot-distance').value);g.respawn=Number(document.getElementById('loot-respawn').value);await saveRules();}
  });
  document.addEventListener('input',event=>{if(event.target.id==='loot-filter'){filter=event.target.value;const pos=event.target.selectionStart;draw();const input=document.getElementById('loot-filter');input.focus();input.setSelectionRange(pos,pos);}});
  window.BSConfigExt=(window.BSConfigExt||[]).concat([{id:'_ext_loot',label:'Scavenging & loot',render:async main=>{
    root=main;main.innerHTML='<p class="shint">Loading supplies…</p>';
    [state,tables]=await Promise.all([rpc('bs_interactions','get'),rpc('bs_economy','get')]);
    if(!state?.ok||!tables?.ok){main.innerHTML='<p class="shint">Loot editor unavailable. Start interactions and economy first.</p>';return;}draw();
  }}]);
})();

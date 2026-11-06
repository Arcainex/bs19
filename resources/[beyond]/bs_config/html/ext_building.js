// Building recipes stage changes through the standard F1 Apply workflow.
(() => {
  'use strict';
  const ui=()=>window.BSConfigUI, E=v=>ui().esc(String(v??''));
  const COST='bs_building:Building.Settings.costOverrides', MODE='bs_building:Building.Settings.constructionMode';
  let root, catalogue, query='', selected='', tier='base';
  const clone=v=>JSON.parse(JSON.stringify(v??{}));
  function overrides(){return clone(ui().value(COST)||{});}
  function piece(){return catalogue.pieces.find(p=>p.id===selected);}
  function rows(){const p=piece(),all=overrides();return all[p.id]?.[tier]||p.tiers.find(t=>t.id===tier)?.cost||{};}
  function stage(value){ui().setValue(COST,value);draw();ui().toast('Material changes staged. Use Apply to save.');}
  function draw(){
    const p=piece();if(!p)return;
    const filtered=catalogue.pieces.filter(p=>(p.id+' '+p.label).toLowerCase().includes(query.toLowerCase()));
    const custom=overrides()[p.id]?.[tier];
    root.innerHTML=`<h2 class="cat">Building materials</h2><p class="shint">Choose a piece and tier, then adjust its materials. Existing plans keep their original material quote. Changes use the current F1 profile and Apply action.</p>
      <div class="card" style="padding:14px"><label>Construction method</label><select id="bc-mode">${[['mixed','Small objects directly; structures as plans'],['direct','All pieces placed directly'],['blueprint','All pieces require material plans']].map(([id,label])=>`<option value="${id}"${ui().value(MODE)===id?' selected':''}>${label}</option>`).join('')}</select></div>
      <div style="display:grid;grid-template-columns:minmax(180px,30%) minmax(0,1fr);gap:14px"><div class="card" style="padding:12px"><input id="bc-search" placeholder="Find a piece" value="${E(query)}" style="width:100%"><div style="max-height:440px;overflow:auto;margin-top:10px">${filtered.map(x=>`<button class="btn${x.id===p.id?' primary':''}" data-bc-piece="${E(x.id)}" style="display:block;width:100%;margin:4px 0;text-align:left">${E(x.label)}</button>`).join('')||'<p class="shint">No matching pieces</p>'}</div></div>
      <div class="card" style="padding:14px"><h4>${E(p.label)}</h4><label>Material tier</label><select id="bc-tier">${p.tiers.map(t=>`<option value="${E(t.id)}"${tier===t.id?' selected':''}>${E(t.label)}</option>`).join('')}</select><p class="shint">${custom?'Custom recipe staged or applied':'Configured default recipe'} · Cost multiplier ${E(catalogue.costScale)} applies afterward.</p>
      <table class="audit"><thead><tr><th>Material</th><th>Quantity</th><th></th></tr></thead><tbody>${Object.entries(rows()).map(([item,qty])=>`<tr><td>${E(catalogue.items.find(i=>i.id===item)?.label||item)}<br><small class="k">${E(item)}</small></td><td><input type="number" min="1" max="100000" step="1" data-bc-quantity="${E(item)}" value="${E(qty)}" style="width:100px"></td><td><button class="btn danger" data-bc-remove="${E(item)}">Remove</button></td></tr>`).join('')}</tbody></table>
      <div style="display:flex;gap:8px;margin-top:12px"><select id="bc-item" style="flex:1">${catalogue.items.filter(i=>!Object.hasOwn(rows(),i.id)).map(i=>`<option value="${E(i.id)}">${E(i.label)} (${E(i.id)})</option>`).join('')}</select><input id="bc-new-quantity" type="number" value="1" min="1" max="100000" step="1" style="width:90px"><button class="btn" data-bc="add">Add material</button></div><div class="mBtns"><button class="btn" data-bc="reset">Reset this tier</button><button class="btn" data-bc="reset-piece">Reset all tiers for this piece</button></div></div></div>`;
  }
  function update(item,qty,remove=false){
    if(!remove&&(!Number.isInteger(qty)||qty<1||qty>100000))return ui().toast('Use a whole quantity from 1 to 100000',true);
    const p=piece(),value=overrides(),recipe=clone(rows());
    if(remove)delete recipe[item];else recipe[item]=qty;
    if(!Object.keys(recipe).length)return ui().toast('A recipe needs at least one material. Use Reset to restore defaults.',true);
    if(Object.keys(recipe).length>32)return ui().toast('Use at most 32 materials',true);
    value[p.id]??={};value[p.id][tier]=recipe;stage(value);
  }
  document.addEventListener('click',event=>{
    if(!root?.contains(event.target))return;
    const pick=event.target.closest('[data-bc-piece]');if(pick){selected=pick.dataset.bcPiece;tier=piece().tiers[0].id;draw();return;}
    const remove=event.target.closest('[data-bc-remove]');if(remove){update(remove.dataset.bcRemove,0,true);return;}
    const action=event.target.closest('[data-bc]')?.dataset.bc;if(!action)return;
    if(action==='add'){const item=document.getElementById('bc-item').value;if(item)update(item,Number(document.getElementById('bc-new-quantity').value));return;}
    const value=overrides(),id=piece().id;
    if(action==='reset') {if(value[id]){delete value[id][tier];if(!Object.keys(value[id]).length)delete value[id];}}
    if(action==='reset-piece')delete value[id];stage(value);
  });
  document.addEventListener('change',event=>{
    if(!root?.contains(event.target))return;
    if(event.target.id==='bc-mode'){ui().setValue(MODE,event.target.value);ui().toast('Construction method staged. Use Apply to save.');}
    if(event.target.id==='bc-tier'){tier=event.target.value;draw();}
    if(event.target.dataset.bcQuantity)update(event.target.dataset.bcQuantity,Number(event.target.value));
  });
  document.addEventListener('input',event=>{if(event.target.id==='bc-search'){query=event.target.value;const at=event.target.selectionStart;draw();const input=document.getElementById('bc-search');input.focus();input.setSelectionRange(at,at);}});
  window.BSConfigExt=(window.BSConfigExt||[]).concat([{id:'_ext_building',label:'Building materials',render:async main=>{
    root=main;main.innerHTML='<p class="shint">Loading building catalogue…</p>';
    catalogue=await ui().rpc('ext','bs_building','get');
    if(!catalogue?.ok||!catalogue.pieces.length){main.innerHTML='<p class="shint">Building catalogue unavailable</p>';return;}
    if(!piece()){selected=catalogue.pieces[0].id;tier=piece().tiers[0].id;}draw();
  }}]);
})();

// ALPHA-Z F10 Crafting & Food Studio. Uses authoritative server storage only.
(() => {
  'use strict';
  const $=id=>document.getElementById(id), pane=$('cePane'); if(!pane)return;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const S={tab:'recipes',recipes:[],foods:[],stations:[],items:[],categories:[],id:null,fresh:false,loading:false};
  let popup=null;
  const txt=id=>String($(id)?.value??'').trim(), num=id=>Number($(id)?.value);
  const itemName=id=>S.items.find(x=>x.id===id)?.label||id||'';
  const stationName=id=>S.stations.find(x=>x.id===id)?.label||(!id?'Von Hand':id);
  const labelOf=x=>S.tab==='recipes'?(x.recipe?.label||itemName(x.recipe?.result?.item)||x.id):x.label||x.id;
  const groupOf=x=>S.tab==='recipes'?stationName(x.recipe?.station):S.tab==='foods'?(x.category==='drink'?'GETRÄNKE':'NAHRUNG'):'CRAFTING-STATIONEN';
  const entries=()=>S.tab==='recipes'?S.recipes:S.tab==='foods'?S.foods:S.stations;
  const entry=()=>entries().find(x=>x.id===S.id);
  function message(s='',error=false){$('ceFeedback').textContent=s;$('ceFeedback').classList.toggle('is-error',error);}
  function busy(on,caption='Lade …'){S.loading=on;$('ceBusy').hidden=!on;$('ceBusyText').textContent=caption;$('ceRefresh').disabled=on;}
  async function api(action,args={}){try{
    const res=await fetch(`https://${GetParentResourceName()}/server`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,args})});
    if(!res.ok)throw Error('HTTP '+res.status);return await res.json()||{ok:false,error:'Keine Antwort'};
  }catch(e){return {ok:false,error:'Verbindung: '+e.message};}}
  function closePop(){if(popup){popup.remove();popup=null;}}
  function picker(root,initial,onSelect,choices=S.items){
    let selected=initial||'';const button=document.createElement('button');button.type='button';button.className='ce-pick';
    function paint(){button.innerHTML=`<span>${esc(choices.find(x=>x.id===selected)?.label||selected||'ITEM AUSWÄHLEN')}</span><small>${esc(selected||'WÄHLEN')} ▾</small>`;}
    button.onclick=()=>{
      closePop();const box=document.createElement('div');box.className='ce-popover';
      const search=document.createElement('input');search.placeholder='Item suchen …';search.type='search';search.autocomplete='off';
      const results=document.createElement('div');results.className='ce-popover-list';box.append(search,results);document.body.append(box);popup=box;
      const r=button.getBoundingClientRect(),w=Math.min(410,Math.max(275,r.width+75)),h=Math.min(310,Math.max(150,innerHeight*.42));
      box.style.width=w+'px';box.style.left=Math.max(8,Math.min(innerWidth-w-8,r.left))+'px';
      box.style.maxHeight=h+'px';box.style.top=(innerHeight-r.bottom>=h||innerHeight-r.bottom>=r.top?Math.min(innerHeight-h-8,r.bottom+4):Math.max(8,r.top-h-4))+'px';
      function draw(){const q=search.value.toLowerCase();results.replaceChildren();
        const candidates=choices.filter(c=>!q||c.id.toLowerCase().includes(q)||(c.label||'').toLowerCase().includes(q)).slice(0,100);
        for(const c of candidates){const b=document.createElement('button');b.type='button';b.className='ce-option';
          const strong=document.createElement('strong');strong.textContent=c.label||c.id;
          const small=document.createElement('small');small.textContent=c.id;b.append(strong,small);
          b.onclick=()=>{selected=c.id;onSelect(selected);paint();closePop();};results.append(b);}
        if(!candidates.length){const note=document.createElement('p');note.textContent='Kein Item gefunden';results.append(note);}
      }
      search.oninput=draw;search.onkeydown=e=>{if(e.key==='Escape'){e.stopPropagation();closePop();}if(e.key==='Enter'){e.preventDefault();results.querySelector('button')?.click();}};
      draw();search.focus();
      const outside=e=>{if(box!==popup){document.removeEventListener('pointerdown',outside,true);return;}if(!box.contains(e.target)&&!button.contains(e.target)){closePop();document.removeEventListener('pointerdown',outside,true);}};
      setTimeout(()=>document.addEventListener('pointerdown',outside,true),0);
    };
    root.replaceChildren(button);paint();
  }
  function list(){
    const q=txt('ceSearch').toLowerCase(), groups=new Map(), box=$('ceList');box.replaceChildren();
    if(S.fresh){const b=document.createElement('button');b.className='ce-entry is-selected';b.textContent='＋ NEUER EINTRAG';b.onclick=()=>editor();box.append(b);}
    for(const x of entries()){
      const name=labelOf(x),grp=groupOf(x);
      if(q&&!`${x.id} ${name} ${grp} ${x.recipe?.station||''}`.toLowerCase().includes(q))continue;
      if(!groups.has(grp))groups.set(grp,[]);groups.get(grp).push(x);
    }
    if(!groups.size){const n=document.createElement('p');n.className='ce-muted';n.textContent='Keine Einträge gefunden';box.append(n);}
    for(const [group,values] of [...groups].sort((a,b)=>a[0].localeCompare(b[0],'de'))){
      const details=document.createElement('details');details.className='ce-group';details.open=true;
      const summary=document.createElement('summary');const t=document.createElement('span');t.textContent=group;
      const count=document.createElement('small');count.textContent=values.length;summary.append(t,count);details.append(summary);
      for(const x of values.sort((a,b)=>labelOf(a).localeCompare(labelOf(b),'de'))){
        const b=document.createElement('button');b.type='button';b.className='ce-entry'+(x.id===S.id&&!S.fresh?' is-selected':'');
        const dot=document.createElement('i');dot.className='ce-dot '+(x.disabled?'ce-disabled':x.custom?'ce-custom':x.edited?'ce-edited':'ce-original');
        const name=document.createElement('span');name.className='ce-entry-main';const strong=document.createElement('strong');strong.textContent=labelOf(x);
        const small=document.createElement('small');small.textContent=x.id;name.append(strong,small);b.append(dot,name);
        if(x.disabled){const badge=document.createElement('em');badge.textContent='AUS';badge.className='ce-entry-badge';b.append(badge);}
        b.onclick=()=>{S.id=x.id;S.fresh=false;list();editor();};details.append(b);
      }
      box.append(details);
    }
  }
  function field(label,html,note=''){return `<label class="ce-field"><span>${esc(label)}</span>${html}${note?`<small>${esc(note)}</small>`:''}</label>`;}
  function nfield(id,v,min,max,step=1){return `<input type="number" id="${id}" min="${min}" max="${max}" step="${step}" value="${esc(v)}">`;}
  function ingredient(parent,item='',amount=1,tool=false){
    const row=document.createElement('div');row.className='ce-cost-row';row.dataset.item=item;
    const holder=document.createElement('div');holder.className='ce-pick-wrap';picker(holder,item,v=>row.dataset.item=v);
    const n=tool?document.createElement('span'):document.createElement('input');
    if(tool){n.textContent='nicht verbraucht';n.className='ce-tool-note';}
    else{n.type='number';n.className='ce-cost-amount';n.min=1;n.max=999;n.step=1;n.value=amount;}
    const del=document.createElement('button');del.type='button';del.className='ce-remove';del.textContent='×';del.title='Entfernen';del.onclick=()=>row.remove();
    row.append(holder,n,del);parent.append(row);
  }
  function ingredients(selector,tool=false){return [...document.querySelectorAll(selector+' .ce-cost-row')].map(row=>({item:row.dataset.item,amount:tool?1:Number(row.querySelector('input')?.value)}));}
  function recipeForm(x){
    const r=x?.recipe||{},fresh=S.fresh,stations=[{id:'',label:'Von Hand'},...S.stations];
    const choices=S.categories.length?S.categories:['food','water','materials','misc'];
    $('ceEditor').innerHTML=`<div class="ce-title"><div><h3>${fresh?'＋ NEUES REZEPT':esc(labelOf(x))}</h3><p>${esc(x?.id||'Neue Definition')}</p></div><span class="ce-tag ${x?.custom?'ce-tag-custom':x?.edited?'ce-tag-edited':''}">${fresh?'NEU':x?.custom?'NEU':x?.edited?'ANGEPASST':'ORIGINAL'}</span></div>
      <div class="ce-form-grid">
        ${field('Rezept-ID',`<input id="ceRecipeId" maxlength="48" value="${esc(x?.id||'')}" ${fresh?'':'readonly'} placeholder="herb_steak">`,'Nur Kleinbuchstaben, Zahlen und _')}
        ${field('Rezeptname',`<input id="ceRecipeLabel" maxlength="48" value="${esc(r.label||'')}" placeholder="Kräutersteak">`)}
        ${field('Kategorie',`<select id="ceRecipeCat">${choices.map(c=>`<option value="${esc(c)}" ${c===(r.cat||'food')?'selected':''}>${esc(c.toUpperCase())}</option>`).join('')}</select>`)}
        ${field('Station',`<select id="ceRecipeStation">${stations.map(s=>`<option value="${esc(s.id)}" ${s.id===(r.station||'')?'selected':''}>${esc(s.label)}</option>`).join('')}</select>`)}
        ${field('Dauer (Sek.)',nfield('ceRecipeTime',r.time??30,1,3600))}
        ${field('Ergebnismenge',nfield('ceRecipeAmount',r.result?.amount??1,1,100))}
      </div>
      <section class="ce-card"><div class="ce-section-head"><strong>ERGEBNIS</strong><small>Vorhandenes Inventaritem</small></div><div id="ceResult" class="ce-pick-wrap"></div></section>
      <section class="ce-card"><div class="ce-section-head"><strong>ZUTATEN</strong><button type="button" id="ceCostAdd">＋ ZUTAT</button></div><div id="ceCosts"></div><p class="ce-hint">Bis zu 8 Zutaten, Verbrauch pro Herstellung.</p></section>
      <details class="ce-card ce-advanced"><summary>WEITERE EINSTELLUNGEN</summary><div class="ce-section-head"><strong>ALTERNATIVE WERKZEUGE</strong><button type="button" id="ceToolAdd">＋ WERKZEUG</button></div><div id="ceTools"></div><p class="ce-hint">Eines dieser Werkzeuge muss vorhanden sein.</p><div class="ce-section-head"><strong>VERBRANNTES ERGEBNIS</strong></div><div id="ceBurn" class="ce-pick-wrap"></div><label class="ce-checkbox"><input type="checkbox" id="ceExplosive" ${r.explosive?'checked':''}> Explosiv-Rezept</label><label class="ce-checkbox"><input type="checkbox" id="ceFaction" ${r.factionBase?'checked':''}> Nur in Fraktionsbasis</label></details>
      <footer class="ce-actions"><button type="button" class="ce-primary" id="ceRecipeSave">REZEPT SPEICHERN</button>${fresh?'':`<button type="button" class="ce-warning" id="ceRecipeDisable" ${x?.disabled?'disabled':''}>DEAKTIVIEREN</button>`}${!fresh&&x?.custom?'<button type="button" id="ceRecipeDelete" class="ce-danger">REZEPT LÖSCHEN</button>':''}${!fresh&&x?.edited&&!x?.custom?'<button type="button" id="ceRecipeReset" class="ce-danger">ZURÜCKSETZEN</button>':''}</footer>`;
    let result=r.result?.item||'',burn=r.burn||'';
    picker($('ceResult'),result,v=>result=v);
    picker($('ceBurn'),burn,v=>burn=v,[{id:'',label:'Keines'},...S.items]);
    for(const c of r.cost||[])ingredient($('ceCosts'),c.item,c.amount);
    if(!$('ceCosts').children.length)ingredient($('ceCosts'));
    for(const t of r.tool||[])ingredient($('ceTools'),t,1,true);
    $('ceCostAdd').onclick=()=>{if($('ceCosts').children.length<8)ingredient($('ceCosts'));else message('Maximal acht Zutaten.',true);};
    $('ceToolAdd').onclick=()=>{if($('ceTools').children.length<6)ingredient($('ceTools'),'',1,true);else message('Maximal sechs Werkzeuge.',true);};
    $('ceRecipeSave').onclick=async()=>{
      const id=txt('ceRecipeId').toLowerCase(),cost=ingredients('#ceCosts'),tools=ingredients('#ceTools',true).map(t=>t.item),time=num('ceRecipeTime'),amount=num('ceRecipeAmount');
      if(!/^[a-z][a-z0-9_]{1,47}$/.test(id)){message('Rezept-ID ungültig.',true);return;}
      if(fresh&&S.recipes.some(r=>r.id===id)){message('Rezept-ID bereits vorhanden.',true);return;}
      if(!result||!cost.length||cost.some(c=>!c.item||!Number.isInteger(c.amount)||c.amount<1||c.amount>999)||tools.some(t=>!t)||!Number.isInteger(time)||time<1||time>3600||!Number.isInteger(amount)||amount<1||amount>100){message('Ergebnis, Zutaten, Mengen und Zeit prüfen.',true);return;}
      await change('craftSave',{id,recipe:{label:txt('ceRecipeLabel'),cat:$('ceRecipeCat').value,station:$('ceRecipeStation').value||null,time,result:{item:result,amount},cost,tool:tools,burn:burn||null,explosive:$('ceExplosive').checked,factionBase:$('ceFaction').checked}},'Rezept gespeichert.',()=>{S.id=id;S.fresh=false;});
    };
    if(!fresh){$('ceRecipeDisable').onclick=async()=>{if(await ask('REZEPT DEAKTIVIEREN','Dieses Rezept wird für Spieler ausgeblendet.'))await change('craftDisable',{id:x.id},'Rezept deaktiviert.');};
      if($('ceRecipeReset'))$('ceRecipeReset').onclick=async()=>{if(await ask('REZEPT ZURÜCKSETZEN','Anpassungen verwerfen und Original wiederherstellen?'))await change('craftReset',{id:x.id},'Rezept zurückgesetzt.');};
      if($('ceRecipeDelete'))$('ceRecipeDelete').onclick=async()=>{if(await ask('EIGENES REZEPT LÖSCHEN',`„${x.id}“ dauerhaft aus der Rezeptverwaltung entfernen?`))await change('craftDelete',{id:x.id},'Eigenes Rezept gelöscht.',()=>{S.id=null;});};
    }
  }
  function foodForm(x){
    const fresh=S.fresh,v=x||{};
    $('ceEditor').innerHTML=`<div class="ce-title"><div><h3>${fresh?'＋ NEUES LEBENSMITTEL':esc(v.label)}</h3><p>${esc(v.id||'Neue Definition')}</p></div><span class="ce-tag ${v.custom?'ce-tag-custom':v.edited?'ce-tag-edited':''}">${fresh?'NEU':v.custom?'EIGENES ITEM':v.edited?'ANGEPASST':'ORIGINAL'}</span></div>
      <div class="ce-form-grid">
        ${field('Item-ID',`<input id="ceFoodId" maxlength="48" placeholder="beef_jerky" value="${esc(v.id||'')}" ${fresh?'':'readonly'}>`)}
        ${field('Name',`<input id="ceFoodName" maxlength="60" placeholder="Beef Jerky" value="${esc(v.label||'')}">`)}
        ${field('Gewicht (kg)',nfield('ceWeight',v.weight??0.25,0.01,25,.01))}
        ${field('Stapelgrösse',nfield('ceStack',v.stack??10,1,100))}
        ${field('Hunger +',nfield('ceHunger',v.hunger??30,0,100))}
        ${field('Durst +',nfield('ceThirst',v.thirst??0,0,100))}
        ${field('Basiswert',nfield('ceValue',v.value??10,0,10000))}
      </div>
      <section class="ce-card"><div class="ce-section-head"><strong>ICON</strong><small>Automatisch oder vorhandenes Symbol</small></div><div id="ceFoodIcon" class="ce-pick-wrap"></div><p class="ce-hint">Standard: neutrales Nahrungssymbol statt des Icons eines anderen Gerichts. Optional ein vorhandenes Symbol wählen. Eigene PNG-Uploads folgen später.</p></section>
      <footer class="ce-actions"><button type="button" class="ce-primary" id="ceFoodSave">LEBENSMITTEL SPEICHERN</button>${!fresh&&v.edited&&!v.custom?'<button type="button" class="ce-danger" id="ceFoodReset">ORIGINAL WIEDERHERSTELLEN</button>':''}${!fresh&&v.custom?'<button type="button" class="ce-danger" id="ceFoodDelete">LEBENSMITTEL LÖSCHEN</button>':''}</footer>${!fresh&&v.custom?'<p class="ce-hint ce-delete-hint">Löschen ist nur möglich, wenn das Item in keinem Inventar liegt und kein Rezept es benutzt. Es werden keine Spieleritems stillschweigend entfernt.</p>':''}`;
    let icon=v.icon||(fresh?'':v.id);
    picker($('ceFoodIcon'),icon,v=>icon=v,[{id:'',label:'Automatisch (Standardsymbol)'},...S.items]);
    $('ceFoodSave').onclick=async()=>{
      const id=txt('ceFoodId').toLowerCase(),payload={id,label:txt('ceFoodName'),weight:num('ceWeight'),stack:num('ceStack'),hunger:num('ceHunger'),thirst:num('ceThirst'),value:num('ceValue'),icon:icon||id};
      if(!/^[a-z][a-z0-9_]{1,47}$/.test(id)||fresh&&S.items.some(x=>x.id===id)){message('Item-ID ungültig oder bereits vergeben.',true);return;}
      if(payload.label.length<2||payload.weight<.01||payload.weight>25||!Number.isInteger(payload.stack)||payload.stack<1||payload.stack>100||payload.hunger<0||payload.hunger>100||payload.thirst<0||payload.thirst>100||payload.value<0||payload.value>10000||!payload.icon){message('Lebensmittelwerte prüfen.',true);return;}
      await change('foodSave',payload,'Lebensmittel gespeichert.',()=>{S.id=id;S.fresh=false;});
    };
    if($('ceFoodReset'))$('ceFoodReset').onclick=async()=>{if(await ask('ORIGINAL WIEDERHERSTELLEN','Alle Anpassungen dieses vorhandenen Items zurücksetzen?'))await change('foodReset',{id:v.id},'Original wiederhergestellt.');};
    if($('ceFoodDelete'))$('ceFoodDelete').onclick=async()=>{
      if(await ask('EIGENES LEBENSMITTEL LÖSCHEN',`„${v.label}“ (${v.id}) dauerhaft entfernen? Vorhandene Spieleritems und Rezepte sind geschützt.`))
        await change('foodDelete',{id:v.id},'Eigenes Lebensmittel gelöscht.',()=>{S.id=null;});
    };
  }
  function stationForm(x){$('ceEditor').innerHTML=x?`<div class="ce-title"><div><h3>${esc(x.label||x.id)}</h3><p>${esc(x.id)}</p></div><span class="ce-tag">BESTEHEND</span></div><section class="ce-card"><strong>STATIONSKONFIGURATION</strong><p class="ce-muted">Diese Station wird durch bs_crafting und bs_building gesteuert. Zur Sicherheit werden Modell, Kapazität und Bauwerte hier noch nicht geschrieben. Eine dafür geeignete Live-Speicherschnittstelle kommt mit den Stationsmechaniken.</p><p class="ce-hint">Rezepte können bereits im Rezepteditor dieser Station zugeordnet werden.</p></section><button type="button" id="ceShowRecipes" class="ce-primary">REZEPTE ANZEIGEN</button>`:'<p class="ce-muted">Station auswählen.</p>';
    if(x)$('ceShowRecipes').onclick=()=>{switchTab('recipes');$('ceSearch').value=x.id;list();};}
  function editor(){closePop();message();const x=entry();if(S.tab==='stations'){stationForm(x);return;}
    if(!x&&!S.fresh){$('ceEditor').innerHTML='<div class="ce-placeholder"><strong>Eintrag auswählen</strong><p>Links einen Eintrag wählen oder ＋ drücken.</p></div>';return;}
    if(S.tab==='recipes')recipeForm(x);else foodForm(x);
  }
  function switchTab(tab){S.tab=tab;S.id=null;S.fresh=false;$('ceSearch').value='';$('ceNew').hidden=tab==='stations';
    pane.querySelectorAll('[data-ce-tab]').forEach(b=>b.classList.toggle('is-on',b.dataset.ceTab===tab));list();editor();}
  async function load(){if(S.loading)return;closePop();busy(true,'Lade Rezepte und Lebensmittel …');
    const [craft,foods]=await Promise.all([api('craftState'),api('foodState')]);busy(false);
    if(!craft?.ok||!foods?.ok){message('Laden fehlgeschlagen: '+(craft?.error||foods?.error||'Keine Antwort'),true);return;}
    S.recipes=craft.recipes||[];S.items=craft.items||[];S.stations=craft.stations||[];S.categories=craft.categories||[];S.foods=foods.foods||[];
    if(S.id&&!entry()&&!S.fresh)S.id=null;list();editor();
  }
  async function change(action,args,success,done){if(S.loading)return;closePop();busy(true,'Speichere …');
    const result=await api(action,args);busy(false);if(!result?.ok){message(result?.error||'Speichern fehlgeschlagen.',true);return;}
    done?.();await load();message(success);
  }
  function ask(title,body){return new Promise(resolve=>{const overlay=$('ceConfirm');overlay.hidden=false;$('ceConfirmTitle').textContent=title;$('ceConfirmText').textContent=body;
    const finish=v=>{overlay.hidden=true;$('ceConfirmYes').onclick=null;$('ceConfirmCancel').onclick=null;resolve(v);};
    $('ceConfirmYes').onclick=()=>finish(true);$('ceConfirmCancel').onclick=()=>finish(false);$('ceConfirmCancel').focus();});}
  $('ceRefresh').onclick=load;$('ceSearch').oninput=list;$('ceNew').onclick=()=>{S.id=null;S.fresh=true;list();editor();};
  pane.querySelectorAll('[data-ce-tab]').forEach(b=>b.onclick=()=>switchTab(b.dataset.ceTab));
  document.querySelector('.mtab[data-tab="crafting"]')?.addEventListener('click',load);
  window.addEventListener('message',e=>{if(e.data?.action==='close')closePop();});
  switchTab('recipes');
})();

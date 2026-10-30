// BS19 Prop Editor v6. Only catalogue UI; the existing 3D gizmo and F2 pipeline are unchanged.
(() => {
  const $ = id => document.getElementById(id);
  const builtin = {structure:'Struktur',openings:'Öffnungen',defense:'Verteidigung',utility:'Utility',claim:'Claim'};
  let categories={...builtin}, entries=[], selected=null, filter='all', tab='existing';
  const expanded=new Set(), logs=[];
  const slug=s=>s.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'_').replace(/^_+|_+$/g,'').replace(/^[^a-z]+/,'prop_').slice(0,48);
  function activate(name){tab=name;document.querySelectorAll('#psRailSub [data-ps-tab]').forEach(b=>b.classList.toggle('is-active',b.dataset.psTab===name));document.querySelectorAll('#psPane [data-ps-section]').forEach(s=>s.hidden=s.dataset.psSection!==name);if(name==='debug')$('psErrorBadge').hidden=true;if(name==='placed')reloadPlaced();}
  function log(msg,error=false){const line=`[${new Date().toLocaleTimeString('de-DE')}] ${error?'FEHLER':'INFO'}: ${String(msg)}`;logs.push(line);if(logs.length>200)logs.shift();$('psDebugLog').textContent=logs.join('\n');if(error){$('psErrorBadge').hidden=false;activate('debug');}}
  function status(msg,error=false){$('psStatus').textContent=msg;$('psStatus').style.color=error?'#ff9288':'#b8e6c3';log(msg,error);}
  async function call(action,payload){try{const response=await fetch(`https://${GetParentResourceName()}/propStudio`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,payload,id:payload?.id})});return await response.json();}catch(e){return {ok:false,error:'Verbindung fehlgeschlagen: '+e.message};}}
  function dialog(title,body,extra){return new Promise(resolve=>{const d=$('psDialog');$('psDialogTitle').textContent=title;$('psDialogText').textContent=body;const x=$('psDialogExtra');x.replaceChildren();if(extra)x.append(extra);d.hidden=false;const finish=answer=>{d.hidden=true;$('psDialogConfirm').onclick=null;$('psDialogCancel').onclick=null;resolve(answer);};$('psDialogConfirm').onclick=()=>finish(true);$('psDialogCancel').onclick=()=>finish(false);$('psDialogCancel').focus();});}
  function categorySelect(){const select=$('psCat'),current=select.value;select.replaceChildren();for(const [key,label] of Object.entries(categories)){const o=document.createElement('option');o.value=key;o.textContent=label;select.append(o);}if(categories[current])select.value=current;}
  function badge(p){return p.disabled?'DEAKTIVIERT':p.isNew?(p.modified?'BEARBEITET':p.tested?'ORIGINAL':'NICHT GETESTET'):(p.modified?'ANGEPASST':'ORIGINAL');}
  function matchesFilter(p){return filter==='all'||(filter==='disabled'?p.disabled:filter==='custom'?p.isNew:!p.isNew);}
  function render(){
    const search=$('psSearch').value.trim().toLocaleLowerCase('de-DE');
    const list=$('psList');list.replaceChildren();
    const matched=entries.filter(p=>matchesFilter(p)&&`${p.id} ${p.label} ${(p.models||[]).join(' ')} ${categories[p.cat]||p.cat}`.toLocaleLowerCase('de-DE').includes(search));
    const grouped=new Map();for(const p of matched){const cat=p.cat||'utility';if(!grouped.has(cat))grouped.set(cat,[]);grouped.get(cat).push(p);}
    for(const [cat,props] of [...grouped.entries()].sort((a,b)=>(categories[a[0]]||a[0]).localeCompare(categories[b[0]]||b[0],'de'))){
      const group=document.createElement('details');group.className='ps-category';group.open=!!search||expanded.has(cat);
      group.addEventListener('toggle',()=>{if(search)return;group.open?expanded.add(cat):expanded.delete(cat);});
      const head=document.createElement('summary');head.setAttribute('aria-label',`${categories[cat]||cat}, ${props.length} Props, Kategorie auf- oder zuklappen`);const arrow=document.createElement('span');arrow.className='ps-category-arrow';arrow.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent=`${categories[cat]||cat}  ·  ${props.length}`;head.append(arrow,label);group.append(head);
      const content=document.createElement('div');content.className='ps-category-items';
      for(const p of props.sort((a,b)=>(a.label||a.id).localeCompare(b.label||b.id,'de'))){
        const row=document.createElement('div');row.className='ps-prop-row';
        const info=document.createElement('div');info.className='ps-prop-info';
        const title=document.createElement('strong');title.textContent=p.label||p.id;
        const detail=document.createElement('small');detail.textContent=`${p.id} · ${(p.models||[])[0]||'Kein Modell'}`;
        const state=document.createElement('small');state.className='ps-state '+(p.disabled?'is-disabled':p.isNew&&!p.tested?'is-untested':p.isNew&&p.modified?'is-new':p.modified?'is-custom':'is-original');state.textContent=badge(p);
        info.append(title,detail,state);
        const actions=document.createElement('div');actions.className='ps-inline-actions';
        const button=(label,fn,cls='')=>{const el=document.createElement('button');el.type='button';el.className='ps-prop-action '+cls;el.textContent=label;el.onclick=fn;actions.append(el);return el;};
        button('3D BEARBEITEN',()=>preview(p)).disabled=!!p.disabled;
        button('MODELL ÄNDERN',()=>changeModel(p),'ps-model-button').disabled=!!p.disabled;
        button(p.disabled?'WIEDER AKTIVIEREN':p.isNew?'PROP ENTFERNEN':'PROP DEAKTIVIEREN',async()=>{
          if(p.disabled){const r=await call('restore',{id:p.id});if(!r.ok)return status(r.error,true);return reload(p.id);}
          if(!await dialog(p.isNew?'PROP ENTFERNEN':'PROP DEAKTIVIEREN',p.isNew?`„${p.label}“ aus dem Baukatalog entfernen? Bereits platzierte Objekte bleiben bestehen; die Definition bleibt intern zur Sicherheit erhalten.`:`„${p.label}“ deaktivieren? Die Originaldefinition bleibt erhalten.`))return;
          const r=await call('remove',{id:p.id});if(!r.ok)return status(r.error,true);await reload();
        },'ps-danger');
        if(p.modified)button('ORIGINAL WIEDERHERSTELLEN',async()=>{
          if(!await dialog('ORIGINAL WIEDERHERSTELLEN',p.isNew?`Die ursprüngliche 3D-Ausrichtung von „${p.label}“ wiederherstellen? Bei älteren eigenen Props ohne gespeicherten Ausgangszustand werden Offset und Rotation auf 0 zurückgesetzt. Modell und platzierte Objekte bleiben erhalten.`:`Anpassungen von „${p.label}“ jetzt wiederherstellen? Die Änderung wird sofort für alle Spieler synchronisiert.`))return;
          const r=await call('reset',{id:p.id});status(r.ok?(r.restart?'Zurückgesetzt.':r.legacyBaseline?'Ausrichtung auf 0 zurückgesetzt (alter Prop ohne Ausgangszustand).':'Ursprüngliche Ausrichtung wiederhergestellt.'):r.error,!r.ok);if(r.ok)await reload(p.id);
        });
        row.append(info,actions);content.append(row);
      }
      group.append(content);list.append(group);
    }
    if(!matched.length){const empty=document.createElement('p');empty.className='ps-empty';empty.textContent='Keine passenden Props gefunden.';list.append(empty);}
    renderCategories();
  }
  async function reload(prefer){const [r,c]=await Promise.all([call('list'),call('categories')]);if(!r.ok)return status(r.error||'Props konnten nicht geladen werden',true);if(!c.ok)return status(c.error||'Kategorien konnten nicht geladen werden',true);entries=r.pieces||[];categories={...builtin,...c.categories};categorySelect();selected=entries.find(p=>p.id===(prefer||selected?.id))||null;render();status(`${entries.length} Props geladen.`);}
  function form(){const label=$('psLabel').value.trim(),model=$('psModel').value.trim(),cat=$('psCat').value,id=slug(label);if(label.length<2||!model.match(/^[a-zA-Z0-9_]+$/)||!categories[cat]||!id.match(/^[a-z][a-z0-9_]*$/))throw Error('Bitte gültigen Namen, GTA-Modell und Kategorie angeben.');if(entries.some(p=>p.id===id))throw Error(`Prop-ID „${id}“ existiert bereits. Bitte anderen Namen wählen.`);return {id,label,model,cat,size:[1,1,1],offset:[0,0,0],rotation:[0,0,0],create:true};}
  async function preview(p){let payload;try{payload=p?{id:p.id,label:p.label,model:(p.models||[])[0],cat:p.cat,offset:p.studio?.offset||[0,0,0],rotation:p.studio?.rotation||[0,0,0],size:p.size||[1,1,1],create:false}:form();}catch(e){return status(e.message,true);}payload.settings={showBounds:$('psShowBounds').checked,boundsColor:$('psBoundsColor').value,gizmoSize:Number($('psGizmoSize').value),defaultGrid:$('psDefaultGrid').checked};try{const r=await fetch(`https://${GetParentResourceName()}/propStudioPreview`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).then(r=>r.json());if(!r.ok)status(r.error||'3D-Editor konnte nicht geöffnet werden',true);}catch(e){status('3D-Editor: '+e.message,true);}}
  async function changeModel(p){
    const current=(p.models||[])[0]||'';
    const wrapper=document.createElement('div');wrapper.className='ps-model-dialog';
    const caption=document.createElement('label');caption.textContent='GTA-MODELLNAME';
    const input=document.createElement('input');input.type='text';input.maxLength=90;input.value=current;input.placeholder='z. B. prop_beach_fire';input.autocomplete='off';input.spellcheck=false;
    const hint=document.createElement('small');hint.textContent='Ändert die Prop-Definition. Bereits platzierte Objekte können beim Neuladen ebenfalls das neue Modell verwenden.';
    wrapper.append(caption,input,hint);
    const confirmed=await dialog('GTA-MODELL ÄNDERN',`Modell für „${p.label}“ ersetzen:`,wrapper);
    if(!confirmed)return;
    const model=input.value.trim();
    if(!/^[a-zA-Z0-9_]{1,90}$/.test(model))return status('Ungültiger GTA-Modellname.',true);
    if(model===current)return;
    const check=await call('validateModel',{model});
    if(!check.ok)return status(check.error||'Modell konnte nicht geladen werden.',true);
    const result=await call('save',{id:p.id,label:p.label,model,cat:p.cat,size:p.size||[1,1,1],offset:p.studio?.offset||[0,0,0],rotation:p.studio?.rotation||[0,0,0],create:false,tested:false});
    if(!result.ok)return status(result.error||'Modellwechsel fehlgeschlagen.',true);
    await reload(p.id);status(`Modell von „${p.label}“ auf ${model} geändert. Bestehende Objekte ggf. neu laden.`);
  }
  async function directSave(){let payload;try{payload=form();}catch(e){return status(e.message,true);}payload.tested=false;const check=await call('validateModel',{model:payload.model});if(!check.ok)return status(check.error||'GTA-Modell nicht vorhanden',true);const ok=await dialog('PROP DIREKT SPEICHERN',`„${payload.label}“ ohne visuelle Prüfung speichern? Es erhält den Status NICHT GETESTET.`);if(!ok)return;const r=await call('save',payload);if(!r.ok)return status(r.error||'Speichern fehlgeschlagen',true);$('psLabel').value='';$('psModel').value='';activate('existing');await reload(payload.id);}
  function renderCategories(){const root=$('psCategoryList');root.replaceChildren();for(const [id,label] of Object.entries(categories)){const count=entries.filter(p=>p.cat===id).length;const row=document.createElement('div');row.className='ps-manage-row';const name=document.createElement('div');name.textContent=`${label}  ·  ${count} Props`;row.append(name);if(!builtin[id]){const rename=document.createElement('button');rename.className='ps-prop-action';rename.textContent='UMBENENNEN';rename.onclick=async()=>{const input=document.createElement('input');input.maxLength=40;input.value=label;if(!await dialog('KATEGORIE UMBENENNEN',`Neuer Anzeigename für „${label}“:`,input))return;const r=await call('categoryRename',{id,label:input.value.trim()});if(!r.ok)return status(r.error,true);await reload();};const del=document.createElement('button');del.className='ps-prop-action ps-danger';del.textContent='LÖSCHEN';del.onclick=async()=>{const select=document.createElement('select');for(const [target,targetLabel] of Object.entries(categories)){if(target===id)continue;const option=document.createElement('option');option.value=target;option.textContent=targetLabel;select.append(option);}if(!await dialog('KATEGORIE LÖSCHEN',`„${label}“ löschen? ${count} Props werden der ausgewählten Kategorie zugewiesen.`,select))return;const r=await call('categoryDelete',{id,target:select.value});if(!r.ok)return status(r.error,true);await reload();};row.append(rename,del);}root.append(row);}}
  document.querySelectorAll('#psRailSub [data-ps-tab]').forEach(b=>b.onclick=()=>activate(b.dataset.psTab));document.querySelectorAll('#psPane [data-ps-filter]').forEach(b=>b.onclick=()=>{filter=b.dataset.psFilter;document.querySelectorAll('#psPane [data-ps-filter]').forEach(x=>x.classList.toggle('active',x===b));render();});
  async function placedRequest(action,id,coords){try{return await fetch(`https://${GetParentResourceName()}/propPlacedAction`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,id,coords})}).then(r=>r.json());}catch(e){return {ok:false,error:e.message};}}
  async function reloadPlaced(){
    const root=$('psPlacedList');root.textContent='Lade platzierte Objekte…';
    const r=await call('placedNearby');if(!r.ok){root.textContent=r.error||'Laden fehlgeschlagen';return;}
    root.replaceChildren();if(!r.list?.length){root.textContent='Keine platzierten Objekte im Umkreis von 75 m.';return;}
    for(const item of r.list){
      const row=document.createElement('div');row.className='ps-prop-row';
      const info=document.createElement('div');info.className='ps-prop-info';
      const title=document.createElement('strong');title.textContent=`#${item.id} · ${item.piece}`;
      const coords=document.createElement('small');coords.textContent=`${item.x.toFixed(2)}, ${item.y.toFixed(2)}, ${item.z.toFixed(2)} · ${item.h.toFixed(1)}°`;
      info.append(title,coords);const actions=document.createElement('div');actions.className='ps-inline-actions';
      const edit=document.createElement('button');edit.className='ps-prop-action';edit.textContent='POSITION BEARBEITEN';edit.onclick=async()=>{
        const r=await fetch(`https://${GetParentResourceName()}/propPlacedEdit`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:item.id})}).then(r=>r.json());if(!r.ok)status(r.error,true);
      };
      const del=document.createElement('button');del.className='ps-prop-action ps-danger';del.textContent='DAUERHAFT LÖSCHEN';del.onclick=async()=>{
        if(!await dialog('PLATZIERTES OBJEKT LÖSCHEN',`Objekt #${item.id} (${item.piece}) endgültig aus der Datenbank und der Spielwelt entfernen?`))return;
        const r=await placedRequest('delete',item.id);if(!r.ok)return status(r.error,true);status(`Objekt #${item.id} gelöscht.`);await reloadPlaced();
      };
      actions.append(edit,del);row.append(info,actions);root.append(row);
    }
  }
  $('psPlacedReload').onclick=reloadPlaced;
  $('psSearch').oninput=render;$('psReload').onclick=()=>reload();$('psNew').onclick=()=>preview(null);$('psDirectSave').onclick=directSave;
  $('psCatConfirm').onclick=async()=>{const label=$('psCatName').value.trim();const r=await call('categoryCreate',{label});if(!r.ok)return status(r.error,true);$('psCatName').value='';await reload();};
  $('psDebugClear').onclick=()=>{logs.length=0;$('psDebugLog').textContent='';};$('psDebugCopy').onclick=()=>{const area=document.createElement('textarea');area.value=logs.join('\n');document.body.append(area);area.select();document.execCommand('copy');area.remove();};
  const settingsKey='bs19.propstudio.settings.v6';const ids=['psShowBounds','psBoundsColor','psGizmoSize','psDefaultGrid'];try{const saved=JSON.parse(localStorage.getItem(settingsKey)||'{}');for(const id of ids){if(saved[id]!==undefined){const node=$(id);if(node.type==='checkbox')node.checked=!!saved[id];else node.value=saved[id];}}}catch(_){};
  function saveSettings(){const values={};for(const id of ids){const node=$(id);values[id]=node.type==='checkbox'?node.checked:node.value;}localStorage.setItem(settingsKey,JSON.stringify(values));$('psGizmoSizeValue').textContent=values.psGizmoSize;}
  for(const id of ids)$(id).addEventListener('input',saveSettings);saveSettings();
  window.addEventListener('message',e=>{if(e.data?.action==='propStudioError')status(e.data.message||'3D-Editor Fehler',true);});window.addEventListener('error',e=>status(`${e.message} (${e.filename}:${e.lineno})`,true));window.addEventListener('unhandledrejection',e=>status(e.reason?.stack||e.reason||'Promise-Fehler',true));
  const psTab = document.querySelector('.mtab[data-tab="propstudio"]');
  const psRail = $('psRailSub');
  if (psTab && psRail) {
    psTab.setAttribute('aria-expanded','false');
    psTab.addEventListener('click', () => {
      const opening = psRail.hidden;
      psRail.hidden = !opening;
      psTab.setAttribute('aria-expanded',String(opening));
      if (opening) { activate(tab); reload(); }
    });
    psRail.querySelectorAll('[data-ps-tab]').forEach(button => button.addEventListener('click', () => {
      // Switching a subview must not toggle the parent accordion closed.
      if (!psTab.classList.contains('is-active')) {
        document.querySelectorAll('.mtab').forEach(x => x.classList.remove('is-active'));
        document.querySelectorAll('.mpane').forEach(x => x.classList.remove('is-active'));
        psTab.classList.add('is-active');
        $('psPane').classList.add('is-active');
      }
      if (psRail.hidden) { psRail.hidden=false; psTab.setAttribute('aria-expanded','true'); }
      activate(button.dataset.psTab);
      if (button.dataset.psTab === 'existing' || button.dataset.psTab === 'categories') reload();
    }));
  }
  activate('existing');
})();

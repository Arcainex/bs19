// BS19 Prop Editor v6. Only catalogue UI; the existing 3D gizmo and F2 pipeline are unchanged.
(() => {
  const $ = id => document.getElementById(id);
  const builtin = {claim:'Claim'};
  let categories={...builtin}, entries=[], selected=null, filter='all', tab='existing';
  const expanded=new Set(), logs=[];const moveSelected=new Set();let initialCategoriesOpened=false;
  let debugErrorCount=0;
  const f2Seen=new Set();
  function debugRender(){
    const onlyErrors=$('psDebugOnlyErrors')?.checked;
    $('psDebugLog').textContent=logs.filter(x=>!onlyErrors||x.level==='FEHLER').map(x=>x.line).join('\n');
    $('psDebugCounter').textContent=`${debugErrorCount} Fehler · ${logs.length} Einträge`;
  }
  const slug=s=>s.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'_').replace(/^_+|_+$/g,'').replace(/^[^a-z]+/,'prop_').slice(0,48);
  function activate(name){if(typeof closeMaterialPopover==='function')closeMaterialPopover();tab=name;document.querySelectorAll('#psRailSub [data-ps-tab]').forEach(b=>b.classList.toggle('is-active',b.dataset.psTab===name));document.querySelectorAll('#psPane [data-ps-section]').forEach(s=>s.hidden=s.dataset.psSection!==name);if(name==='debug')$('psErrorBadge').hidden=true;if(name==='placed')reloadPlaced();if(name==='new')initNewCosts();}
  function log(msg,error=false,source='F10'){
    const level=error?'FEHLER':'INFO';
    const line=`[${new Date().toLocaleTimeString('de-DE')}] ${level} [${source}]: ${String(msg)}`;
    logs.push({line,level}); if(logs.length>500)logs.shift();
    if(error){debugErrorCount++;$('psErrorBadge').hidden=false;activate('debug');}
    debugRender();
  }
  function status(msg,error=false,source='F10'){$('psStatus').textContent=msg;$('psStatus').style.color=error?'#ff9288':'#b8e6c3';log(msg,error,source);}
  async function post(endpoint,data){
    const response=await fetch(`https://${GetParentResourceName()}/${endpoint}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    if(!response.ok)throw Error(`HTTP ${response.status} (${endpoint})`);
    return await response.json();
  }
  async function call(action,payload){
    try{
      const r=await post('propStudio',{action,payload,id:payload?.id});
      if(!r?.ok)log(`${action}${payload?.id?' · '+payload.id:''}: ${r?.error||'Keine Serverantwort'}`,true,'Server / '+action);
      return r;
    }catch(e){const error='Verbindung fehlgeschlagen: '+e.message;log(`${action}: ${error}`,true,'NUI');return {ok:false,error};}
  }
  function dialog(title,body,extra){return new Promise(resolve=>{
    const d=$('psDialog');$('psDialogTitle').textContent=title;$('psDialogText').textContent=body;
    const x=$('psDialogExtra');x.replaceChildren();if(extra)x.append(extra);
    const confirm=$('psDialogConfirm'),destructive=/LÖSCHEN|ENTFERNEN/.test(title);
    confirm.classList.toggle('ps-danger',destructive);
    confirm.classList.toggle('ps-primary',!destructive);
    confirm.textContent=destructive?'LÖSCHEN':(title.startsWith('BAUKOSTEN')?'SPEICHERN':'BESTÄTIGEN');
    d.hidden=false;
    const finish=answer=>{closeMaterialPopover();d.hidden=true;confirm.onclick=null;$('psDialogCancel').onclick=null;resolve(answer);};
    confirm.onclick=()=>{
      if(extra&&typeof extra.readCosts==='function'){
        try{extra.readCosts();extra.querySelector('.ps-dialog-inline-error')?.remove();}
        catch(e){
          let note=extra.querySelector('.ps-dialog-inline-error');
          if(!note){note=document.createElement('p');note.className='ps-dialog-inline-error';extra.append(note);}
          note.textContent=e.message;return;
        }
      }
      finish(true);
    };
    $('psDialogCancel').onclick=()=>finish(false);$('psDialogCancel').focus();
  });}

  function categorySelect(){const select=$('psCat'),current=select.value;select.replaceChildren();for(const [key,label] of Object.entries(categories)){const o=document.createElement('option');o.value=key;o.textContent=label;select.append(o);}if(categories[current])select.value=current;}
  function badge(p){return p.disabled?'DEAKTIVIERT':p.isNew?(p.modified?'BEARBEITET':p.tested?'ORIGINAL':'NICHT GETESTET'):(p.modified?'ANGEPASST':'ORIGINAL');}
  function matchesFilter(p){return filter==='all'||(filter==='disabled'?p.disabled:filter==='custom'?p.isNew:!p.isNew);}
  async function moveProps(ids){
    ids=[...new Set(ids)].filter(id=>entries.some(p=>p.id===id));
    if(!ids.length)return status('Bitte zuerst mindestens ein Prop markieren.',true,'Kategorien');
    if(ids.length>100)return status('Maximal 100 Props auf einmal verschieben.',true,'Kategorien');
    const selectedEntries=entries.filter(p=>ids.includes(p.id));
    const options=Object.entries(categories).sort((a,b)=>a[1].localeCompare(b[1],'de'));
    const targetBox=document.createElement('div');targetBox.className='ps-category-targets ps-move-options';
    const hint=document.createElement('p');hint.className='ps-move-hint';
    hint.textContent='Zielkategorie auswählen · Modell, Position und Baukosten bleiben unverändert.';
    targetBox.append(hint);
    let target=options.find(([key])=>selectedEntries.some(p=>p.cat!==key))?.[0]||options[0]?.[0];
    for(const [key,title] of options){
      const option=document.createElement('button');option.type='button';option.className='ps-target-choice';
      const count=selectedEntries.filter(p=>p.cat===key).length;
      option.textContent=title+(count?'  · '+count+' bereits dort':'');
      option.classList.toggle('active',key===target);
      option.onclick=()=>{target=key;targetBox.querySelectorAll('.ps-target-choice').forEach(b=>b.classList.toggle('active',b===option));};
      targetBox.append(option);
    }
    if(!target)return status('Keine Kategorie verfügbar.',true,'Kategorien');
    const ask=ids.length===1?'„'+selectedEntries[0].label+'“ verschieben?':`${ids.length} Props gemeinsam verschieben?`;
    if(!await dialog('PROPS VERSCHIEBEN',ask,targetBox))return;
    const result=await call('categoryMove',{ids,target});
    if(!result.ok)return status(result.error||'Verschieben fehlgeschlagen',true,'Kategorien');
    moveSelected.clear();
    await reload(ids[0]);
    status(`${result.moved} Prop(s) in „${categories[target]||target}“ verschoben. F2 aktualisiert.`);
  }
  function render(){
    const search=$('psSearch').value.trim().toLocaleLowerCase('de-DE');
    const list=$('psList');const preservedScroll=list.scrollTop;list.replaceChildren();
    const matched=entries.filter(p=>(categories[p.cat] || $('psShowLegacy')?.checked) && matchesFilter(p)&&`${p.id} ${p.label} ${(p.models||[]).join(' ')} ${categories[p.cat]||p.cat}`.toLocaleLowerCase('de-DE').includes(search));
    const grouped=new Map();for(const p of matched){const cat=p.cat||'utility';if(!grouped.has(cat))grouped.set(cat,[]);grouped.get(cat).push(p);}
    // Compact multi-select toolbar above the scrollable catalogue.
    const tools=document.createElement('div');tools.className='ps-move-toolbar';
    const count=document.createElement('span');count.className='ps-move-count';
    count.textContent=`${moveSelected.size} ausgewählt · ${matched.length} sichtbar`;
    const all=document.createElement('button');all.type='button';all.className='ps-prop-action';all.textContent='Sichtbare markieren';
    all.onclick=()=>{for(const p of matched){if(moveSelected.size>=100)break;if(p.id!=='claim')moveSelected.add(p.id);}render();};
    const clear=document.createElement('button');clear.type='button';clear.className='ps-prop-action';clear.textContent='Auswahl leeren';
    clear.disabled=moveSelected.size===0;clear.onclick=()=>{moveSelected.clear();render();};
    const move=document.createElement('button');move.type='button';move.className='ps-prop-action ps-primary';
    move.textContent=`${moveSelected.size} verschieben →`;move.disabled=moveSelected.size===0;
    move.onclick=()=>moveProps([...moveSelected]);
    tools.append(count,all,clear,move);list.append(tools);
    // First visit: show actual props/actions instead of a page of folded headings.
    if(!initialCategoriesOpened && grouped.size){for(const cat of grouped.keys())expanded.add(cat);initialCategoriesOpened=true;}
    for(const [cat,props] of [...grouped.entries()].sort((a,b)=>(categories[a[0]]||a[0]).localeCompare(categories[b[0]]||b[0],'de'))){
      const group=document.createElement('details');group.className='ps-category';group.open=!!search||expanded.has(cat);
      group.addEventListener('toggle',()=>{if(search)return;group.open?expanded.add(cat):expanded.delete(cat);});
      const head=document.createElement('summary');head.setAttribute('aria-label',`${categories[cat]||cat}, ${props.length} Props, Kategorie auf- oder zuklappen`);const arrow=document.createElement('span');arrow.className='ps-category-arrow';arrow.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent=`${categories[cat]||cat}  ·  ${props.length}`;head.append(arrow,label);group.append(head);
      const content=document.createElement('div');content.className='ps-category-items';
      for(const p of props.sort((a,b)=>(a.label||a.id).localeCompare(b.label||b.id,'de'))){
        const row=document.createElement('div');row.className='ps-prop-row';
        const pick=document.createElement('input');pick.type='checkbox';pick.className='ps-move-checkbox';
        pick.checked=moveSelected.has(p.id);pick.disabled=p.id==='claim';pick.title=pick.disabled?'Geschütztes System-Prop':'Prop für Kategorieverschiebung markieren';
        pick.setAttribute('aria-label','Für Verschieben markieren: '+(p.label||p.id));
        pick.onchange=()=>{if(pick.checked){if(moveSelected.size>=100){pick.checked=false;return status('Maximal 100 Props markieren.',true,'Kategorien');}moveSelected.add(p.id);}else moveSelected.delete(p.id);render();};
        row.append(pick);
        const info=document.createElement('div');info.className='ps-prop-info';
        const title=document.createElement('strong');title.textContent=p.label||p.id;
        const detail=document.createElement('small');detail.textContent=`${p.id} · ${(p.models||[])[0]||'Kein Modell'}`;
        const state=document.createElement('small');state.className='ps-state '+(p.disabled?'is-disabled':p.isNew&&!p.tested?'is-untested':p.isNew&&p.modified?'is-new':p.modified?'is-custom':'is-original');state.textContent=badge(p);
        info.append(title,detail,state);
        const actions=document.createElement('div');actions.className='ps-inline-actions';
        const button=(label,fn,cls='')=>{const el=document.createElement('button');el.type='button';el.className='ps-prop-action '+cls;el.textContent=label;el.onclick=fn;actions.append(el);return el;};
        button('3D BEARBEITEN',()=>preview(p)).disabled=!!p.disabled;
        button('BEARBEITEN',()=>editGeneral(p),'ps-primary').disabled=!!p.disabled;
        button('VERSCHIEBEN',()=>moveProps([p.id])).disabled=p.id==='claim';
        button(p.disabled?'AKTIVIEREN':'DEAKTIVIEREN',async()=>{
          const disabling=!p.disabled;
          const ok=await dialog(disabling?'PROP DEAKTIVIEREN?':'PROP AKTIVIEREN?',
            disabling?`„${p.label}“ aus dem F2-Baukatalog ausblenden? Bereits platzierte Objekte bleiben erhalten. Du kannst das Prop jederzeit wieder aktivieren.`
                     :`„${p.label}“ wieder im F2-Baukatalog verfügbar machen?`);
          if(!ok)return;
          const r=await call(disabling?'remove':'restore',{id:p.id});
          if(!r.ok)return status(r.error||(disabling?'Deaktivieren fehlgeschlagen':'Aktivieren fehlgeschlagen'),true);
          await reload(p.id);
          status(`„${p.label}“ ${disabling?'deaktiviert und aus F2 ausgeblendet':'aktiviert und in F2 verfügbar'}.`);
        },p.disabled?'ps-danger':'');
        button('LÖSCHEN',async()=>{
          const ok=await dialog('PROP WIRKLICH LÖSCHEN?',`Möchtest du „${p.label}“ wirklich dauerhaft aus dem F10- und F2-Baukatalog löschen? Das kann nicht rückgängig gemacht werden. Bereits platzierte Objekte bleiben bestehen.`);
          if(!ok)return;
          const r=await call('deletePermanent',{id:p.id});
          if(!r.ok)return status(r.error||'Dauerhaftes Löschen fehlgeschlagen',true);
          selected=null;
          await reload();
          status(`„${p.label}“ dauerhaft aus F10 und F2 entfernt.${r.placedCount ? ` ${r.placedCount} bereits platzierte Objekte bleiben bestehen.` : ''}`);
        },'ps-danger');
        row.append(info,actions);content.append(row);
      }
      group.append(content);list.append(group);
    }
    if(!matched.length){const empty=document.createElement('p');empty.className='ps-empty';empty.textContent='Keine passenden Props gefunden.';list.append(empty);}
    renderCategories();
    list.scrollTop=preservedScroll;
  }
  async function reload(prefer){const [r,c]=await Promise.all([call('list'),call('categories')]);if(!r.ok)return status(r.error||'Props konnten nicht geladen werden',true);if(!c.ok)return status(c.error||'Kategorien konnten nicht geladen werden',true);entries=r.pieces||[];categories={...c.categories};for(const id of [...moveSelected]){if(!entries.some(p=>p.id===id))moveSelected.delete(id);}categorySelect();selected=entries.find(p=>p.id===(prefer||selected?.id))||null;render();status(`${entries.length} Props geladen.`);}
  function newPropError(message){
    const note=$('psNewFeedback');note.textContent=message;note.hidden=false;
    note.scrollIntoView({block:'nearest',behavior:'smooth'});
  }
  function clearNewPropError(){const note=$('psNewFeedback');note.textContent='';note.hidden=true;}
  let materialOptions=null, newCosts=[], newCostWidget=null;
  async function materials(){
    if(materialOptions)return materialOptions;
    const result=await call('materials');
    if(!result.ok)throw Error(result.error||'Inventar-Materialien konnten nicht geladen werden');
    materialOptions=(result.items||[]).map(item=>({id:String(item.id||''),label:String(item.label||item.id||''),category:String(item.category||'item').toLowerCase()}));
    if(!materialOptions.length)throw Error('Keine Materialien im BS19-Inventar gefunden');
    return materialOptions;
  }
  // Categories come directly from bs_inventory. 'Alle Items' is deliberately opt-in:
  // no ammo, weapons, food or medicine mixed into the default building-material picker.
  const recommendedIds=['wood_plank','nails','scrap_metal','steel','cement','stone','log','screws','cloth','duct_tape'];
  const offTopicMaterial=/^(ammo_|ammo_casing$|gunpowder$|gun_parts$|lead$|poop$|toilet_paper$|expired_meat$|rotten_flesh$|zombie_|animal_|bone$|herbs$|potato_seeds$|herb_seeds$)/;
  const isBuildItem=item=>['material','construction'].includes(item.category)&&!offTopicMaterial.test(item.id);
  const norm=s=>String(s||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('de-DE');
  let activeMaterialPopover=null;
  function closeMaterialPopover(){
    if(!activeMaterialPopover)return;
    const current=activeMaterialPopover;activeMaterialPopover=null;
    current.cleanup();current.panel.remove();current.trigger.setAttribute('aria-expanded','false');
  }
  function costWidget(value,options){
    const root=document.createElement('div');root.className='ps-cost-widget';
    const rows=document.createElement('div');rows.className='ps-cost-rows';root.append(rows);
    const byId=new Map(options.map(item=>[item.id,item]));
    let showAll=false;
    const toolbar=document.createElement('div');toolbar.className='ps-cost-toolbar';
    const note=document.createElement('span');note.className='ps-cost-note';note.textContent='Baumaterialien';
    const switchLabel=document.createElement('label');switchLabel.className='ps-all-items-toggle';
    const switchInput=document.createElement('input');switchInput.type='checkbox';
    const switchText=document.createElement('span');switchText.textContent='Alle Inventaritems anzeigen';
    switchLabel.append(switchInput,switchText);toolbar.append(note,switchLabel);root.prepend(toolbar);
    const hint=document.createElement('p');hint.className='ps-cost-hint';hint.textContent='Suche nach Materialnamen oder wähle einen häufigen Rohstoff.';
    root.insertBefore(hint,rows);
    function allowed(item, selectedId){return showAll||isBuildItem(item)||item.id===selectedId;}
    function optionsFor(query,selectedId){
      const words=norm(query).split(/\s+/).filter(Boolean);
      return options.filter(item=>allowed(item,selectedId)&&words.every(w=>norm(`${item.label} ${item.id}`).includes(w))).sort((a,b)=>{
        const aFav=recommendedIds.indexOf(a.id),bFav=recommendedIds.indexOf(b.id);
        const ap=aFav===-1?99:aFav,bp=bFav===-1?99:bFav;
        return ap!==bp?ap-bp:a.label.localeCompare(b.label,'de');
      });
    }
    function newRow(data){
      const wrap=document.createElement('div');wrap.className='ps-material-row';wrap.dataset.item=data.item||'';
      const picker=document.createElement('div');picker.className='ps-material-picker';
      const trigger=document.createElement('button');trigger.type='button';trigger.className='ps-material-pick';trigger.setAttribute('aria-haspopup','listbox');trigger.setAttribute('aria-expanded','false');
      const choice=document.createElement('span');choice.className='ps-material-choice';
      const chevron=document.createElement('span');chevron.className='ps-material-chevron';chevron.textContent='⌄';
      trigger.append(choice,chevron);picker.append(trigger);
      const labelFor=id=>byId.get(id)?.label||id||'';
      const refresh=()=>{
        const chosen=wrap.dataset.item;
        choice.textContent=chosen?labelFor(chosen):'Material auswählen …';
        trigger.classList.toggle('is-empty',!chosen);
        trigger.title=chosen?`${labelFor(chosen)} (${chosen})`:'Material auswählen';
      };
      const selectItem=id=>{wrap.dataset.item=id;refresh();closeMaterialPopover();};
      trigger.onclick=()=>{
        if(activeMaterialPopover?.trigger===trigger){closeMaterialPopover();return;}
        closeMaterialPopover();
        const panel=document.createElement('div');panel.className='ps-material-popover';
        const search=document.createElement('input');search.type='search';search.placeholder='Material suchen …';search.className='ps-popover-search';search.setAttribute('aria-label','Material suchen');search.autocomplete='off';
        const resultList=document.createElement('div');resultList.className='ps-popover-list';resultList.setAttribute('role','listbox');
        const caption=document.createElement('div');caption.className='ps-popover-caption';
        panel.append(search,caption,resultList);document.body.append(panel);
        const place=()=>{
          const rect=trigger.getBoundingClientRect();const width=Math.min(Math.max(rect.width,330),Math.max(240,window.innerWidth-24));
          const left=Math.max(12,Math.min(rect.left,window.innerWidth-width-12));
          const below=window.innerHeight-rect.bottom-12;const above=rect.top-12;
          const up=below<270&&above>below;
          panel.style.width=width+'px';panel.style.left=left+'px';
          panel.style.maxHeight=Math.max(140,Math.min(340,(up?above:below)-8))+'px';
          panel.style.top=(up?Math.max(8,rect.top-Math.min(340,Math.max(140,above-8))-6):rect.bottom+6)+'px';
        };
        let highlighted=0;
        const redraw=()=>{
          resultList.replaceChildren();const matches=optionsFor(search.value,wrap.dataset.item);highlighted=Math.min(highlighted,Math.max(0,matches.length-1));
          caption.textContent=showAll?'ALLE INVENTARITEMS · '+matches.length:'BAUMATERIALIEN · '+matches.length;
          if(!matches.length){const empty=document.createElement('p');empty.className='ps-popover-empty';empty.textContent='Keine passenden Materialien.';resultList.append(empty);return;}
          for(const [index,item] of matches.entries()){
            const option=document.createElement('button');option.type='button';option.className='ps-popover-option'+(item.id===wrap.dataset.item?' is-chosen':'')+(index===highlighted?' is-highlighted':'');
            option.setAttribute('role','option');option.setAttribute('aria-selected',String(item.id===wrap.dataset.item));
            const name=document.createElement('span');name.textContent=item.label;
            const id=document.createElement('small');id.textContent=item.id;
            option.append(name,id);
            option.onmouseenter=()=>{highlighted=index;for(const sibling of resultList.children)sibling.classList.remove('is-highlighted');option.classList.add('is-highlighted');};
            option.onclick=()=>selectItem(item.id);
            resultList.append(option);
          }
        };
        const handleKeys=e=>{
          if(e.key==='Escape'){e.preventDefault();closeMaterialPopover();trigger.focus();}
          if(e.key==='ArrowDown'||e.key==='ArrowUp'){
            e.preventDefault();const count=resultList.children.length;if(!count)return;
            highlighted=(highlighted+(e.key==='ArrowDown'?1:-1)+count)%count;redraw();resultList.children[highlighted]?.scrollIntoView({block:'nearest'});
          }
          if(e.key==='Enter'){e.preventDefault();resultList.children[highlighted]?.click();trigger.focus();}
        };
        const onOutside=e=>{if(!panel.contains(e.target)&&!trigger.contains(e.target))closeMaterialPopover();};
        const onScroll=e=>{if(!panel.contains(e.target)&&e.target!==search)closeMaterialPopover();};
        const cleanup=()=>{document.removeEventListener('pointerdown',onOutside,true);window.removeEventListener('resize',closeMaterialPopover);document.removeEventListener('scroll',onScroll,true);};
        activeMaterialPopover={panel,trigger,cleanup};trigger.setAttribute('aria-expanded','true');
        document.addEventListener('pointerdown',onOutside,true);window.addEventListener('resize',closeMaterialPopover);document.addEventListener('scroll',onScroll,true);
        search.addEventListener('input',()=>{highlighted=0;redraw();});search.addEventListener('keydown',handleKeys);
        place();redraw();search.focus();
      };
      const qty=document.createElement('label');qty.className='ps-material-qty';qty.textContent='MENGE';
      const amount=document.createElement('input');amount.type='number';amount.min='1';amount.max='100000';amount.step='1';amount.value=data.amount||1;amount.setAttribute('aria-label','Materialmenge');qty.append(amount);
      const remove=document.createElement('button');remove.type='button';remove.className='ps-material-remove';remove.textContent='×';remove.title='Material entfernen';remove.setAttribute('aria-label','Material entfernen');remove.onclick=()=>{if(activeMaterialPopover?.trigger===trigger)closeMaterialPopover();wrap.remove();updateEmpty();};
      wrap.append(picker,qty,remove);rows.append(wrap);refresh();updateEmpty();return wrap;
    }
    const empty=document.createElement('div');empty.className='ps-material-empty';empty.textContent='Noch keine Baukosten hinterlegt. Füge ein Material hinzu.';
    root.append(empty);
    function updateEmpty(){empty.hidden=rows.childElementCount!==0;}
    for(const c of value||[])newRow({item:c.item,amount:c.amount});updateEmpty();
    const foot=document.createElement('div');foot.className='ps-cost-footer';
    const add=document.createElement('button');add.type='button';add.className='ps-add-cost';add.textContent='＋ Material hinzufügen';
    add.onclick=()=>{if(rows.childElementCount>=24)return;const row=newRow({item:'',amount:1});row.querySelector('.ps-material-pick').click();};
    const quick=document.createElement('div');quick.className='ps-cost-quick';
    const quickTitle=document.createElement('span');quickTitle.textContent='SCHNELL HINZUFÜGEN';quick.append(quickTitle);
    for(const id of recommendedIds.slice(0,6)){
      const item=byId.get(id);if(!item)continue;
      const b=document.createElement('button');b.type='button';b.className='ps-quick-item';b.textContent='＋ '+item.label;b.title=item.id;
      b.onclick=()=>{if([...rows.children].some(r=>r.dataset.item===id))return; if(rows.childElementCount>=24)return;newRow({item:id,amount:1});};
      quick.append(b);
    }
    foot.append(add,quick);root.append(foot);
    switchInput.onchange=()=>{
      showAll=switchInput.checked;
      note.textContent=showAll?'Alle Inventaritems':'Baumaterialien';
      if(activeMaterialPopover?.trigger?.closest('.ps-cost-widget')===root)closeMaterialPopover();
    };
    root.readCosts=()=>{
      const out=[],seen=new Set();
      for(const row of rows.children){const id=row.dataset.item,number=Number(row.querySelector('input[type=number]').value);
        if(!id)throw Error('Bitte für jede Zeile ein Material auswählen.');
        if(!Number.isSafeInteger(number)||number<1||number>100000)throw Error('Materialmenge muss zwischen 1 und 100000 liegen.');
        if(seen.has(id))throw Error('Material doppelt ausgewählt: '+labelForId(id));
        seen.add(id);out.push({item:id,amount:number});
      }
      return out;
    };
    const labelForId=id=>byId.get(id)?.label||id;
    return root;
  }
  async function editCost(p){
    let options;try{options=await materials();}catch(e){return status(e.message,true);}
    const editor=costWidget(p.cost||[],options);
    const ok=await dialog('BAUKOSTEN · '+p.label,'Wähle passende Rohstoffe und die benötigte Menge:',editor);
    closeMaterialPopover();if(!ok)return;
    let cost;try{cost=editor.readCosts();}catch(e){return status(e.message,true);}
    const result=await call('save',{id:p.id,label:p.label,model:(p.models||[])[0],cat:p.cat,size:p.size||[1,1,1],offset:p.studio?.offset||[0,0,0],rotation:p.studio?.rotation||[0,0,0],cost,create:false});
    if(!result.ok)return status(result.error||'Kosten konnten nicht gespeichert werden',true);
    await reload(p.id);status('Baukosten gespeichert und an F2 synchronisiert.');
  }
  function form(){
    const label=$('psLabel').value.trim(),model=$('psModel').value.trim(),cat=$('psCat').value,id=slug(label);
    if(label.length<2)throw Error('Bitte einen Namen mit mindestens zwei Zeichen eingeben.');
    if(!/^[a-zA-Z0-9_]{1,90}$/.test(model))throw Error('Bitte einen gültigen GTA-Modellnamen eingeben (Buchstaben, Zahlen, _).');
    if(!categories[cat])throw Error('Bitte eine Kategorie auswählen.');
    if(!/^[a-z][a-z0-9_]*$/.test(id))throw Error('Bitte einen anderen Prop-Namen wählen.');
    if(entries.some(p=>p.id===id))throw Error(`Der Name ist bereits vergeben (ID: ${id}).`);
    if(!newCostWidget||!materialOptions?.length)throw Error('Materialliste noch nicht geladen.');
    const cost=newCostWidget.readCosts();if(!cost.length)throw Error('Bitte mindestens ein Baumaterial hinzufügen.');
    return {id,label,model,cat,size:[1,1,1],offset:[0,0,0],rotation:[0,0,0],create:true,cost};
  }
  async function initNewCosts(){
    const container=$('psNewCosts');if(!container)return;
    if(newCostWidget && container.contains(newCostWidget) && materialOptions)return;
    if(newCostWidget){try{newCosts=newCostWidget.readCosts();}catch(_){/* keep last valid selection */}}
    try{const options=await materials();newCostWidget=costWidget(newCosts,options);container.replaceChildren(newCostWidget);}
    catch(e){container.textContent='Materialliste konnte nicht geladen werden: '+e.message;status(e.message,true);}
  }
  const idPreview=$('psIdPreview');
  $('psLabel').addEventListener('input',()=>{const raw=$('psLabel').value.trim();idPreview.textContent=raw?slug(raw):'–';});
  async function preview(p){let payload;try{if(!p)clearNewPropError();payload=p?{id:p.id,label:p.label,model:(p.models||[])[0],cat:p.cat,offset:p.studio?.offset||[0,0,0],rotation:p.studio?.rotation||[0,0,0],size:p.size||[1,1,1],cost:p.cost||[],create:false}:form();}catch(e){return p?status(e.message,true):newPropError(e.message);}payload.settings={showBounds:$('psShowBounds').checked,boundsColor:$('psBoundsColor').value,gizmoSize:Number($('psGizmoSize').value),defaultGrid:$('psDefaultGrid').checked};try{const r=await fetch(`https://${GetParentResourceName()}/propStudioPreview`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).then(r=>r.json());if(!r.ok){if(p)status(r.error||'3D-Editor konnte nicht geöffnet werden',true);else newPropError(r.error||'3D-Editor konnte nicht geöffnet werden');}}catch(e){status('3D-Editor: '+e.message,true);}}
  async function editGeneral(p){
    let options;
    try{options=await materials();}catch(e){return status(e.message,true,'Inventar');}
    const wrap=document.createElement('div');wrap.className='ps-general-edit';
    const header=document.createElement('div');header.className='ps-editor-intro';header.textContent='Name, Modell, Kategorie und Baukosten an einem Ort bearbeiten.';wrap.append(header);
    const grid=document.createElement('div');grid.className='ps-edit-grid';wrap.append(grid);
    function field(text,value,max,placeholder){
      const label=document.createElement('label');label.textContent=text;
      const input=document.createElement('input');input.value=value||'';input.maxLength=max;input.placeholder=placeholder||'';
      label.append(input);grid.append(label);return input;
    }
    const name=field('ANZEIGENAME',p.label||p.id,80,'Name im F2-Menü');
    const id=field('PROP-ID',p.id,48,'interne ID');
    if(!p.isNew){id.readOnly=true;id.title='System-IDs bleiben für Snapping und vorhandene Speicherstände unverändert';id.classList.add('ps-locked');}
    const model=field('GTA-MODELL',p.models?.[0]||'',90,'prop_beach_fire');
    const label=document.createElement('label');label.textContent='KATEGORIE';
    const cat=document.createElement('select');cat.className='ps-editor-select';
    for(const [key,title] of Object.entries(categories)){const option=document.createElement('option');option.value=key;option.textContent=title;cat.append(option);}cat.value=p.cat;
    label.append(cat);grid.append(label);
    const caption=document.createElement('div');caption.className='ps-edit-subheading';caption.innerHTML='<strong>BAUKOSTEN</strong><small>Rohstoffe und Menge direkt ändern</small>';
    const costEditor=costWidget(p.cost||[],options);
    wrap.append(caption,costEditor);
    const note=document.createElement('p');note.className='ps-muted';note.textContent=p.isNew?'Die Prop-ID kann geändert werden. Bereits platzierte Objekte behalten ihre bisherige interne ID.':'System-Prop-IDs sind zum Schutz von Snapping und Spielmechanik gesperrt.';wrap.append(note);
    wrap.readCosts=()=>{
      if(name.value.trim().length<2)throw Error('Bitte einen Anzeigenamen mit mindestens zwei Zeichen eingeben.');
      if(!/^[a-z][a-z0-9_]*$/.test(id.value.trim())||id.value.trim().length>48)throw Error('Ungültige Prop-ID: a-z, 0-9 und _');
      if(!/^[a-zA-Z0-9_]{1,90}$/.test(model.value.trim()))throw Error('Ungültiger GTA-Modellname.');
      if(!categories[cat.value])throw Error('Bitte gültige Kategorie auswählen.');
      return costEditor.readCosts();
    };
    const accepted=await dialog('PROP BEARBEITEN · '+(p.label||p.id),'Alle Änderungen werden gemeinsam gespeichert.',wrap);
    if(!accepted)return;
    const modelName=model.value.trim(),newId=id.value.trim(),newName=name.value.trim();
    let cost;try{cost=wrap.readCosts();}catch(e){return status(e.message,true,'Editor');}
    if(modelName!==(p.models?.[0]||'')){
      const check=await call('validateModel',{model:modelName});
      if(!check.ok)return status(check.error||'GTA-Modell nicht vorhanden',true,'Modellprüfung');
    }
    const payload={id:p.id,newId,label:newName,model:modelName,cat:cat.value,cost,size:p.size||[1,1,1],offset:p.studio?.offset||[0,0,0],rotation:p.studio?.rotation||[0,0,0],create:false};
    const saved=await call('save',payload);
    if(!saved.ok)return status(saved.error||'Änderungen konnten nicht gespeichert werden',true,'Server');
    await reload(saved.id||newId);
    status(`„${newName}“ gespeichert${saved.renamed?' · neue ID: '+newId:''}. F2-Katalog aktualisiert.`);
  }
  async function directSave(){clearNewPropError();let payload;try{payload=form();}catch(e){return newPropError(e.message);}payload.tested=false;const check=await call('validateModel',{model:payload.model});if(!check.ok)return newPropError(check.error||'GTA-Modell nicht vorhanden');const ok=await dialog('PROP DIREKT SPEICHERN',`„${payload.label}“ ohne visuelle Prüfung speichern? Es erhält den Status NICHT GETESTET.`);if(!ok)return;const r=await call('save',payload);if(!r.ok)return status(r.error||'Speichern fehlgeschlagen',true);$('psLabel').value='';$('psModel').value='';$('psIdPreview').textContent='–';clearNewPropError();newCosts=[];newCostWidget=null;await initNewCosts();activate('existing');await reload(payload.id);}
  function renderCategories(){
    const root=$('psCategoryList');root.replaceChildren();
    const heading=document.createElement('p');heading.className='ps-category-summary';heading.textContent=`${Object.keys(categories).length} Kategorien · Props bleiben beim Löschen erhalten`;
    root.append(heading);
    for(const [id,label] of Object.entries(categories).sort((a,b)=>a[1].localeCompare(b[1],'de'))){
      const count=entries.filter(p=>p.cat===id).length;
      const row=document.createElement('div');row.className='ps-category-manage-card';
      const info=document.createElement('div');info.className='ps-category-card-info';
      const title=document.createElement('strong');title.textContent=label;
      const sub=document.createElement('small');sub.textContent=`${count} Props · ${id}`;info.append(title,sub);
      const actions=document.createElement('div');actions.className='ps-inline-actions';
      const rename=document.createElement('button');rename.type='button';rename.className='ps-prop-action';rename.textContent='UMBENENNEN';
      rename.onclick=async()=>{
        const input=document.createElement('input');input.className='ps-category-input';input.maxLength=40;input.value=label;
        if(!await dialog('KATEGORIE UMBENENNEN',`Neuer Name für „${label}“`,input))return;
        const r=await call('categoryRename',{id,label:input.value.trim()});if(!r.ok)return status(r.error,true);
        await reload();status(`Kategorie „${label}“ umbenannt.`);
      };
      const del=document.createElement('button');del.type='button';del.className='ps-prop-action ps-danger';del.textContent='LÖSCHEN';del.disabled=Object.keys(categories).length<=1;
      del.onclick=async()=>{
        const other=Object.entries(categories).filter(([key])=>key!==id);
        const container=document.createElement('div');container.className='ps-category-targets';
        const caption=document.createElement('strong');caption.textContent='Props verschieben nach:';container.append(caption);
        let target=other[0]?.[0];
        for(const [key,name] of other){
          const opt=document.createElement('button');opt.type='button';opt.className='ps-target-choice';opt.textContent=name;
          opt.classList.toggle('active',key===target);
          opt.onclick=()=>{target=key;container.querySelectorAll('.ps-target-choice').forEach(b=>b.classList.toggle('active',b===opt));};
          container.append(opt);
        }
        if(!await dialog('KATEGORIE LÖSCHEN',`„${label}“ löschen? ${count} Props bleiben erhalten und werden neu zugeordnet.`,container))return;
        const r=await call('categoryDelete',{id,target});if(!r.ok)return status(r.error||'Kategorie konnte nicht gelöscht werden',true);
        await reload();status(`Kategorie „${label}“ gelöscht. Props nach „${categories[target]}“ verschoben.`);
      };
      actions.append(rename,del);row.append(info,actions);root.append(row);
    }
  }
  document.querySelectorAll('#psRailSub [data-ps-tab]').forEach(b=>b.onclick=()=>activate(b.dataset.psTab));document.querySelectorAll('#psPane [data-ps-filter]').forEach(b=>b.onclick=()=>{filter=b.dataset.psFilter;document.querySelectorAll('#psPane [data-ps-filter]').forEach(x=>x.classList.toggle('active',x===b));render();});
  async function placedRequest(action,id,coords){
    try{const r=await post('propPlacedAction',{action,id,coords});if(!r?.ok)log(`${action} #${id}: ${r.error||'Fehler'}`,true,'Platzierte Objekte');return r;}
    catch(e){log(e.message,true,'Platzierte Objekte');return {ok:false,error:e.message};}
  }
  let placedList=[], placedSelected=new Set();
  const placedVisible=()=>placedList.filter(item=>`${item.id} ${item.piece}`.toLocaleLowerCase('de-DE').includes($('psPlacedSearch').value.trim().toLocaleLowerCase('de-DE')));
  function updatePlacedToolbar(){
    const visible=placedVisible(), n=placedSelected.size;
    $('psPlacedSummary').textContent=`${visible.length} von ${placedList.length} Objekten`;
    $('psPlacedSelected').textContent=`${n} ausgewählt`;
    $('psPlacedDeleteSelected').disabled=n===0;
    $('psPlacedAll').checked=visible.length>0&&visible.every(x=>placedSelected.has(x.id));
    $('psPlacedAll').indeterminate=visible.some(x=>placedSelected.has(x.id))&&!$('psPlacedAll').checked;
  }
  function renderPlaced(){
    const root=$('psPlacedList');root.replaceChildren();
    const visible=placedVisible();
    if(!visible.length){const empty=document.createElement('p');empty.className='ps-empty';empty.textContent='Keine passenden platzierten Objekte gefunden.';root.append(empty);}
    for(const item of visible){
      const row=document.createElement('div');row.className='ps-prop-row ps-placed-item';row.classList.toggle('is-selected',placedSelected.has(item.id));
      const check=document.createElement('input');check.type='checkbox';check.className='ps-placed-checkbox';check.checked=placedSelected.has(item.id);check.setAttribute('aria-label',`Objekt #${item.id} auswählen`);
      check.onchange=()=>{if(check.checked)placedSelected.add(item.id);else placedSelected.delete(item.id);row.classList.toggle('is-selected',check.checked);updatePlacedToolbar();};
      const info=document.createElement('div');info.className='ps-prop-info';
      const title=document.createElement('strong');title.textContent=`#${item.id} · ${item.label||item.piece}`;
      const coords=document.createElement('small');coords.textContent=`${item.piece} · ${Number(item.x).toFixed(1)}, ${Number(item.y).toFixed(1)}, ${Number(item.z).toFixed(1)} · ${Number(item.h).toFixed(0)}°`;
      info.append(title,coords);const actions=document.createElement('div');actions.className='ps-inline-actions';
      const edit=document.createElement('button');edit.type='button';edit.className='ps-prop-action';edit.textContent='POSITION';edit.onclick=async()=>{
        try{const r=await post('propPlacedEdit',{id:item.id});if(!r.ok)status(r.error||'Positionseditor fehlgeschlagen',true,'Position');}
        catch(e){status(e.message,true,'Position');}
      };
      const del=document.createElement('button');del.type='button';del.className='ps-prop-action ps-danger';del.textContent='LÖSCHEN';del.onclick=async()=>{
        if(!await dialog('OBJEKT LÖSCHEN',`Objekt #${item.id} (${item.piece}) endgültig aus der Spielwelt entfernen?`))return;
        const r=await placedRequest('delete',item.id);if(!r.ok)return status(r.error,true);
        status(`Objekt #${item.id} gelöscht.`);await reloadPlaced();
      };
      actions.append(edit,del);row.append(check,info,actions);root.append(row);
    }
    updatePlacedToolbar();
  }
  async function reloadPlaced(){
    const root=$('psPlacedList');root.textContent='Lade platzierte Objekte…';
    const r=await call('placedNearby');
    if(!r?.ok){root.textContent=r?.error||'Laden fehlgeschlagen';return;}
    placedList=r.list||[];
    placedSelected=new Set([...placedSelected].filter(id=>placedList.some(item=>item.id===id)));
    renderPlaced();
  }
  $('psPlacedReload').onclick=reloadPlaced;
  $('psPlacedSearch').oninput=renderPlaced;
  $('psPlacedClear').onclick=()=>{placedSelected.clear();renderPlaced();};
  $('psPlacedAll').onchange=e=>{
    const visible=placedVisible();
    if(e.target.checked){for(const item of visible)placedSelected.add(item.id);}
    else for(const item of visible)placedSelected.delete(item.id);
    renderPlaced();
  };
  $('psPlacedDeleteSelected').onclick=async()=>{
    const ids=[...placedSelected];if(!ids.length)return;
    if(ids.length>100)return status('Maximal 100 Objekte gleichzeitig löschen. Bitte kleinere Auswahl treffen.',true);
    if(!await dialog('AUSGEWÄHLTE OBJEKTE LÖSCHEN',`${ids.length} platzierte Objekte wirklich endgültig aus der Spielwelt und Datenbank entfernen? Die Prop-Definitionen bleiben erhalten.`))return;
    try{
      const r=await post('propPlacedBatchDelete',{ids});
      if(!r?.ok){
        if(r?.deleted?.length){r.deleted.forEach(id=>placedSelected.delete(id));await reloadPlaced();}
        return status(r?.error||'Mehrfachlöschung fehlgeschlagen',true,'Mehrfachlöschung');
      }
      placedSelected.clear();await reloadPlaced();status(`${r.count||ids.length} platzierte Objekte gelöscht.`);
    }catch(e){status(e.message,true,'Mehrfachlöschung');}
  };
  $('psSearch').oninput=render;$('psShowLegacy').onchange=render;$('psReload').onclick=()=>reload();$('psNew').onclick=()=>preview(null);$('psDirectSave').onclick=directSave;
  $('psCatConfirm').onclick=async()=>{const label=$('psCatName').value.trim();const r=await call('categoryCreate',{label});if(!r.ok)return status(r.error,true);$('psCatName').value='';await reload();};
  $('psDebugOnlyErrors').onchange=debugRender;
  $('psDebugClear').onclick=()=>{logs.length=0;debugErrorCount=0;f2Seen.clear();debugRender();};
  $('psDebugCopy').onclick=()=>{
    const area=document.createElement('textarea');area.value=logs.map(x=>x.line).join('\n');document.body.append(area);area.select();document.execCommand('copy');area.remove();
  };
  $('psDebugF2').onclick=async()=>{
    try{
      const r=await post('buildingDebugRead',{});
      if(!r?.ok){log(r?.error||'F2-Snapshot fehlgeschlagen',true,'F2 Diagnose');return;}
      const data=r.data||{},state=data.state||{};
      log(`F2 Zustand: aktiv=${!!data.active}, Snapping=${!!data.magnet}, Phase=${state.phase||'–'}, Server=${state.server||'–'}`,false,'F2 Diagnose');
      for(const e of (data.events||[]).slice().reverse()){
        const key=`${e.time}:${e.step}:${e.detail}`;if(f2Seen.has(key))continue;
        f2Seen.add(key);log(`${e.step}: ${e.detail}`,e.level==='error','F2 Trace');
      }
      if(state.lastError&&state.lastError!=='-'&&!(data.events||[]).some(e=>e.level==='error'&&e.detail===state.lastError)){
        const key='last:'+state.lastError;if(!f2Seen.has(key)){f2Seen.add(key);log(state.lastError,true,'F2 Letzter Fehler');}
      }
      if(f2Seen.size>600)f2Seen.clear();
    }catch(e){log(e.message,true,'F2 Diagnose');}
  };
  const settingsKey='bs19.propstudio.settings.v6';const ids=['psShowBounds','psBoundsColor','psGizmoSize','psDefaultGrid'];try{const saved=JSON.parse(localStorage.getItem(settingsKey)||'{}');for(const id of ids){if(saved[id]!==undefined){const node=$(id);if(node.type==='checkbox')node.checked=!!saved[id];else node.value=saved[id];}}}catch(_){};
  function saveSettings(){const values={};for(const id of ids){const node=$(id);values[id]=node.type==='checkbox'?node.checked:node.value;}localStorage.setItem(settingsKey,JSON.stringify(values));$('psGizmoSizeValue').textContent=values.psGizmoSize;}
  for(const id of ids)$(id).addEventListener('input',saveSettings);saveSettings();
  window.addEventListener('message',e=>{if(e.data?.action==='propStudioError')status(e.data.message||'3D-Editor Fehler',true,e.data.source||'F2 / 3D');});
  window.addEventListener('error',e=>status(`${e.message} (${e.filename}:${e.lineno}:${e.colno})\n${e.error?.stack||''}`,true,'NUI JavaScript'));
  window.addEventListener('unhandledrejection',e=>status(e.reason?.stack||String(e.reason||'Promise-Fehler'),true,'NUI Promise'));
  window.addEventListener('securitypolicyviolation',e=>log(`${e.violatedDirective} · ${e.blockedURI}`,true,'NUI CSP'));
  // Some F10 modules report recoverable problems through console.error instead
  // of throwing. Capture those too without changing their console output.
  const previousConsoleError=console.error.bind(console);
  console.error=(...args)=>{
    previousConsoleError(...args);
    try{log(args.map(v=>v?.stack||String(v)).join(' '),true,'NUI Konsole');}catch(_){}
  };
  
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
  categorySelect();activate('existing');initNewCosts();
})();

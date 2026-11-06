(()=>{
const $=id=>document.getElementById(id);let state=null,stance='defensive',pending=null,working=false,hudAllowed=true,hudState=null;let receivedAt=0;const waits=new Map();
const orders=[['follow','Follow','Stay close'],['wait','Hold here','Keep this position'],['guard','Guard','Watch this position'],['hide','Stay hidden','Quiet defensive stance'],['sit','Sit tight','Rest in place'],['regroup','Regroup','Return to your side'],['enter','Get in','Use a free passenger seat'],['exit','Get out','Leave the vehicle'],['target','Target NPC','Engage your aimed target'],['cancel','Stand down','Cancel the current order']];
async function post(route,body={}){try{const r=await fetch(`https://${GetParentResourceName()}/${route}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});return await r.json()}catch(_){return {ok:false,error:'No server response.'}}}
function text(node,value){node.textContent=value}
let dict={};const t=(k,f)=>dict[k]||f||k;
function translate(){document.querySelectorAll('[data-i18n]').forEach(n=>{if(dict[n.dataset.i18n])n.textContent=dict[n.dataset.i18n]})}
function ammoRow(c){const m=c?.ammoMode||'normal';document.querySelectorAll('[data-ammo]').forEach(b=>{b.classList.toggle('selected',b.dataset.ammo===m);b.disabled=!c});const w=c?.weapon;text($('ammoNow'),w?(w.melee?t('link.melee','Melee'):t('link.rounds','{n} rds').replace('{n}',w.ammo)):t('link.unarmed','Unarmed'))}
async function action(route,body){if(working)return;working=true;text($('status'),'Working...');const r=await post(route,body);working=false;text($('status'),r.ok?'Done':r.error||'Unavailable');return r}
function tab(name){document.querySelectorAll('.page').forEach(n=>n.hidden=n.id!==name);document.querySelectorAll('[data-tab]').forEach(n=>n.classList.toggle('selected',n.dataset.tab===name));if(name==='trade')bags()}
function remaining(char){return Math.max(0,Math.ceil((waits.get(String(char.id))||0)-(Date.now()-receivedAt)/1000))}
function duration(seconds){return `${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')}`}
function renderRoster(){
 const data=state;if(!data?.ok)return;const box=$('roster');box.replaceChildren();const c=data.companion;
 text($('rosterCount'),`${data.characters.length} saved survivors`);
 for(const [index,char]of data.characters.entries()){
  const active=String(char.id)===String(data.active),linked=c&&String(c.id)===String(char.id),wait=remaining(char);
  const row=document.createElement('article');row.className='survivor'+(active?' active':linked?' linked':'');
  const number=document.createElement('span');number.className='record-number';text(number,String(index+1).padStart(2,'0'));
  const label=document.createElement('div');label.className='record-details';
  const tag=document.createElement('span');tag.className='tag';text(tag,active?'In control':linked?(c.life?.status==='alive'?'Companion':c.life?.status||'Unavailable'):wait?'Recovering':'Available');
  const name=document.createElement('h2'),detail=document.createElement('p');text(name,`${char.first_name} ${char.last_name}`);text(detail,`${char.classLabel||char.class||'Survivor'} / Level ${char.level||1}`);
  label.append(tag,name,detail);row.append(number,label);
  const side=document.createElement('div');side.className='record-action';
  if(!active&&!linked){const button=document.createElement('button');text(button,wait?`Available in ${duration(wait)}`:'Call survivor');button.disabled=!!c||wait>0;button.onclick=()=>action('summon',{id:char.id});side.append(button);if(c&&!wait){const hint=document.createElement('small');text(hint,'Dismiss your companion first');side.append(hint)}}
  else {const badge=document.createElement('span');badge.className='record-badge';text(badge,active?'Active survivor':c.command||'Following');side.append(badge)}
  row.append(side);box.append(row);
 }
 ammoRow(c);$('gear').disabled=!c||c.life?.status==='dead'; $('companionActions').hidden=!c; const alive=c?.life?.status==='alive';$('switch').disabled=!alive;$('revive').disabled=c?.life?.status!=='downed'||!!c?.life?.flat;$('dismiss').disabled=!c||c.life?.status==='downed';
 const listening=!!c&&c.life?.status!=='dead';document.querySelectorAll('#orders button,[data-stance]').forEach(b=>b.disabled=!listening);document.querySelectorAll('#factionJoin,#squadJoin').forEach(b=>b.disabled=!alive);
 const notice=$('cooldownNotice'),recovering=data.characters.filter(char=>remaining(char)>0);
 notice.hidden=!recovering.length;text(notice,recovering.length?`Companion recall available in ${duration(Math.min(...recovering.map(remaining)))}.`:'');
 text($('subtitle'),c?`${c.name} / ${c.command||'Follow'} / ${c.stance||'Defensive'}`:'Call a saved survivor to join you. One companion at a time.');
}
function roster(data){state=data;if(!data?.ok){text($('status'),data?.error||'Unavailable');return}receivedAt=Date.now();waits.clear();for(const char of data.characters||[])waits.set(String(char.id),Math.max(0,Math.max(Number(char.linkAvailableIn)||0,Number(data.cooldown)||0)));renderRoster()}
setInterval(()=>{if(!$('root').hidden&&state?.ok&&[...waits.values()].some(v=>v>0))renderRoster()},1000);
async function command(id){const r=await action('command',{command:id,stance:id==='hide'?'hidden':stance});if(r?.queued)text($('status'),r.label);return r}
for(const [id,label,hint]of orders){const b=document.createElement('button'),s=document.createElement('small');text(b,label);text(s,hint);b.append(s);b.onclick=()=>command(id);$('orders').append(b)}
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>b.dataset.tab==='trade'?post('tradeStart'):tab(b.dataset.tab));document.querySelectorAll('[data-stance]').forEach(b=>b.onclick=()=>{stance=b.dataset.stance;document.querySelectorAll('[data-stance]').forEach(x=>x.classList.toggle('selected',x===b));});
async function bags(){const r=await action('bags');if(!r?.ok)return;for(const [key,direction]of [['mine','give'],['theirs','take']]){$(key).replaceChildren();for(const e of r[key]){const b=document.createElement('button'),count=document.createElement('span');text(b,e.label);text(count,'�'+e.amount);b.append(count);b.onclick=()=>{pending={direction,slot:e.slot,id:e.id};text($('offer'),`${direction==='give'?'Give':'Take'} ${e.amount} � ${e.label}?`);$('confirm').hidden=false};$(key).append(b)}}}
$('confirmTrade').onclick=async()=>{if(!pending)return;const r=await action('trade',pending);if(r?.ok){pending=null;$('confirm').hidden=true;bags()}};$('cancelTrade').onclick=()=>{pending=null;$('confirm').hidden=true};
document.querySelectorAll('[data-ammo]').forEach(b=>b.onclick=async()=>{const r=await action('ammoMode',{mode:b.dataset.ammo});if(r?.ok&&state?.companion){state.companion.ammoMode=b.dataset.ammo;ammoRow(state.companion)}});
$('gear').onclick=()=>action('gear');
$('factionJoin').onclick=()=>action('factionJoin');$('squadJoin').onclick=()=>action('squadJoin');
$('close').onclick=()=>post('close');$('switch').onclick=()=>action('switch');$('dismiss').onclick=()=>action('dismiss');$('revive').onclick=()=>action('revive');
window.addEventListener('keydown',e=>{if(e.key==='Escape')post('close')});window.addEventListener('message',({data:d})=>{
if(d.action==='bs_i18n'){dict=d.dict||{};translate()}
if(d.action==='open'){roster(d.data);$('root').hidden=false;tab('squad')}
if(d.action==='close'){$('root').hidden=true;pending=null;$('confirm').hidden=true}
if(d.action==='tab'&&d.tab==='commands')tab(d.tab);
if(d.action==='roster')roster(d.data);
if(d.action==='hudVisibility'){hudAllowed=d.visible===true;$('indicator').hidden=!hudAllowed||!hudState?.data||!hudState?.showHud;}
if(d.action==='state'){hudState=d;$('indicator').hidden=!hudAllowed||!d.data||!d.showHud;if(d.data){text($('hudName'),d.data.name);text($('hudState'),d.data.life.status==='alive'?d.data.command:d.data.life.status)}if(state){state.companion=d.data;renderRoster()}}
});})();

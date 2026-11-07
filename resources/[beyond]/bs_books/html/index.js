// BS19 book reader: legacy image books + F10-created dynamic books.
'use strict';
const reader=document.getElementById('reader'),bookElement=document.getElementById('book');
const prev=document.getElementById('prev'),next=document.getElementById('next');
const themes=['standard','clean','rusty','torn'];
let pages=[],book='',index=0,turning=false;
const $=id=>document.getElementById(id);
function safeUrl(v){return typeof v==='string'&&(/^https:\/\/[^\s"'<>]+$/i.test(v)||/^data:image\/(?:jpeg|png|webp);base64,[a-z0-9+/=]+$/i.test(v))?v:'';}
function fontStack(key){return ({georgia:'Georgia,serif',arial:'Arial,sans-serif',courier:'"Courier New",monospace',caveat:'Caveat,cursive',kalam:'Kalam,cursive',cinzel:'Cinzel,serif'})[key]||'Georgia,serif';}
function drawPage(side,p){
 const im=$(side),outer=im.closest('.page'),box=$(side+'Content');
 outer.classList.remove(...themes.map(t=>'theme-'+t));outer.classList.add('theme-'+(themes.includes(p?.layout)?p.layout:'standard'));
 const bg=safeUrl(p?.background)||safeUrl(pages[0]?.background);
 outer.style.backgroundImage=bg?`url("${bg}")`:'';outer.style.backgroundSize=bg?'100% 100%':'';
 box.replaceChildren();
 if(p?.source==='dynamic'){
  im.hidden=true;im.removeAttribute('src');box.hidden=false;
  const t=document.createElement('div');t.className='dynamic-page__text';t.textContent=p.text||'';
  t.style.fontSize=Math.max(12,Math.min(24,Number(p.fontSize)||({small:13,normal:17,large:23})[p.font]||17))+'px';
  t.style.fontFamily=fontStack(p.fontFamily);t.style.textAlign=['left','center','right'].includes(p.align)?p.align:'left';
  t.style.color=/^#[0-9a-f]{6}$/i.test(p.color||'')?p.color:'#352719';box.append(t);
  const url=safeUrl(p.image);if(url){const pic=document.createElement('img');pic.className='dynamic-page__image';pic.src=url;pic.alt='Buchillustration';box.append(pic)}
 }else{
  box.hidden=true;im.hidden=!p;
  if(p){const name=String(p.pageName||'');if(p.source==='web')im.src=safeUrl(name);else if(/^[a-z0-9_-]+$/i.test(name))im.src=`img/${book}/${name}.png`;else im.removeAttribute('src')}
  else im.removeAttribute('src');
 }
}
function update(){
 const theme=themes.includes(pages[0]?.layout)?pages[0].layout:'standard';
 bookElement.classList.remove(...themes.map(t=>'theme-'+t));bookElement.classList.add('theme-'+theme);
 drawPage('left',pages[index]);drawPage('right',pages[index+1]);
 $('counter').textContent=pages.length?`${index+1}–${Math.min(index+2,pages.length)} / ${pages.length}`:'–';
 prev.disabled=index===0;next.disabled=index+2>=pages.length;
}
function clear(){reader.hidden=true;pages=[];turning=false;bookElement.classList.remove('turn-next','turn-prev')}
function close(){clear();if(typeof GetParentResourceName==='function')fetch(`https://${GetParentResourceName()}/closeBook`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});}
function turn(direction){if(turning||reader.hidden)return;const target=Math.max(0,Math.min(index+direction*2,Math.max(0,Math.ceil(pages.length/2)*2-2)));if(target===index)return;turning=true;const cls=direction>0?'turn-next':'turn-prev';bookElement.classList.add(cls);setTimeout(()=>{index=target;update();bookElement.classList.remove(cls);turning=false},170)}
window.addEventListener('message',e=>{const d=e.data;if(!d||typeof d!=='object')return;
 if(d.action==='open'&&Array.isArray(d.pages)&&/^[a-z0-9_]+$/.test(d.book)){
  book=d.book;pages=d.pages;index=0;turning=false;bookElement.classList.remove('turn-next','turn-prev');
  $('title').textContent=d.title||book.replaceAll('_',' ');reader.hidden=false;update();
 }else if(d.action==='close')clear();
});
$('close').addEventListener('click',close);prev.addEventListener('click',()=>turn(-1));next.addEventListener('click',()=>turn(1));
document.addEventListener('keydown',e=>{if(reader.hidden)return;if(e.key==='Escape')close();else if(e.key==='ArrowRight')turn(1);else if(e.key==='ArrowLeft')turn(-1)});

const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(process.argv[2]||'.');let count=0;
const check=(v,label)=>{count++;assert(v,label);};
function world(){
 let now=0,sequence=0,listener,fetches=0,ids=0;const timers=new Map();
 const style=()=>({setProperty(k,v){this[k]=v;}});
 const host={hidden:true,style:style(),classList:{set:new Set(),add(v){this.set.add(v)},remove(v){this.set.delete(v)}}};
 const grid={children:[],style:style(),replaceChildren(){this.children=[]},appendChild(v){this.children.push(v)}};
 const context={document:{getElementById:id=>id==='pickupVisual'?host:grid},performance:{now:()=>now},
  setTimeout:(fn,ms)=>{const id=++ids;timers.set(id,{fn,at:now+ms});return id;},clearTimeout:id=>timers.delete(id),
  GetParentResourceName:()=> 'bs_inventory',fetch:()=>{fetches++;return Promise.resolve({});},console};
 context.window=context;context.addEventListener=(_,fn)=>listener=fn;
 context.BSInventorySlots={cells(){},create:(entry,options)=>({entry:{...entry},options,style:style()})};
 vm.runInNewContext(fs.readFileSync(path.join(root,'resources/[beyond]/bs_inventory/html/js/pickups.js'),'utf8'),context);
 const send=data=>listener({data});
 function receive(changes,settings,seq){send({action:'pickups',settings,packet:{epoch:'run',sequence:seq??++sequence,changes}});}
 function advance(ms){const end=now+ms;while(true){let id,earliest=Infinity;for(const[k,t]of timers)if(t.at<earliest){id=k;earliest=t.at;}if(id===undefined||earliest>end)break;const t=timers.get(id);timers.delete(id);now=earliest;t.fn();}now=end;}
 return{host,grid,send,receive,advance,timers,fetches:()=>fetches,plate:()=>grid.children.at(-1)};
}
const item=(name='water',n=1)=>({item:name,amount:n,kind:'received',w:1,h:1,category:'drink'});
let w=world();check(w.host.hidden,'initially hidden');w.receive([item()]);check(w.plate().entry.amount===1,'x1');
check(w.plate().options.name===false&&w.plate().options.countOnly,'image and count only');
w.advance(2500);check(w.host.classList.set.has('is-fading'),'CSS fade after display duration');w.advance(180);check(w.host.hidden&&w.timers.size===0,'ends without idle timer');check(w.fetches()===1,'one NUI startup handshake');
w=world();w.receive([item('water',2)]);w.advance(200);w.receive([item('water',4)]);check(w.plate().entry.amount===6,'short-window merge is true sum');
w.advance(400);w.receive([item('water',3)]);w.advance(2080);check(w.plate().entry.amount===3,'later same item queued separately');
w=world();w.receive([item('water',2),item('scrap',4),item('food',1)]);check(w.plate().entry.item==='water','ordered first');w.advance(2680);check(w.plate().entry.item==='scrap','ordered second');w.advance(2680);check(w.plate().entry.item==='food','ordered third');
w=world();w.send({action:'pickupProgress',state:{active:true,bottom:'177.25px'}});w.receive([item()]);check(w.host.hidden,'progress takes priority');check(w.host.style.bottom==='177.25px','real progress owner placement');w.advance(5000);check(w.host.hidden,'no guessed progress timeout');
w.send({action:'pickupProgress',state:{active:false}});check(!w.host.hidden,'starts only when area free');w.advance(1000);w.send({action:'pickupProgress',state:{active:true}});check(w.host.hidden,'hides immediately on overlap');w.advance(8000);w.send({action:'pickupProgress',state:{active:false}});w.advance(1499);check(!w.host.hidden,'preserves remaining visible time');w.advance(181);check(w.host.hidden,'no duplicated receipt on resume');
w=world();w.receive([item()],undefined,1);w.receive([item()],undefined,1);check(w.plate().entry.amount===1,'duplicate batch suppressed');
w=world();w.receive([item()],{enabled:false});check(w.host.hidden&&w.timers.size===0,'disabled has no output or work');
w=world();w.receive([item(),{...item('scrap'),kind:'removed'}]);w.advance(2680);check(w.host.hidden,'removed hidden by default');
w.receive([{...item('scrap',2),kind:'removed'}],{showRemoved:true});check(w.plate().entry.amount===2,'opt-in removals');
w=world();w.receive([item()],{showAmount:false});check(w.plate().options.amount===false,'optional quantity');
w=world();w.receive([{...item(),w:2,h:3}]);check(w.grid.style['--cols']===2&&w.grid.style['--rows']===3,'native multi-cell footprint');
w=world();w.receive([{...item(),item:'<img src=x onerror=alert(1)>'},item('water',NaN),item('water',-1)]);check(w.host.hidden,'unsafe identifiers and invalid quantities rejected');
w=world();w.receive([item('active')]);w.advance(500);w.send({action:'pickupProgress',state:{active:true}});w.receive(Array.from({length:25},(_,i)=>item('item'+i)));w.send({action:'pickupProgress',state:{active:false}});w.advance(2180);check(w.plate().entry.item==='item5','bounded queue discards oldest waiting visuals');
w=world();w.receive([item()]);w.send({action:'pickupReset'});check(w.host.hidden&&w.grid.children.length===0&&w.timers.size===0,'logout/restart reset');
w=world();w.receive([item()],{duration:100,mergeWindow:400});w.advance(110);w.receive([item()]);w.advance(170);check(w.plate().entry.amount===1,'does not merge new item into a fading receipt');
const code=fs.readFileSync(path.join(root,'resources/[beyond]/bs_inventory/html/js/pickups.js'),'utf8');
check(!/setInterval|requestAnimationFrame/.test(code),'no recurring poll or render loop');
console.log(`PASS: ${count} pickup queue/lifecycle/security assertions`);

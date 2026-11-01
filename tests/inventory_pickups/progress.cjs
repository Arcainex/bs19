const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(process.argv[2]||'.');let n=0,now=0,id=0;const timers=new Map(),events={},reports=[];
const check=(v,label)=>{n++;assert(v,label);};
const element=()=>({style:{},classList:{values:new Set(['hidden']),add(v){this.values.add(v)},remove(v){this.values.delete(v)},contains(v){return this.values.has(v)},toggle(v,on){if(on)this.add(v);else this.remove(v);}},textContent:'',innerHTML:''});
const nodes={progress:element(),'progress-fill':element(),'progress-label':element(),dot:element(),options:element()};let bottom='237.6px';
const c={document:{getElementById:k=>nodes[k],documentElement:{style:{setProperty(){}}}},getComputedStyle:()=>({bottom}),
 GetParentResourceName:()=> 'bs_interactions',fetch:(_,o)=>{reports.push(JSON.parse(o.body));return Promise.resolve({});},
 setTimeout:(fn,ms)=>{const key=++id;timers.set(key,{fn,at:now+ms});return key;},clearTimeout:key=>timers.delete(key),t:key=>key};
c.window=c;c.addEventListener=(key,fn)=>events[key]=fn;
vm.runInNewContext(fs.readFileSync(path.join(root,'resources/[beyond]/bs_interactions/html/js/app.js'),'utf8'),c);
const send=data=>events.message({data});
function advance(ms){const end=now+ms;while(true){let k,min=Infinity;for(const[key,t]of timers)if(t.at<min){k=key;min=t.at;}if(k===undefined||min>end)break;const t=timers.get(k);timers.delete(k);now=min;t.fn();}now=end;}
check(reports.length===1&&!reports[0].active,'initial layout and idle status');
send({action:'progress',id:1,duration:1000,label:'SEARCH'});check(reports.at(-1).active,'busy only when actual progress visible');
send({action:'progress',id:2,duration:1000,label:'MACHINE',auto:true});
send({action:'progress',id:1,cancel:true});check(!nodes.progress.classList.contains('hidden'),'old search cannot hide newer progress');
check(timers.size===1,'stale cancel does not kill current auto completion');
advance(1800);check(nodes.progress.classList.contains('hidden')&&!reports.at(-1).active,'auto close releases actual area');
const before=reports.length;events.resize();check(reports.length===before,'no duplicate bridge updates');
bottom='199.75px';events.resize();check(reports.at(-1).bottom===bottom,'placement follows actual owner CSS');
send({action:'progress',id:3,duration:2000});send({action:'progress',id:3,cancel:true});check(!reports.at(-1).active&&timers.size===0,'cancel clears actual occupancy');
console.log(`PASS: ${n} progress ownership/placement assertions`);

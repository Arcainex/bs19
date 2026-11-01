// No browser library dependency. CHROME_BIN can select Chromium on any supported OS.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),http=require('node:http'),cp=require('node:child_process'),assert=require('node:assert/strict');
const readPNG=require('./png.cjs');
const root=path.resolve(process.argv[2]||'.'),output=path.resolve(process.argv[3]||fs.mkdtempSync(path.join(os.tmpdir(),'bs-pickups-')));
fs.mkdirSync(output,{recursive:true});
const candidates=[process.env.CHROME_BIN,...(process.platform==='win32'?['C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe']:['/usr/bin/chromium','/usr/bin/chromium-browser','/usr/bin/google-chrome'])];
const chrome=candidates.find(p=>p&&fs.existsSync(p));assert(chrome,'Set CHROME_BIN to Chromium/Chrome');
const base=path.join(root,'resources/[beyond]'),reports=new Map();let origin;
const fixtureBoot=String.raw`<script>
window.fixtureErrors=[];window.addEventListener('error',e=>fixtureErrors.push(e.message));
const realFetch=window.fetch.bind(window);
window.GetParentResourceName=()=> location.pathname==='/interactions'?'bs_interactions':'bs_inventory';
window.fetch=(url,options)=>{
 if(String(url).startsWith('https://')){
  if(String(url).endsWith('/progressState'))parent.postMessage({fixtureProgress:JSON.parse(options.body)},'*');
  return Promise.resolve(new Response(JSON.stringify({ok:true,scale:Number(new URLSearchParams(location.search).get('scale'))||1,lang:'en',dict:{}}),{headers:{'Content-Type':'application/json'}}));
 }return realFetch(url,options);
};
</script>`;
const fixtureTest=String.raw`<script>
window.addEventListener('load',async()=>{
try{
 const q=new URLSearchParams(location.search),scene=q.get('scene')||'compare',multi=q.get('multi')==='1',missing=q.get('case')==='missing-art';
 BSScale.set(Number(q.get('scale'))||1);
 const entry={item:multi?'toolbox':'scrap_metal',category:multi?'tool':'material',label:'Reference item',amount:5,w:multi?2:1,h:multi?3:1,x:1,y:1,ongrid:true};
 const inv={grid:{w:entry.w,h:entry.h},gridSlots:40,size:45,weight:5,maxWeight:40,slots:{'1':entry}};
 S.player=inv;
 const control=document.createElement('div');control.id='nativeComparison';control.className='grid';control.style.position='fixed';document.body.appendChild(control);
 renderGrid(control,inv,'player');
 window.dispatchEvent(new MessageEvent('message',{data:{action:'pickups',settings:{duration:2500},packet:{epoch:'visual',sequence:1,changes:[entry]}}}));
 const host=document.getElementById('pickupVisual'),pickup=host.querySelector('.slot'),native=control.querySelector('.slot');
 await Promise.all([...document.querySelectorAll('#nativeComparison img,#pickupVisual img')].map(img=>img.complete?Promise.resolve():new Promise(resolve=>{img.addEventListener('load',resolve,{once:true});img.addEventListener('error',resolve,{once:true});})));
 const scale=BSScale.get(),rect=pickup.getBoundingClientRect();
 // Keep real placement for the standalone screenshot. Align wrappers on the same pixel lattice
 // only for the neutral side-by-side plate comparison; no plate style is changed.
 if(scene==='compare'){host.style.left='800px';host.style.top='500px';host.style.bottom='auto';host.style.transform='none';}
 const placed=pickup.getBoundingClientRect();
 control.style.left=(placed.left/scale-330)+'px';control.style.top=(placed.top/scale-10)+'px';
 let checks=0;function check(v,label){checks++;if(!v)throw new Error(label);}
 const props=['backgroundColor','backgroundImage','borderTopWidth','borderTopColor','borderTopStyle','borderRadius','boxShadow','width','height','padding','fontFamily'];
 for(const prop of props)check(getComputedStyle(native)[prop]===getComputedStyle(pickup)[prop],'native plate '+prop);
 for(const selector of ['.slot__icon',missing?'.slot__icon svg':'.slot__icon img','.slot__amount']){
  const a=native.querySelector(selector),b=pickup.querySelector(selector);check(!!a&&!!b,'same element '+selector);
  for(const prop of ['width','height','fontSize','fontFamily','fontWeight','color','textShadow','objectFit'])check(getComputedStyle(a)[prop]===getComputedStyle(b)[prop],selector+' '+prop);
 }
 if(missing){check(!native.querySelector('img')&&!pickup.querySelector('img'),'broken image replaced');check(native.querySelector('svg').outerHTML===pickup.querySelector('svg').outerHTML,'same native fallback art');}
 else{check(native.querySelector('img').naturalWidth>0&&pickup.querySelector('img').naturalWidth>0,'original raster images loaded');check(native.querySelector('img').src===pickup.querySelector('img').src,'identical original image URL');}
 check(!pickup.querySelector('.slot__name'),'no pickup item-name node');
 check(pickup.querySelector('.slot__amount').textContent==='5','correct received amount');
 check(getComputedStyle(pickup.querySelector('.slot__amount'),'::before').content===getComputedStyle(native.querySelector('.slot__amount'),'::before').content,'native x prefix');
 const nr=native.getBoundingClientRect(),pr=pickup.getBoundingClientRect();
 check(Math.abs(nr.width-pr.width)<.001&&Math.abs(nr.height-pr.height)<.001,'exact native dimensions');
 check(Math.abs(nr.left-(pr.left-320*scale))<.03&&Math.abs(nr.top-pr.top)<.03,'aligned screenshot samples');
 check(Math.abs(rect.left+rect.width/2-innerWidth/2)<.03,'real pickup placement is horizontally centred');
 check(getComputedStyle(document.body).backgroundColor==='rgba(0, 0, 0, 0)','transparent NUI canvas CSS');
 check(fixtureErrors.length===0,'no browser errors: '+fixtureErrors.join(';'));
 const result={checks,scale,scene,native:{x:nr.left,y:nr.top,w:nr.width,h:nr.height},pickup:{x:pr.left,y:pr.top,w:pr.width,h:pr.height}};
 if(scene==='inventory'){
  host.hidden=true;control.remove();document.getElementById('root').classList.remove('hidden');renderGrid(document.getElementById('playerGrid'),inv,'player');
  await Promise.all(document.getAnimations().filter(a=>a.effect.getTiming().iterations!==Infinity).map(a=>a.finished.catch(()=>{})));
 }else if(scene==='progress'){
  control.remove();
  async function change(active,id){const completed=new Promise(resolve=>{function listener(event){if(event.data?.action==='pickupProgress'&&event.data.state.active===active){window.removeEventListener('message',listener);resolve();}}window.addEventListener('message',listener);});parent.postMessage({fixtureCommand:{active,id}},'*');await completed;}
  await change(true,1);check(host.hidden,'real progress owner hides active receipt');
  await change(false,1);check(!host.hidden,'actual owner completion releases receipt');
  await change(true,2);check(host.hidden,'new progress keeps queued receipt out of the area');
  await Promise.all(parent.document.getElementById('owner').contentDocument.getElementById('progress').getAnimations().filter(a=>a.effect.getTiming().iterations!==Infinity).map(a=>a.finished.catch(()=>{})));
  result.checks=checks;
 }else if(scene==='pickup')control.remove();
 await realFetch('/__result?case='+q.get('case'),{method:'POST',body:JSON.stringify(result)});
}catch(error){await realFetch('/__result?case='+new URLSearchParams(location.search).get('case'),{method:'POST',body:JSON.stringify({error:error.stack,errors:fixtureErrors})});}
});</script>`;
const server=http.createServer((req,res)=>{
 const u=new URL(req.url,'http://localhost');
 if(u.pathname==='/__result'){
  let text='';req.on('data',b=>text+=b);req.on('end',()=>{reports.set(u.searchParams.get('case'),JSON.parse(text));res.end('{}');});return;
 }
 if(u.pathname==='/'){
  const progress=u.searchParams.get('scene')==='progress';
  const relay=`<script>let ready=false,commands=[];window.addEventListener('message',e=>{if(e.data.fixtureProgress)document.getElementById('inventory').contentWindow.postMessage({action:'pickupProgress',state:e.data.fixtureProgress},'*');if(e.data.fixtureCommand){if(ready)send(e.data.fixtureCommand);else commands.push(e.data.fixtureCommand);}});function send(c){document.getElementById('owner').contentWindow.postMessage(c.active?{action:'progress',id:c.id,duration:10000,auto:true,label:'SEARCHING'}:{action:'progress',id:c.id,cancel:true},'*');}function ownerReady(){ready=true;commands.forEach(send);commands=[];}</script>`;
  const frameStyle='position:fixed;inset:0;width:100%;height:100%;border:0';
  res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html style="height:100%;background:rgb(23,187,122)"><head>${progress?relay:''}</head><body style="margin:0;height:100%;"><iframe id="inventory" style="${frameStyle}" src="/frame${u.search}"></iframe>${progress?`<iframe id="owner" onload="ownerReady()" style="${frameStyle};pointer-events:none" src="/interactions${u.search}"></iframe>`:''}</body></html>`);return;
 }
 let file;
 if(u.pathname==='/frame'){
  let html=fs.readFileSync(path.join(base,'bs_inventory/html/index.html'),'utf8');
  html=html.replace('<head>','<head>'+fixtureBoot+'<base href="/nui/bs_inventory/html/">').replaceAll('nui://',origin+'/nui/').replace('</body>',fixtureTest+'</body>');
  res.setHeader('Content-Type','text/html');res.end(html);return;
 }
 if(u.pathname==='/interactions'){
  let html=fs.readFileSync(path.join(base,'bs_interactions/html/index.html'),'utf8');
  html=html.replace('<head>','<head>'+fixtureBoot+'<base href="/nui/bs_interactions/html/">').replaceAll('nui://',origin+'/nui/');
  res.setHeader('Content-Type','text/html');res.end(html);return;
 }
 if(u.pathname.startsWith('/nui/'))file=path.resolve(base,decodeURIComponent(u.pathname.slice(5)));
 if(!file||!file.startsWith(base+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.statusCode=404;res.end();return;}
 if((req.headers.referer||'').includes('case=missing-art')&&path.extname(file)==='.png'){res.statusCode=404;res.end();return;}
 const ext=path.extname(file);res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.html':'text/html'})[ext]||'application/octet-stream');
 if(ext==='.js')res.end(fs.readFileSync(file,'utf8').replaceAll('nui://',origin+'/nui/'));else fs.createReadStream(file).pipe(res);
});
async function run(){
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));origin=`http://127.0.0.1:${server.address().port}`;
 const cases=[{name:'native-vs-pickup-1080',w:1920,h:1080,scale:1},{name:'native-vs-pickup-720',w:1280,h:720,scale:1},
 {name:'native-vs-pickup-1440-scaled',w:2560,h:1440,scale:1.25,multi:true},
 {name:'inventory-open',w:1920,h:1080,scale:1,scene:'inventory'},{name:'pickup-only',w:1920,h:1080,scale:1,scene:'pickup'},
 {name:'missing-art',w:1920,h:1080,scale:1},{name:'progress-priority',w:1920,h:1080,scale:1,scene:'progress'}];
 let assertions=0;const results=[];
 for(const c of cases){
  const screenshot=path.join(output,c.name+'.png'),profile=path.join(output,c.name+'-profile');
  const url=origin+'/?'+new URLSearchParams({case:c.name,scale:c.scale,scene:c.scene||'compare',multi:c.multi?'1':'0'});
  // Explicit DevTools viewport avoids the CLI screenshot resizing the page after its measurements.
  const portFile=path.join(profile,'DevToolsActivePort');if(fs.existsSync(profile))fs.rmSync(profile,{recursive:true,force:true});
  const child=cp.spawn(chrome,['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-extensions','--hide-scrollbars','--remote-debugging-port=0',`--user-data-dir=${profile}`],{windowsHide:true,stdio:'ignore'});
  let socket;
  try {
   const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));const started=Date.now();
   while(!fs.existsSync(portFile)){assert(Date.now()-started<15000,'Chromium startup timeout');await wait(30);}
   const [port,endpoint]=fs.readFileSync(portFile,'utf8').trim().split(/\r?\n/);
   socket=new WebSocket(`ws://127.0.0.1:${port}${endpoint}`);await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
   let id=0;const pending=new Map();socket.onmessage=message=>{const data=JSON.parse(message.data);if(data.id&&pending.has(data.id)){const p=pending.get(data.id);pending.delete(data.id);data.error?p.reject(new Error(JSON.stringify(data.error))):p.resolve(data.result);}};
   const call=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const request={id:++id,method,params};if(sessionId)request.sessionId=sessionId;pending.set(id,{resolve,reject});socket.send(JSON.stringify(request));});
   const {targetId}=await call('Target.createTarget',{url:'about:blank'});const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
   await call('Page.enable',{},sessionId);await call('Emulation.setDeviceMetricsOverride',{width:c.w,height:c.h,deviceScaleFactor:1,mobile:false},sessionId);
   await call('Page.navigate',{url},sessionId);
   while(!reports.has(c.name)){assert(Date.now()-started<20000,'NUI test result timeout');await wait(20);}
   const image=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},sessionId);fs.writeFileSync(screenshot,Buffer.from(image.data,'base64'));
  } finally {if(socket)socket.close();child.kill();await new Promise(resolve=>child.exitCode!==null?resolve():child.once('exit',resolve));}
  const report=reports.get(c.name);assert(report,`No browser result: ${c.name}`);fs.writeFileSync(path.join(output,c.name+'.json'),JSON.stringify(report,null,2));assert(!report.error,report.error);assertions+=report.checks;
  const png=readPNG(screenshot);
  // The opened native inventory intentionally draws its existing vignette; pickup-only must not.
  if(c.scene!=='inventory'){assert.deepEqual(png.pixel(5,5),[23,187,122,255],'no opaque NUI overlay');assertions++;}
  if(!c.scene){
   let differences=0,total=0,max=0;const a=report.native,b=report.pickup;
   const width=Math.ceil(a.w),height=Math.ceil(a.h);
   for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const p=png.pixel(Math.floor(a.x)+x,Math.floor(a.y)+y),q=png.pixel(Math.floor(b.x)+x,Math.floor(b.y)+y);
    // CSS/geometry equality above is exact. Allow only small raster/compositor rounding
    // in screenshot channels (the fading wrapper and the ordinary grid can use different layers).
    const delta=Math.max(...p.map((v,i)=>Math.abs(v-q[i])));max=Math.max(max,delta);if(delta>4)differences++;total++;
   }
   report.pixelComparison={differences,total,maxChannelDelta:max,channelRoundingTolerance:4};
   assert.equal(differences,0,`slot pixel mismatch ${c.name}: ${differences}/${total}, max ${max}`);assertions++;
  }
  results.push({name:c.name,...report,screenshot:path.basename(screenshot)});
  // These are test-created browser profiles under the supplied output directory, never source files.
  assert(profile.startsWith(output+path.sep));fs.rmSync(profile,{recursive:true,force:true});
 }
 fs.writeFileSync(path.join(output,'browser-results.json'),JSON.stringify({assertions,results},null,2));
 console.log(`PASS: ${assertions} real-browser visual assertions; ${cases.length} screenshots in ${output}`);
}
run().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>server.close());

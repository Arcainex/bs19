// HSV colour wheel: hue ring, saturation/value square and a hex field. Used by the weapon workbench.
(() => {
'use strict';
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
function hsvToRgb(h,s,v){const f=n=>{const k=(n+h/60)%6;return v-v*s*Math.max(0,Math.min(k,4-k,1));};return[f(5),f(3),f(1)].map(x=>Math.round(x*255));}
function rgbToHsv(r,g,b){r/=255;g/=255;b/=255;const max=Math.max(r,g,b),min=Math.min(r,g,b),d=max-min;let h=0;
 if(d){if(max===r)h=((g-b)/d)%6;else if(max===g)h=(b-r)/d+2;else h=(r-g)/d+4;h*=60;if(h<0)h+=360;}return[h,max?d/max:0,max];}
const toHex=rgb=>'#'+rgb.map(x=>x.toString(16).padStart(2,'0')).join('').toUpperCase();
const fromHex=hex=>{const m=/^#?([0-9a-f]{6})$/i.exec(String(hex||'').trim());if(!m)return null;const n=parseInt(m[1],16);return[n>>16&255,n>>8&255,n&255];};
function create(host,opts={}){
 const size=opts.size||200,ring=Math.round(size*.1),outer=size/2-2,inner=outer-ring,half=inner*.70;
 host.classList.add('cw');host.innerHTML=`<canvas width="${size*2}" height="${size*2}" style="width:${size}px;height:${size}px"></canvas><div class="cw__side"><span class="cw__swatch"></span><label class="cw__hex">HEX<input maxlength="7" spellcheck="false"></label>${opts.note?`<small class="cw__note"></small>`:''}</div>`;
 const canvas=host.querySelector('canvas'),ctx=canvas.getContext('2d'),input=host.querySelector('input'),swatch=host.querySelector('.cw__swatch'),note=host.querySelector('.cw__note');
 if(ctx)ctx.scale(2,2);
 let h=0,s=0,v=1,mode=null;
 function draw(){
  const hex0=toHex(hsvToRgb(h,s,v));swatch.style.background=hex0;if(document.activeElement!==input)input.value=hex0;if(!ctx)return;
  const c=size/2;ctx.clearRect(0,0,size,size);
  for(let a=0;a<360;a+=1){ctx.beginPath();ctx.arc(c,c,(outer+inner)/2,(a-91)*Math.PI/180,(a-89)*Math.PI/180);ctx.lineWidth=ring;ctx.strokeStyle=`hsl(${a},90%,52%)`;ctx.stroke();}
  ctx.lineWidth=1;ctx.strokeStyle='rgba(0,0,0,.6)';ctx.beginPath();ctx.arc(c,c,outer,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.arc(c,c,inner,0,Math.PI*2);ctx.stroke();
  const x0=c-half,y0=c-half,w=half*2;
  ctx.fillStyle=toHex(hsvToRgb(h,1,1));ctx.fillRect(x0,y0,w,w);
  let g=ctx.createLinearGradient(x0,0,x0+w,0);g.addColorStop(0,'#fff');g.addColorStop(1,'rgba(255,255,255,0)');ctx.fillStyle=g;ctx.fillRect(x0,y0,w,w);
  g=ctx.createLinearGradient(0,y0,0,y0+w);g.addColorStop(0,'rgba(0,0,0,0)');g.addColorStop(1,'#000');ctx.fillStyle=g;ctx.fillRect(x0,y0,w,w);
  ctx.strokeStyle='rgba(0,0,0,.7)';ctx.strokeRect(x0+.5,y0+.5,w-1,w-1);
  const ha=(h-90)*Math.PI/180,hr=(outer+inner)/2;
  ctx.lineWidth=3;ctx.strokeStyle='#fff';ctx.beginPath();ctx.arc(c+Math.cos(ha)*hr,c+Math.sin(ha)*hr,ring/2,0,Math.PI*2);ctx.stroke();
  ctx.lineWidth=1.5;ctx.strokeStyle='#000';ctx.beginPath();ctx.arc(c+Math.cos(ha)*hr,c+Math.sin(ha)*hr,ring/2+2,0,Math.PI*2);ctx.stroke();
  const sx=x0+s*w,sy=y0+(1-v)*w;ctx.lineWidth=2.5;ctx.strokeStyle=v>.55?'#000':'#fff';ctx.beginPath();ctx.arc(sx,sy,6,0,Math.PI*2);ctx.stroke();
  const hex=toHex(hsvToRgb(h,s,v));swatch.style.background=hex;if(document.activeElement!==input)input.value=hex;
 }
 function pick(e,emit){
  const r=canvas.getBoundingClientRect(),k=size/r.width,x=(e.clientX-r.left)*k-size/2,y=(e.clientY-r.top)*k-size/2;
  if(!mode){const d=Math.hypot(x,y);mode=d>=inner-3&&d<=outer+4?'ring':Math.abs(x)<=half+4&&Math.abs(y)<=half+4?'square':null;if(!mode)return false;}
  if(mode==='ring'){h=(Math.atan2(y,x)*180/Math.PI+90+360)%360;}else{s=clamp((x+half)/(half*2),0,1);v=clamp(1-(y+half)/(half*2),0,1);}
  draw();emit&&opts.onInput&&opts.onInput(toHex(hsvToRgb(h,s,v)));return true;
 }
 canvas.addEventListener('pointerdown',e=>{if(e.button!==0||host.classList.contains('is-disabled'))return;mode=null;if(pick(e,true))canvas.setPointerCapture(e.pointerId);});
 canvas.addEventListener('pointermove',e=>{if(mode)pick(e,true);});
 const done=()=>{if(!mode)return;mode=null;opts.onChange&&opts.onChange(toHex(hsvToRgb(h,s,v)));};
 canvas.addEventListener('pointerup',done);canvas.addEventListener('pointercancel',done);
 input.addEventListener('keydown',e=>{e.stopPropagation();if(e.key==='Enter')input.blur();});
 input.addEventListener('change',()=>{const rgb=fromHex(input.value);if(!rgb){input.classList.add('is-bad');return;}input.classList.remove('is-bad');api.set(toHex(rgb));opts.onInput&&opts.onInput(api.get());opts.onChange&&opts.onChange(api.get());});
 const api={
  set(hex){const rgb=fromHex(hex);if(!rgb)return;const[nh,ns,nv]=rgbToHsv(...rgb);if(ns>0&&nv>0)h=nh;s=ns;v=nv;draw();},
  get(){return toHex(hsvToRgb(h,s,v));},
  note(text){if(note)note.textContent=text||'';},
  disable(on){host.classList.toggle('is-disabled',!!on);input.disabled=!!on;},
 };
 draw();return api;
}
window.BSColourWheel={create,fromHex,toHex,distance(a,b){const x=fromHex(a),y=fromHex(b);if(!x||!y)return Infinity;
 // weighted RGB distance, close enough to perceptual for picking a finish
 const r=(x[0]+y[0])/2,dr=x[0]-y[0],dg=x[1]-y[1],db=x[2]-y[2];return Math.sqrt((2+r/256)*dr*dr+4*dg*dg+(2+(255-r)/256)*db*db);}};
})();

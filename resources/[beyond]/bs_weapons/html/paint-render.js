// Draws one painted texture part: base colour, pattern, wear/grain and brush strokes, in texture (UV) space.
// Shared by the in-game texture page (paint.html) and the workbench brush canvas, so both look the same.
(() => {
'use strict';
function rng(seed){let s=seed>>>0||1;return()=>{s^=s<<13;s^=s>>>17;s^=s<<5;return((s>>>0)%100000)/100000}}
function seedOf(text){let h=2166136261;for(const c of String(text))h=Math.imul(h^c.charCodeAt(0),16777619);return h>>>0}
function draw(ctx,size,part,seedText){
 ctx.save();ctx.clearRect(0,0,size,size);
 if(!part||!part.base){ctx.restore();return}
 ctx.fillStyle=part.base;ctx.fillRect(0,0,size,size);
 const r=rng(seedOf(seedText||'paint')),c2=part.colour2||'#1E1E1C',k=size/512;
 if(part.pattern==='stripes'){ctx.fillStyle=c2;ctx.save();ctx.translate(size/2,size/2);ctx.rotate(-Math.PI/4);for(let x=-size;x<size;x+=64*k)ctx.fillRect(x,-size,24*k,size*2);ctx.restore()}
 else if(part.pattern==='twotone'){ctx.fillStyle=c2;ctx.fillRect(0,size*.5,size,size*.5)}
 else if(part.pattern==='camo'){ctx.fillStyle=c2;for(let i=0;i<22;i++){ctx.beginPath();const x=r()*size,y=r()*size,w=(30+r()*70)*k;for(let a=0;a<7;a++){const t=a/7*Math.PI*2,rr=w*(.55+r()*.6);ctx[a?'lineTo':'moveTo'](x+Math.cos(t)*rr,y+Math.sin(t)*rr*.7)}ctx.closePath();ctx.fill()}}
 // Lua sends an empty list as {}; accept both shapes.
 const strokes=Array.isArray(part.strokes)?part.strokes:Object.values(part.strokes||{});
 for(const s of strokes){const p=s.p||[];if(p.length<2)continue;ctx.strokeStyle=s.e?part.base:s.c;ctx.fillStyle=ctx.strokeStyle;ctx.lineWidth=s.s*k;ctx.lineCap='round';ctx.lineJoin='round';ctx.beginPath();
  ctx.moveTo(p[0]/1000*size,p[1]/1000*size);if(p.length===2){ctx.arc(p[0]/1000*size,p[1]/1000*size,s.s*k/2,0,Math.PI*2);ctx.fill();continue}
  for(let i=2;i<p.length;i+=2)ctx.lineTo(p[i]/1000*size,p[i+1]/1000*size);ctx.stroke()}
 // grain and wear: keeps a flat colour from looking like plastic; wear lightens random edges
 const wear=Number(part.wear??.35);ctx.globalAlpha=.10+wear*.12;
 for(let i=0;i<1400*k*k;i++){ctx.fillStyle=r()<.5?'#000':'#fff';ctx.fillRect(r()*size,r()*size,1+r()*2*k,1+r()*2*k)}
 ctx.globalAlpha=wear*.5;ctx.strokeStyle='#cfc8b8';ctx.lineWidth=1.2*k;
 for(let i=0;i<Math.round(60*wear);i++){const x=r()*size,y=r()*size;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+(r()-.5)*40*k,y+(r()-.5)*10*k);ctx.stroke()}
 ctx.restore();
}
window.BSPaintRender={draw};
})();

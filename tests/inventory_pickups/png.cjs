// Minimal read-only PNG decoder for Chromium screenshot comparisons (RGB/RGBA, 8 bit, non-interlaced).
const fs=require('node:fs'),zlib=require('node:zlib'),assert=require('node:assert/strict');
module.exports=function readPNG(file){
 const bytes=fs.readFileSync(file);assert.equal(bytes.readUInt32BE(0),0x89504e47);
 let width,height,bpp;const chunks=[];
 for(let p=8;p<bytes.length;){const length=bytes.readUInt32BE(p),type=bytes.toString('ascii',p+4,p+8),data=bytes.subarray(p+8,p+8+length);p+=length+12;
  if(type==='IHDR'){width=data.readUInt32BE(0);height=data.readUInt32BE(4);assert.equal(data[8],8);bpp=data[9]===6?4:data[9]===2?3:0;assert(bpp);assert.equal(data[12],0);}
  if(type==='IDAT')chunks.push(data);
 }
 const raw=zlib.inflateSync(Buffer.concat(chunks)),stride=width*bpp,out=Buffer.alloc(width*height*bpp);
 const paeth=(a,b,c)=>{const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;};
 for(let y=0;y<height;y++){const filter=raw[y*(stride+1)];assert(filter<=4);for(let x=0;x<stride;x++){
  const a=x>=bpp?out[y*stride+x-bpp]:0,b=y?out[(y-1)*stride+x]:0,c=y&&x>=bpp?out[(y-1)*stride+x-bpp]:0;
  const predict=[0,a,b,Math.floor((a+b)/2),paeth(a,b,c)][filter];out[y*stride+x]=(raw[y*(stride+1)+1+x]+predict)&255;
 }}
 return{width,height,pixel(x,y){assert(x>=0&&y>=0&&x<width&&y<height);const p=(y*width+x)*bpp;return[out[p],out[p+1],out[p+2],bpp===4?out[p+3]:255];}};
};

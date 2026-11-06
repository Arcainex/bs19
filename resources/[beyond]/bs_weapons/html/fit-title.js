// Shrinks a one-line title until it fits its box; CSS ellipsis takes over below the minimum size.
window.BSFitTitle=function(el,max,min){
 if(!el)return;max=max||34;min=min||18;let size=max;el.style.fontSize=size+'px';
 const fit=()=>{size=max;el.style.fontSize=size+'px';while(size>min&&el.scrollWidth>el.clientWidth+1){size-=1;el.style.fontSize=size+'px';}};
 fit();requestAnimationFrame(fit);
 if(document.fonts&&document.fonts.ready)document.fonts.ready.then(fit);
};

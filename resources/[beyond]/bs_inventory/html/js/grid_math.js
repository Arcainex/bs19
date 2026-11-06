(function(root) {
    'use strict';
    function footprint(item, rotated = !!item.rot) {
        const w = Math.max(1,Math.floor(Number(item.w)||1)), h = Math.max(1,Math.floor(Number(item.h)||1));
        return rotated ? {w:h,h:w} : {w,h};
    }
    function fits(inv, item, x, y, rotated, ignoreSlot) {
        const size=footprint(item,rotated), width=inv?.grid?.w||8, height=inv?.grid?.h||5;
        if (!Number.isInteger(x)||!Number.isInteger(y)||x<1||y<1||x+size.w-1>width||y+size.h-1>height) return false;
        return Object.entries(inv?.slots||{}).every(([slot,other])=>{
            if (String(slot)===String(ignoreSlot)||!other.x||!other.y||other.ongrid===false) return true;
            const used=footprint(other);
            return x+size.w<=other.x||other.x+used.w<=x||y+size.h<=other.y||other.y+used.h<=y;
        });
    }
    const api={footprint,fits};
    if(typeof module!=='undefined'&&module.exports) module.exports=api;
    else root.BSGridMath=api;
})(typeof window==='undefined'?globalThis:window);

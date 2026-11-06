(()=>{'use strict';
const paths={
 paint_patch:'M20 26 233 19l-6 216-210-7z',
 paint_stripes:'M10 20h48L10 151zm65 0h48L37 236H0zm65 0h48L102 236H54zm65 0h48l-86 216h-48zm51 62v131l-9 23h-48z',
 paint_checker:'M16 16h56v56H16zm112 0h56v56h-56zM72 72h56v56H72zm112 0h56v56h-56zM16 128h56v56H16zm112 0h56v56h-56zM72 184h56v56H72zm112 0h56v56h-56z',
 paint_camo:'M12 34q50-35 91 1t54 7l-23 58-65-17-41 33zM177 12l64 20-16 61-38-24-29-37zM95 117l56-31 32 51 55-7 3 75-68 32-23-63-55 21-47 40-29-71z',

 radiation:'M128 112a16 16 0 1 0 0 32 16 16 0 0 0 0-32M112 100 79 43a98 98 0 0 0-49 86h66a32 32 0 0 1 16-29m32 0 33-57a98 98 0 0 1 49 86h-66a32 32 0 0 0-16-29m-16 60-33 57a98 98 0 0 0 66 0l-33-57',
 biohazard:'M128 112a16 16 0 1 0 0 32 16 16 0 0 0 0-32M117 98C48 62 98 14 117 26 76 26 83 76 122 84V45h12v39c39-8 46-58 5-58 19-12 69 36 0 72l-5 8 23 14c58-29 81 36 58 46 22-32-22-48-53-23l34 20-6 10-34-20c-13 38 27 71 48 36-3 23-69 36-64-36h-10c5 72-61 59-64 36 21 35 61 2 48-36l-34 20-6-10 34-20c-31-25-75-9-53 23-23-10 0-75 58-46l23-14Z',
 lightning:'M144 20 58 142h58l-9 94 91-131h-64z',
 cross:'M98 28h60v70h70v60h-70v70H98v-70H28V98h70z',
 crosshair:'M116 16h24v42h-24zm0 182h24v42h-24zM16 116h42v24H16zm182 0h42v24h-42zM128 69a59 59 0 1 0 0 118 59 59 0 0 0 0-118m0 18a41 41 0 1 1 0 82 41 41 0 0 1 0-82',
 eye:'M18 128q110-124 220 0-110 124-220 0m110-47a47 47 0 1 0 0 94 47 47 0 0 0 0-94m0 22a25 25 0 1 1 0 50 25 25 0 0 1 0-50',
 claw:'M58 18 78 94 45 232 96 99 87 18zm65 0 9 81-23 133 42-137-3-77zm64 0-6 80-19 134 42-134 12-80z',
 tally:'M42 24h13v201H42zm45 0h13v201H87zm45 0h13v201h-13zm45 0h13v201h-13zM16 201 229 52l9 13L25 214z',
 wolf:'M28 28 96 57l32-12 32 12 68-29-22 121-42 59-36 29-36-29-42-59zM69 102l40 25-35 4zm118 0-40 25 35 4zm-79 62 20 13 20-13-20 42z',
 raven:'M21 40 105 79l25-29 30 8 18 25 54 12-43 14-22 48 29 57-72-30-42 21 16-51-61-39 46-3z',
 snake:'M170 28c-121-10-165 85-61 100 96 14 83 86-2 90l-17-22c63 1 84-35 14-48C-23 126 15-4 174 7l45 22-43 28-41-5z',
 reaper:'M128 19 52 74 31 193l68 35-15-69 44 25 44-25-15 69 68-35-21-119zm-43 79 34 16-7 26-35-11zm86 0 8 31-35 11-7-26zm-43 43-13 22h26z',
 broken_heart:'M126 56C43-24-21 107 63 176l65 64 70-68C277 94 205-17 132 51l21 39-30 24 28 34-38 42 10-48-32-34 39-25z',
 blood_hand:'M69 131V64q0-19 16-19t16 19v53V35q0-18 16-18t16 18v79V48q0-17 15-17t15 17v72V76q0-17 14-17t14 17v67q0 50-33 72l-2 25h-61v-24L45 153q-14-22 2-29t22 7z',
 scavenger:'M38 53h180v139H38zm15 20v99h150V73zm25 11h18v42H78zm41 0h18v65h-18zm41 0h18v42h-18zM22 207h212v21H22z',
 chevrons:'M21 59 128 14l107 45v43L128 57 21 102zm0 76 107-45 107 45v43l-107-45-107 45zm0 75 107-45 107 45v32l-107-45-107 45z',
 barbed_wire:'M18 118h220v20H18zM39 66l18-9 46 112-18 9zm65 0 18-9 46 112-18 9zm65 0 18-9 46 112-18 9z',
 cracked_star:'M128 15 154 91l81 2-64 49 23 79-66-46-66 46 23-79-64-49 81-2zm-2 39-11 54 24 17-27 32 21-18 15 28-5-46-18-15z'
};
const words={quarantine:['QUARANTINE'],infected:['INFECTED'],survivor:['SURVIVOR'],no_mercy:['NO','MERCY'],dead_inside:['DEAD','INSIDE'],do_not_open:['DO NOT','OPEN'],stay_back:['STAY','BACK'],last_round:['LAST','ROUND']};
function svg(d){if(d.emblem||d.art==='faction'){const E=window.BSEmblem;if(E)return E.render(d.emblem||E.fromLegacy(d.logo,d.id));}
 const colour=d.category==='Paint'?'#ffffff':d.category==='Warnings'?'#e9b958':'#e5ddc5';let shape=paths[d.art||d.id];let body=shape?`<path fill-rule="evenodd" d="${shape}"/>`:'';const lines=words[d.art||d.id];if(lines)body=lines.map((t,i)=>`<text x="128" y="${lines.length===1?143:109+i*65}" text-anchor="middle" font-family="Impact,Arial Black,sans-serif" font-size="${lines.length===1?34:53}" letter-spacing="1">${t}</text>`).join('');
 return `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><g fill="${colour}">${body}</g><path d="M25 81 220 57M33 176 210 156M90 22 78 230" stroke="#0e1010" stroke-width="3" opacity=".25"/></svg>`;}
window.BSStickerArt={svg,uri:d=>'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(svg(d))};
})();

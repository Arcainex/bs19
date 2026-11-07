'use strict';

const $ = id => document.getElementById(id);
const app = $('app');
const slotsInfo = {
  rifle: {label:'RÜCKEN · FERNKAMPF', short:'Fernkampf · Rücken'},
  melee: {label:'RÜCKEN · NAHKAMPF', short:'Nahkampf · Rücken'},
  left:  {label:'GÜRTEL · LINKS', short:'Gürtel · Links'},
  right: {label:'GÜRTEL · RECHTS', short:'Gürtel · Rechts'}
};
let bones = [];
let slots = {};
let items = {};
let overrides = {slots:{}, items:{}};
let scope = 'slots';
let key = 'rifle';
let precision = 'fine';
let dirty = false;
let waiting = false;
let opened = false;
let canGlobal = false;
let gizmoActive = false;
let gizmoTool = 'move';
let gizmoFrame = null;
let gizmoDrag = null;
let gizmoOrbit = null;
let gizmoPreviewQueued = false;
let cameraMode = false;
let cameraLastPointer = null;
let orbitQueued = false;
let orbitDX = 0, orbitDY = 0;
const cameraDragLayer = $('cameraDragLayer');
function queueCameraOrbit(dx,dy) {
  orbitDX += dx; orbitDY += dy;
  if (orbitQueued) return;
  orbitQueued = true;
  requestAnimationFrame(() => {
    orbitQueued = false;
    const x=orbitDX, y=orbitDY;
    orbitDX=0; orbitDY=0;
    if (opened && (x || y)) post('cameraOrbit',{dx:x,dy:y});
  });
}
function setCameraMode(active) {
  const next = Boolean(active && opened);
  if (cameraMode === next) return;
  cameraMode = next;
  cameraLastPointer = null;
  app.classList.toggle('cameraActive',cameraMode);
  if (cameraMode) {
    gizmoDrag = null;
    gizmoOrbit = null;
    if (gizmoActive) drawGizmo();
  }
}
cameraDragLayer.addEventListener('pointermove',e=>{
  if (!cameraMode) return;
  const current={x:e.clientX,y:e.clientY};
  if (cameraLastPointer) {
    const dx=current.x-cameraLastPointer.x,dy=current.y-cameraLastPointer.y;
    if (dx || dy) queueCameraOrbit(dx,dy);
  }
  cameraLastPointer=current;
  e.preventDefault();
});
cameraDragLayer.addEventListener('pointerleave',()=>{cameraLastPointer=null;});
cameraDragLayer.addEventListener('wheel',e=>{
  if (!cameraMode) return;
  e.preventDefault();
  const normalized=e.deltaMode===1 ? e.deltaY*16 : e.deltaMode===2 ? e.deltaY*window.innerHeight : e.deltaY;
  post('cameraZoom',{delta:Math.max(-600,Math.min(600,normalized))});
},{passive:false});
cameraDragLayer.addEventListener('contextmenu',e=>e.preventDefault());

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'alpha_z_weaponcarry';
async function post(action, data = {}) {
  try {
    const result = await fetch(`https://${resource}/${action}`, {
      method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)
    });
    if (!result.ok) throw new Error(`HTTP ${result.status}`);
    return await result.json().catch(() => ({ok:true}));
  } catch (err) {
    // A local HTML preview has no NUI endpoint; never claim a save succeeded.
    if (action === 'save' || action === 'reset') {
      waiting = false;
      renderFeedback('Verbindung zum Spiel fehlgeschlagen', 'error');
    }
    return false;
  }
}

const axisInputs = {position:[], rotation:[]};
function makeAxisRows(group) {
  const target = $(group);
  ['X','Y','Z'].forEach((axis, i) => {
    const row = document.createElement('div');
    row.className = 'axisRow';
    const name = document.createElement('span');
    name.className = 'axisName'; name.textContent = axis;
    const input = document.createElement('input');
    input.type = 'number'; input.inputMode = 'decimal'; input.step = group === 'position' ? '.001' : '.5';
    input.setAttribute('aria-label',`${group} Achse ${axis}`);
    input.dataset.axis = String(i);
    input.addEventListener('input', onChange);
    row.append(name, input);
    target.appendChild(row);
    axisInputs[group].push(input);
  });
}
makeAxisRows('position'); makeAxisRows('rotation');

function renderFeedback(message, kind = '') {
  const el = $('feedback');
  el.className = `feedback${kind ? ' ' + kind : ''}`;
  const dot = document.createElement('span'); dot.className = 'feedbackDot';
  el.replaceChildren(dot, document.createTextNode(message));
}
function setDirty() {
  dirty = true;
  if (!waiting) renderFeedback('Änderungen noch nicht gespeichert', 'unsaved');
}
function refreshButtons() {
  $('save').disabled = waiting || !key;
  $('reset').disabled = waiting || !key;
  document.querySelectorAll('.axisRow input, .slotCard, .tab, .precisionSwitch button, #itemSelect, #itemSearch, #bone, #rotationTest, #rotationDebug, #gizmoStart')
    .forEach(element => {element.disabled = waiting;});
}
function itemLabel(itemKey) {
  const item = items[itemKey];
  return item && typeof item[2] === 'string' && item[2].trim()
    ? item[2].trim() : itemKey.replaceAll('_', ' ');
}
function selectedSlot() {
  return scope === 'slots' ? key : items[key]?.[1];
}
function selectedBaseline() {
  const slot = selectedSlot();
  return (overrides[scope] && overrides[scope][key]) || slots[slot] || null;
}
function populateBones() {
  const selector = $('bone');
  selector.replaceChildren();
  bones.forEach(b => {
    const option = document.createElement('option');
    option.value = String(b.id);
    option.textContent = `${b.label} · ${b.id}`;
    selector.appendChild(option);
  });
  if (bones.length === 0) {
    const option = document.createElement('option');
    option.value = '';
    option.textContent = 'Keine passenden Knochen vorhanden';
    selector.appendChild(option);
  }
}
function fillInputs(d) {
  if (!d) return;
  $('bone').querySelectorAll('option[data-unavailable]').forEach(option => option.remove());
  const chosen = String(d.bone);
  if (bones.some(b => String(b.id) === chosen)) {
    $('bone').value = chosen;
  } else {
    // Never silently replace a saved invalid/missing bone with another ID.
    const option = document.createElement('option');
    option.value = '';
    option.dataset.unavailable = 'true';
    option.textContent = 'Ankerpunkt nicht verfügbar – bitte wählen';
    $('bone').prepend(option);
    $('bone').value = '';
  }
  for (let i=0;i<3;i++) {
    axisInputs.position[i].value = Number(d.pos[i]).toFixed(3);
    axisInputs.rotation[i].value = Number(d.rot[i]).toFixed(1);
  }
  dirty = false;
  waiting = false;
  renderFeedback('Bereit zur Bearbeitung');
  refreshButtons();
}
function loadSelection() {
  const slot = selectedSlot();
  $('selectionBadge').textContent = scope === 'slots'
    ? (slotsInfo[slot]?.label || slot || 'KEINE AUSWAHL')
    : (items[key] ? itemLabel(key) : 'KEINE WAFFE');
  document.querySelectorAll('.slotCard').forEach(b => b.classList.toggle('active', scope === 'slots' && b.dataset.slot === key));
  fillInputs(selectedBaseline());
  if (opened) {
    // The camera always orbits the currently selected visible weapon.
    // This is separate from preview so changing selection also works when
    // the user has not edited any position or rotation values.
    post('cameraTarget', {scope,key});
    if (key) preview();
  }
}
function getData() {
  const b = $('bone').value.trim();
  const parseValues = inputs => inputs.map(input => input.value.trim() === '' ? NaN : Number(input.value));
  const pos = parseValues(axisInputs.position), rot = parseValues(axisInputs.rotation);
  const bone = b === '' ? NaN : Number(b);
  if (!Number.isInteger(bone) || !bones.some(entry => entry.id === bone) ||
      pos.some(n => !Number.isFinite(n) || Math.abs(n) > 2) ||
      rot.some(n => !Number.isFinite(n) || Math.abs(n) > 360)) return null;
  return {bone, pos, rot};
}
function preview() {
  const data = getData();
  if (!key || !data) {
    renderFeedback('Ungültige Position, Rotation oder Knochen-Auswahl', 'error');
    return;
  }
  post('preview', {scope,key,data});
}
function onChange() {
  setDirty();
  preview();
}
function adjust(group, index, direction) {
  const input = axisInputs[group][index];
  const current = input.value.trim() === '' ? 0 : Number(input.value);
  const increment = group === 'position' ? (precision === 'fine' ? .001 : .01) : (precision === 'fine' ? .5 : 5);
  const limit = group === 'position' ? 2 : 360;
  const digits = group === 'position' ? 3 : 1;
  const next = Math.max(-limit, Math.min(limit, current + increment * direction));
  input.value = next.toFixed(digits);
  onChange();
}
function testRotation() {
  if (waiting || !key) return;
  const input = axisInputs.rotation[2];
  const old = Number(input.value) || 0;
  let next = old + 90;
  if (next > 360) next -= 360;
  input.value = next.toFixed(1);
  onChange();
  renderFeedback('Test: Z um 90° gedreht – noch nicht gespeichert', 'unsaved');
}
function setPrecision(value) {
  precision = value;
  document.querySelectorAll('[data-precision]').forEach(b => b.classList.toggle('active', b.dataset.precision === value));
  $('stepText').textContent = value === 'fine' ? '± 0,001 m / 0,5°' : '± 0,01 m / 5°';
}
function setScope(value) {
  scope = value;
  document.querySelectorAll('[data-mode]').forEach(b => b.classList.toggle('active', b.dataset.mode === value));
  $('slotSection').classList.toggle('hidden', value !== 'slots');
  $('itemSection').classList.toggle('hidden', value !== 'items');
  if (value === 'slots') {
    key = Object.hasOwn(slots, key) ? key : (slots.rifle ? 'rifle' : Object.keys(slots)[0] || '');
  } else {
    const keys = Object.keys(items).sort((a,b)=>itemLabel(a).localeCompare(itemLabel(b),'de'));
    key = Object.hasOwn(items, key) ? key : (keys[0] || '');
    $('itemSearch').value = '';
    populateItems();
  }
  loadSelection();
}
function normalizeItemSearch(value) {
  return String(value || '').toLocaleLowerCase('de').normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').replace(/ß/g, 'ss');
}
function populateItems() {
  const query = normalizeItemSearch($('itemSearch').value.trim());
  const keys = Object.keys(items).filter(k => normalizeItemSearch(k + ' ' + itemLabel(k) + ' ' + items[k][0] + ' ' + (slotsInfo[items[k][1]]?.short || '')).includes(query));
  keys.sort((a,b) => itemLabel(a).localeCompare(itemLabel(b),'de'));
  const selector = $('itemSelect');
  selector.replaceChildren();
  keys.forEach(k => {
    const o = document.createElement('option');
    o.value = k; o.textContent = `${itemLabel(k)}  ·  ${slotsInfo[items[k][1]]?.short || items[k][1]}`;
    selector.appendChild(o);
  });
  $('itemCount').textContent = `${keys.length} WAFFEN`;
  if (keys.length === 0) {
    key = '';
    const option = document.createElement('option');
    option.textContent = 'Keine Treffer'; option.value = '';
    selector.appendChild(option);
    selector.disabled = true;
    $('selectionBadge').textContent = 'KEINE WAFFE';
    if (opened) post('cameraTarget', {scope,key:''});
    refreshButtons();
  } else {
    selector.disabled = false;
    key = keys.includes(key) ? key : keys[0];
    selector.value = key;
    loadSelection();
  }
}

function save() {
  if (waiting || !key) return;
  const data = getData();
  if (!data) {renderFeedback('Bitte gültige Werte eingeben', 'error');return;}
  waiting = true; refreshButtons();
  renderFeedback(canGlobal ? 'Speichere serverweit ...' : 'Speichere nur für deinen Charakter ...');
  post('save', {scope,key,data});
}
function reset() {
  if (waiting || !key) return;
  waiting = true; refreshButtons();
  renderFeedback('Setze Position auf Standard zurück ...');
  post('reset', {scope,key});
}
function close() {
  if (!opened) return;
  setCameraMode(false);
  opened = false; dirty = false; waiting = false;
  gizmoActive = false; gizmoDrag = null; gizmoOrbit = null;
  app.classList.remove('gizmoActive');
  $('gizmoOverlay').classList.add('hidden');
  app.classList.add('hidden');
  post('close', {});
}

// NUI messages originate from the local game client, not arbitrary HTML content.
window.addEventListener('message', event => {
  const d = event.data;
  if (!d || typeof d !== 'object') return;
  if (d.action === 'open') {
    canGlobal = d.canGlobal === true;
    $('saveText').textContent = canGlobal ? 'SERVERSEITIG SPEICHERN' : 'FÜR MEINEN CHARAKTER SPEICHERN';
    $('saveScopeNotice').textContent = canGlobal ? 'Diese Speicherung gilt für alle Spieler.' : 'Diese Speicherung gilt nur für deinen Charakter.';
    bones = Array.isArray(d.bones) ? d.bones.filter(b => Number.isInteger(b.id) && typeof b.label === 'string') : [];
    populateBones();
    slots = d.slots && typeof d.slots === 'object' ? d.slots : {};
    items = d.items && typeof d.items === 'object' ? d.items : {};
    overrides = d.overrides && typeof d.overrides === 'object' ? d.overrides : {slots:{},items:{}};
    if (!overrides.slots) overrides.slots = {};
    if (!overrides.items) overrides.items = {};
    setCameraMode(false);
    opened = true; gizmoActive = false; gizmoFrame = null;
    // Start with the first weapon actually visible on the character.
    key = typeof d.initialSlot === 'string' && Object.hasOwn(slots,d.initialSlot) ? d.initialSlot : 'rifle';
    app.classList.remove('gizmoActive');
    $('gizmoOverlay').classList.add('hidden');
    app.classList.remove('hidden');
    setScope('slots');
  } else if (d.action === 'positions') {
    overrides = d.overrides && typeof d.overrides === 'object' ? d.overrides : {slots:{},items:{}};
    if (!overrides.slots) overrides.slots = {};
    if (!overrides.items) overrides.items = {};
    if (opened && !dirty && !waiting) loadSelection();
  } else if (d.action === 'gizmoFrame') {
    gizmoFrame = d.frame || null;
    if (gizmoActive) drawGizmo();
  } else if (d.action === 'gizmoLost') {
    exitGizmo(false);
    renderFeedback(d.message || 'Waffe nicht mehr sichtbar', 'error');
  } else if (d.action === 'editorResult') {
    waiting = false;
    refreshButtons();
    if (d.ok) {
      if (d.overrides && typeof d.overrides === 'object') {
        overrides = {slots:d.overrides.slots || {},items:d.overrides.items || {}};
      }
      if (d.operation === 'reset' && d.scope === scope && d.key === key) {
        fillInputs(selectedBaseline());
        preview();
      }
      dirty = false;
      renderFeedback(d.message || (d.operation === 'reset' ? 'Position zurückgesetzt' : 'Position gespeichert'), 'success');
      if (gizmoActive) $('gizmoStatus').textContent = canGlobal ? 'Serverweit gespeichert' : 'Für deinen Charakter gespeichert';
    } else {
      renderFeedback(d.message || 'Speichern fehlgeschlagen', 'error');
    }
  }
});

$('bone').addEventListener('change', onChange);
$('gizmoStart').onclick = enterGizmo;
$('rotationTest').onclick = testRotation;
$('rotationDebug').onclick = async () => {
  const ok = await post('rotationDebug', {});
  if (ok) renderFeedback('F8: Rotationsdiagnose ausgegeben', 'unsaved');
};
$('itemSearch').addEventListener('input', populateItems);
$('itemSelect').addEventListener('change', e => {key = e.target.value; loadSelection()});
document.querySelectorAll('.slotCard').forEach(button => button.onclick = () => {key = button.dataset.slot; loadSelection()});
document.querySelectorAll('[data-mode]').forEach(button => button.onclick = () => setScope(button.dataset.mode));
document.querySelectorAll('[data-precision]').forEach(button => button.onclick = () => setPrecision(button.dataset.precision));
$('save').onclick = save;
$('reset').onclick = reset;
$('close').onclick = close;
$('closeTop').onclick = close;
window.addEventListener('keydown', e => {
  if (!opened) return;
  if (e.key === 'Alt') {
    e.preventDefault();
    setCameraMode(true);
    return;
  }
  if (e.key === 'Escape') {
    e.preventDefault();
    setCameraMode(false);
    if (gizmoActive) exitGizmo(true); else close();
  } else if (gizmoActive && !cameraMode && (e.key.toLowerCase() === 'r' || e.key.toLowerCase() === 'g')) {
    e.preventDefault();
    setGizmoTool(e.key.toLowerCase() === 'r' ? 'rotate' : 'move');
  }
});
window.addEventListener('keyup', e => {
  if (e.key === 'Alt') {e.preventDefault();setCameraMode(false);}
});
// ALT+TAB and focus loss must never leave an invisible mouse-blocking overlay.
window.addEventListener('blur', () => setCameraMode(false));


// ---------------------------------------------------------------------------
// V1.6: in-world gizmo. The CFX client projects real ped-bone axes and rings
// into screen space; mouse dragging changes the attachment's local transform.
// The NUI never changes the inventory or saves without a deliberate click.
// ---------------------------------------------------------------------------
const gizmoCanvas = $('gizmoCanvas');
const ctx = gizmoCanvas.getContext('2d');
const axisColors = {x:'#ef6a64',y:'#9dd66e',z:'#65aef6'};
const axisIndex = {x:0,y:1,z:2};
function screen(point) {
  if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return null;
  return {x:point.x * window.innerWidth,y:point.y * window.innerHeight};
}
function resizeGizmo() {
  const dpr = Math.min(window.devicePixelRatio || 1,2);
  gizmoCanvas.width = Math.round(window.innerWidth*dpr);
  gizmoCanvas.height = Math.round(window.innerHeight*dpr);
  ctx.setTransform(dpr,0,0,dpr,0,0);
  if (gizmoActive) drawGizmo();
}
window.addEventListener('resize',resizeGizmo);
resizeGizmo();
function setGizmoTool(tool) {
  gizmoTool = tool;
  gizmoDrag = null;
  document.querySelectorAll('[data-gizmo-tool]').forEach(button =>
    button.classList.toggle('active',button.dataset.gizmoTool === tool));
  $('gizmoStatus').textContent = tool === 'move' ? 'Achse greifen und verschieben' : 'Ring greifen und drehen';
  drawGizmo();
}
function updateGizmoValues() {
  const d = getData();
  if (!d) return;
  const values = gizmoTool === 'move' ? d.pos : d.rot;
  const suffix = gizmoTool === 'move' ? 'm' : '°';
  $('gizmoValues').textContent = ['X','Y','Z'].map((name,i)=>
    `${name} ${values[i].toFixed(gizmoTool === 'move' ? 3 : 1)}${suffix}`).join('    ·    ');
}
async function enterGizmo() {
  if (!opened || waiting || !key || gizmoActive) return;
  const data = getData();
  if (!data) {renderFeedback('Bitte gültige Position und Knochen wählen','error');return;}
  const result = await post('gizmoStart',{scope,key,data});
  if (!result || result.ok !== true) {
    renderFeedback(result?.message || 'Gizmo konnte nicht gestartet werden','error');
    return;
  }
  gizmoActive = true;
  gizmoFrame = null;
  gizmoDrag = null;
  gizmoOrbit = null;
  app.classList.add('gizmoActive');
  $('gizmoOverlay').classList.remove('hidden');
  $('gizmoSelection').textContent = $('selectionBadge').textContent;
  setGizmoTool('move');
  updateGizmoValues();
  resizeGizmo();
}
function exitGizmo(notifyClient=true) {
  if (!gizmoActive) return;
  gizmoActive = false;
  gizmoFrame = null;
  gizmoDrag = null;
  gizmoOrbit = null;
  app.classList.remove('gizmoActive');
  $('gizmoOverlay').classList.add('hidden');
  if (notifyClient) post('gizmoStop',{});
  if (dirty && !waiting) renderFeedback('Gizmo-Änderungen noch nicht gespeichert','unsaved');
}
function distanceToSegment(p,a,b) {
  const vx=b.x-a.x,vy=b.y-a.y;
  const lengthSq=vx*vx+vy*vy;
  if (lengthSq < 1) return Math.hypot(p.x-a.x,p.y-a.y);
  const t=Math.max(0,Math.min(1,((p.x-a.x)*vx+(p.y-a.y)*vy)/lengthSq));
  return Math.hypot(p.x-(a.x+t*vx),p.y-(a.y+t*vy));
}
function hitTestGizmo(point) {
  if (!gizmoFrame?.center) return null;
  const origin=screen(gizmoFrame.center);
  if (!origin) return null;
  let hit=null,nearest=gizmoTool === 'move' ? 19 : 15;
  for (const axis of ['x','y','z']) {
    if (gizmoTool === 'move') {
      const end=screen(gizmoFrame.axes?.[axis]);
      if (!end) continue;
      const dist=distanceToSegment(point,origin,end);
      if (dist<nearest) {nearest=dist;hit={axis,kind:'move',origin,end};}
    } else {
      const ring=gizmoFrame.rings?.[axis] || [];
      for (let i=1;i<ring.length;i++) {
        const a=screen(ring[i-1]),b=screen(ring[i]);
        if (!a || !b) continue;
        const dist=distanceToSegment(point,a,b);
        if (dist<nearest) {nearest=dist;hit={axis,kind:'rotate',origin};}
      }
    }
  }
  return hit;
}
function drawGizmo() {
  const w=window.innerWidth,h=window.innerHeight;
  ctx.clearRect(0,0,w,h);
  if (!gizmoActive) return;
  const frame=gizmoFrame;
  const origin=screen(frame?.center);
  $('gizmoNoView').classList.toggle('hidden',!!origin);
  if (!origin) return;
  const activeAxis=gizmoDrag?.axis || null;
  const hovered=gizmoDrag ? null : hitTestGizmo(lastPointer);
  const highlight=activeAxis || hovered?.axis || null;
  if (gizmoTool === 'move') {
    for (const axis of ['x','y','z']) {
      const end=screen(frame.axes?.[axis]);
      if (!end) continue;
      const color=axisColors[axis],isHot=highlight===axis;
      ctx.save();
      ctx.strokeStyle=color;ctx.fillStyle=color;
      ctx.lineWidth=isHot ? 7 : 5;ctx.lineCap='round';
      ctx.shadowColor=color;ctx.shadowBlur=isHot ? 24 : 10;
      ctx.beginPath();ctx.moveTo(origin.x,origin.y);ctx.lineTo(end.x,end.y);ctx.stroke();
      const angle=Math.atan2(end.y-origin.y,end.x-origin.x);
      ctx.beginPath();ctx.moveTo(end.x,end.y);
      ctx.lineTo(end.x-16*Math.cos(angle-.42),end.y-16*Math.sin(angle-.42));
      ctx.lineTo(end.x-16*Math.cos(angle+.42),end.y-16*Math.sin(angle+.42));
      ctx.closePath();ctx.fill();
      ctx.shadowBlur=0;ctx.font='bold 15px Segoe UI,Arial';
      ctx.fillText(axis.toUpperCase(),end.x+11,end.y-10);
      ctx.restore();
    }
  } else {
    for (const axis of ['x','y','z']) {
      const ring=frame.rings?.[axis] || [];
      const color=axisColors[axis],isHot=highlight===axis;
      ctx.save();ctx.strokeStyle=color;ctx.lineWidth=isHot ? 5 : 3;
      ctx.shadowColor=color;ctx.shadowBlur=isHot ? 20 : 7;
      ctx.beginPath();let wasVisible=false;
      for (const point of ring) {
        const p=screen(point);
        if (!p) {wasVisible=false;continue;}
        if (!wasVisible) ctx.moveTo(p.x,p.y); else ctx.lineTo(p.x,p.y);
        wasVisible=true;
      }
      ctx.stroke();ctx.restore();
      const label=screen(ring[9]);
      if (label) {
        ctx.save();ctx.fillStyle=color;ctx.font='bold 15px Segoe UI,Arial';
        ctx.fillText(axis.toUpperCase(),label.x+8,label.y-8);ctx.restore();
      }
    }
  }
  ctx.save();ctx.beginPath();ctx.arc(origin.x,origin.y,7,0,Math.PI*2);
  ctx.fillStyle='#f5f7ee';ctx.fill();ctx.lineWidth=2;ctx.strokeStyle='#101717';ctx.stroke();ctx.restore();
}
const lastPointer={x:-9999,y:-9999};
function queueGizmoPreview() {
  if (gizmoPreviewQueued) return;
  gizmoPreviewQueued = true;
  requestAnimationFrame(()=>{
    gizmoPreviewQueued=false;
    if (gizmoActive) preview();
  });
}
function gizmoChange(kind,axis,value) {
  const i=axisIndex[axis];
  const input=axisInputs[kind === 'move' ? 'position' : 'rotation'][i];
  const limit=kind === 'move' ? 2 : 360;
  const digits=kind === 'move' ? 3 : 1;
  const snap=kind === 'move' ? (precision === 'fine' ? 0.001 : 0.01) : (precision === 'fine' ? 0.5 : 5);
  const n=Math.max(-limit,Math.min(limit,Math.round(value/snap)*snap));
  input.value=n.toFixed(digits);
  setDirty();updateGizmoValues();queueGizmoPreview();
}
gizmoCanvas.addEventListener('contextmenu',e=>e.preventDefault());
gizmoCanvas.addEventListener('pointerdown',e=>{
  if (!gizmoActive) return;
  if (e.button===2) {
    gizmoOrbit={x:e.clientX,y:e.clientY};
    gizmoCanvas.setPointerCapture(e.pointerId);e.preventDefault();return;
  }
  if (e.button!==0) return;
  const hit=hitTestGizmo({x:e.clientX,y:e.clientY});
  if (!hit) return;
  const d=getData();if (!d) return;
  const origin=screen(gizmoFrame.center);
  gizmoDrag={...hit,startX:e.clientX,startY:e.clientY,
    initial:(hit.kind==='move'?d.pos:d.rot)[axisIndex[hit.axis]],
    length:gizmoFrame.length,previousAngle:Math.atan2(e.clientY-origin.y,e.clientX-origin.x),
    totalAngle:0};
  gizmoCanvas.setPointerCapture(e.pointerId);
  $('gizmoStatus').textContent=`${hit.axis.toUpperCase()}-Achse ${hit.kind==='move'?'verschieben':'drehen'}`;
  e.preventDefault();drawGizmo();
});
gizmoCanvas.addEventListener('pointermove',e=>{
  lastPointer.x=e.clientX;lastPointer.y=e.clientY;
  if (gizmoOrbit) {
    const dx=e.clientX-gizmoOrbit.x,dy=e.clientY-gizmoOrbit.y;
    gizmoOrbit={x:e.clientX,y:e.clientY};
    if (dx||dy) queueCameraOrbit(dx,dy);
  } else if (gizmoDrag) {
    const drag=gizmoDrag;
    if (drag.kind==='move') {
      const vx=drag.end.x-drag.origin.x,vy=drag.end.y-drag.origin.y;
      const lenSq=vx*vx+vy*vy;
      if (lenSq>36) {
        const dx=e.clientX-drag.startX,dy=e.clientY-drag.startY;
        const delta=(dx*vx+dy*vy)/lenSq*drag.length*(e.shiftKey ? 0.2 : 1);
        gizmoChange('move',drag.axis,drag.initial+delta);
      }
    } else {
      // Angle around the ring's projected center, continuous across ±180°.
      const a=Math.atan2(e.clientY-drag.origin.y,e.clientX-drag.origin.x);
      let delta=a-drag.previousAngle;
      if (delta>Math.PI) delta-=Math.PI*2;
      if (delta<-Math.PI) delta+=Math.PI*2;
      drag.previousAngle=a;
      drag.totalAngle+=delta*180/Math.PI*(e.shiftKey ? 0.2 : 1);
      gizmoChange('rotate',drag.axis,drag.initial+drag.totalAngle);
    }
    e.preventDefault();
  }
  if (gizmoActive) drawGizmo();
});
function stopGizmoPointer() {
  gizmoDrag=null;gizmoOrbit=null;
  if (gizmoActive) {
    $('gizmoStatus').textContent='Änderungen noch nicht gespeichert';
    drawGizmo();
  }
}
gizmoCanvas.addEventListener('pointerup',stopGizmoPointer);
gizmoCanvas.addEventListener('pointercancel',stopGizmoPointer);
gizmoCanvas.addEventListener('lostpointercapture',stopGizmoPointer);
document.querySelectorAll('[data-gizmo-tool]').forEach(button=>
  button.onclick=()=>setGizmoTool(button.dataset.gizmoTool));
$('gizmoBack').onclick=()=>exitGizmo(true);
$('gizmoSave').onclick=()=>{if (!waiting) save();};

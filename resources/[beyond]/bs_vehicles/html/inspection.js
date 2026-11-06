(() => {
    const style = document.createElement('style');
    style.textContent = '#vehicleInspection[hidden]{display:none}#vehicleInspection{position:fixed;inset:12vh auto auto 50%;transform:translateX(-50%);width:min(600px,90vw);max-height:76vh;overflow:auto;padding:25px;background:#151a15f7;color:#e4dece;border:1px solid #81735b77;border-top:3px solid #dc924b;font-family:"Segoe UI",Arial,sans-serif;box-shadow:0 20px 80px #0009}#vehicleInspection h2{font-size:23px;font-weight:500;margin:0 0 6px}#vehicleInspection .sub{font-size:12px;color:#aaa99b;margin:0 0 20px}#vehicleInspection .vpart{display:grid;grid-template-columns:140px 1fr 110px;gap:15px;align-items:center;padding:12px 0;border-top:1px solid #756b503d;font-size:13px}#vehicleInspection .track{height:5px;background:#ffffff12}#vehicleInspection .fill{height:100%;background:#aab286}#vehicleInspection .value{text-align:right;color:#c5c7b3}#vehicleInspection .missing .value{color:#dc924b}#vehicleInspection button{display:block;margin:20px 0 0 auto;padding:10px 25px;border:1px solid #b78450;background:#dc924b;color:#1c1b14;font:600 13px "Segoe UI",sans-serif;cursor:pointer}#vehicleInspection::-webkit-scrollbar{width:5px}#vehicleInspection::-webkit-scrollbar-thumb{background:#856541}';
    document.head.append(style);
    const panel = document.createElement('section'); panel.id = 'vehicleInspection'; panel.hidden = true;
    document.body.append(panel);
    function close() {
        if (panel.hidden) return;
        panel.hidden = true;
        fetch(`https://${GetParentResourceName()}/inspectionClose`, {method:'POST',body:'{}',headers:{'Content-Type':'application/json'}}).catch(() => {});
    }
    window.addEventListener('message', ({data}) => {
        if (data.action !== 'vehicleInspection') return;
        panel.replaceChildren(); panel.hidden = false;
        const title = document.createElement('h2'); title.textContent = 'Vehicle condition';
        const sub = document.createElement('p'); sub.className = 'sub'; sub.textContent = `${String(data.plate || '').trim()} · Field inspection`;
        panel.append(title, sub);
        for (const part of data.rows || []) {
            const row = document.createElement('div'); row.className = 'vpart' + (part.missing ? ' missing' : '');
            const label = document.createElement('span'); label.textContent = part.label;
            const track = document.createElement('div'); track.className = 'track';
            const fill = document.createElement('div'); fill.className = 'fill'; fill.style.width = `${part.missing ? 0 : Math.max(0, Math.min(100, Number(part.value) || 0))}%`; track.append(fill);
            const value = document.createElement('span'); value.className = 'value'; value.textContent = part.missing ? part.state : `${part.value}% · ${part.state}`;
            row.append(label, track, value); panel.append(row);
        }
        const button = document.createElement('button'); button.textContent = 'Close'; button.onclick = close; panel.append(button);
    });
    window.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
})();

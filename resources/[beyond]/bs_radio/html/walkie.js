(() => {
    const panel = document.createElement('section');
    panel.id = 'walkie';
    panel.setAttribute('aria-label', 'Handheld radio');
    panel.innerHTML = `
        <div class="radio-antenna" aria-hidden="true"><i></i></div>
        <button class="radio-volume" id="radioPower" title="Power / volume knob" aria-label="Power radio"><i></i></button>
        <div class="radio-neck" aria-hidden="true"></div>
        <div class="radio-body">
            <span class="radio-side radio-side--ptt" aria-hidden="true">PTT</span>
            <span class="radio-side radio-side--aux" aria-hidden="true"></span>
            <div class="radio-shoulders"><span class="radio-led" id="radioLed"></span><strong>BS19</strong><span>TRANSCEIVER</span></div>
            <div class="radio-speaker" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i></div>
            <div class="radio-model" id="radioModel">XR-19 / FIELD</div>
            <div class="radio-bezel">
                <div class="radio-lcd" id="radioLcd">
                    <div class="lcd-top"><span id="radioMode">OFF</span><span class="lcd-power"><span id="radioChargeSymbol"></span><span id="radioBatteryNumber">--%</span><i id="radioBattery"><b></b></i></span></div>
                    <div class="lcd-label"><span>A</span><span>CHANNEL</span><span id="radioEditLabel">MEM</span></div>
                    <input id="frequency" aria-label="Radio channel" inputmode="numeric" maxlength="4" value="0101" autocomplete="off" spellcheck="false">
                    <div class="lcd-divider"></div>
                    <div class="lcd-label"><span>B</span><span>NETWORK</span><span id="radioTierMark">FIELD</span></div>
                    <div id="walkieStatus" role="status">POWER OFF</div>
                    <div class="lcd-bottom"><span id="radioCharging">BATTERY PACK</span><span>CAPS : PTT</span></div>
                </div>
            </div>
            <div class="radio-function-row">
                <button id="tune" class="radio-key radio-key--orange"><b>MENU</b><small>TUNE</small></button>
                <div class="radio-rocker"><button id="channelUp" aria-label="Next channel">&#9650;</button><button id="channelDown" aria-label="Previous channel">&#9660;</button></div>
                <button id="walkieClose" class="radio-key"><b>EXIT</b><small>CLOSE</small></button>
            </div>
            <div class="radio-keypad" id="radioKeypad"></div>
            <div class="radio-utility"><button id="secure">FACTION</button><button id="contracts">CONTRACTS</button><button id="radioChargeToggle">CHARGE</button></div>
            <div class="radio-base"><span>DUAL BAND / FM</span><i aria-hidden="true"></i><span id="radioBatteryLabel">LI-ION</span></div>
            <span class="radio-screw radio-screw--left" aria-hidden="true"></span><span class="radio-screw radio-screw--right" aria-hidden="true"></span>
        </div>
        <div class="radio-charger" id="radioCharger" hidden><strong>CHARGING LEAD</strong><p>Connect to an available power source.</p><button id="chargeVehicle">12V VEHICLE</button><button id="chargeMains">MAINS POWER</button><button id="chargeStop">DISCONNECT</button></div>
        <p class="radio-caption">CAPS LOCK to transmit · ESC to put away</p>`;
    document.body.appendChild(panel);
    const $ = id => document.getElementById(id);
    const frequency = $('frequency');
    let current = {}, editing = false, shown = false;
    const clampChannel = value => Math.max(1, Math.min(9999, Math.floor(Number(value) || 1)));
    async function post(route, data = {}) {
        try {
            const response = await fetch(`https://${GetParentResourceName()}/${route}`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data)
            });
            const result = await response.json();
            if (result && result.ok === false && result.error) $('walkieStatus').textContent = result.error;
            return result;
        } catch (_) { $('walkieStatus').textContent = 'NO RESPONSE'; return null; }
    }
    function edited() {
        editing = true;
        $('radioEditLabel').textContent = 'EDIT';
    }
    function tune() {
        const channel = clampChannel(frequency.value);
        frequency.value = String(channel).padStart(4, '0');
        editing = false;
        $('radioEditLabel').textContent = 'MEM';
        post('walkieJoin', { channel });
    }
    function keypad(key) {
        if (key === '#') return tune();
        if (key === '*') { frequency.value = editing ? frequency.value.slice(0, -1) : ''; edited(); return; }
        if (!editing || frequency.value.length >= 4) frequency.value = '';
        frequency.value += key;
        edited();
    }
    const legends = ['STEP', 'TXP', 'SAVE', 'VOX', 'WN', 'ABR', 'TDR', 'BEEP', 'TOT', 'DEL', 'SQL', 'ENTER'];
    ['1','2','3','4','5','6','7','8','9','*','0','#'].forEach((key, index) => {
        const button = document.createElement('button');
        button.className = 'radio-key';
        button.innerHTML = `<b>${key}</b><small>${legends[index]}</small>`;
        button.setAttribute('aria-label', key === '#' ? 'Confirm channel' : key === '*' ? 'Delete digit' : `Channel digit ${key}`);
        button.onclick = () => keypad(key);
        $('radioKeypad').appendChild(button);
    });
    frequency.addEventListener('input', () => { frequency.value = frequency.value.replace(/\D/g, '').slice(0, 4); edited(); });
    frequency.addEventListener('keydown', event => { if (event.key === 'Enter') { event.preventDefault(); tune(); } });
    $('tune').onclick = tune;
    $('channelUp').onclick = () => { frequency.value = String(clampChannel(frequency.value) + 1 > 9999 ? 1 : clampChannel(frequency.value) + 1).padStart(4, '0'); tune(); };
    $('channelDown').onclick = () => { frequency.value = String(clampChannel(frequency.value) - 1 < 1 ? 9999 : clampChannel(frequency.value) - 1).padStart(4, '0'); tune(); };
    $('radioPower').onclick = () => current.channel ? post('walkieJoin', { channel: 0 }) : tune();
    $('secure').onclick = () => post('walkieFaction', { channel: clampChannel(frequency.value) });
    $('contracts').onclick = () => post('walkieMissions');
    $('walkieClose').onclick = () => post('walkieClose');
    $('radioChargeToggle').onclick = () => { $('radioCharger').hidden = !$('radioCharger').hidden; };
    $('chargeVehicle').onclick = () => post('walkieCharge', { source: 'vehicle' });
    $('chargeMains').onclick = () => post('walkieCharge', { source: 'mains' });
    $('chargeStop').onclick = () => post('walkieStopCharge');
    document.addEventListener('keydown', event => {
        if (!shown) return;
        if (event.key === 'Escape') { event.preventDefault(); post('walkieClose'); }
        if (event.target !== frequency && /^[0-9*#]$/.test(event.key)) { event.preventDefault(); keypad(event.key); }
        if (event.target !== frequency && event.key === 'Enter') tune();
    });
    function radioState(state) {
        current = state || {};
        const tier = Math.max(1, Math.min(3, Number(current.tier) || 1));
        if (!editing && current.channel) frequency.value = String(current.channel).padStart(4, '0');
        const battery = Number(current.battery);
        const known = Number.isFinite(battery);
        const percent = known ? Math.max(0, Math.min(100, battery)) : 0;
        $('radioBatteryNumber').textContent = known ? Math.round(percent) + '%' : '--%';
        $('radioBattery').style.setProperty('--battery', percent + '%');
        $('radioChargeSymbol').textContent = current.charging ? '+' : '';
        $('radioCharging').textContent = current.charging ? (current.source === 'vehicle' ? '12V CHARGING' : 'MAINS CHARGING') : 'BATTERY PACK';
        $('radioBatteryLabel').textContent = current.charging ? 'DC IN' : 'LI-ION';
        $('radioMode').textContent = current.transmitting ? 'TX' : current.channel ? 'RX READY' : 'OFF';
        $('radioModel').textContent = ['XR-19 / FIELD', 'XR-19E / EXPEDITION', 'XR-19M / MILITARY'][tier - 1];
        $('radioTierMark').textContent = ['FIELD', 'EXP', 'MIL'][tier - 1];
        $('walkieStatus').textContent = current.transmitting ? 'TRANSMITTING' : current.channel ? 'STANDBY' : known && percent <= 0 ? 'BATTERY EMPTY' : 'POWER OFF';
        panel.classList.toggle('transmitting', current.transmitting === true);
        panel.classList.toggle('powered', !!current.channel);
        panel.classList.toggle('charging', current.charging === true);
        panel.classList.toggle('battery-low', known && percent < 10);
    }
    function fit() { panel.style.setProperty('--radio-scale', Math.min(1, Math.max(0.42, (innerHeight - 42) / 790), (innerWidth - 50) / 360)); }
    addEventListener('resize', fit);
    fit();
    window.addEventListener('message', ({ data }) => {
        if (data.action === 'walkieOpen') { shown = true; panel.style.display = 'block'; editing = false; $('radioCharger').hidden = true; radioState(data.state || {}); fit(); }
        if (data.action === 'walkieClose') { shown = false; panel.style.display = 'none'; editing = false; }
        if (data.action === 'walkieState') radioState(data.state);
        if (data.action === 'walkieNotice') $('walkieStatus').textContent = data.message || '';
    });
})();

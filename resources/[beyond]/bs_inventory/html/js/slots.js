// Shared inventory plate: grid and pickup use the same DOM, icons and existing CSS.
(function (global) {
    'use strict';
    const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    function count(entry) {
        if (entry.battery != null) return `${Math.round(entry.battery)}%`;
        if (!entry.capacity) return entry.amount;
        return `${Math.round(((entry.fill || 0) / entry.capacity) * 100)}%`;
    }
    function badge(entry) {
        const value = escape(count(entry));
        return entry.capacity || entry.battery != null ? `<span>${value}</span>` : `<span class="slot__amount">${value}</span>`;
    }
    function fill(entry) {
        if (!entry.capacity) return '';
        const pct = Math.max(0, Math.min(100, Math.round(((entry.fill || 0) / entry.capacity) * 100)));
        return `<span class="slot__fill"><i style="width:${pct}%"></i></span>`;
    }
    function create(entry, options = {}) {
        const node = document.createElement('div');
        node.className = 'slot has-item';
        node.dataset.cat = entry.category || 'misc';
        if (entry.rarity) node.dataset.rarity = entry.rarity;
        const icon = document.createElement('span'); icon.className = 'slot__icon';
        const icons = global.BSIcons;
        icon.innerHTML = icons ? icons.get(entry.item, entry.category) : '';
        icon.addEventListener('error', event => {
            if (event.target.tagName === 'IMG') icon.innerHTML = icons ? icons.get(null, entry.category) : '';
        }, true);
        node.appendChild(icon);
        if (options.name !== false) {
            const label = document.createElement('span'); label.className = 'slot__name'; label.textContent = entry.label || '';
            node.appendChild(label);
        }
        if (options.amount !== false) {
            const foot = document.createElement('span'); foot.className = 'slot__foot';
            foot.innerHTML = options.countOnly ? `<span class="slot__amount">${escape(entry.amount)}</span>` : badge(entry);
            node.appendChild(foot);
        }
        if (!options.countOnly) node.insertAdjacentHTML('beforeend', fill(entry));
        return node;
    }
    function cells(grid, width, height, inventory) {
        for (let y=1;y<=height;y++) for (let x=1;x<=width;x++) {
            const cell=document.createElement('div'); cell.className='cell';
            cell.style.gridColumn=x; cell.style.gridRow=y;
            if (inventory) { cell.dataset.inv=inventory; cell.dataset.x=x; cell.dataset.y=y; }
            grid.appendChild(cell);
        }
    }
    global.BSInventorySlots = Object.freeze({ create, cells, badge, count, fill });
})(window);

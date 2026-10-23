/* BeyondSurvival | notify.js - stacked, self-expiring toasts. */

const notifyRoot = document.getElementById('notifications');
const MAX_VISIBLE = 5;
const recent = new Map();

const ICON_FOR = { success: 'check', error: 'error', warn: 'warn', info: 'info' };

function dismiss(node) {
    if (!node.isConnected) return;
    if (recent.get(node.dataset.key)?.node === node) recent.delete(node.dataset.key);
    node.classList.add('notification--closing');
    setTimeout(() => node.remove(), 200);
}

BS.on('notify', ({ notification }) => {
    if (!notification) return;

    const type = notification.type || 'info';
    const key = JSON.stringify([type, notification.title || '', notification.message || '']);
    const prior = recent.get(key);
    if (prior && prior.node.isConnected && Date.now() - prior.time < 2500) {
        prior.time = Date.now();
        prior.count += 1;
        prior.message.textContent = `${notification.message ?? ''}  ×${prior.count}`;
        clearTimeout(prior.timer);
        prior.timer = setTimeout(() => dismiss(prior.node), notification.duration || 4500);
        return;
    }
    const node = document.createElement('div');
    node.className = `notification notification--${type}`;
    node.dataset.key = key;

    // Title and message are built as DOM text, not innerHTML, so payloads from other resources can't inject markup.
    const icon = document.createElement('div');
    icon.innerHTML = BS.icon(notification.icon || ICON_FOR[type] || 'info', 'notification__icon');
    node.appendChild(icon.firstElementChild);

    const body = document.createElement('div');
    body.className = 'notification__body';

    if (notification.title) {
        const title = document.createElement('div');
        title.className = 'notification__title';
        title.textContent = notification.title;
        body.appendChild(title);
    }

    const message = document.createElement('div');
    message.className = 'notification__message';
    message.textContent = notification.message ?? '';
    body.appendChild(message);

    node.appendChild(body);
    notifyRoot.appendChild(node);
    const record = { node, message, count: 1, time: Date.now(), timer: null };
    recent.set(key, record);

    while (notifyRoot.children.length > MAX_VISIBLE) {
        dismiss(notifyRoot.firstElementChild);
    }

    record.timer = setTimeout(() => dismiss(node), notification.duration || 4500);
});

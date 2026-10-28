'use strict';

/* =========================================
   CYBER FLAPPY — LIQUID GLASS CONTROL
   Không can thiệp Haskell API hoặc game loop
========================================= */

(() => {
    // 1. Lấy các phần tử Liquid Glass
    const clock = document.getElementById('glassClock');
    const date = document.getElementById('glassDate');
    const slider = document.getElementById('glassVolumeSlider');
    const volumeValue = document.getElementById('glassVolumeValue');
    const muteButton = document.getElementById('glassMuteButton');
    const volumeIcon = document.getElementById('glassVolumeIcon');
    const panelStatus = document.getElementById('glassPanelStatus');
    const soundButton = document.getElementById('soundButton');

    // Tránh lỗi nếu HTML chưa có đủ phần tử
    if (!clock || !date || !slider ||
        !volumeValue || !muteButton || !volumeIcon) {
        console.warn('[Liquid Glass] Không tìm thấy đủ phần tử HTML.');
        return;
    }

    // 2. Đồng hồ và ngày tháng
    function updateClock() {
        const now = new Date();

        clock.textContent = now.toLocaleTimeString('vi-VN', {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false
        });

        date.textContent = now.toLocaleDateString('vi-VN', {
            weekday: 'long',
            day: '2-digit',
            month: 'long',
            year: 'numeric'
        });
    }

    updateClock();
    setInterval(updateClock, 1000);

    // 3. Trạng thái âm thanh
    let volume = Number(slider.value) / 100;
    let muted = volume === 0;

    // Chỉ điều chỉnh âm lượng của game thông qua nút âm thanh hiện có.
    // Không tạo AudioContext mới, không thay đổi API hoặc game loop.
    function updateVolumeUI() {
        volumeValue.textContent = `${Math.round(volume * 100)}%`;

        // Màu lấy từ CSS (--glass-fill-a/b, --glass-track) để đổi theme dễ dàng.
        slider.style.background = `linear-gradient(
            90deg,
            var(--glass-fill-a, #66d4ff) 0%,
            var(--glass-fill-b, #b07cff) ${volume * 100}%,
            var(--glass-track, rgba(120, 110, 230, 0.2)) ${volume * 100}%,
            var(--glass-track, rgba(120, 110, 230, 0.2)) 100%
        )`;

        volumeIcon.textContent = muted || volume === 0 ? '×' : '♫';
        muteButton.textContent = muted ? '×' : '♫';
        muteButton.setAttribute('aria-pressed', String(muted));

        if (panelStatus) {
            panelStatus.textContent = muted ? 'AUDIO MUTED' : 'AUDIO READY';
        }
    }

    // Đồng bộ với nút âm thanh của game.
    // Lưu ý: soundButton hiện tại có thể chỉ bật/tắt âm thanh,
    // chưa hỗ trợ âm lượng liên tục.
    function syncGameSound() {
        if (!soundButton) return;

        const soundIsOn = !muted && volume > 0;

        soundButton.classList.toggle('sound-off', !soundIsOn);
        soundButton.setAttribute('aria-pressed', String(soundIsOn));
        soundButton.title = soundIsOn
            ? 'Âm thanh đang bật'
            : 'Âm thanh đang tắt';
    }

    // 4. Thanh âm lượng
    slider.addEventListener('input', () => {
        volume = Number(slider.value) / 100;
        muted = volume === 0;

        updateVolumeUI();
        syncGameSound();
    });

    // 5. Nút mute/unmute
    muteButton.addEventListener('click', () => {
        if (muted || volume === 0) {
            volume = 0.6;
            slider.value = '60';
            muted = false;
        } else {
            muted = true;
        }

        updateVolumeUI();
        syncGameSound();
    });

    // Khởi tạo giao diện
    updateVolumeUI();
    syncGameSound();

    console.log('[Liquid Glass] Control panel đã khởi tạo.');
})();



// 6. Kéo thả Liquid Glass nhưng giữ nguyên bố cục
const glassPanel = document.getElementById('glassControlPanel');
const dragHandle = glassPanel?.querySelector('.glass-panel-header');

if (glassPanel && dragHandle) {
    let dragging = false;
    let startX = 0;
    let startY = 0;
    let moveX = 0;
    let moveY = 0;

    dragHandle.style.cursor = 'grab';
    dragHandle.style.touchAction = 'none';

    dragHandle.addEventListener('pointerdown', (event) => {
        if (event.button !== undefined && event.button !== 0) return;

        dragging = true;
        startX = event.clientX - moveX;
        startY = event.clientY - moveY;

        dragHandle.style.cursor = 'grabbing';
        dragHandle.setPointerCapture(event.pointerId);
        glassPanel.classList.add('is-dragging');

        event.preventDefault();
    });

    dragHandle.addEventListener('pointermove', (event) => {
        if (!dragging) return;

        const rect = glassPanel.getBoundingClientRect();

        let nextX = event.clientX - startX;
        let nextY = event.clientY - startY;

        // Giới hạn bảng trong màn hình
        nextX = Math.max(
            -rect.left + moveX,
            Math.min(
                window.innerWidth - rect.right + moveX,
                nextX
            )
        );

        nextY = Math.max(
            -rect.top + moveY,
            Math.min(
                window.innerHeight - rect.bottom + moveY,
                nextY
            )
        );

        moveX = nextX;
        moveY = nextY;

        glassPanel.style.transform =
            `translate(${moveX}px, ${moveY}px)`;
    });

    function stopDragging() {
        dragging = false;
        glassPanel.classList.remove('is-dragging');
        dragHandle.style.cursor = 'grab';
    }

    dragHandle.addEventListener('pointerup', stopDragging);
    dragHandle.addEventListener('pointercancel', stopDragging);

    console.log('[Liquid Glass] Drag đã khởi tạo.');
} else {
    console.error(
        '[Liquid Glass] Không tìm thấy bảng hoặc phần tiêu đề kéo thả.'
    );
}
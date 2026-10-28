'use strict';

// Frontend Cyber Flappy: game rules remain in the Haskell REST API.
const API_BASE = 'http://localhost:3000/api';

const canvas = document.getElementById('gameCanvas');
// Kích thước thế giới game: khớp screenWidth/screenHeight (800x600) của backend Haskell.
const WORLD_W = 800;
const WORLD_H = 600;
canvas.width = WORLD_W;
canvas.height = WORLD_H;
// Hệ số thu nhỏ hình vẽ (chỉnh ở đây nếu muốn to/nhỏ hơn).
const PIPE_VISUAL_SCALE = 1;   // độ rộng cột
const ACCENT_PIPE = false;      // true = bật lại cột thứ 2 màu tím hồng như trước
const TRAP_VISUAL_SCALE = 1;   // bẫy (gai, cầu lửa...)
const ITEM_VISUAL_SCALE = 1;   // xu, khiên, vật phẩm gió
// Phải bằng spikeWidth / spikeHeight trong GameState.hs (defaultParams).
const SPIKE_WIDTH = 70;
const SPIKE_HEIGHT = 180;
// Chiều cao thế giới backend (screenH). Bằng WORLD_H nên không cần quy đổi Y.
const BACKEND_WORLD_H = 600;
const Y_SCALE = WORLD_H / BACKEND_WORLD_H;
const ctx = canvas.getContext('2d');
const frame = document.getElementById('canvasFrame');
const overlay = document.getElementById('overlay');
const playButton = document.getElementById('playButton');
const playButtonText = document.getElementById('playButtonText');
const restartButton = document.getElementById('restartButton');
const soundButton = document.getElementById('soundButton');
const apiStatus = document.getElementById('apiStatus');
const scoreValue = document.getElementById('scoreValue');
const tickValue = document.getElementById('tickValue');
const statusValue = document.getElementById('statusValue');
const gameStateLabel = document.getElementById('gameState');
const messageText = document.getElementById('messageText');
const overlayKicker = document.getElementById('overlayKicker');
const overlayTitle = document.getElementById('overlayTitle');
const overlayText = document.getElementById('overlayText');
const overlaySymbol = document.getElementById('overlaySymbol');
const bestValue = document.getElementById('bestValue');
const scoreProgress = document.getElementById('scoreProgress');

let game = null;
let busy = false;
let lastFrameTime = 0;
let accumulator = 0;
let soundEnabled = false;
let audioContext = null;
let bestScore = 0;
let particles = [];
let trailParticles = [];
let backgroundTime = 0;
let pendingJump = false;
let pendingSkill = false;
// Chế độ chơi: false = sinh tồn (mặc định), true = bất tử (test: xuyên cột).
let immortalMode = false;

// Chuyển JSON Haskell sang định dạng giao diện đang sử dụng.
function normalizeGameState(raw, tick = 0) {
  return scaleStateY(normalizeGameStateRaw(raw, tick));
}

// Quy đổi toạ độ Y của backend về chiều cao canvas để sàn trùng đáy màn hình.
function scaleStateY(s) {
  if (Y_SCALE === 1) return s;
  const sy = (o, k) => (o && Number.isFinite(Number(o[k])) ? { ...o, [k]: Number(o[k]) * Y_SCALE } : o);
  return {
    ...s,
    bird: s.bird ? sy(s.bird, 'birdY') : s.bird,
    pipes: s.pipes.map(p => ({
      ...p,
      pipeGapY: Number(p.pipeGapY) * Y_SCALE,
      pipeGapHeight: Number(p.pipeGapHeight) * Y_SCALE
    })),
    coins: s.coins.map(c => sy(c, 'coinY')),
    items: s.items.map(i => sy(i, 'itemY')),
    traps: s.traps.map(t => sy(t, 'trapY'))
  };
}

function normalizeGameStateRaw(raw, tick = 0) {
  const bird = raw.gameBird || raw.bird || null;
  const sourcePipes = raw.gamePipes || raw.pipes || [];

  return {
    ...raw,
    bird: bird
      ? {
          ...bird,
          birdVelocityY:
            bird.birdVelocityY ?? bird.birdVelocity ?? 0
        }
      : null,

    pipes: sourcePipes.map(pipe => {
      const top = Number(pipe.pipeGapTop);
      const bottom = Number(pipe.pipeGapBottom);
      const hasBounds =
        Number.isFinite(top) && Number.isFinite(bottom);

      return {
        ...pipe,
        pipeGapY: hasBounds
          ? (top + bottom) / 2
          : pipe.pipeGapY ?? pipe.gapY ?? WORLD_H / 2,
        pipeGapHeight: hasBounds
          ? bottom - top
          : pipe.pipeGapHeight ?? pipe.gapHeight ?? 170
      };
    }),

    
    score: raw.gameScore ?? raw.score ?? 0,
    status: raw.gameStatus ?? raw.status ?? "Ready",
    tick: raw.tick ?? tick,

    
    // Chuẩn hóa Coin, Item, Effect và Trap từ JSON của Haskell
    coins: raw.gameCoins ?? raw.coins ?? [],
    items: raw.gameItems ?? raw.items ?? [],
    effects: raw.gameEffects ?? raw.effects ?? [],
    traps: raw.gameTraps ?? raw.traps ?? [],
    // Boss là trạng thái do Haskell điều khiển; null khi chưa đến mốc boss.
    boss: raw.gameBoss ?? raw.boss ?? null
  };
}

// Chuyển input của giao diện thành input Haskell hỗ trợ.
function toApiInput(input) {
  if (input === "Jump") return "Flap";
  return input;
}
const STEP_SECONDS = 1 / 60;



async function api(path, body) {
  const options = {
    method: body === undefined ? 'GET' : 'POST'
  };

  if (body !== undefined) {
    options.headers = {
      'Content-Type': 'application/json'
    };
    options.body = JSON.stringify(body);
  }

  const url = `${API_BASE}${path}`;

  console.log(`[API] Gửi request: ${options.method} ${url}`);

  const startedAt = performance.now();

  const response = await fetch(url, options);
  const text = await response.text();

  console.log(`[API] HTTP status: ${response.status}`);
  console.log(`[API] Response body: ${text}`);
  console.log(
    `[API] Thời gian phản hồi: ${Math.round(performance.now() - startedAt)} ms`
  );

  if (!response.ok) {
    throw new Error(`API ${response.status}: ${text.slice(0, 200)}`);
  }

  return JSON.parse(text);
}


function setApiOnline(online, message) {
  apiStatus.classList.toggle('online', online);
  apiStatus.classList.toggle('offline', !online);

  if (apiStatus.lastElementChild) {
    apiStatus.lastElementChild.textContent = online
      ? 'Haskell API đã kết nối'
      : 'Không kết nối được Haskell API';
  }

  if (message) {
    messageText.textContent = message;
  }
}

async function checkApi() {
  // Tách lỗi kết nối khỏi lỗi khởi tạo game.
  try {
    await api('/health');
    setApiOnline(true, 'API đã kết nối. Đang khởi tạo game...');
  } catch (error) {
    setApiOnline(
      false,
      'Không thể kết nối Haskell API. Kiểm tra backend và địa chỉ API.'
    );

    console.error('Lỗi kiểm tra Haskell API (/health):', error);

    if (typeof drawScene === 'function') {
      drawScene();
    }

    if (typeof drawCenteredText === 'function') {
      drawCenteredText(
        'KHÔNG KẾT NỐI ĐƯỢC HASKELL API',
        300,
        '#ff8bdc'
      );
    }

    return;
  }

  try {
    await newGame();
  } catch (error) {
    setApiOnline(
      true,
      'API đã kết nối nhưng không thể khởi tạo game.'
    );

    console.error('Lỗi khởi tạo game (/game/start):', error);
  }
}

async function newGame() {
  game = normalizeGameState(
  await api('/game/start', { bird: equippedBird, immortal: immortalMode }),
  0
);
  
  updateHud();
  showReadyOverlay();
  drawScene();
}

// ---------- Chọn chế độ: Sinh tồn / Bất tử (hiện trên màn hình mở đầu) ----------
function ensureModePicker() {
  let picker = document.getElementById('modePicker');
  if (picker) return picker;

  picker = document.createElement('div');
  picker.id = 'modePicker';
  picker.style.cssText =
    'display:flex;flex-direction:column;align-items:center;gap:10px;margin:14px 0;';

  const question = document.createElement('div');
  question.textContent = 'Bạn muốn chơi chế độ bất tử hay sinh tồn?';
  question.style.cssText =
    'font:600 14px "Space Grotesk",sans-serif;color:#fff;text-align:center;';

  const row = document.createElement('div');
  row.style.cssText = 'display:flex;gap:10px;';

  [['survival', 'SINH TỒN'], ['immortal', 'BẤT TỬ']].forEach(([mode, text]) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.dataset.mode = mode;
    btn.textContent = text;
    btn.tabIndex = -1;
    btn.style.cssText =
      'padding:8px 18px;border-radius:999px;cursor:pointer;' +
      'font:700 13px "Space Grotesk",sans-serif;letter-spacing:.06em;';
    // Không nhận focus để phím Space không kích hoạt lại nút.
    btn.addEventListener('mousedown', event => event.preventDefault());
    btn.addEventListener('click', () => setImmortalMode(mode === 'immortal'));
    row.appendChild(btn);
  });

  picker.append(question, row);
  playButton.parentElement.insertBefore(picker, playButton);
  refreshModePicker();
  return picker;
}

function refreshModePicker() {
  const picker = document.getElementById('modePicker');
  if (!picker) return;

  picker.querySelectorAll('button').forEach(btn => {
    const selected = (btn.dataset.mode === 'immortal') === immortalMode;
    const color = btn.dataset.mode === 'immortal' ? '#ffd640' : '#45f7ff';
    btn.style.border = `2px solid ${color}`;
    btn.style.background = selected ? color : 'transparent';
    btn.style.color = selected ? '#07091c' : color;
  });
}

function showModePicker(visible) {
  const picker = ensureModePicker();
  picker.style.display = visible ? 'flex' : 'none';
  refreshModePicker();
}

function setImmortalMode(value) {
  immortalMode = Boolean(value);
  // Ván chưa bắt đầu: state do client giữ nên đổi thẳng, lần gọi step sẽ gửi lên backend.
  if (game?.status === 'Ready') game.gameImmortal = immortalMode;
  refreshModePicker();
}

function showReadyOverlay() {
  showModePicker(true);
  overlay.classList.remove('hidden');
  overlaySymbol.textContent = '✦';
  overlayKicker.textContent = 'READY PLAYER ONE';
  overlayTitle.textContent = 'Cyber Flappy';
  overlayText.textContent =
    'Nhấn bắt đầu, sau đó click hoặc nhấn Space để vỗ cánh.';
  playButtonText.textContent = 'BẮT ĐẦU CHƠI';
}

function showGameOverOverlay() {
  showModePicker(true);
  overlay.classList.remove('hidden');
  overlaySymbol.textContent = '×';
  overlayKicker.textContent = 'Lại gặp nhau nữa rồi :(';
  overlayTitle.textContent = `Điểm của bạn: ${game.score ?? 0}`;
  overlayText.textContent =
    'Nạp lại năng lượng và thử phá kỷ lục của bạn.';
  playButtonText.textContent = 'CHƠI LẠI';
}

function showPauseOverlay() {
  showModePicker(false);
  overlay.classList.remove('hidden');
  overlaySymbol.textContent = 'Ⅱ';
  overlayKicker.textContent = 'SYSTEM PAUSED';
  overlayTitle.textContent = 'Tạm dừng';
  overlayText.textContent =
    'Nhấn tiếp tục để quay lại đường bay.';
  playButtonText.textContent = 'TIẾP TỤC';
}

function updateHud() {
  if (!game) return;

  const score = Number(game.score || 0);

  scoreValue.textContent = String(score).padStart(3, '0');
  tickValue.textContent = game.tick ?? 0;
  statusValue.textContent = game.status ?? 'Unknown';

  gameStateLabel.textContent = ({
    Ready: 'READY',
    Playing: 'PLAYING',
    Paused: 'PAUSED',
    GameOver: 'GAME OVER'
  })[game.status] || String(game.status || 'UNKNOWN').toUpperCase();

  bestScore = Math.max(bestScore, score);
  bestValue.textContent = bestScore;
  scoreProgress.style.width = `${Math.min(100, score * 5)}%`;
}


async function sendInput(input) {
  if (!game) return;

  if (busy) {
    if (input === 'Jump') pendingJump = true;
    if (input === 'Skill') pendingSkill = true;
    return;
  }

  if (game.status === 'GameOver' && input !== 'Restart') return;

  busy = true;

  try {
    // Chuyển tên input của frontend sang đúng tên Haskell
    // 'Skill' -> {"UseSkill":1} (slot 1 của backend Haskell).
    const apiInput =
      input === 'Jump' ? 'Flap'
      : input === 'Skill' ? { UseSkill: 1 }
      : input;

    

    // Lưu trạng thái trước khi gọi Haskell API.
    const previousGold = Number(game.gameGold ?? 0);
    const previousCoins = game.coins ?? [];

    const nextGame = await api('/game/step', {
      input: apiInput,
      state: game
    });

    // Lấy số xu tích lũy mà Haskell trả về.
    const nextGold = Number(
      nextGame.gameGold ?? nextGame.gold ?? previousGold
    );

    // Cách 1: Haskell đã tăng gameGold.
    let earnedCoins = Math.max(0, nextGold - previousGold);

    // Cách 2: Nếu gameGold chưa tăng, kiểm tra xu vừa được nhặt.
    if (earnedCoins === 0) {
      const nextCoins = nextGame.gameCoins ?? nextGame.coins ?? [];

      const previousCollected = new Set(
        previousCoins
          .filter(coin => coin.coinCollected)
          .map(coin => `${coin.coinKind}:${coin.coinX}:${coin.coinY}`)
      );

      earnedCoins = nextCoins.filter(coin => {
        if (!coin.coinCollected) return false;

        const key = `${coin.coinKind}:${coin.coinX}:${coin.coinY}`;
        return !previousCollected.has(key);
      }).filter(coin => coin.coinKind === "GoldCoin").length;
    }

    // Chỉ cộng số xu mới nhặt được.
    if (earnedCoins > 0) {
      addWalletCoins(earnedCoins);
      console.log("[SHOP] Nhặt được:", earnedCoins, "xu");
    }

    game = normalizeGameState(
      nextGame,
      (game.tick ?? 0) + 1
    );


    updateHud();

    if (game.status === 'Playing') {
      overlay.classList.add('hidden');
    }

    if (game.status === 'GameOver') {
      showGameOverOverlay();

      burstParticles(
        canvas.width * 0.5,
        canvas.height * 0.42,
        '#ff48d7',
        24
      );

      playTone(170, 0.16);
    }

    if (input === 'Jump' && game.status === 'Playing') {
      burstParticles(
        Number(game.bird?.birdX ?? 90) - 10,
        Number(game.bird?.birdY ?? WORLD_H / 2) + 10,
        '#45f7ff',
        7
      );

      playTone(520, 0.055);
    }

    drawScene();
  } catch (error) {
    console.error('Lỗi /game/step:', error);

    setApiOnline(
      false,
      'Lỗi gọi API. Hãy kiểm tra terminal backend Haskell.'
    );
  } finally {
    busy = false;

    if (pendingSkill) {
      pendingSkill = false;
      if (game?.status === 'Playing') void useSkill();
    }

    if (pendingJump) {
      pendingJump = false;

      if (game?.status === 'Playing' || game?.status === 'Ready') {
        void flap();
      }
    }
  }
}

async function startOrRestart() {
  if (!game || game.status === 'GameOver') {
    await restartGame();
    return;
  }

  if (game.status === 'Ready') {
    await sendInput('Start');

    if (game?.status === 'Playing') {
      overlay.classList.add('hidden');
    }
  } else if (game.status === 'Paused') {
    await sendInput('Resume');

    if (game?.status === 'Playing') {
      overlay.classList.add('hidden');
    }
  } else if (game.status === 'Playing') {
    await flap();
  }
}

async function restartGame() {
  if (busy) return;

  busy = true;

  try {
    game = normalizeGameState(
      await api('/game/restart', { bird: equippedBird, immortal: immortalMode }),
      0
    );
    updateHud();
    overlay.classList.add('hidden');
    particles = [];
    drawScene();

    setApiOnline(true, 'Lượt chơi mới đã sẵn sàng. Click để vỗ cánh!');

    burstParticles(
      canvas.width / 2,
      canvas.height * 0.7,
      '#45f7ff',
      18
    );
  } catch (error) {
    console.error('Lỗi /game/restart:', error);
    setApiOnline(
      false,
      'Không thể chơi lại. Kiểm tra backend Haskell.'
    );
  } finally {
    busy = false;
  }
}

// Dùng skill khi nộ đầy (backend kiểm tra lại điều kiện).
async function useSkill() {
  if (game?.status !== 'Playing') return;
  if (!game.gameDecision?.decSkillReady) return;
  await sendInput('Skill');
  playTone(760, 0.12);
}

async function flap() {
  if (!game) return;

  if (game.status === 'Ready') {
    await sendInput('Jump');

    if (game?.status === 'Playing') {
      overlay.classList.add('hidden');
    }
  } else if (game.status === 'GameOver') {
    await restartGame();
  } else if (game.status === 'Playing') {
    await sendInput('Jump');
  } else if (game.status === 'Paused') {
    await sendInput('Resume');

    if (game?.status === 'Playing') {
      overlay.classList.add('hidden');
    }
  }
}
const backgroundThemes = {
  bg_sky: {
    pipeStyle: "classic",   // cột xanh lá như Flappy Bird nguyên bản
    sky: ["#79cdf6", "#a9b7ef", "#efaed6"],
    glow1: "rgba(255,246,200,.30)",
    glow2: "rgba(255,150,220,.20)",
    pipe: "#45f7ff",
    pipeDark: "#101b39",
    ground: "#090b24"
  },
  bg_cyber: {
    sky: ["#090b28", "#171047", "#071d38"],
    glow1: "rgba(255,55,220,.26)",
    glow2: "rgba(0,238,255,.22)",
    pipe: "#45f7ff",
    pipeDark: "#101b39",
    ground: "#090b24"
  },
  bg_sunset: {
    sky: ["#35102f", "#762b50", "#201b45"],
    glow1: "rgba(255,120,70,.30)",
    glow2: "rgba(255,72,215,.20)",
    pipe: "#ffad68",
    pipeDark: "#482044",
    ground: "#25102f"
  },
  bg_arctic: {
    sky: ["#061b36", "#0d4564", "#101d49"],
    glow1: "rgba(100,255,255,.25)",
    glow2: "rgba(80,140,255,.25)",
    pipe: "#8dfaff",
    pipeDark: "#123654",
    ground: "#07172e"
  }
};
const backgroundImages = {
  bg_cyber: new Image(),
  bg_sunset: new Image(),
  bg_arctic: new Image()
};

backgroundImages.bg_cyber.src = "picture/chienbinh.jpg";
backgroundImages.bg_sunset.src = "picture/soicodoc.jpg";
backgroundImages.bg_arctic.src = "picture/vua.jpg";

function getBackgroundTheme() {
  return backgroundThemes[equippedBackground]
    || backgroundThemes.bg_sky;
}
// Ảnh thu nhỏ của map mặc định trong Shop (SVG nhúng sẵn, không cần file ảnh).
const SKY_THUMB = 'data:image/svg+xml;utf8,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300">' +
  '<defs>' +
  '<linearGradient id="s" x1="0" y1="0" x2="0" y2="1">' +
  '<stop offset="0" stop-color="#79cdf6"/><stop offset=".5" stop-color="#a9b7ef"/><stop offset="1" stop-color="#efaed6"/>' +
  '</linearGradient>' +
  '<radialGradient id="g" cx=".78" cy=".16" r=".5">' +
  '<stop offset="0" stop-color="#fff6c8" stop-opacity=".85"/><stop offset="1" stop-color="#fff6c8" stop-opacity="0"/>' +
  '</radialGradient>' +
  '<g id="c"><circle cx="30" cy="34" r="22"/><circle cx="62" cy="20" r="28"/><circle cx="98" cy="30" r="22"/>' +
  '<rect x="16" y="32" width="96" height="22" rx="11"/></g>' +
  '</defs>' +
  '<rect width="400" height="300" fill="url(#s)"/><rect width="400" height="300" fill="url(#g)"/>' +
  '<use href="#c" fill="#b3d5f3" transform="translate(30 66) scale(.9)"/><use href="#c" fill="#fff" transform="translate(30 60) scale(.9)"/>' +
  '<use href="#c" fill="#b3d5f3" transform="translate(236 128) scale(1.05)"/><use href="#c" fill="#fff" transform="translate(236 122) scale(1.05)"/>' +
  '<use href="#c" fill="#b3d5f3" transform="translate(90 214) scale(1.4)"/><use href="#c" fill="#fff" transform="translate(90 206) scale(1.4)"/>' +
  '</svg>'
);

// ===== MAP MẶC ĐỊNH (bg_sky): bầu trời kẹo + nhiều lớp mây parallax =====
// Chỉ là phần vẽ nền: không đụng tới trạng thái game hay API Haskell.
// Các lớp mây trôi ngang liên tục, đồng thời dịch dọc theo độ cao của chim
// (camera mượt) nên nền "chạy theo chim" thay vì đứng yên.
const skyMap = {
  scroll: 0,       // quãng đường mây đã trôi
  camY: 0,         // vị trí camera làm mượt, -1 (chim ở đỉnh) .. 1 (chim ở đáy)
  lastTime: 0
};

// Mỗi lớp: tốc độ trôi, độ lệch dọc theo chim, cỡ/độ mờ và vị trí các đám mây.
const SKY_LAYERS = [
  { speed: 7,  depth: 8,  scale: 0.45, alpha: 0.55, clouds: [[40, 70], [300, 150], [520, 60], [720, 190], [900, 110]] },
  { speed: 18, depth: 20, scale: 0.8,  alpha: 0.8,  clouds: [[120, 250], [420, 330], [690, 230], [980, 370]] },
  { speed: 42, depth: 38, scale: 1.3,  alpha: 0.95, clouds: [[60, 520], [380, 560], [700, 505], [1000, 545]] }
];

const SKY_SPARKLES = [
  [90, 120], [210, 60], [330, 210], [470, 90], [600, 170], [700, 70],
  [150, 300], [540, 280], [760, 330], [260, 400], [650, 430], [380, 470]
];

function drawSkyCloud(x, y, s, alpha) {
  // vòng tròn (cx, cy, r) tạo thân mây + 1 khối chữ nhật làm đáy phẳng
  const circles = [
    [0, 4, 30], [40, -14, 40], [92, -6, 34], [126, 8, 24], [-2, 22, 14], [128, 22, 14]
  ];
  const tracePath = (dy) => {
    ctx.beginPath();
    for (const [cx, cy, r] of circles) {
      ctx.moveTo(cx + r, cy + dy);
      ctx.arc(cx, cy + dy, r, 0, Math.PI * 2);
    }
    ctx.rect(-4, 6 + dy, 134, 30);
  };

  ctx.save();
  ctx.translate(x, y);
  ctx.scale(s, s);
  ctx.globalAlpha = alpha;

  tracePath(6);                      // viền bóng xanh nhạt phía dưới
  ctx.fillStyle = '#b3d5f3';
  ctx.fill();

  const body = ctx.createLinearGradient(0, -50, 0, 38);
  body.addColorStop(0, '#ffffff');
  body.addColorStop(0.65, '#ffffff');
  body.addColorStop(1, '#dcecfb');
  tracePath(0);
  ctx.fillStyle = body;
  ctx.fill();
  ctx.restore();
}

function drawSkyMap(w, h) {
  const now = Date.now();
  const dt = skyMap.lastTime ? Math.min(0.05, (now - skyMap.lastTime) / 1000) : 0;
  skyMap.lastTime = now;

  // Mây trôi nhanh khi đang chơi, chậm khi chờ / thua, đứng khi tạm dừng.
  const status = game?.status;
  const flow = status === 'Playing' ? 1 : status === 'Paused' ? 0 : 0.35;
  skyMap.scroll += dt * flow;

  // Camera bám theo độ cao của chim (làm mượt để không bị giật).
  const birdY = Number(game?.bird?.birdY);
  const target = Number.isFinite(birdY)
    ? Math.max(-1, Math.min(1, (birdY - h / 2) / (h / 2)))
    : 0;
  skyMap.camY += (target - skyMap.camY) * Math.min(1, dt * 4);

  // 1. Bầu trời: xanh → tím nhạt → hồng
  const sky = ctx.createLinearGradient(0, 0, 0, h);
  sky.addColorStop(0, '#79cdf6');
  sky.addColorStop(0.5, '#a9b7ef');
  sky.addColorStop(1, '#efaed6');
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, w, h);

  // 2. Hào quang mặt trời (lớp xa nhất)
  const glowY = h * 0.16 - skyMap.camY * 8;
  const glow = ctx.createRadialGradient(w * 0.78, glowY, 10, w * 0.78, glowY, 230);
  glow.addColorStop(0, 'rgba(255, 246, 200, .60)');
  glow.addColorStop(0.5, 'rgba(255, 232, 190, .20)');
  glow.addColorStop(1, 'rgba(255, 232, 190, 0)');
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, w, h);

  // 3. Các ánh lấp lánh nhấp nháy (trôi cùng lớp xa)
  const span0 = w + 300;
  for (let i = 0; i < SKY_SPARKLES.length; i++) {
    const [sx, sy] = SKY_SPARKLES[i];
    const px = ((sx - skyMap.scroll * 7) % span0 + span0) % span0 - 150;
    const py = sy - skyMap.camY * 8;
    const tw = 0.5 + 0.5 * Math.sin(now / 420 + i * 1.7);
    const r = 2 + 2.2 * tw;
    ctx.save();
    ctx.globalAlpha = 0.25 + 0.45 * tw;
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.moveTo(px, py - r * 1.8);
    ctx.lineTo(px + r * 0.5, py - r * 0.5);
    ctx.lineTo(px + r * 1.8, py);
    ctx.lineTo(px + r * 0.5, py + r * 0.5);
    ctx.lineTo(px, py + r * 1.8);
    ctx.lineTo(px - r * 0.5, py + r * 0.5);
    ctx.lineTo(px - r * 1.8, py);
    ctx.lineTo(px - r * 0.5, py - r * 0.5);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  // 4. Các lớp mây: xa → gần, mỗi lớp trôi và lệch theo chim khác nhau
  for (const layer of SKY_LAYERS) {
    const span = w + 300;
    const shiftY = -skyMap.camY * layer.depth;
    for (const [cx, cy] of layer.clouds) {
      const x = ((cx - skyMap.scroll * layer.speed) % span + span) % span - 200;
      drawSkyCloud(x, cy + shiftY, layer.scale, layer.alpha);
    }
  }
}

// ----- Cyber city background -----
function drawBackground() {
  const w = canvas.width;
  const h = canvas.height;

  // Map mặc định: bầu trời vẽ bằng canvas, có mây trôi theo chim.
  if (!backgroundThemes[equippedBackground] || equippedBackground === 'bg_sky') {
    drawSkyMap(w, h);
    return;
  }

  const theme = getBackgroundTheme();
  const image = backgroundImages[equippedBackground];

  // Nếu ảnh đã tải xong thì vẽ ảnh làm nền
  if (image && image.complete && image.naturalWidth > 0) {
    const scale = Math.max(
      w / image.naturalWidth,
      h / image.naturalHeight
    );

    const imageWidth = image.naturalWidth * scale;
    const imageHeight = image.naturalHeight * scale;
    const x = (w - imageWidth) / 2;
    const y = (h - imageHeight) / 2;

    ctx.drawImage(image, x, y, imageWidth, imageHeight);
  } else {
    // Nếu ảnh chưa tải được thì dùng nền gradient dự phòng
    const sky = ctx.createLinearGradient(0, 0, w, h);
    sky.addColorStop(0, theme.sky[0]);
    sky.addColorStop(0.45, theme.sky[1]);
    sky.addColorStop(1, theme.sky[2]);

    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);
  }

  // Lớp phủ tối nhẹ để giữ phong cách cyberpunk
  ctx.save();
  ctx.globalAlpha = 0.3;

  const overlay = ctx.createLinearGradient(0, 0, 0, h);
  overlay.addColorStop(0, "rgba(5, 8, 30, 0.1)");
  overlay.addColorStop(1, theme.ground);

  ctx.fillStyle = overlay;
  ctx.fillRect(0, 0, w, h);
  ctx.restore();
}

function roundedRect(x, y, w, h, r) {
  const radius = Math.max(0, Math.min(r, w / 2, h / 2));

  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + w, y, x + w, y + h, radius);
  ctx.arcTo(x + w, y + h, x, y + h, radius);
  ctx.arcTo(x, y + h, x, y, radius);
  ctx.arcTo(x, y, x + w, y, radius);
  ctx.closePath();
}

function getPipeValue(pipe, candidates, fallback = 0) {
  for (const key of candidates) {
    if (pipe && pipe[key] !== undefined && pipe[key] !== null) {
      const value = Number(pipe[key]);

      if (Number.isFinite(value)) {
        return value;
      }
    }
  }

  return fallback;
}

function getPipeStyle(ctx, isMoving) {
    const gradient = ctx.createLinearGradient(0, 0, 64, 0);

    if (isMoving) {
        // Cột di chuyển: tím hồng neon
        gradient.addColorStop(0, "#6817B8");
        gradient.addColorStop(0.35, "#FF35D3");
        gradient.addColorStop(0.55, "#FFC4F6");
        gradient.addColorStop(0.8, "#C653FF");
        gradient.addColorStop(1, "#6817B8");
    } else {
        // Cột thường: cyan neon
        gradient.addColorStop(0, "#087FAD");
        gradient.addColorStop(0.35, "#19E8FF");
        gradient.addColorStop(0.55, "#C8FFFF");
        gradient.addColorStop(0.8, "#53F5FF");
        gradient.addColorStop(1, "#087FAD");
    }

    return gradient;
}

// ---------- Token gió: hạt năng lượng lục giác, nhặt để ăn ----------
function hexPath(R) {
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const a = Math.PI / 6 + i * Math.PI / 3;
    const px = Math.cos(a) * R;
    const py = Math.sin(a) * R;
    if (i === 0) ctx.moveTo(px, py);
    else ctx.lineTo(px, py);
  }
  ctx.closePath();
}

function drawWindToken(x, y, radius) {
  const R = Math.max(radius, 12) * 1.1;
  const bob = Math.sin(backgroundTime * 3 + x * 0.02) * 2.5;
  const pulse = 0.5 + 0.5 * Math.sin(backgroundTime * 3.4);

  ctx.save();
  ctx.translate(x, y + bob);

  // Quầng sáng nhịp thở — màu đỏ tím nguy hiểm
  const aura = ctx.createRadialGradient(
    0, 0, R * 0.4, 0, 0, R * (2 + pulse * 0.4)
  );
  aura.addColorStop(0, 'rgba(255, 45, 100, 0.42)');
  aura.addColorStop(1, 'rgba(255, 45, 100, 0)');
  ctx.fillStyle = aura;
  ctx.beginPath();
  ctx.arc(0, 0, R * (2 + pulse * 0.4), 0, Math.PI * 2);
  ctx.fill();


  // Vòng đứt nét cảnh báo
  ctx.save();
  ctx.rotate(-backgroundTime * 1.6);
  ctx.strokeStyle = 'rgba(255, 170, 210, 0.9)';
  ctx.lineWidth = 1.8;
  ctx.lineCap = 'round';
  ctx.setLineDash([R * 0.45, R * 0.4]);
  ctx.beginPath();
  ctx.arc(0, 0, R * 1.45, 0, Math.PI * 2);
  ctx.stroke();
  ctx.restore();

  // Viền lục giác đỏ hồng
  const edge = ctx.createLinearGradient(-R, -R, R, R);
  edge.addColorStop(0, '#fff0f5');
  edge.addColorStop(0.5, '#ff315b');
  edge.addColorStop(1, '#a855f7');

  ctx.shadowColor = '#ff315b';
  ctx.shadowBlur = 18;
  hexPath(R);
  ctx.fillStyle = edge;
  ctx.fill();
  ctx.shadowBlur = 0;


  // Mặt trong tối
  ctx.save();
  ctx.scale(0.76, 0.76);
  hexPath(R);
  const inner = ctx.createLinearGradient(0, -R, 0, R);
  inner.addColorStop(0, '#53102f');
  inner.addColorStop(1, '#17091f');
  ctx.fillStyle = inner;
  ctx.fill();
  ctx.restore();

  // Biểu tượng » (hai mũi tên gió)
  ctx.strokeStyle = '#e8ffff';
  ctx.shadowColor = '#ffffff';
  ctx.shadowBlur = 8;
  ctx.lineWidth = Math.max(2, R * 0.16);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (const dx of [-R * 0.22, R * 0.2]) {
    ctx.beginPath();
    ctx.moveTo(dx - R * 0.16, -R * 0.3);
    ctx.lineTo(dx + R * 0.14, 0);
    ctx.lineTo(dx - R * 0.16, R * 0.3);
    ctx.stroke();
  }
  ctx.shadowBlur = 0;

  // Vệt sáng bóng góc trái trên
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(-R * 0.82, -R * 0.1);
  ctx.lineTo(-R * 0.5, -R * 0.72);
  ctx.stroke();

  // Tia lấp lánh
  const tw = Math.max(0, Math.sin(backgroundTime * 4 + x * 0.03));
  if (tw > 0.05) {
    const s = R * 0.4 * tw;
    ctx.globalAlpha = tw;
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1.3;
    ctx.beginPath();
    ctx.moveTo(R * 0.75 - s, -R * 0.8);
    ctx.lineTo(R * 0.75 + s, -R * 0.8);
    ctx.moveTo(R * 0.75, -R * 0.8 - s);
    ctx.lineTo(R * 0.75, -R * 0.8 + s);
    ctx.stroke();
  }

  ctx.restore();
}


function drawWindCurse(item) {
  if (!item || item.itemCollected) return;

  const x = Number(item.itemX);
  const y = Number(item.itemY);
  const radius = Number(item.itemRadius ?? 18) * ITEM_VISUAL_SCALE;

  if (![x, y, radius].every(Number.isFinite) || radius <= 0) {
    return;
  }

  drawWindToken(x, y, radius);
}


function drawTrap(trap) {
  if (!trap || trap.trapActive === false) return;

  const x = Number(trap.trapX);
  const y = Number(trap.trapY);
  const radius = Number(trap.trapRadius) * TRAP_VISUAL_SCALE;
  const kind = trap.trapKind;

  if (![x, y, radius].every(Number.isFinite)) return;

  ctx.save();

  switch (kind) {
    case "CeilingSpikes":
    case "FloorSpikes": {
      // Vẽ đúng kích thước backend (spikeWidth/spikeHeight) để hình khớp vùng va chạm.
      drawSpikes(
        x,
        kind === "CeilingSpikes",
        SPIKE_WIDTH,
        SPIKE_HEIGHT
      );
      break;
    }

    case "Fireball": {
      const gradient = ctx.createRadialGradient(
        x, y, 2, x, y, Math.max(radius, 8)
      );
      gradient.addColorStop(0, "#fff8b0");
      gradient.addColorStop(0.35, "#ff9f43");
      gradient.addColorStop(1, "#ff304f");

      ctx.fillStyle = gradient;
      ctx.shadowColor = "#ff5722";
      ctx.shadowBlur = 18;
      ctx.beginPath();
      ctx.arc(x, y, Math.max(radius, 8), 0, Math.PI * 2);
      ctx.fill();
      break;
    }

    case "HunterBird": {
      ctx.translate(x, y);
      ctx.fillStyle = "#c084fc";
      ctx.shadowColor = "#a855f7";
      ctx.shadowBlur = 14;

      // Thân chim
      ctx.beginPath();
      ctx.ellipse(0, 0, Math.max(radius, 10), Math.max(radius * 0.65, 7), 0, 0, Math.PI * 2);
      ctx.fill();

      // Cánh
      ctx.beginPath();
      ctx.moveTo(-4, 0);
      ctx.lineTo(-radius * 0.7, -radius);
      ctx.lineTo(radius * 0.4, -radius * 0.35);
      ctx.closePath();
      ctx.fill();

      // Mỏ
      ctx.fillStyle = "#fbbf24";
      ctx.beginPath();
      ctx.moveTo(radius * 0.7, -2);
      ctx.lineTo(radius * 1.3, 1);
      ctx.lineTo(radius * 0.7, 4);
      ctx.closePath();
      ctx.fill();

      // Mắt
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(radius * 0.35, -2, 2, 0, Math.PI * 2);
      ctx.fill();
      break;
    }

    default:
      break;
  }

  ctx.restore();
}


// Colourful neon pipes: cyan, purple and hot-pink gradient trims.
function drawPipe(pipe, index = 0) {
  const theme = getBackgroundTheme();
  const x = getPipeValue(pipe, ['pipeX', 'x'], 0);
  const gapY = getPipeValue(pipe, ['pipeGapY', 'gapY'], WORLD_H / 2);
  const gapHeight = getPipeValue(
    pipe,
    ['pipeGapHeight', 'gapHeight'],
    170
  );
  const rawWidth = getPipeValue(pipe, ['pipeWidth', 'width'], 64);
  const width = rawWidth * PIPE_VISUAL_SCALE;
  const pipeLeft = x + (rawWidth - width) / 2;

  const topHeight = Math.max(0, gapY - gapHeight / 2);
  const bottomY = gapY + gapHeight / 2;

  // Cột thứ 2 từng được tô tím hồng; nay mặc định dùng chung màu với các cột khác.
  const isMoving = ACCENT_PIPE && index === 1;

  const pipeColor = getPipeStyle(ctx, isMoving);

  const palette = isMoving
    ? ["#FF35D3", "#C653FF", "#6817B8"]
    : [theme.pipe, theme.pipe, theme.pipeDark];

  function pipePart(px, py, pw, ph, capAtBottom) {
    if (ph <= 0 || pw <= 0) return;

        const grad = ctx.createLinearGradient(px, 0, px + pw, 0);

    if (isMoving) {
      // Cột tím hồng neon
      grad.addColorStop(0, "#6817B8");
      grad.addColorStop(0.35, "#FF35D3");
      grad.addColorStop(0.55, "#FFC4F6");
      grad.addColorStop(0.8, "#C653FF");
      grad.addColorStop(1, "#6817B8");
    } else {
      // Cột cyan như ban đầu
      grad.addColorStop(0, palette[2]);
      grad.addColorStop(0.17, palette[0]);
      grad.addColorStop(0.34, palette[1]);
      grad.addColorStop(0.55, palette[2]);
      grad.addColorStop(0.78, palette[1]);
      grad.addColorStop(1, palette[2]);
    }

    ctx.save();
    ctx.shadowColor = palette[0];
    ctx.shadowBlur = 11;
    ctx.fillStyle = grad;
    ctx.fillRect(px, py, pw, ph);

    ctx.shadowBlur = 0;
    ctx.strokeStyle = palette[0];
    ctx.lineWidth = 1.5;
    ctx.strokeRect(px + 0.75, py + 0.75, pw - 1.5, ph - 1.5);

    // Glass-like shine
    const shine = ctx.createLinearGradient(px, 0, px + pw, 0);
    shine.addColorStop(0, 'rgba(255,255,255,.02)');
    shine.addColorStop(0.22, 'rgba(255,255,255,.34)');
    shine.addColorStop(0.36, 'rgba(255,255,255,.03)');
    shine.addColorStop(1, 'rgba(255,255,255,0)');

    ctx.fillStyle = shine;
    ctx.fillRect(px + 3, py + 2, pw - 6, Math.max(0, ph - 4));

    // Tech stripes
    ctx.globalAlpha = 0.55;
    ctx.strokeStyle = palette[0];
    ctx.lineWidth = 1;

    for (let sy = py + 15; sy < py + ph - 8; sy += 30) {
      ctx.beginPath();
      ctx.moveTo(px + 8, sy);
      ctx.lineTo(px + pw - 8, sy);
      ctx.stroke();
    }

    ctx.globalAlpha = 1;

    const capH = 8;
    const capW = pw + 8;
    const capX = px - 4;
    const capY = capAtBottom ? py + ph - capH : py;

    const capGrad = ctx.createLinearGradient(
      capX,
      capY,
      capX + capW,
      capY
    );

    capGrad.addColorStop(0, palette[2]);
    capGrad.addColorStop(0.25, palette[0]);
    capGrad.addColorStop(0.6, palette[1]);
    capGrad.addColorStop(1, palette[2]);

    ctx.fillStyle = capGrad;
    ctx.fillRect(capX, capY, capW, capH);
    ctx.strokeStyle = palette[0];
    ctx.strokeRect(capX + 0.5, capY + 0.5, capW - 1, capH - 1);

    ctx.restore();
  }

  // Cột xanh lá kiểu Flappy Bird gốc: thân có vệt sáng, miệng cột to, viền tối.
  function classicPart(px, py, pw, ph, capAtBottom) {
    if (ph <= 0 || pw <= 0) return;

    const shade = (x0, w) => {
      const g = ctx.createLinearGradient(x0, 0, x0 + w, 0);
      g.addColorStop(0, '#4f8a1e');
      g.addColorStop(0.14, '#93d84f');
      g.addColorStop(0.34, '#c8f27c');
      g.addColorStop(0.58, '#78c43a');
      g.addColorStop(0.86, '#5aa529');
      g.addColorStop(1, '#3d7519');
      return g;
    };

    ctx.save();
    ctx.lineJoin = 'miter';
    ctx.strokeStyle = '#2b4f12';
    ctx.lineWidth = 2;

    // thân cột
    ctx.fillStyle = shade(px, pw);
    ctx.fillRect(px, py, pw, ph);
    ctx.strokeRect(px + 1, py + 1, pw - 2, ph - 2);

    // miệng cột (to hơn thân 4px mỗi bên)
    const capH = Math.min(26, ph);
    const capW = pw + 8;
    const capX = px - 4;
    const capY = capAtBottom ? py + ph - capH : py;
    ctx.fillStyle = shade(capX, capW);
    ctx.fillRect(capX, capY, capW, capH);
    ctx.strokeRect(capX + 1, capY + 1, capW - 2, capH - 2);

    // vệt bóng mờ dưới miệng cột để nổi khối
    ctx.fillStyle = 'rgba(30, 70, 10, .22)';
    if (capAtBottom) {
      ctx.fillRect(px + 2, capY - 6, pw - 4, 6);
    } else {
      ctx.fillRect(px + 2, capY + capH, pw - 4, 6);
    }
    ctx.restore();
  }

  const drawPart = theme.pipeStyle === 'classic' ? classicPart : pipePart;

  // Top tube ends at the gap; bottom tube starts at the gap.
  drawPart(pipeLeft, 0, width, topHeight, true);
  drawPart(pipeLeft, bottomY, width, canvas.height - bottomY, false);
}

function updateBirdTrail(dt) {
  if (!game || game.status !== "Playing" || !equippedEffect) {
    return;
  }

  const bird = game.bird;
  if (!bird) return;

  // Chỉ tạo vệt khi chim đang bay
  trailParticles.push({
    x: Number(bird.birdX) - 12,
    y: Number(bird.birdY),
    life: 0.38,
    maxLife: 0.38,
    size: 5,
    color:
      equippedEffect === "fire" ? "#ff7a36" :
      equippedEffect === "lightning" ? "#45f7ff" :
      "#d8b4ff"
  });

  // Giới hạn số hạt để tránh tốn tài nguyên
  if (trailParticles.length > 70) {
    trailParticles.shift();
  }

  for (const p of trailParticles) {
    p.x -= 65 * dt;
    p.life -= dt;
  }

  trailParticles = trailParticles.filter(p => p.life > 0);
}

function drawBirdTrail() {
  for (const p of trailParticles) {
    const alpha = Math.max(0, p.life / p.maxLife);

    ctx.save();
    ctx.globalAlpha = alpha * 0.45;
    ctx.fillStyle = p.color;
    ctx.shadowColor = p.color;
    ctx.shadowBlur = 14;

    ctx.beginPath();
    ctx.ellipse(
      p.x,
      p.y,
      p.size * alpha * 1.8,
      p.size * alpha * 0.7,
      0,
      0,
      Math.PI * 2
    );
    ctx.fill();
    ctx.restore();
  }
}



// ---------- Bảng màu ----------
const ART = {
  coin: {
    rim:   ['#fff6b8', '#ffc928', '#b8680c'],
    face:  ['#ffe680', '#f5ad1c'],
    emboss: '#8a4f0a',
    glow:  'rgba(255, 196, 40, 0.38)'
  },
  shield: {
    edge:  ['#c9fdff', '#35e6ff', '#1478ff'],
    inner: ['#0e3a78', '#071b44'],
    glow:  '#45f7ff'
  },
  spike: {
    steelLight: '#8f9ccf',
    steelDark:  '#2b3263',
    plate:      ['#323a73', '#12162f'],
    neon:       '#ff4d79',
    tip:        '#ffd0dc'
  }
};
 
// ---------- Đồng xu: xoay 3D, bóng viền, lấp lánh ----------
function drawCoin(coin) {
  if (coin.coinCollected) return;
 
  const x = Number(coin.coinX);
  const y = Number(coin.coinY);
  const r = Number(coin.coinRadius ?? 9) * ITEM_VISUAL_SCALE;
 
  if (![x, y, r].every(Number.isFinite) || r <= 0) return;
 
  // y gần như không đổi nên mỗi xu có pha xoay riêng, không xoay đồng loạt.
  const phase = backgroundTime * 3.4 + y * 0.07;
  const squash = Math.max(0.16, Math.abs(Math.cos(phase)));
  const bob = Math.sin(backgroundTime * 3 + y * 0.05) * 1.8;
  const cy = y + bob;
 
  ctx.save();
 
  // Quầng sáng mềm phía sau xu
  const halo = ctx.createRadialGradient(x, cy, r * 0.4, x, cy, r * 2.5);
  halo.addColorStop(0, ART.coin.glow);
  halo.addColorStop(1, 'rgba(255, 196, 40, 0)');
  ctx.fillStyle = halo;
  ctx.beginPath();
  ctx.arc(x, cy, r * 2.5, 0, Math.PI * 2);
  ctx.fill();
 
  // Thân xu (ép theo trục X để tạo cảm giác xoay)
  ctx.translate(x, cy);
  ctx.scale(squash, 1);
 
  // Viền ngoài kim loại
  const rim = ctx.createLinearGradient(-r, -r, r, r);
  rim.addColorStop(0, ART.coin.rim[0]);
  rim.addColorStop(0.5, ART.coin.rim[1]);
  rim.addColorStop(1, ART.coin.rim[2]);
 
  ctx.shadowColor = '#ffb81c';
  ctx.shadowBlur = 12;
  ctx.fillStyle = rim;
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
 
  // Mặt xu lõm vào bên trong viền
  const face = ctx.createRadialGradient(
    -r * 0.25, -r * 0.3, r * 0.1, 0, 0, r * 0.78
  );
  face.addColorStop(0, ART.coin.face[0]);
  face.addColorStop(1, ART.coin.face[1]);
  ctx.fillStyle = face;
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.76, 0, Math.PI * 2);
  ctx.fill();
 
  ctx.strokeStyle = 'rgba(138, 79, 10, 0.55)';
  ctx.lineWidth = Math.max(0.8, r * 0.09);
  ctx.stroke();
 
  // Biểu tượng chỉ hiện khi xu quay mặt về phía người chơi
  if (squash > 0.42) {
    ctx.font = `800 ${r * 1.08}px "Space Grotesk", sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
 
    ctx.fillStyle = 'rgba(255, 255, 255, 0.55)';
    ctx.fillText('$', 0.6, r * 0.06 + 0.7);
    ctx.fillStyle = ART.coin.emboss;
    ctx.fillText('$', 0, r * 0.06);
  }
 
  // Vệt sáng bóng loáng trên cung trái
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
  ctx.lineWidth = Math.max(1, r * 0.14);
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.88, Math.PI * 1.08, Math.PI * 1.42);
  ctx.stroke();
 
  ctx.restore();
 
  // Tia lấp lánh nhấp nháy ở góc trên phải
  const twinkle = Math.max(0, Math.sin(backgroundTime * 4 + y * 0.11));
  if (twinkle > 0.05) {
    const s = r * 0.7 * twinkle;
    const sx = x + r * 0.85;
    const sy = cy - r * 0.9;
 
    ctx.save();
    ctx.globalAlpha = twinkle;
    ctx.strokeStyle = '#ffffff';
    ctx.shadowColor = '#fff6b8';
    ctx.shadowBlur = 8;
    ctx.lineWidth = 1.4;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(sx - s, sy);
    ctx.lineTo(sx + s, sy);
    ctx.moveTo(sx, sy - s);
    ctx.lineTo(sx, sy + s);
    ctx.stroke();
    ctx.restore();
  }
}
 
// ---------- Khiên: viền neon, hai mặt phẳng, quầng năng lượng ----------
function shieldPath(R) {
  ctx.beginPath();
  ctx.moveTo(0, -R);
  ctx.bezierCurveTo(R * 0.35, -R * 0.78, R * 0.72, -R * 0.8, R * 0.92, -R * 0.7);
  ctx.bezierCurveTo(R * 1.02, -R * 0.08, R * 0.74, R * 0.62, 0, R * 1.08);
  ctx.bezierCurveTo(-R * 0.74, R * 0.62, -R * 1.02, -R * 0.08, -R * 0.92, -R * 0.7);
  ctx.bezierCurveTo(-R * 0.72, -R * 0.8, -R * 0.35, -R * 0.78, 0, -R);
  ctx.closePath();
}
 
function drawShield(item) {
  if (item.itemCollected) return;
 
  const x = Number(item.itemX);
  const y = Number(item.itemY);
  const r = Number(item.itemRadius ?? 13) * ITEM_VISUAL_SCALE;
 
  if (![x, y, r].every(Number.isFinite) || r <= 0) return;
 
  // Vẽ lớn hơn vùng nhặt một chút để dễ nhìn
  const R = r * 1.25;
  const bob = Math.sin(backgroundTime * 2.6 + x * 0.01) * 2;
  const cy = y + bob;
  const pulse = 0.5 + 0.5 * Math.sin(backgroundTime * 3.2);
 
  ctx.save();
  ctx.translate(x, cy);
 
  // Quầng năng lượng nhịp thở
  const aura = ctx.createRadialGradient(0, 0, R * 0.5, 0, 0, R * (2 + pulse * 0.4));
  aura.addColorStop(0, 'rgba(69, 247, 255, 0.35)');
  aura.addColorStop(1, 'rgba(69, 247, 255, 0)');
  ctx.fillStyle = aura;
  ctx.beginPath();
  ctx.arc(0, 0, R * (2 + pulse * 0.4), 0, Math.PI * 2);
  ctx.fill();
 
  // Vòng mảnh nở ra rồi mờ dần
  ctx.save();
  ctx.globalAlpha = 0.5 * (1 - pulse);
  ctx.strokeStyle = ART.shield.glow;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.arc(0, 0, R * (1.15 + pulse * 0.55), 0, Math.PI * 2);
  ctx.stroke();
  ctx.restore();
 
  // Viền ngoài
  const edge = ctx.createLinearGradient(-R, -R, R, R);
  edge.addColorStop(0, ART.shield.edge[0]);
  edge.addColorStop(0.5, ART.shield.edge[1]);
  edge.addColorStop(1, ART.shield.edge[2]);
 
  ctx.shadowColor = ART.shield.glow;
  ctx.shadowBlur = 16;
  shieldPath(R);
  ctx.fillStyle = edge;
  ctx.fill();
  ctx.shadowBlur = 0;
 
  // Mặt trong tối, thụt vào để viền nổi lên
  ctx.save();
  ctx.scale(0.74, 0.74);
  shieldPath(R);
  const inner = ctx.createLinearGradient(0, -R, 0, R);
  inner.addColorStop(0, ART.shield.inner[0]);
  inner.addColorStop(1, ART.shield.inner[1]);
  ctx.fillStyle = inner;
  ctx.fill();
 
  // Nửa trái sáng hơn để tạo khối
  ctx.clip();
  ctx.fillStyle = 'rgba(120, 220, 255, 0.2)';
  ctx.fillRect(-R, -R * 1.2, R, R * 2.4);
  ctx.restore();
 
  // Lõi năng lượng hình thoi
  const core = R * 0.36;
  ctx.shadowColor = '#ffffff';
  ctx.shadowBlur = 10;
  ctx.fillStyle = '#e8ffff';
  ctx.beginPath();
  ctx.moveTo(0, -core);
  ctx.lineTo(core * 0.72, 0);
  ctx.lineTo(0, core);
  ctx.lineTo(-core * 0.72, 0);
  ctx.closePath();
  ctx.fill();
  ctx.shadowBlur = 0;
 
  // Vệt sáng bóng trên góc trái viền
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.75)';
  ctx.lineWidth = 1.6;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(-R * 0.78, -R * 0.52);
  ctx.quadraticCurveTo(-R * 0.86, -R * 0.1, -R * 0.55, R * 0.3);
  ctx.stroke();
 
  // Tia lửa nhỏ xoay quanh khiên
  const a = backgroundTime * 2.2 + x * 0.02;
  ctx.fillStyle = '#ffffff';
  ctx.shadowColor = ART.shield.glow;
  ctx.shadowBlur = 8;
  ctx.beginPath();
  ctx.arc(Math.cos(a) * R * 1.45, Math.sin(a) * R * 1.45, 1.8, 0, Math.PI * 2);
  ctx.fill();
 
  ctx.restore();
}

// ---------- Gai: bệ kim loại + các mũi nhọn hai mặt phẳng ----------
function drawSpikes(x, isCeiling, width, height) {
  const teeth = Math.max(3, Math.round(width / 16));
  const toothW = width / teeth;
  const left = x - width / 2;
  const baseH = Math.min(9, height * 0.3);
  const pulse = 0.65 + 0.35 * Math.sin(backgroundTime * 4 + x * 0.05);

  ctx.save();

  if (!isCeiling) {
    ctx.translate(0, canvas.height);
    ctx.scale(1, -1);
  }

  // Mũi gai
  for (let i = 0; i < teeth; i++) {
    const x0 = left + i * toothW;
    const tipX = x0 + toothW / 2;
    const x1 = x0 + toothW;

    ctx.fillStyle = ART.spike.steelLight;
    ctx.beginPath();
    ctx.moveTo(x0, baseH - 1);
    ctx.lineTo(tipX, height);
    ctx.lineTo(tipX, baseH - 1);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = ART.spike.steelDark;
    ctx.beginPath();
    ctx.moveTo(tipX, baseH - 1);
    ctx.lineTo(tipX, height);
    ctx.lineTo(x1, baseH - 1);
    ctx.closePath();
    ctx.fill();

    ctx.save();
    ctx.shadowColor = ART.spike.neon;
    ctx.shadowBlur = 8 * pulse;
    ctx.strokeStyle = ART.spike.neon;
    ctx.lineWidth = 1.3;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(x0, baseH - 1);
    ctx.lineTo(tipX, height);
    ctx.lineTo(x1, baseH - 1);
    ctx.stroke();
    ctx.restore();

    ctx.save();
    ctx.globalAlpha = pulse;
    ctx.fillStyle = ART.spike.tip;
    ctx.shadowColor = ART.spike.neon;
    ctx.shadowBlur = 10;
    ctx.beginPath();
    ctx.arc(tipX, height - 1.5, 1.7, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  // Bệ kim loại giữ các mũi gai
  const plate = ctx.createLinearGradient(0, 0, 0, baseH);
  plate.addColorStop(0, ART.spike.plate[0]);
  plate.addColorStop(1, ART.spike.plate[1]);

  ctx.save();
  ctx.shadowColor = ART.spike.neon;
  ctx.shadowBlur = 6;
  roundedRect(left - 3, -2, width + 6, baseH + 2, 3);
  ctx.fillStyle = plate;
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.strokeStyle = ART.spike.neon;
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.restore();

  // Đinh tán ở hai đầu bệ
  ctx.fillStyle = ART.spike.steelLight;
  for (const rx of [left + 2, left + width - 2]) {
    ctx.beginPath();
    ctx.arc(rx, baseH / 2 - 0.5, 1.2, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

const TAU = Math.PI * 2;

// ---------- Chim pixel-art: Classic (chim vàng), Chim đỏ đội vương miện, Chim đen ----------
// Mỗi con được vẽ từ lưới ô vuông rồi cache vào canvas nhỏ, phóng to bằng nearest-neighbor.
const PIXEL_W = 20;
const PIXEL_H = 18;
const PIXEL_BODY = { cx: 8.0, cy: 10.0, rx: 8.0, ry: 6.0 };
const PIXEL_PARTS = {
  eye:      [".KKKK.", "KWWWWK", "KWWPPK", "KWWPPK", "KWWWWK", ".KKKK."],
  eyeHeart: [".KKKK.", "KWWWWK", "KWHWHK", "KWHHHK", "KWWHWK", ".KKKK."],
  beak:     ["KKKKK.", "KRRRRK", "KRRRRK", "KKKKKK", "KOOOOK", ".KKKK."],
  wing:     [".KKKKK.", "KVVVVVK", "KVVVVSK", "KSSSSSK", ".KKKKK."],
  wingStripe: [".KKKKK.", "KVVVVVK", "KQQQQQK", "KVVVVVK", ".KKKKK."],
  crown:    [["C...Y...C", "CC.YYY.CC", "CYYYLYYYC", "CYEYYYEYC", "CCCCCCCCC"], ["C..Y...C.", "CCYYY.CCC", "CYYYLYYYC", "CYEYYYEYC", "CCCCCCCCC"]],
  band:     ["..GGGGGG..", ".GJJJJJJG.", "GG......GG"],
  cup:      ["KKKKK", "KGGGK", "KGJGK", "KGJGK", "KGGGK", "KKKKK"],
  tongue:   ["TT", "TT", "T."]
};
const PIXEL_THEMES = {
  classic: { pal: {"K": "#4a2c3a", "W": "#ffffff", "P": "#1a1020", "a": "#fbe04a", "b": "#f7c82e", "c": "#e8962a", "d": "#fcefae", "R": "#f4511e", "O": "#f78c28", "V": "#ffffff", "S": "#f3dca0"}, wing: 'wing' },
  red:     { pal: {"K": "#3a1414", "W": "#ffffff", "P": "#1a1020", "a": "#e8483a", "b": "#d63a2e", "c": "#9c2418", "d": "#f07a6a", "R": "#ff7a70", "O": "#e8504a", "V": "#fff3d2", "S": "#f2cf9a", "H": "#e8272a", "C": "#f5a623", "Y": "#ffe14a", "L": "#fff6a0", "E": "#e8272a"}, wing: 'wing', heart: true, crown: true },
  black:   { pal: {"K": "#050508", "W": "#ffffff", "P": "#1a1020", "a": "#4a4a5a", "b": "#2b2b36", "c": "#18181f", "d": "#3f3f4d", "R": "#4a4a58", "O": "#32323d", "V": "#e8392e", "S": "#a82118", "Q": "#0f0f14", "G": "#6b6b7a", "J": "#a9a9bb", "T": "#ff8fb0"}, wing: 'wingStripe', phones: true, tongue: true }
};
const pixelBirdCache = {};

function pixelBirdSprite(themeName, wingFrame, extra) {
  const key = themeName + '|' + wingFrame + '|' + extra;
  if (pixelBirdCache[key]) return pixelBirdCache[key];

  const theme = PIXEL_THEMES[themeName];
  const B = PIXEL_BODY;
  const inside = (i, j) =>
    Math.pow((i + 0.5 - B.cx) / B.rx, 2) + Math.pow((j + 0.5 - B.cy) / B.ry, 2) <= 1;
  const g = Array.from({ length: PIXEL_H }, () => Array(PIXEL_W).fill('.'));

  for (let j = 0; j < PIXEL_H; j++) {
    for (let i = 0; i < PIXEL_W; i++) {
      if (!inside(i, j)) continue;
      const edge = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([di, dj]) => !inside(i + di, j + dj));
      if (edge) g[j][i] = 'K';
      else if (j <= 5) g[j][i] = 'a';
      else if (j >= 14) g[j][i] = 'c';
      else if (j >= 12 && i >= 5) g[j][i] = 'd';
      else g[j][i] = 'b';
    }
  }

  const stamp = (grid, x0, y0) => {
    grid.forEach((row, dj) => {
      for (let di = 0; di < row.length; di++) {
        const ch = row[di];
        const x = x0 + di;
        const y = y0 + dj;
        if (ch !== '.' && x >= 0 && x < PIXEL_W && y >= 0 && y < PIXEL_H) g[y][x] = ch;
      }
    });
  };

  stamp(theme.heart ? PIXEL_PARTS.eyeHeart : PIXEL_PARTS.eye, 10, 5);
  stamp(PIXEL_PARTS.beak, 14, 10);
  stamp(PIXEL_PARTS[theme.wing], 2, [9, 10, 11][wingFrame]);
  if (theme.crown) stamp(PIXEL_PARTS.crown[extra], 4, 0);
  if (theme.phones) {
    stamp(PIXEL_PARTS.band, 3, 2);
    stamp(PIXEL_PARTS.cup, 4, 5);
  }
  if (theme.tongue) stamp(PIXEL_PARTS.tongue, 17, 15);

  const cv = document.createElement('canvas');
  cv.width = PIXEL_W;
  cv.height = PIXEL_H;
  const c = cv.getContext('2d');
  for (let j = 0; j < PIXEL_H; j++) {
    for (let i = 0; i < PIXEL_W; i++) {
      const color = theme.pal[g[j][i]];
      if (g[j][i] === '.' || !color) continue;
      c.fillStyle = color;
      c.fillRect(i, j, 1, 1);
    }
  }
  pixelBirdCache[key] = cv;
  return cv;
}

function drawPixelBird(themeName, r, flap) {
  const wingFrame = flap > 0.35 ? 0 : (flap < -0.35 ? 2 : 1);
  const extra = Math.floor(Date.now() / 180) % 2;
  const sprite = pixelBirdSprite(themeName, wingFrame, extra);

  // Giữ nguyên kích thước cũ của chim: thân + mỏ rộng khoảng 3.2 * r.
  const p = (r * 3.2) / PIXEL_W;
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(
    sprite,
    -PIXEL_BODY.cx * p,
    -PIXEL_BODY.cy * p,
    PIXEL_W * p,
    PIXEL_H * p
  );
  ctx.restore();
}

// ---------- Classic: chim vàng Flappy Bird gốc ----------
function drawClassicBird(r, flap) {
  drawPixelBird('classic', r, flap);
}

// ---------- Skin chim đỏ đội vương miện (id 'neon') ----------
function drawNeonBird(r, flap) {
  drawPixelBird('red', r, flap);
}

// ---------- Skin chim đen (id 'cyber') ----------
function drawCyberOwl(r, flap) {
  drawPixelBird('black', r, flap);
}

function drawBird() {
  const b = game?.bird;
  if (!b) return;

  const x = Number(b.birdX ?? 90);
  const y = Number(b.birdY ?? WORLD_H / 2);
  const r = Number(b.birdRadius ?? 14);
  const velocity = Number(b.birdVelocityY ?? 0);

  if (![x, y, r, velocity].every(Number.isFinite) || r <= 0) return;

  const rotation = Math.max(-0.42, Math.min(0.7, velocity / 550));
  const flap = Math.sin(Date.now() / 72);

  const skillOn = Number(b.birdSkillDuration ?? 0) > 0;

  // Nam châm: hào quang tia nắng nhẹ quanh chim khi đang hút xu.
  // Vẽ dịu (alpha thấp, không shadowBlur) để vẫn thấy rõ nhưng không lấn át chim.
  if (skillOn && b.birdSkill === 'CoinMagnet') {
    const t = Date.now();
    const rays = 14;
    const inner = r * 1.15;
    const outer = r * (3.3 + 0.2 * Math.sin(t / 320));
    const halfOut = (Math.PI / rays) * 0.6;   // tia rộng dần ra phía ngoài
    const halfIn = 0.035;

    ctx.save();
    ctx.translate(x, y);

    // quầng ấm rất nhạt phía sau tia
    const glow = ctx.createRadialGradient(0, 0, r * 0.6, 0, 0, r * 2);
    glow.addColorStop(0, 'rgba(255, 224, 110, .16)');
    glow.addColorStop(1, 'rgba(255, 224, 110, 0)');
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(0, 0, r * 2, 0, Math.PI * 2);
    ctx.fill();

    // các tia xoay chậm, mờ dần ra ngoài
    ctx.rotate(t / 4500);
    const g = ctx.createRadialGradient(0, 0, inner, 0, 0, outer);
    g.addColorStop(0, 'rgba(255, 226, 90, .30)');
    g.addColorStop(0.55, 'rgba(255, 226, 90, .13)');
    g.addColorStop(1, 'rgba(255, 226, 90, 0)');
    ctx.fillStyle = g;

    for (let i = 0; i < rays; i++) {
      const a = (i * Math.PI * 2) / rays;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a - halfIn) * inner, Math.sin(a - halfIn) * inner);
      ctx.lineTo(Math.cos(a - halfOut) * outer, Math.sin(a - halfOut) * outer);
      ctx.lineTo(Math.cos(a + halfOut) * outer, Math.sin(a + halfOut) * outer);
      ctx.lineTo(Math.cos(a + halfIn) * inner, Math.sin(a + halfIn) * inner);
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();
  }

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rotation);

  // Tàng hình: chim gần như trong suốt.
  if (skillOn && b.birdSkill === 'Invisibility') {
    ctx.globalAlpha = 0.25;
  }

  if (equippedBird === 'neon') {
    drawNeonBird(r, flap);
  } else if (equippedBird === 'cyber') {
    drawCyberOwl(r, flap);
  } else {
    drawClassicBird(r, flap);
  }

  ctx.restore();
}

function drawCenteredText(text, y, color = '#fff') {
  ctx.save();
  ctx.font = '600 12px "DM Mono", monospace';
  ctx.textAlign = 'center';
  ctx.fillStyle = color;
  ctx.shadowColor = color;
  ctx.shadowBlur = 12;
  ctx.fillText(text, canvas.width / 2, y);
  ctx.restore();
}

function drawParticles() {
  for (const p of particles) {
    const x = Number(p.x);
    const y = Number(p.y);
    const life = Number(p.life);
    const maxLife = Number(p.maxLife);
    const size = Number(p.size);

    // Guard against invalid or negative Canvas arc radius.
    if (![x, y, life, maxLife, size].every(Number.isFinite)) {
      continue;
    }

    if (life <= 0 || maxLife <= 0 || size <= 0) {
      continue;
    }

    const alpha = Math.max(0, Math.min(1, life / maxLife));
    const radius = size * alpha;

    if (!Number.isFinite(radius) || radius <= 0) {
      continue;
    }

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = p.color || '#45f7ff';
    ctx.shadowColor = p.color || '#45f7ff';
    ctx.shadowBlur = 10;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}

function burstParticles(x, y, color = '#45f7ff', count = 12) {
  for (let i = 0; i < count; i++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = 25 + Math.random() * 115;

    particles.push({
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      size: 1.5 + Math.random() * 3.5,
      color: i % 3 === 0 ? '#ff48d7' : color,
      life: 0.35 + Math.random() * 0.4,
      maxLife: 0.75
    });
  }
}

function updateParticles(dt) {
  for (const p of particles) {
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vy += 40 * dt;
    p.life -= dt;
  }

  particles = particles.filter(
    p => Number.isFinite(p.life) && p.life > 0
  );
}

// Vẽ Boss theo gameBoss do Haskell trả về.
// Frontend chỉ hiển thị; vị trí và thời gian vẫn do backend quyết định.
function drawBoss(boss) {
  if (!boss || boss.bossActive === false) return;

  const x = Number(boss.bossX);
  const y = Number(boss.bossY);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return;

  const round = Math.max(1, Number(boss.bossRound) || 1);
  const timeLeft = Math.max(0, Number(boss.bossTimeLeft) || 0);
  const totalTime = Math.max(0.1, Number(boss.bossTotalTime) || 5);
  const progress = Math.max(0, Math.min(1, timeLeft / totalTime));
  const pulse = 1 + Math.sin(backgroundTime * 7) * 0.045;

  ctx.save();
  ctx.translate(x, y);
  ctx.scale(pulse, pulse);

  // Bóng hào quang
  const aura = ctx.createRadialGradient(0, 0, 8, 0, 0, 72);
  aura.addColorStop(0, 'rgba(255,45,105,.32)');
  aura.addColorStop(1, 'rgba(255,45,105,0)');
  ctx.fillStyle = aura;
  ctx.beginPath();
  ctx.arc(0, 0, 72, 0, Math.PI * 2);
  ctx.fill();

  // Sừng
  ctx.shadowColor = '#ff315f';
  ctx.shadowBlur = 18;
  ctx.fillStyle = '#ff315f';
  ctx.beginPath();
  ctx.moveTo(-27, -23); ctx.lineTo(-43, -47); ctx.lineTo(-10, -34);
  ctx.closePath(); ctx.fill();
  ctx.beginPath();
  ctx.moveTo(27, -23); ctx.lineTo(43, -47); ctx.lineTo(10, -34);
  ctx.closePath(); ctx.fill();

  // Giáp đầu
  const armor = ctx.createLinearGradient(-36, -35, 36, 36);
  armor.addColorStop(0, '#ff789a');
  armor.addColorStop(0.48, '#9d174d');
  armor.addColorStop(1, '#3b124e');
  ctx.fillStyle = armor;
  ctx.strokeStyle = '#ff8aa8';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(0, -39);
  ctx.lineTo(31, -24);
  ctx.lineTo(36, 7);
  ctx.lineTo(18, 32);
  ctx.lineTo(0, 40);
  ctx.lineTo(-18, 32);
  ctx.lineTo(-36, 7);
  ctx.lineTo(-31, -24);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Mặt nạ
  ctx.shadowBlur = 0;
  ctx.fillStyle = '#210d35';
  ctx.beginPath();
  ctx.moveTo(-23, -13); ctx.lineTo(-8, -4); ctx.lineTo(-20, 1);
  ctx.closePath(); ctx.fill();
  ctx.beginPath();
  ctx.moveTo(23, -13); ctx.lineTo(8, -4); ctx.lineTo(20, 1);
  ctx.closePath(); ctx.fill();

  // Mắt phát sáng
  ctx.fillStyle = '#fff4a8';
  ctx.shadowColor = '#ffef69';
  ctx.shadowBlur = 12;
  ctx.beginPath(); ctx.ellipse(-16, -9, 6, 3.5, -0.2, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.ellipse(16, -9, 6, 3.5, 0.2, 0, Math.PI * 2); ctx.fill();

  // Miệng / lõi năng lượng
  ctx.shadowBlur = 0;
  ctx.fillStyle = '#ff315f';
  ctx.beginPath();
  ctx.moveTo(-11, 15); ctx.lineTo(0, 22); ctx.lineTo(11, 15);
  ctx.lineTo(0, 30); ctx.closePath(); ctx.fill();

  // Nhãn boss phía trên đầu
  ctx.restore();
  ctx.save();
  ctx.textAlign = 'center';
  ctx.font = '700 12px "DM Mono", monospace';
  ctx.fillStyle = '#fff';
  ctx.shadowColor = '#ff315f';
  ctx.shadowBlur = 12;
  ctx.fillText(`BOSS  //  ROUND ${round}`, x, Math.max(24, y - 58));
  ctx.shadowBlur = 0;

  // Thanh thời gian sống sót; boss dùng bộ đếm thời gian, không phải HP bị bắn.
  const barW = 100;
  const barX = x - barW / 2;
  const barY = Math.max(30, y - 48);
  ctx.fillStyle = 'rgba(18,8,35,.9)';
  roundedRect(barX, barY, barW, 6, 3);
  ctx.fill();
  ctx.fillStyle = progress > 0.35 ? '#ff477e' : '#ffb84d';
  roundedRect(barX, barY, barW * progress, 6, 3);
  ctx.fill();
  ctx.font = '9px "DM Mono", monospace';
  ctx.fillStyle = '#ffd5e1';
  ctx.fillText(`${timeLeft.toFixed(1)}s`, x, barY + 18);
  ctx.restore();
}

function drawBossWarning() {
  const boss = game?.boss;
  if (!boss || boss.bossActive === false) return;
  ctx.save();
  ctx.fillStyle = 'rgba(52, 5, 31, .78)';
  roundedRect(12, 12, 170, 31, 7);
  ctx.fill();
  ctx.strokeStyle = 'rgba(255, 72, 125, .8)';
  ctx.lineWidth = 1;
  roundedRect(12, 12, 170, 31, 7);
  ctx.stroke();
  ctx.textAlign = 'left';
  ctx.font = '700 10px "DM Mono", monospace';
  ctx.fillStyle = '#ff8ba8';
  ctx.shadowColor = '#ff315f';
  ctx.shadowBlur = 9;
  ctx.fillText(`⚠ BOSS ROUND ${Math.max(1, Number(boss.bossRound) || 1)}`, 22, 31);
  ctx.restore();
}

// ---------- HUD từ Decision & Warning Engine (Haskell) ----------
const SKILL_LABELS = {
  Invisibility: 'TÀNG HÌNH',
  CoinMagnet: 'NAM CHÂM'
};

function drawDangerWarning(dec) {
  if (!dec?.decWarningRed) return;

  const pulse = 0.35 + 0.25 * Math.sin(Date.now() / 90);

  ctx.save();
  const g = ctx.createRadialGradient(
    canvas.width / 2, canvas.height / 2, canvas.height * 0.35,
    canvas.width / 2, canvas.height / 2, canvas.height * 0.85
  );
  g.addColorStop(0, 'rgba(255,0,40,0)');
  g.addColorStop(1, `rgba(255,0,40,${pulse})`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  ctx.textAlign = 'center';
  ctx.font = '700 22px "Space Grotesk", sans-serif';
  ctx.fillStyle = '#ff5468';
  ctx.shadowColor = '#ff0028';
  ctx.shadowBlur = 14;
  ctx.fillText(
    dec.decSuggestSkill ? '⚠ NGUY HIỂM — NHẤN E DÙNG SKILL' : '⚠ NGUY HIỂM',
    canvas.width / 2,
    canvas.height - 24
  );
  ctx.restore();
}

function drawRageBar() {
  const bird = game?.bird;
  const dec = game?.gameDecision;
  // Chim thường không có skill => không có thanh nộ.
  if (!bird || !dec || !bird.birdSkill || bird.birdSkill === 'NoSkill') return;

  // ----- Cơ chế giữ nguyên: chỉ đọc lại cùng các giá trị như trước -----
  const rage = Math.max(0, Math.min(100, Number(dec.decRage ?? 0)));
  const ready = Boolean(dec.decSkillReady);
  const active = Boolean(dec.decSkillActive);
  const pulse = ready ? 0.75 + 0.25 * Math.sin(Date.now() / 120) : 1;

  // ----- Bố cục (vẫn ở góc trên-trái như cũ) -----
  const x = 20, y = 20;
  const cx = x + 27, cy = y + 27, R = 26;          // huy hiệu tròn
  const bx = x + 32, by = y + 10, bw = 214, bh = 24; // thanh nộ
  const ix = bx + 3, iy = by + 3, iw = bw - 6, ih = bh - 6; // lòng thanh

  ctx.save();

  // ----- Bảng đếm giây (chỉ hiện khi skill đang chạy) -----
  if (active) {
    const text = `ĐANG DÙNG ${Number(dec.decSkillTimeLeft ?? 0).toFixed(1)}s`;
    ctx.font = '700 13px "Space Grotesk", sans-serif';
    const tw = ctx.measureText(text).width;
    const px = x + 40, py = by + bh + 1, ph = 21, pw = tw + 42;

    ctx.beginPath();
    ctx.moveTo(px, py);
    ctx.lineTo(px + pw, py);
    ctx.lineTo(px + pw - 13, py + ph);
    ctx.lineTo(px, py + ph);
    ctx.closePath();
    ctx.fillStyle = 'rgba(22, 20, 44, .88)';
    ctx.fill();
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = 'rgba(255, 255, 255, .18)';
    ctx.stroke();

    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#ffd640';
    ctx.fillText(text, x + 62, py + ph / 2 + 1);
    ctx.textBaseline = 'alphabetic';
  }

  // ----- Khung thanh: viền đen → viền tím → lòng thanh -----
  roundedRect(bx - 3, by - 3, bw + 6, bh + 6, (bh + 6) / 2);
  ctx.fillStyle = '#120a24';
  ctx.fill();

  const frame = ctx.createLinearGradient(0, by, 0, by + bh);
  frame.addColorStop(0, '#b27ae8');
  frame.addColorStop(1, '#6b36b2');
  roundedRect(bx - 1, by - 1, bw + 2, bh + 2, (bh + 2) / 2);
  ctx.fillStyle = frame;
  ctx.fill();

  // Lòng thanh (phần chưa đầy: vàng olive như hình mẫu)
  roundedRect(ix, iy, iw, ih, ih / 2);
  const track = ctx.createLinearGradient(0, iy, 0, iy + ih);
  track.addColorStop(0, '#c9c940');
  track.addColorStop(1, '#8c8c26');
  ctx.fillStyle = track;
  ctx.fill();

  ctx.save();
  roundedRect(ix, iy, iw, ih, ih / 2);
  ctx.clip();

  // Phần nộ đã đầy: xanh lá (đầy thì chuyển xanh ngọc + nhấp nháy như cũ)
  const fw = iw * rage / 100;
  if (fw > 0) {
    const fill = ctx.createLinearGradient(0, iy, 0, iy + ih);
    if (ready) {
      fill.addColorStop(0, '#9ff8ff');
      fill.addColorStop(0.5, '#45d8f0');
      fill.addColorStop(1, '#1f9fcb');
    } else {
      fill.addColorStop(0, '#86e656');
      fill.addColorStop(0.5, '#47b32f');
      fill.addColorStop(1, '#2a8421');
    }
    ctx.globalAlpha = pulse;
    ctx.fillStyle = fill;
    ctx.fillRect(ix, iy, fw, ih);
    ctx.globalAlpha = 1;

    // vạch tối ở đầu phần đầy
    if (rage < 100) {
      ctx.fillStyle = 'rgba(8, 24, 10, .55)';
      ctx.fillRect(ix + fw - 1.5, iy, 1.5, ih);
    }
  }

  // vạch chia 5 cột (mỗi cột = 20 nộ)
  ctx.fillStyle = 'rgba(10, 8, 30, .35)';
  for (let i = 1; i < 5; i++) ctx.fillRect(ix + (iw * i) / 5 - 0.75, iy, 1.5, ih);

  // bóng sáng phía trên + bóng đổ trong
  const gloss = ctx.createLinearGradient(0, iy, 0, iy + ih);
  gloss.addColorStop(0, 'rgba(255,255,255,.42)');
  gloss.addColorStop(0.45, 'rgba(255,255,255,.08)');
  gloss.addColorStop(1, 'rgba(0,0,0,.18)');
  ctx.fillStyle = gloss;
  ctx.fillRect(ix, iy, iw, ih);
  ctx.restore();

  // ----- Huy hiệu tròn bên trái -----
  if (ready) {
    ctx.shadowColor = '#45f7ff';
    ctx.shadowBlur = 10 + 6 * Math.sin(Date.now() / 120);
  }
  ctx.beginPath();
  ctx.arc(cx, cy, R + 3, 0, Math.PI * 2);
  ctx.fillStyle = '#120a24';
  ctx.fill();
  ctx.shadowBlur = 0;

  const ring = ctx.createLinearGradient(0, cy - R, 0, cy + R);
  ring.addColorStop(0, '#b784ee');
  ring.addColorStop(1, '#6a35b0');
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.fillStyle = ring;
  ctx.fill();

  const core = ctx.createRadialGradient(cx - 6, cy - 8, 2, cx, cy, R - 4);
  core.addColorStop(0, '#3f6fd0');
  core.addColorStop(1, '#0c1233');
  ctx.beginPath();
  ctx.arc(cx, cy, R - 5, 0, Math.PI * 2);
  ctx.fillStyle = core;
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = '#120a24';
  ctx.stroke();

  // Biểu tượng skill
  ctx.lineJoin = 'round';
  if (bird.birdSkill === 'CoinMagnet') {
    // nam châm hình móng ngựa
    const stroke = (w, color, fn) => {
      ctx.lineWidth = w;
      ctx.strokeStyle = color;
      ctx.lineCap = 'butt';
      fn();
    };
    const horseshoe = () => {
      ctx.beginPath();
      ctx.arc(cx, cy - 1, 9, Math.PI, 0, false);
      ctx.moveTo(cx - 9, cy - 1); ctx.lineTo(cx - 9, cy + 8);
      ctx.moveTo(cx + 9, cy - 1); ctx.lineTo(cx + 9, cy + 8);
      ctx.stroke();
    };
    stroke(9, '#120a24', horseshoe);
    stroke(6, '#ff4d5e', horseshoe);
    stroke(6, '#e6ecff', () => {
      ctx.beginPath();
      ctx.moveTo(cx - 9, cy + 5); ctx.lineTo(cx - 9, cy + 10);
      ctx.moveTo(cx + 9, cy + 5); ctx.lineTo(cx + 9, cy + 10);
      ctx.stroke();
    });
  } else if (bird.birdSkill === 'Invisibility') {
    // con mắt
    ctx.beginPath();
    ctx.moveTo(cx - 14, cy);
    ctx.quadraticCurveTo(cx, cy - 14, cx + 14, cy);
    ctx.quadraticCurveTo(cx, cy + 14, cx - 14, cy);
    ctx.closePath();
    ctx.fillStyle = '#f4f8ff';
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#120a24';
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx, cy, 5.5, 0, Math.PI * 2);
    ctx.fillStyle = '#4fc8ff';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(cx, cy, 2.6, 0, Math.PI * 2);
    ctx.fillStyle = '#0c1233';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(cx - 1.8, cy - 1.8, 1.1, 0, Math.PI * 2);
    ctx.fillStyle = '#fff';
    ctx.fill();
  } else {
    // skill khác: tia chớp
    ctx.beginPath();
    ctx.moveTo(cx + 2, cy - 12);
    ctx.lineTo(cx - 8, cy + 2);
    ctx.lineTo(cx - 1, cy + 2);
    ctx.lineTo(cx - 3, cy + 12);
    ctx.lineTo(cx + 8, cy - 3);
    ctx.lineTo(cx + 1, cy - 3);
    ctx.closePath();
    ctx.fillStyle = '#ffd640';
    ctx.fill();
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = '#120a24';
    ctx.stroke();
  }

  // vệt sáng trên huy hiệu
  ctx.beginPath();
  ctx.arc(cx, cy, R - 7, Math.PI * 1.08, Math.PI * 1.62);
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';
  ctx.strokeStyle = 'rgba(255,255,255,.35)';
  ctx.stroke();

  ctx.restore();
}

function drawImmortalBadge() {
  if (!game?.gameImmortal) return;

  ctx.save();
  ctx.textAlign = 'right';
  ctx.font = '700 14px "Space Grotesk", sans-serif';
  ctx.fillStyle = '#ffd640';
  ctx.shadowColor = '#ffd640';
  ctx.shadowBlur = 10;
  ctx.fillText('CHẾ ĐỘ BẤT TỬ (TEST)', canvas.width - 20, 30);
  ctx.restore();
}

function drawScene() {
  drawBackground();
  frame?.classList.toggle('boss-mode', Boolean(game?.boss?.bossActive));

  // Assumes the Haskell API returns the pipes array as game.pipes.
  if (game && Array.isArray(game.pipes)) {
    game.pipes.forEach((pipe, index) => {
      drawPipe(pipe, index);
    });
  }


  // Boss và đạn lửa do Haskell mô phỏng.
  if (game?.boss?.bossActive) {
    drawBoss(game.boss);
    drawBossWarning();
  }

  // Vẽ bẫy từ trạng thái Haskell (bao gồm Fireball của boss).
  if (Array.isArray(game?.traps)) {
    game.traps.forEach(drawTrap);
  }

  // Vẽ các đồng xu từ trạng thái Haskell
  if (Array.isArray(game?.coins)) {
    game.coins.forEach(drawCoin);
  }


  // Vẽ vật phẩm từ trạng thái Haskell
  if (Array.isArray(game?.items)) {
    game.items.forEach(item => {
      switch (item.itemKind) {
        case "Shield":
          drawShield(item);
          break;

        case "WindCurse":
          drawWindCurse(item);
          break;

        default:
          break;
      }
    });
  }

  drawBirdTrail();
  drawBird();
  drawParticles();
  if (game?.status === 'Playing') {
    drawDangerWarning(game.gameDecision);
    drawRageBar();
    drawImmortalBadge();
    ctx.save();
    ctx.textAlign = 'center';
    ctx.font = '700 36px "Space Grotesk", sans-serif';
    ctx.lineWidth = 4;
    ctx.strokeStyle = 'rgba(7,9,28,.65)';
    ctx.strokeText(String(game.score ?? 0), canvas.width / 2, 53);
    ctx.fillStyle = '#fff';
    ctx.shadowColor = '#45f7ff';
    ctx.shadowBlur = 12;
    ctx.fillText(String(game.score ?? 0), canvas.width / 2, 53);
    ctx.restore();
  }
}

function playTone(frequency, duration) {
  if (!soundEnabled) return;

  try {
    audioContext ||= new (
      window.AudioContext || window.webkitAudioContext
    )();

    if (audioContext.state === 'suspended') {
      audioContext.resume();
    }

    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();

    oscillator.frequency.value = frequency;
    oscillator.type = 'sine';

    gain.gain.setValueAtTime(0.04, audioContext.currentTime);
    gain.gain.exponentialRampToValueAtTime(
      0.001,
      audioContext.currentTime + duration
    );

    oscillator.connect(gain);
    gain.connect(audioContext.destination);

    oscillator.start();
    oscillator.stop(audioContext.currentTime + duration);
  } catch (error) {
    console.debug('Audio không khả dụng:', error);
  }
}

function showClickEffect(event) {
  const rect = frame.getBoundingClientRect();
  const ripple = document.createElement('span');

  ripple.className = 'click-ripple';
  ripple.style.left = `${event.clientX - rect.left}px`;
  ripple.style.top = `${event.clientY - rect.top}px`;

  frame.appendChild(ripple);
  ripple.addEventListener('animationend', () => ripple.remove(), {
    once: true
  });
}

function animationLoop(timestamp) {
  if (!lastFrameTime) {
    lastFrameTime = timestamp;
  }

  const elapsed = Math.min((timestamp - lastFrameTime) / 1000, 0.05);
  lastFrameTime = timestamp;
  backgroundTime += elapsed;

  updateParticles(elapsed);
  updateBirdTrail(elapsed);

  if (game?.status === 'Playing' && !busy) {
    accumulator += elapsed;

    if (accumulator >= STEP_SECONDS) {
      accumulator %= STEP_SECONDS;
      // Only one API request is allowed at a time.
      sendInput('NoInput');
    }
  } else {
    accumulator = 0;
  }

  drawScene();
  requestAnimationFrame(animationLoop);
}

playButton.addEventListener('click', () => {
  burstParticles(
    canvas.width / 2,
    canvas.height / 2,
    '#45f7ff',
    18
  );

  playTone(620, 0.07);
  startOrRestart();
});

restartButton.addEventListener('click', () => {
  burstParticles(
    canvas.width / 2,
    canvas.height * 0.7,
    '#ff48d7',
    12
  );

  restartGame();
});

soundButton.addEventListener('click', () => {
  soundEnabled = !soundEnabled;
  soundButton.classList.toggle('active', soundEnabled);
  soundButton.textContent = soundEnabled ? '♫' : '♪';

  messageText.textContent = soundEnabled
    ? 'Âm thanh neon đã bật.'
    : 'Âm thanh đã tắt.';

  playTone(660, 0.08);
});

canvas.addEventListener('pointerdown', event => {
  event.preventDefault();
  showClickEffect(event);

  const rect = canvas.getBoundingClientRect();
  const x = (event.clientX - rect.left) * canvas.width / rect.width;
  const y = (event.clientY - rect.top) * canvas.height / rect.height;

  burstParticles(x, y, '#45f7ff', 10);
  playTone(480, 0.045);
  flap();
});

document.addEventListener('keydown', event => {
  if (event.code === 'Space' || event.code === 'ArrowUp') {
    event.preventDefault();

    if (!event.repeat) {
      flap();
    }
  } else if (event.code === 'KeyE' || event.code === 'ShiftLeft') {
    event.preventDefault();

    if (!event.repeat) {
      useSkill();
    }
  } else if (
    event.code === 'Escape' &&
    game?.status === 'Playing'
  ) {
    sendInput('Pause');
    showPauseOverlay();
  }
});

checkApi();
requestAnimationFrame(animationLoop);


/* =========================
   CYBER FLAPPY SHOP
========================= */

// Lấy các phần tử Shop từ HTML
const shopOpenButton = document.getElementById("shopOpenButton");
const shopCloseButton = document.getElementById("shopCloseButton");
const shopModal = document.getElementById("shopModal");

// Mở cửa sổ Shop
shopOpenButton.addEventListener("click", () => {
  shopModal.classList.remove("hidden");
});

// Đóng cửa sổ Shop bằng nút X
shopCloseButton.addEventListener("click", () => {
  shopModal.classList.add("hidden");
});

// Đóng Shop khi nhấn phím Escape
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    shopModal.classList.add("hidden");
  }
});

// Đóng Shop khi click ra ngoài khung Shop
shopModal.addEventListener("click", (event) => {
  if (event.target === shopModal) {
    shopModal.classList.add("hidden");
  }
});

/*CYBER FLAPPY - SHOP ITEMS */

const shopGrid = document.getElementById("shopGrid");
const shopCoinsDisplay = document.getElementById("shopCoins");
const shopMessage = document.getElementById("shopMessage");

const shopItems = [
  { id: "classic", name: "Classic Bird", category: "bird", image: "picture/1_classic_bird.png", price: 0, description: "Chú chim vàng cổ điển." },
  { id: "neon", name: "Neon Bird", category: "bird", image: "picture/2_neon_bird.png", price: 150, description: "Skin chim phong cách neon." },
  { id: "cyber", name: "Cyber Owl", category: "bird", image: "picture/3_cyber_owl.png", price: 250, description: "Chú cú công nghệ tương lai." },
  {
    id: "bg_sky",
    name: "Bầu Trời Kẹo",
    category: "background",
    image: SKY_THUMB,
    price: 0,
    description: "Map mặc định: mây trôi theo chim."
  },
  {
    id: "bg_cyber",
    name: "Chiến binh DC",
    category: "background",
    image: "picture/chienbinh.jpg",
    price: 0,
    description: "Chỉ có gái mới đánh bại được ta."
  },
  {
    id: "bg_sunset",
    name: "Sối cô độc",
    category: "background",
    image: "picture/soicodoc.jpg",
    price: 180,
    description: "Ready for building a kingdom."
  },
  {
    id: "bg_arctic",
    name: "Cyber Punk",
    category: "background",
    image: "picture/vua.jpg",
    price: 220,
    description: "Thế giới băng xanh."
  }
];
/* SHOP PROFILE - LƯU DỮ LIỆU*/

const SHOP_STORAGE_KEY = "cyberFlappyShopProfile";

function loadShopProfile() {
  try {
    const saved = localStorage.getItem(SHOP_STORAGE_KEY);

    if (saved) {
      const profile = JSON.parse(saved);

      return {
        coins: Math.max(0, Number(profile.coins) || 0),
        owned: Array.isArray(profile.owned)
          ? profile.owned
          : ["classic", "bg_sky"],
        bird: profile.bird || "classic",
        effect: profile.effect || null,
        background: profile.background || "bg_sky"
      };
    }
  } catch (error) {
    console.error("Không đọc được dữ liệu Shop:", error);
  }

  // Chỉ cấp số xu khởi đầu ở lần đầu tạo hồ sơ.
  const initialProfile = {
    coins: 500,
    owned: ["classic", "bg_sky"],
    bird: "classic",
    effect: null,
    background: "bg_sky"
  };

  try {
    localStorage.setItem(
      SHOP_STORAGE_KEY,
      JSON.stringify(initialProfile)
    );
  } catch (error) {
    console.error("Không lưu được hồ sơ Shop:", error);
  }

  return initialProfile;
}

const savedShopProfile = loadShopProfile();

let shopCoins = savedShopProfile.coins;
const ownedShopItems = new Set(savedShopProfile.owned);
// Map mặc định luôn thuộc sở hữu, có thể trang bị lại bất cứ lúc nào (giống chim Classic).
ownedShopItems.add("bg_sky");

let equippedBird = savedShopProfile.bird;
// Đã bỏ các hiệu ứng vệt bay (Fire / Lightning / Star) khỏi Shop.
let equippedEffect = null;
let equippedBackground = savedShopProfile.background;

// Lưu ví, vật phẩm sở hữu và các trang bị hiện tại.
function saveShopProfile() {
  try {
    localStorage.setItem(
      SHOP_STORAGE_KEY,
      JSON.stringify({
        coins: shopCoins,
        owned: [...ownedShopItems],
        bird: equippedBird,
        effect: equippedEffect,
        background: equippedBackground
      })
    );
  } catch (error) {
    console.error("Không lưu được hồ sơ Shop:", error);
    if (shopMessage) {
      shopMessage.textContent =
        "Không thể lưu dữ liệu. Hãy kiểm tra cài đặt trình duyệt.";
    }
  }
}

// Cộng xu từ lượt chơi vào ví tích lũy.
function addWalletCoins(amount) {
  const coins = Math.floor(Number(amount));

  if (!Number.isFinite(coins) || coins <= 0) return;

  shopCoins += coins;
  saveShopProfile();
  renderShopItems();

  if (shopMessage) {
    shopMessage.textContent =
      `Bạn nhận được ${coins} xu! Ví hiện có ${shopCoins} xu.`;
  }
}


let selectedShopCategory = "all";
let selectedShopItem = null;

function renderShopItems() {
  if (!shopGrid) return;

  const items = shopItems.filter(item =>
    selectedShopCategory === "all" ||
    item.category === selectedShopCategory
  );

  shopGrid.innerHTML = items.map(item => {
    const owned = ownedShopItems.has(item.id);

    return `
      <article class="shop-item-card ${selectedShopItem?.id === item.id ? "selected" : ""}"
               data-item-id="${item.id}">
        <button class="shop-item-select" type="button"
                data-select-item="${item.id}"
                aria-label="Xem ${item.name}">
          <div class="shop-item-image"> <img src="${item.image}" alt="${item.name}"> </div>
          <h3>${item.name}</h3>
          <p class="shop-item-description">${item.description}</p>
          <div class="shop-item-price">🪙 ${item.price}</div>
        </button>
        <button class="shop-buy-button" type="button"
                data-buy-item="${item.id}">
          ${!owned ? "MUA" : item.category === "bird" ? (equippedBird === item.id ? "ĐÃ TRANG BỊ" : "TRANG BỊ") : item.category === "effect" ? (equippedEffect === item.id ? "ĐÃ TRANG BỊ" : "TRANG BỊ") : (equippedBackground === item.id ? "ĐÃ TRANG BỊ" : "TRANG BỊ")}
        </button>
      </article>
    `;
  }).join("");

  if (shopCoinsDisplay) shopCoinsDisplay.textContent = shopCoins;
}

if (shopGrid) {
  shopGrid.addEventListener("click", event => {
    const selectButton = event.target.closest("[data-select-item]");
    const buyButton = event.target.closest("[data-buy-item]");

    if (selectButton) {
      selectedShopItem = shopItems.find(
        item => item.id === selectButton.dataset.selectItem
      );

      if (shopMessage && selectedShopItem) {
        shopMessage.textContent =
          `${selectedShopItem.name} — ${selectedShopItem.description} Giá: ${selectedShopItem.price} xu.`;
      }

      renderShopItems();
      return;
    }

    
    if (buyButton) {
      const item = shopItems.find(
        item => item.id === buyButton.dataset.buyItem
      );

      if (!item) return;

      // Nếu đã mua thì cho phép trang bị ngay
      if (ownedShopItems.has(item.id)) {
        if (item.category === "bird") {
          equippedBird = item.id;
          shopMessage.textContent = `Đã trang bị ${item.name}!`;
        } else if (item.category === "effect") {
          equippedEffect =
            equippedEffect === item.id ? null : item.id;

          shopMessage.textContent = equippedEffect
            ? `Đã trang bị hiệu ứng ${item.name}!`
            : "Đã tháo hiệu ứng.";
        } else if (item.category === "background") {
              equippedBackground = item.id;
              shopMessage.textContent = `Đã trang bị background ${item.name}!`;
            }

        saveShopProfile();
        renderShopItems();
        drawScene();
        return;
      }

      // Chưa sở hữu thì kiểm tra xu để mua
      if (shopCoins < item.price) {
        shopMessage.textContent = "Không đủ xu để mua vật phẩm này!";
        return;
      }

      shopCoins -= item.price;
      ownedShopItems.add(item.id);

      // Mua xong tự động trang bị
      if (item.category === "bird") {
        equippedBird = item.id;
      } else if (item.category === "effect") {
        equippedEffect = item.id;
      } else if (item.category == "background"){
        shopMessage.textContent = `Đã mua ${item.name}! Nhấn TRANG BỊ để sử dụng.`;
      } else {
            shopMessage.textContent = `Đã mua ${item.name} thành công!`;
      }
      saveShopProfile();
      renderShopItems();
      drawScene();
    }

  });

  // Không còn vật phẩm hiệu ứng nên bỏ luôn tab HIỆU ỨNG.
  document.querySelector('.shop-tab[data-category="effect"]')?.remove();

  document.querySelectorAll(".shop-tab[data-category]").forEach(tab => {
    tab.addEventListener("click", () => {
      selectedShopCategory = tab.dataset.category;

      document.querySelectorAll(".shop-tab").forEach(button => {
        button.classList.toggle("active", button === tab);
      });

      renderShopItems();
    });
  });

  renderShopItems();
}
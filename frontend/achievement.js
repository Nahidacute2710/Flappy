
(() => {
  "use strict";

  const API_BASE = "http://localhost:3000/api";

  const modal = document.getElementById("achievementModal");
  const openButton = document.getElementById("achievementOpenButton");
  const closeButton = document.getElementById("achievementCloseButton");
  const detail = document.getElementById("achievementDetail");
  const cards = [...document.querySelectorAll(".achievement-card")];
  const count = document.getElementById("achievementUnlockedCount");
  const progressBar = document.getElementById("achievementOverallBar");

  if (!modal || !openButton || !closeButton) {
    console.warn("Achievement: Không tìm thấy các phần tử HTML cần thiết.");
    return;
  }

  let previousFocus = null;
  let stats = {
    totalGames: 0,
    bestScore: 0,
    totalScore: 0
  };

  let loadError = false;

  function openModal() {
    previousFocus = document.activeElement;
    modal.classList.add("is-open");
    modal.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    closeButton.focus();
    loadAchievements();
  }

  function closeModal() {
    modal.classList.remove("is-open");
    modal.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";

    if (previousFocus && previousFocus.focus) {
      previousFocus.focus();
    }
  }

  openButton.addEventListener("click", openModal);
  closeButton.addEventListener("click", closeModal);

  modal.addEventListener("click", (event) => {
    if (event.target === modal) closeModal();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && modal.classList.contains("is-open")) {
      closeModal();
    }
  });

  // Xác định tiến độ và điều kiện của từng thành tựu.
  function getProgress(card) {
    const name = (
      card.dataset.name ||
      card.querySelector("h4")?.textContent ||
      ""
    ).trim().toLowerCase();

    const target = Number(card.dataset.target) || 1;
    const unit = (card.dataset.unit || "").toLowerCase();
    const requirement = (
      card.dataset.requirement || ""
    ).toLowerCase();

    // Thành tựu cần cả điểm số và số trận.
    if (name === "bá vương") {
      const gamesProgress = Math.min(stats.totalGames, target);
      const unlocked = stats.bestScore >= 10 && stats.totalGames >= 10;

      return {
        progress: gamesProgress,
        target,
        unit: "trận",
        unlocked,
        description: "Đạt ít nhất 10 điểm và hoàn thành 10 trận."
      };
    }

    // Thành tựu dựa vào điểm cao nhất của một trận.
    if (
      unit.includes("điểm") ||
      requirement.includes("điểm trong một trận")
    ) {
      return {
        progress: Math.min(stats.bestScore, target),
        target,
        unit: card.dataset.unit || "điểm",
        unlocked: stats.bestScore >= target,
        description: card.dataset.requirement || ""
      };
    }

    // Thành tựu dựa vào tổng số trận.
    if (
      unit.includes("trận") ||
      requirement.includes("hoàn thành") && requirement.includes("trận")
    ) {
      return {
        progress: Math.min(stats.totalGames, target),
        target,
        unit: card.dataset.unit || "trận",
        unlocked: stats.totalGames >= target,
        description: card.dataset.requirement || ""
      };
    }

    // Các điều kiện chưa được backend cung cấp.
    if (
      unit.includes("chướng ngại vật") ||
      name === "đặc thù" ||
      unit.includes("skin")
    ) {
      return {
        progress: 0,
        target,
        unit: card.dataset.unit || "",
        unlocked: false,
        description: card.dataset.requirement || ""
      };
    }

    return {
      progress: 0,
      target,
      unit: card.dataset.unit || "",
      unlocked: false,
      description: card.dataset.requirement || ""
    };
  }

  function renderAchievements() {
    let unlockedCount = 0;

    cards.forEach((card) => {
      const result = getProgress(card);
      const percent = result.target > 0
        ? Math.min(100, Math.round(result.progress / result.target * 100))
        : 0;

      if (result.unlocked) unlockedCount++;

      // Cập nhật trạng thái thẻ theo class CSS hiện có.
      card.classList.toggle("locked", !result.unlocked);
      card.classList.toggle("unlocked", result.unlocked);

      // HTML hiện tại dùng .achievement-state.
      const state = card.querySelector(".achievement-state");

      if (state) {
        state.textContent = result.unlocked
          ? "✓ ĐÃ MỞ KHÓA"
          : "🔒 CHƯA MỞ KHÓA";
      }

      // Cập nhật số tiến độ và phần trăm.
      const progressInfo = card.querySelector(".achievement-card-progress");

      if (progressInfo) {
        const progressText = progressInfo.querySelector("span");
        const percentText = progressInfo.querySelector("strong");

        if (progressText) {
          progressText.textContent =
            `${result.progress} / ${result.target} ${result.unit}`;
        }

        if (percentText) {
          percentText.textContent = `${percent}%`;
        }
      }

      // Cập nhật thanh tiến độ bên trong thẻ.
      const track = card.querySelector(".achievement-card-track span");

      if (track) {
        track.style.width = `${percent}%`;
      }

      card.dataset.currentProgress = String(result.progress);
      card.dataset.unlocked = String(result.unlocked);
    });

    if (count) {
      count.textContent = String(unlockedCount);
    }

    if (progressBar) {
      const overall = cards.length
        ? Math.round(unlockedCount / cards.length * 100)
        : 0;

      progressBar.style.width = `${overall}%`;
      progressBar.setAttribute("aria-valuenow", String(overall));
    }
  }

  function showDetails(card) {
    if (!detail) return;

    cards.forEach((item) => item.classList.remove("is-selected"));
    card.classList.add("is-selected");

    const name =
      card.dataset.name ||
      card.querySelector("h4")?.textContent ||
      "Thành tựu";

    const result = getProgress(card);

    detail.textContent = loadError
      ? "Không tải được dữ liệu từ Haskell API. Hãy kiểm tra backend."
      : `${name}: ${result.unlocked ? "Đã mở khóa!" : "Chưa mở khóa."} ` +
        `${result.description} Tiến độ: ${result.progress}/${result.target}.`;
  }

  cards.forEach((card) => {
    card.tabIndex = 0;
    card.style.cursor = "pointer";

    card.addEventListener("click", () => showDetails(card));

    card.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        showDetails(card);
      }
    });
  });

  async function loadAchievements() {
    try {
      const response = await fetch(`${API_BASE}/achievements`);

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const data = await response.json();

      stats = {
        totalGames: Number(data.totalGames) || 0,
        bestScore: Number(data.bestScore) || 0,
        totalScore: Number(data.totalScore) || 0
      };

      loadError = false;
      renderAchievements();
    } catch (error) {
      console.error("Không tải được thành tựu từ Haskell:", error);
      loadError = true;

      // Không tự tạo số liệu giả khi API lỗi.
      renderAchievements();

      if (detail) {
        detail.textContent =
          "Không kết nối được Haskell API. Hãy kiểm tra server và endpoint /api/achievements.";
      }
    }
  }

  renderAchievements();
  loadAchievements();
})();


/* =========================================================
   CYBER FLAPPY — LEADERBOARD
   BEST SCORES lấy dữ liệu từ Haskell API
   ========================================================= */

document.addEventListener("DOMContentLoaded", () => {
    // 1. Lấy các phần tử HTML
    const modal = document.getElementById("leaderboardModal");
    const openButton = document.getElementById("leaderboardOpenButton");
    const closeButton = document.getElementById("leaderboardCloseButton");

    const periodButtons = document.querySelectorAll(".leaderboard-period");
    const kindButtons = document.querySelectorAll(".leaderboard-kind");

    const monthSelect = document.getElementById("leaderboardMonth");
    const yearSelect = document.getElementById("leaderboardYear");

    const podium = document.getElementById("leaderboardPodium");
    const list = document.getElementById("leaderboardList");
    const listHead = document.getElementById("leaderboardListHead");
    const note = document.getElementById("leaderboardNote");

    const personalBest = document.getElementById("leaderboardPersonalBest");
    const gamesPlayed = document.getElementById("leaderboardGamesPlayed");
    const personalRank = document.getElementById("leaderboardPersonalRank");

    // Nếu chưa có HTML leaderboard thì dừng để tránh lỗi.
    if (!modal || !openButton || !closeButton) {
        console.warn(
            "Leaderboard: Không tìm thấy HTML cần thiết. Hãy kiểm tra index.html."
        );
        return;
    }

    // 2. Trạng thái hiện tại
    let currentPeriod = "all";
    let currentKind = "scores";

    const now = new Date();
    const currentMonth = now.getMonth() + 1;
    const currentYear = now.getFullYear();

    // 3. BEST SCORES lấy trực tiếp từ Haskell API
    const API_BASE = "http://localhost:3000/api";

    let scoreData = [];
    let leaderboardLoadError = false;

    // Donation vẫn là dữ liệu minh họa vì backend chưa có API donation.
    const donationData = [
        {
            name: "Duy lợ",
            amount: 500000,
            date: "2026-10-10T20:30:00",
            avatar: "L",
            image: "picture/duyloido.jpg"
        },
        {
            name: "NPC",
            amount: 300000,
            date: "2026-10-09T18:15:00",
            avatar: "T",
            image: "picture/soicodoc.jpg"
        },
        {
            name: "NPC",
            amount: 200000,
            date: "2026-10-08T21:10:00",
            avatar: "N",
            image: "picture/chienbinh.jpg"
        },
        {
            name: "NIGHT_OWL",
            amount: 100000,
            date: "2026-10-06T19:45:00",
            avatar: "N"
        },
        {
            name: "SKY_BREAKER",
            amount: 50000,
            date: "2026-09-28T16:20:00",
            avatar: "S"
        }
    ];

    // Tên người chơi hiện tại, nếu frontend đã lưu tên.
    const playerData = {
        name: localStorage.getItem("flappyPlayerName") || "YOU"
    };

    // 4. Điền năm vào dropdown
    if (yearSelect) {
        yearSelect.innerHTML = "";

        for (let year = currentYear; year >= currentYear - 5; year--) {
            const option = document.createElement("option");
            option.value = String(year);
            option.textContent = String(year);
            yearSelect.appendChild(option);
        }

        yearSelect.value = String(currentYear);
    }

    // Chọn tháng hiện tại mặc định
    if (monthSelect) {
        monthSelect.value = String(currentMonth);
    }

    // 5. Mở bảng xếp hạng
    function openLeaderboard() {
        modal.classList.add("is-open");
        modal.setAttribute("aria-hidden", "false");
        document.body.classList.add("leaderboard-no-scroll");

        renderLeaderboard();
        loadLeaderboard();
    }

    // Tải dữ liệu điểm từ Haskell API.
    // Không có dữ liệu thì vẫn giữ nguyên khung giao diện.
    async function loadLeaderboard() {
        if (currentKind !== "scores") return;

        try {
            const response = await fetch(`${API_BASE}/leaderboard`);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }

            const result = await response.json();
            const entries = Array.isArray(result.entries)
                ? result.entries
                : [];

            scoreData = entries.map((entry) => ({
                name: String(entry.name || "PLAYER"),
                score: Number(entry.score) || 0,
                date: entry.date || "",
                avatar:
                    entry.avatar ||
                    String(entry.name || "P").charAt(0)
            }));

            leaderboardLoadError = false;
            renderLeaderboard();
        } catch (error) {
            console.error(
                "Không tải được leaderboard từ Haskell API:",
                error
            );

            scoreData = [];
            leaderboardLoadError = true;
            renderLeaderboard();
        }
    }

    // 6. Đóng bảng xếp hạng
    function closeLeaderboard() {
        modal.classList.remove("is-open");
        modal.setAttribute("aria-hidden", "true");
        document.body.classList.remove("leaderboard-no-scroll");
    }

    openButton.addEventListener("click", openLeaderboard);
    closeButton.addEventListener("click", closeLeaderboard);

    // Nhấn vùng nền bên ngoài panel để đóng
    modal.addEventListener("click", (event) => {
        if (event.target === modal) {
            closeLeaderboard();
        }
    });

    // Nhấn Escape để đóng
    document.addEventListener("keydown", (event) => {
        if (
            event.key === "Escape" &&
            modal.classList.contains("is-open")
        ) {
            closeLeaderboard();
        }
    });

    // 7. Chuyển ALL TIME / MONTH / YEAR
    periodButtons.forEach((button) => {
        button.addEventListener("click", () => {
            currentPeriod = button.dataset.period;

            periodButtons.forEach((item) => {
                item.classList.toggle("active", item === button);
            });

            renderLeaderboard();
        });
    });

    // 8. Chuyển BEST SCORES / DONATIONS
    kindButtons.forEach((button) => {
        button.addEventListener("click", () => {
            currentKind = button.dataset.kind;

            kindButtons.forEach((item) => {
                item.classList.toggle("active", item === button);
            });

            renderLeaderboard();

            if (currentKind === "scores") {
                loadLeaderboard();
            }
        });
    });

    // 9. Khi thay đổi tháng hoặc năm
    if (monthSelect) {
        monthSelect.addEventListener("change", renderLeaderboard);
    }

    if (yearSelect) {
        yearSelect.addEventListener("change", renderLeaderboard);
    }

    // 10. Lọc dữ liệu theo thời gian
    function filterByPeriod(data) {
        if (currentPeriod === "all") {
            return [...data];
        }

        const selectedMonth = monthSelect
            ? Number(monthSelect.value)
            : currentMonth;

        const selectedYear = yearSelect
            ? Number(yearSelect.value)
            : currentYear;

        return data.filter((item) => {
            const date = new Date(item.date);

            if (Number.isNaN(date.getTime())) {
                return false;
            }

            if (currentPeriod === "month") {
                return (
                    date.getFullYear() === selectedYear &&
                    date.getMonth() + 1 === selectedMonth
                );
            }

            if (currentPeriod === "year") {
                return date.getFullYear() === selectedYear;
            }

            return true;
        });
    }

    // 11. Định dạng ngày giờ
    function formatDate(dateString) {
        const date = new Date(dateString);

        if (Number.isNaN(date.getTime())) {
            return "—";
        }

        return new Intl.DateTimeFormat("vi-VN", {
            day: "2-digit",
            month: "2-digit",
            year: "numeric",
            hour: "2-digit",
            minute: "2-digit",
            hour12: false
        }).format(date);
    }

    // 12. Định dạng điểm
    function formatScore(score) {
        return Number(score).toLocaleString("vi-VN");
    }

    // 13. Định dạng tiền donation
    function formatMoney(amount) {
        return Number(amount).toLocaleString("vi-VN") + " ₫";
    }

    // 14. Render top 3
    function renderPodium(data) {
        if (!podium) return;

        podium.innerHTML = "";

        if (data.length === 0) {
            podium.innerHTML = `
                <div class="leaderboard-empty">
                    Chưa có dữ liệu trong khoảng thời gian này.
                </div>
            `;
            return;
        }

        // Thứ tự hiển thị: hạng 2, hạng 1, hạng 3
        const podiumOrder = [
            {
                index: 1,
                rank: "Second",
                className: "silver",
                medal: "🥈"
            },
            {
                index: 0,
                rank: "First",
                className: "gold",
                medal: "🥇"
            },
            {
                index: 2,
                rank: "Third",
                className: "bronze",
                medal: "🥉"
            }
        ];

        podiumOrder.forEach((position) => {
            const player = data[position.index];

            if (!player) return;

            const value =
                currentKind === "scores"
                    ? formatScore(player.score)
                    : formatMoney(player.amount);

            const card = document.createElement("div");
            card.className =
                `leaderboard-podium-card ${position.className}`;

            card.innerHTML = `
                <div class="leaderboard-podium-rank">
                    ${position.medal} ${position.rank}
                </div>

                ${
                    player.image
                        ? `
                            <img
                                class="leaderboard-player-image"
                                src="${escapeHTML(player.image)}"
                                alt="${escapeHTML(player.name)}"
                            >
                        `
                        : `
                            <div class="leaderboard-avatar">
                                ${escapeHTML(
                                    player.avatar || player.name.charAt(0)
                                )}
                            </div>
                        `
                }

                <div class="leaderboard-podium-name">
                    ${escapeHTML(player.name)}
                </div>

                <div class="leaderboard-podium-value">
                    ${value}
                </div>
            `;

            podium.appendChild(card);
        });
    }

    // 15. Render danh sách người chơi
    function renderList(data) {
        if (!list) return;

        list.innerHTML = "";

        if (data.length === 0) {
            list.innerHTML = `
                <div class="leaderboard-empty">
                    Không có dữ liệu phù hợp.
                </div>
            `;
            return;
        }

        data.forEach((player, index) => {
            const rank = index + 1;

            const value =
                currentKind === "scores"
                    ? formatScore(player.score)
                    : formatMoney(player.amount);

            const row = document.createElement("div");
            row.className = "leaderboard-row";

            row.innerHTML = `
                <div class="leaderboard-player">
                    <span class="leaderboard-rank">
                        #${String(rank).padStart(2, "0")}
                    </span>

                    <span class="leaderboard-avatar">
                        ${escapeHTML(
                            player.avatar || player.name.charAt(0)
                        )}
                    </span>

                    <span class="leaderboard-player-name">
                        ${escapeHTML(player.name)}
                    </span>
                </div>

                <div class="leaderboard-date">
                    ${formatDate(player.date)}
                </div>

                <div class="leaderboard-score">
                    ${value}
                </div>
            `;

            list.appendChild(row);
        });
    }

    // 16. Cập nhật thống kê cá nhân
    function renderPersonalStats(sortedData) {
        const ownEntries = scoreData.filter(
            (player) =>
                player.name.toLowerCase() ===
                playerData.name.toLowerCase()
        );

        const ownBest = ownEntries.length
            ? Math.max(...ownEntries.map((player) => player.score))
            : 0;

        if (personalBest) {
            personalBest.textContent = ownEntries.length
                ? formatScore(ownBest)
                : "—";
        }

        // API hiện chỉ cung cấp Top 10, chưa có tổng lượt chơi cá nhân.
        if (gamesPlayed) {
            gamesPlayed.textContent = "—";
        }

        if (personalRank) {
            const rank = sortedData.findIndex(
                (player) =>
                    player.name.toLowerCase() ===
                    playerData.name.toLowerCase()
            );

            personalRank.textContent =
                rank === -1
                    ? "—"
                    : `#${String(rank + 1).padStart(2, "0")}`;
        }
    }

    // 17. Cập nhật tiêu đề cột
    function renderListHeader() {
        if (!listHead) return;

        if (currentKind === "scores") {
            listHead.innerHTML = `
                <span>RANK / PLAYER</span>
                <span>DATE &amp; TIME</span>
                <span>SCORE</span>
            `;
        } else {
            listHead.innerHTML = `
                <span>RANK / PLAYER</span>
                <span>DATE &amp; TIME</span>
                <span>DONATION</span>
            `;
        }
    }

    // 18. Render toàn bộ bảng
    function renderLeaderboard() {
        const sourceData =
            currentKind === "scores" ? scoreData : donationData;

        const filteredData = filterByPeriod(sourceData);

        const sortedData = [...filteredData].sort((a, b) => {
            const valueA =
                currentKind === "scores" ? a.score : a.amount;

            const valueB =
                currentKind === "scores" ? b.score : b.amount;

            return valueB - valueA;
        });

        renderListHeader();
        renderPodium(sortedData);
        renderList(sortedData);
        renderPersonalStats(sortedData);

        if (note) {
            if (currentKind === "scores") {
                if (leaderboardLoadError) {
                    note.textContent =
                        "KHÔNG KẾT NỐI ĐƯỢC HASKELL API · Kiểm tra backend tại localhost:3000";
                } else if (sortedData.length === 0) {
                    note.textContent =
                        "BEST SCORES · Chưa có dữ liệu điểm từ Haskell";
                } else {
                    note.textContent =
                        "BEST SCORES · Dữ liệu trực tiếp từ Haskell API";
                }
            } else {
                note.textContent =
                    "DONATIONS · Dữ liệu minh họa, chưa có API donation từ Haskell";
            }
        }
    }

    // 19. Tránh chèn HTML ngoài ý muốn khi hiển thị tên
    function escapeHTML(value) {
        return String(value).replace(/[&<>"']/g, (character) => {
            const entities = {
                "&": "&amp;",
                "<": "&lt;",
                ">": "&gt;",
                '"': "&quot;",
                "'": "&#039;"
            };

            return entities[character];
        });
    }

    // 20. Hiển thị bảng lần đầu và tải điểm từ Haskell
    renderLeaderboard();
    loadLeaderboard();
});

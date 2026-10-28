# Cyber Flappy — Haskell + JavaScript

## 1. Tổng quan

Cyber Flappy là trò chơi kiểu Flappy Bird với phần giao diện viết bằng HTML/CSS/JavaScript và phần logic trò chơi/API viết bằng Haskell. Frontend gửi yêu cầu đến backend qua HTTP JSON; backend cập nhật trạng thái game và trả trạng thái mới về cho giao diện.

## 2. Cấu trúc thư mục

```text
flappy_bird_lth_game/
├── frontend/                  # HTML, CSS, JavaScript và hình ảnh
├── logic/
│   ├── app/Main.hs             # Khởi chạy Scotty API
│   ├── src/Game/               # Các module logic Haskell
│   ├── data/                   # Dữ liệu leaderboard/achievement
│   ├── test/                   # Khu vực kiểm thử
│   └── flappy-bird-haskell.cabal
└── README.md
```

Các file build trong `dist-newstyle/` do Cabal tạo ra; không cần chỉnh sửa thủ công.

## 3. Yêu cầu

- GHC và Cabal (có thể cài qua GHCup).
- Python 3 để chạy web server tĩnh cho frontend.
- Trình duyệt hiện đại.

## 4. Chạy project trên macOS

Mở **Terminal 1** để chạy backend:

```bash
cd logic
export PATH="$HOME/.ghcup/bin:$PATH"
cabal build
cabal run flappy-bird-api -- +RTS -N -RTS
```

Backend chạy tại `http://localhost:3000`. Có thể kiểm tra bằng:

```bash
curl http://localhost:3000/api/health
```

Mở **Terminal 2** để chạy frontend:

```bash
cd frontend
python3 -m http.server 5501
```

Mở `http://localhost:5501` trên trình duyệt. Giữ cả hai Terminal chạy khi chơi. Nếu port 5501 đang được sử dụng, chọn port khác và cập nhật cấu hình CORS/API của project tương ứng.

## 5. API chính

| Method | Endpoint | Mục đích |
|---|---|---|
| GET | `/api/health` | Kiểm tra backend |
| POST | `/api/game/start` | Tạo trạng thái game mới |
| POST | `/api/game/step` | Xử lý input và cập nhật game |
| POST | `/api/game/restart` | Tạo lại trạng thái để chơi lại |
| GET | `/api/leaderboard` | Lấy bảng xếp hạng |
| GET | `/api/achievements` | Lấy thống kê thành tích |
| POST | `/api/simulation/run` | Benchmark mô phỏng thường tuần tự/song song |
| POST | `/api/boss/simulate` | Benchmark mô phỏng boss tuần tự/song song |

Chi tiết payload và module xem `logic/HUONG_DAN.md`, `logic/CHUC_NANG.md`.

## 6. Lưu ý

- API dùng cổng `3000`; frontend mặc định cần truy cập được API này.
- Các dữ liệu leaderboard và achievement được lưu trong thư mục `logic/data/` theo đường dẫn tương đối với thư mục làm việc khi chạy backend. Nên khởi chạy backend từ thư mục `logic`.
- Benchmark đo thời gian thực thi hai cách mô phỏng trên backend; kết quả benchmark không tự nó chứng minh FPS của giao diện tăng lên.
- `Physics.hs`, `PipeSystem.hs` và `Stage.hs` là các module trong project, không xóa chỉ vì chưa thấy chúng được gọi trực tiếp từ một vị trí cụ thể.

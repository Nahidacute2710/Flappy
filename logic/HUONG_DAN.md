# Hướng dẫn cài đặt, chạy và kiểm thử

Tài liệu này dành cho project Cyber Flappy. Các lệnh dưới đây giả định cấu trúc `flappy_bird_lth_game/logic` và `flappy_bird_lth_game/frontend`.

## 1. Chuẩn bị môi trường

Kiểm tra công cụ:

```bash
ghc --version
cabal --version
python3 --version
```

Nếu `cabal: command not found` trên macOS và đã cài GHCup, chạy:

```bash
export PATH="$HOME/.ghcup/bin:$PATH"
```

## 2. Build và chạy backend

Mở Terminal thứ nhất:

```bash
cd logic
export PATH="$HOME/.ghcup/bin:$PATH"
cabal build
cabal run flappy-bird-api -- +RTS -N -RTS
```

Khi backend khởi động, Scotty lắng nghe ở cổng `3000`. Giữ Terminal này mở trong lúc chơi.

Kiểm tra health endpoint ở Terminal khác:

```bash
curl -s http://localhost:3000/api/health
```

Kết quả mong đợi có dạng:

```json
{"ok":true,"service":"flappy-bird-haskell"}
```

## 3. Chạy frontend

Mở Terminal thứ hai, từ thư mục gốc project:

```bash
cd frontend
python3 -m http.server 5501
```

Mở `http://localhost:5501`. Nếu terminal báo `Address already in use`, dừng server cũ hoặc dùng port khác. Cấu hình CORS trong `logic/app/Main.hs` hiện cho phép một số origin localhost, trong đó có `5501` và `5502`; nếu đổi port, cần kiểm tra cấu hình này.

Có thể chạy server và mở trình duyệt bằng một lệnh trên macOS:

```bash
python3 -m http.server 5501 & sleep 1 && open "http://localhost:5501"
```

## 4. Một số request API

### Health

```bash
curl -s http://localhost:3000/api/health
```

### Tạo game mới

```bash
curl -s -X POST http://localhost:3000/api/game/start \
  -H 'Content-Type: application/json' \
  -d '{}'
```

Có thể gửi lựa chọn chim và cờ bất tử dùng cho kiểm thử, nếu cần:

```bash
curl -s -X POST http://localhost:3000/api/game/start \
  -H 'Content-Type: application/json' \
  -d '{"bird":"classic","immortal":false}'
```

### Benchmark mô phỏng

```bash
curl -s -X POST http://localhost:3000/api/simulation/run \
  -H 'Content-Type: application/json' \
  -d '{"count":100,"framesPerScenario":300}'
```

### Benchmark boss

```bash
curl -s -X POST http://localhost:3000/api/boss/simulate \
  -H 'Content-Type: application/json' \
  -d '{"round":3,"count":100}'
```

Hai endpoint benchmark trả về thời gian tuần tự, song song, speedup và trường `matchesSequential` để so sánh kết quả.

## 5. Chạy kiểm thử parser

Trong `logic`, chạy:

```bash
cabal run test-parser
```

Test parser hiện kiểm tra lệnh hợp lệ ở hai chế độ, số frame bằng 0, giá trị không phải số, thiếu mode, vượt giới hạn và lệnh sai. Đây là test cho parser, không phải toàn bộ test suite của game.

## 6. Đo benchmark bằng Python và xuất JSON

Nếu có script benchmark Python, hãy chạy nó từ thư mục gốc project để các đường dẫn tương đối như `logic/src/Benchmark/benchmark_results.json` hoặc `src/Benchmark/benchmark_results.json` được xác định đúng theo script đang dùng. Nên chọn một đường dẫn thống nhất và đảm bảo thư mục đích tồn tại trước khi ghi.

Để kết quả có ý nghĩa hơn:

- Chạy backend trước khi chạy script.
- Giữ nguyên `count`, `framesPerScenario`/`round` giữa các lần so sánh.
- Chạy nhiều lần và báo cáo median thay vì chỉ một phép đo.
- Ghi rõ máy, phiên bản GHC, số scenario và số lần lặp trong báo cáo.
- Xác nhận `matchesSequential` là `true` ở các trường hợp đo.

## 7. Xử lý lỗi thường gặp

### `can't find source for Physics`

Cabal vẫn khai báo module `Physics` trong `other-modules`, hoặc mã nguồn còn import `Physics`. Khôi phục `logic/src/Game/Physics.hs`; không xóa file nếu chưa kiểm tra các tham chiếu.

### `cabal: command not found`

```bash
export PATH="$HOME/.ghcup/bin:$PATH"
```

### Frontend mở nhưng API lỗi/disconnect

1. Kiểm tra backend còn chạy và health endpoint trả về `ok: true`.
2. Mở Developer Tools → Console/Network để xem URL và lỗi request.
3. Kiểm tra API base trong `frontend/function.js` và origin/port được cho phép trong `logic/app/Main.hs`.
4. Chạy frontend qua HTTP server, không mở `index.html` trực tiếp bằng `file://`.

### JSON data không được lưu đúng vị trí

Các file `data/leaderboard.json` và `data/achievements.json` dùng đường dẫn tương đối. Khởi chạy backend từ thư mục `logic` để dữ liệu nằm trong `logic/data/`.

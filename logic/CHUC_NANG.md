# Chức năng hệ thống Cyber Flappy

## 1. Kiến trúc tổng quát

- **Frontend (`frontend/`)**: HTML/CSS/JavaScript, hiển thị canvas/giao diện, nhận bàn phím hoặc click và gửi request đến backend.
- **Backend (`logic/app/Main.hs`)**: API HTTP dùng Scotty, nhận JSON, gọi logic Haskell và trả JSON.
- **Logic game (`logic/src/Game/`)**: kiểu dữ liệu, trạng thái game, vòng lặp, vật lý, hình học va chạm, ống/bẫy, stage, phân tích và mô phỏng.
- **Dữ liệu (`logic/data/`)**: leaderboard và achievement.

## 2. API

| Method | Endpoint | Chức năng |
|---|---|---|
| GET | `/api/health` | Trả trạng thái backend và tên service. |
| POST | `/api/game/start` | Tạo trạng thái mới, khởi tạo chim và collectible. Body có thể có `bird`, `immortal`. |
| POST | `/api/game/step` | Nhận `input`, `state`, tùy chọn `stepSeconds` và `playerName`; xử lý một hoặc nhiều tick có giới hạn rồi trả trạng thái. |
| POST | `/api/game/restart` | Tạo trạng thái mới để chơi lại. |
| GET | `/api/leaderboard` | Trả các mục xếp hạng lấy từ dữ liệu lưu. |
| GET | `/api/achievements` | Trả thống kê số trận, điểm cao nhất và tổng điểm. |
| POST | `/api/simulation/run` | Chạy các scenario tuần tự và song song, đo thời gian và so sánh kết quả. |
| POST | `/api/boss/simulate` | Chạy mô phỏng boss tuần tự/song song, trả số sống sót, thời gian và so sánh kết quả. |

### Request benchmark mẫu

`/api/simulation/run`:

```json
{"count":100,"framesPerScenario":300}
```

`/api/boss/simulate`:

```json
{"round":3,"count":100}
```

Backend giới hạn số lượng và frame/round trong `Main.hs` để tránh request quá lớn.

## 3. Vai trò các module Haskell

| Module | Vai trò chính |
|---|---|
| `GameState.hs` | Kiểu dữ liệu dùng chung, trạng thái game, tham số mặc định. |
| `Config.hs` | Re-export `Params`, `Modifiers` và giá trị mặc định từ `GameState` để tương thích. |
| `GameLoop.hs` | Trạng thái ban đầu, `stepGame`, cập nhật một bước game và các hành vi game chính. |
| `Physics.hs` | Chuyển động chim, flap/revive, gió, kiểm tra biên/ống/bẫy và va chạm. |
| `Geometry.hs` | Hình học vùng va chạm của ống và bẫy. |
| `PipeSystem.hs` | Tạo/cập nhật ống và bẫy, tính điểm ống, phá hoặc dọn ống/bẫy. |
| `Stage.hs` | Chọn cấu hình độ khó theo điểm: tốc độ, khe ống, trọng số ống/bẫy. |
| `Input.hs` | Ánh xạ phím/click thành các giá trị input game. |
| `ApiJSON.hs` | Các instance JSON để chuyển đổi kiểu dữ liệu game. |
| `Simulation.hs` | Chạy scenario mô phỏng tuần tự và song song; có cả mô phỏng boss. |
| `Analyzer.hs` | Phân tích nguy hiểm/nộ và quyết định; cung cấp bản tuần tự và song song. |
| `Leaderboard.hs` | Đọc/ghi điểm người chơi và lấy top 10. |
| `Achievement.hs` | Ghi nhận trận kết thúc và thống kê thành tích. |
| `CommandParser.hs` | Parse lệnh mô phỏng theo định dạng `simulate frames=... runs=... mode=...`. |
| `TestParser.hs` | Chạy các trường hợp kiểm thử parser. |

## 4. Input điều khiển

Trong `Input.hs`, Space và Arrow Up được ánh xạ thành flap/start tùy trạng thái; Enter bắt đầu khi ở `Ready`; phím restart chỉ có tác dụng khi `GameOver`; phím số 1–9 gửi `UseSkill` khi đang chơi. Click được ánh xạ thông qua `mapPointerInput`.

## 5. Mô phỏng song song

`Simulation.hs` có hai cặp hàm:

- `runSequential` và `runParallel` cho các scenario game thông thường.
- `runBossSequential` và `runBossParallel` cho các scenario boss.

Các scenario được tạo độc lập; bản song song dùng `parMap rdeepseq`, cùng với `NFData` để buộc đánh giá sâu kết quả. API đo thời gian bằng đồng hồ monotonic và trả:

- `sequentialMs`: thời gian bản tuần tự.
- `parallelMs`: thời gian bản song song.
- `speedup`: `sequentialMs / parallelMs` nếu thời gian song song lớn hơn 0.
- `matchesSequential`: kết quả hai phương pháp có bằng nhau hay không.

Benchmark này đo workload mô phỏng trên backend. Nó không tự động đo FPS hoặc độ trễ mỗi frame của giao diện chơi chính.

## 6. Lưu dữ liệu

- `Leaderboard.hs` sử dụng `data/leaderboard.json`.
- `Achievement.hs` sử dụng `data/achievements.json`.

Do đây là đường dẫn tương đối, nên chạy backend từ thư mục `logic` để file được lưu đúng trong `logic/data/`.

## 7. Phạm vi cần phân biệt

Một module có mặt trong source không đồng nghĩa tất cả hàm của nó đều được gọi trong mỗi frame. Khi báo cáo, nên phân biệt rõ:

1. Chức năng đã được gọi trực tiếp trong luồng API/game loop.
2. Module hỗ trợ được gọi từ module khác.
3. Chức năng độc lập, chẳng hạn parser hoặc benchmark.

Không nên khẳng định benchmark làm tăng FPS gameplay nếu chưa đo trực tiếp FPS hoặc frame time khi chơi.

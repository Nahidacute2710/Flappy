# Tài liệu logic Haskell

Thư mục này chứa backend/API và các module logic của Cyber Flappy.

## Luồng xử lý

1. `Main.hs` nhận HTTP request bằng Scotty.
2. `ApiJSON.hs` cung cấp chuyển đổi JSON cho các kiểu dữ liệu.
3. API gọi `GameLoop.stepGame` để xử lý trạng thái hoặc gọi `Simulation` để chạy benchmark.
4. Kết quả được serialize thành JSON và trả về frontend.

## Module

- `GameState.hs`: mô hình dữ liệu chung và tham số mặc định.
- `GameLoop.hs`: trạng thái ban đầu và cập nhật game.
- `Physics.hs`: chuyển động và va chạm.
- `Geometry.hs`: hình dạng va chạm.
- `PipeSystem.hs`: sinh/cập nhật ống, bẫy và các tiện ích liên quan.
- `Stage.hs`: cấu hình stage/độ khó.
- `Input.hs`: ánh xạ sự kiện điều khiển.
- `Simulation.hs`: benchmark mô phỏng tuần tự/song song, gồm boss.
- `Analyzer.hs`: phân tích nguy hiểm/nộ và quyết định tuần tự/song song.
- `Leaderboard.hs`, `Achievement.hs`: lưu và truy vấn thống kê người chơi.
- `CommandParser.hs`, `TestParser.hs`: parser lệnh mô phỏng và các test parser.
- `ApiJSON.hs`: JSON instances.
- `Config.hs`: module tương thích re-export cấu hình từ `GameState`.

## Build/run

Chạy từ thư mục `logic`:

```bash
export PATH="$HOME/.ghcup/bin:$PATH"
cabal build
cabal run flappy-bird-api -- +RTS -N -RTS
```

Backend mặc định lắng nghe ở cổng `3000`. Endpoint kiểm tra:

```bash
curl -s http://localhost:3000/api/health
```

Xem `HUONG_DAN.md` ở thư mục `logic` để biết các lệnh API/test và `CHUC_NANG.md` để xem bảng chức năng.

## Lưu ý về cấu hình Cabal

`flappy-bird-haskell.cabal` liệt kê `Physics`, `PipeSystem`, `Stage` và các module khác trong `other-modules`. Vì vậy không được xóa các file `.hs` này nếu chưa gỡ mọi import/khai báo liên quan và kiểm tra build lại. Nếu Cabal báo `can't find source for Physics`, kiểm tra `logic/src/Game/Physics.hs` và các tham chiếu trong source/Cabal.

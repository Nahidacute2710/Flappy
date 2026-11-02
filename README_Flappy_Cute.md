# Flappy Cute — Haskell + HTML/CSS/JavaScript

## 1. Giới thiệu

**Flappy Cute** là trò chơi phát triển từ Flappy Bird, sử dụng **Haskell** để xử lý luật chơi và cung cấp HTTP API; giao diện chạy trên trình duyệt được xây dựng bằng **HTML, CSS và JavaScript**. Frontend gửi thao tác cùng trạng thái game đến backend qua HTTP/JSON và nhận trạng thái mới để hiển thị.

Trò chơi hỗ trợ ba loại chim (Classic, Neon, Cyber), kỹ năng, cột và bẫy, vật phẩm, boss, bảng xếp hạng và thống kê thành tích. Dự án còn có parser lệnh mô phỏng, mô phỏng tuần tự/song song và các chương trình kiểm thử.

## 2. Cấu trúc thư mục

```text
Flappy-Bird-Final/
├── README.md
├── frontend/
│   ├── index.html
│   ├── interf.css
│   ├── function.js
│   ├── liquid.js
│   ├── Leaderboard.js
│   ├── achievement.js
│   └── picture/                 # Tài nguyên hình ảnh
└── logic/
    ├── flappy-bird-haskell.cabal
    ├── app/
    │   └── Main.hs             # HTTP API (Scotty/Warp)
    ├── src/
    │   ├── Game/               # Module gameplay và file kiểm thử .hs
    │   └── Benchmark/
    │       └── benchmark_results.json
    ├── data/
    │   ├── leaderboard.json
    │   └── achievements.json
    ├── TestHTTP.py             # Kiểm thử HTTP đồng thời
    ├── HUONG_DAN.md
    └── CHUC_NANG.md
```

Tên `Flappy-Bird-Final/` là tên thư mục ví dụ sau khi giải nén; tên thực tế có thể khác. **Không có thư mục `logic/test/` riêng** trong bản nộp này: các chương trình kiểm thử Haskell nằm trong `logic/src/Game/`.

Thư mục `dist-newstyle/` được Cabal tự tạo khi build; không cần đưa vào source hoặc sửa thủ công.

## 3. Yêu cầu môi trường

- **GHC** và **Cabal** (có thể cài bằng [GHCup](https://www.haskell.org/ghcup/)).
- **Python 3** để phục vụ frontend qua HTTP.
- Trình duyệt web hiện đại.
- Kết nối mạng khi Cabal cần tải các thư viện còn thiếu trong lần build đầu.

Kiểm tra phiên bản trong terminal:

```text
ghc --version
cabal --version
```

Kiểm tra Python:

- **macOS:** `python3 --version`
- **Windows PowerShell:** `py --version` hoặc `python --version`

> Trên Windows nên dùng **PowerShell** hoặc Windows Terminal. Nếu cài Haskell trong **WSL**, thực hiện các lệnh theo hướng dẫn macOS/Linux bên trong terminal WSL.

## 4. Chạy chương trình trên macOS và Windows

**Cần mở hai cửa sổ terminal** và giữ cả hai đang chạy khi chơi. Các lệnh `cd logic` và `cd frontend` dưới đây được thực hiện từ **thư mục gốc đã giải nén**.

### Bước 1 — Build và chạy Haskell backend

**macOS (Terminal):**

```bash
cd logic
# Chỉ cần dòng tiếp theo nếu đã cài GHCup nhưng ghc/cabal chưa có trong PATH:
export PATH="$HOME/.ghcup/bin:$PATH"
cabal build all
cabal run flappy-bird-api -- +RTS -N2 -RTS
```

**Windows (PowerShell):**

```powershell
cd logic
cabal build all
cabal run flappy-bird-api -- +RTS -N2 -RTS
```

Lệnh `-N2` yêu cầu Haskell runtime sử dụng 2 capabilities khi chạy backend. Đây là cấu hình chạy thử, **không bảo đảm máy nào cũng có cùng kết quả benchmark**. Có thể bỏ phần `-- +RTS -N2 -RTS` nếu chỉ cần chạy game bình thường.

Backend mặc định hoạt động tại `http://localhost:3000`. Mở địa chỉ sau bằng trình duyệt để kiểm tra:

http://localhost:3000/api/health

Nếu có lỗi thiếu thư viện khi build, thử `cabal update` rồi `cabal build all` và kiểm tra kết nối mạng.

### Bước 2 — Chạy frontend

Mở **terminal thứ hai**, quay về thư mục gốc của project, rồi chạy:

**macOS (Terminal):**

```bash
cd frontend
python3 -m http.server 5501
```

**Windows (PowerShell):**

```powershell
cd frontend
py -m http.server 5501
```

Nếu Windows không có lệnh `py`, thay bằng `python -m http.server 5501`.

Mở trang game:

http://localhost:5501

Frontend mặc định gọi backend tại `http://localhost:3000/api`. Vì vậy, **không mở trực tiếp file `frontend/index.html` bằng `file://`**; hãy truy cập qua `http://localhost:5501`.

**Lưu ý:** Backend hiện cấu hình CORS cho các origin localhost ở cổng `5501` và `5502`. Nếu đổi cổng frontend, cần cập nhật cấu hình CORS trong `logic/app/Main.hs` rồi build lại. Nếu cổng `3000` hoặc `5501` đang được chương trình khác sử dụng, hãy dừng tiến trình cũ trước khi chạy lại.

## 5. Cấu trúc backend và các kỹ thuật chính

| Thành phần | Chức năng |
|---|---|
| `GameState.hs`, `Config.hs` | Kiểu dữ liệu và cấu hình game |
| `GameLoop.hs` | Chuyển trạng thái thông qua `stepGame` |
| `Physics.hs`, `Geometry.hs` | Chuyển động và kiểm tra va chạm |
| `PipeSystem.hs`, `Stage.hs` | Sinh/tái chế cột, bẫy và điều chỉnh độ khó |
| `Analyzer.hs` | Phân tích nguy hiểm, trạng thái thanh nộ/kỹ năng |
| `Simulation.hs` | Mô phỏng tuần tự và song song |
| `CommandParser.hs` | Phân tích lệnh mô phỏng bằng Parsec |
| `ApiJSON.hs`, `Main.hs` | JSON, API và kết nối frontend/backend |
| `Leaderboard.hs`, `Achievement.hs`, `StorageFile.hs` | Lưu trữ JSON và ghi qua tệp tạm |

Lõi gameplay chủ yếu sử dụng **hàm thuần**. Xử lý song song sử dụng `rpar`, `rseq` và `parMap`; các thao tác đọc–sửa–ghi dữ liệu JSON dùng chung trong một tiến trình backend được bảo vệ bằng `MVar`.

## 6. Các API chính

| Method | Endpoint | Mục đích |
|---|---|---|
| GET | `/api/health` | Kiểm tra trạng thái backend |
| GET | `/api/leaderboard` | Lấy bảng xếp hạng |
| GET | `/api/achievements` | Lấy thống kê thành tích |
| POST | `/api/game/start` | Khởi tạo ván chơi |
| POST | `/api/game/step` | Xử lý thao tác và cập nhật trạng thái |
| POST | `/api/game/restart` | Khởi động lại ván |
| POST | `/api/simulation/command` | Chạy lệnh mô phỏng qua parser |
| POST | `/api/simulation/run` | Mô phỏng thông thường tuần tự/song song |
| POST | `/api/boss/simulate` | Mô phỏng boss tuần tự/song song |

Chi tiết request/response xem `logic/HUONG_DAN.md` và `logic/CHUC_NANG.md`.

## 7. Chạy các chương trình kiểm thử

Mở terminal tại thư mục `logic/`, chạy từng lệnh:

```text
cabal run test-game
cabal run test-parser
cabal run test-storage -- +RTS -N2 -RTS
cabal run test-evaluation
```

Các chương trình kiểm thử thuộc **executable** trong file `.cabal`, không phải `test-suite`, vì vậy sử dụng `cabal run` thay vì `cabal test`.

Để kiểm tra HTTP đồng thời, cần **khởi động backend trước**, sau đó ở một terminal khác tại `logic/` chạy:

**macOS:**

```bash
python3 TestHTTP.py
```

**Windows PowerShell:**

```powershell
py TestHTTP.py
```

`test-game` kiểm tra luật chơi; `test-parser` chạy các ca lệnh hợp lệ/không hợp lệ; `test-storage` kiểm tra cập nhật lưu trữ từ nhiều luồng dùng chung MVar; `test-evaluation` so sánh `foldl` và `foldl'`; `TestHTTP.py` kiểm tra các **yêu cầu GET đồng thời**, không phải kiểm thử ghi điểm qua HTTP.

## 8. Benchmark và lưu trữ

- Kết quả benchmark đã ghi nhận nằm trong `logic/src/Benchmark/benchmark_results.json`, gồm mô phỏng thường và boss, tại các mức 100, 300 và 1.000 kịch bản. Mỗi cấu hình có 5 lần đo cho từng chế độ tuần tự/song song và có kết quả trung vị.
- Đây là kết quả đã lưu từ một môi trường đo cụ thể; khi chạy trên Windows hoặc máy khác, **thời gian thực thi có thể thay đổi**. Benchmark không phải phép đo FPS của game.
- `logic/data/leaderboard.json` lưu các kết quả điểm cao; `logic/data/achievements.json` lưu thống kê tổng hợp.
- Backend dùng đường dẫn dữ liệu tương đối với thư mục làm việc: nên luôn chạy backend từ `logic/`.
- Nếu tệp JSON chưa tồn tại, chương trình có thể dùng giá trị khởi tạo; nếu tệp tồn tại nhưng JSON không hợp lệ, backend báo lỗi thay vì tự ghi đè nội dung cũ.
- Việc ghi qua tệp tạm giúp hạn chế ghi dở, nhưng chưa bảo đảm phục hồi hoàn toàn trong mọi trường hợp mất điện hoặc nhiều tiến trình cùng ghi.

## 9. Một số lỗi thường gặp

| Hiện tượng | Cách kiểm tra |
|---|---|
| `ghc` hoặc `cabal` không nhận lệnh | Kiểm tra đã cài GHCup/GHC và PATH; mở terminal mới |
| `cabal` không tìm thấy `.cabal` | Đảm bảo đang đứng trong thư mục `logic/` |
| Cổng `3000` hoặc `5501` bị chiếm | Dừng server đang chạy ở cổng đó, sau đó chạy lại |
| Trang web mở được nhưng không chơi được | Kiểm tra backend cổng 3000, địa chỉ API và CORS |
| Lỗi tải ảnh hoặc JavaScript | Mở game bằng `http://localhost:5501`, không mở `index.html` trực tiếp |
| Báo lỗi đọc JSON | Kiểm tra dữ liệu trong `logic/data/`; không xóa hoặc ghi đè file bị hỏng nếu cần giữ dữ liệu |

---

**Ghi chú:** Đây là mã nguồn đồ án Flappy Cute; frontend dùng **JavaScript**, không phải Java. Các lệnh trên là hướng dẫn chạy cho hệ điều hành tương ứng; kết quả build và thời gian thực thi còn phụ thuộc phiên bản GHC/Cabal và môi trường từng máy.

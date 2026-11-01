
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_URL = "http://localhost:3000"
REQUEST_COUNT = 30

ENDPOINTS = [
    "/api/health",
    "/api/achievements",
    "/api/leaderboard",
]


def send_request(index):
    endpoint = ENDPOINTS[index % len(ENDPOINTS)]
    url = BASE_URL + endpoint

    start = time.perf_counter()

    with urllib.request.urlopen(url, timeout=10) as response:
        status = response.status
        data = json.loads(response.read().decode("utf-8"))

    elapsed = time.perf_counter() - start

    return index, endpoint, status, data, elapsed


def main():
    print(f"Dang gui {REQUEST_COUNT} HTTP request dong thoi...")

    results = []
    errors = []

    with ThreadPoolExecutor(max_workers=REQUEST_COUNT) as executor:
        futures = [
            executor.submit(send_request, i)
            for i in range(REQUEST_COUNT)
        ]

        for future in as_completed(futures):
            try:
                results.append(future.result())
            except Exception as error:
                errors.append(str(error))

    successful = sum(
        1 for _, _, status, _, _ in results
        if status == 200
    )

    print("\n===== KET QUA KIEM THU HTTP =====")
    print("Tong request:", REQUEST_COUNT)
    print("Thanh cong:", successful)
    print("That bai:", len(errors))

    if results:
        average_time = (
            sum(item[4] for item in results)
            / len(results)
        )
        print(f"Thoi gian trung binh: {average_time:.4f}s")

    if errors:
        for error in errors:
            print("ERROR:", error)

    if successful == REQUEST_COUNT and not errors:
        print("PASS: Tat ca HTTP request thanh cong.")
    else:
        print("FAIL: Co HTTP request that bai.")
        raise SystemExit(1)


if __name__ == "__main__":
    main()

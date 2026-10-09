# FNMF Ops Test — Vận hành & Cổng kết nối thử nghiệm

Repository này chứa các script tự động hóa, kiểm thử vận hành và lớp gateway bảo mật dành riêng cho môi trường thử nghiệm phân tán FNMF (chạy trên Samsung Galaxy Note 10+ và máy trạm).

---

## 1. Kiến trúc Cổng kết nối (Public API Gateway)

Để cho phép người dùng kiểm thử kết nối từ Internet mà **không mở trực tiếp** các cổng nội bộ (`8083` Spring Boot, `8080` Qwen LLM, `5432` PostgreSQL), hệ thống sử dụng lớp gateway tối giản fail-closed:

* **Tệp mã nguồn:** `public_api_gateway.js`
* **Cổng lắng nghe:** `127.0.0.1:8084` (loopback only)
* **Cổng upstream:** `127.0.0.1:8083` (Backend Spring Boot)
* **Chính sách định tuyến (Allowlist Only):**
  * Chỉ chuyển tiếp các route cần thiết cho ứng dụng Android:
    * `/api/auth/login`, `/api/auth/me`
    * `/api/market/candles`, `/api/market/prices`
    * `/api/mobile/news/sync`, `/api/news/sync`, `/api/news/refresh`
    * `/api/trade/order`, `/api/trade/portfolio`, `/api/trade/history`
    * `/api/forecast/**`, `/api/refresh-quota/status`
    * `/api/watchlist/**`
    * `/api/payments/**`
    * `/api/stocks/**`
    * `/actuator/health`
  * **Chặn tuyệt đối (HTTP 404):** Mọi truy cập vào `/api/admin/**`, `/admin/**`, `/swagger-ui/**`, `/v3/api-docs/**`, `/h2-console/**`, và `/api/news/diagnostics`.
  * **Bảo vệ Rate Limiting & Header Sanitization:**
    * Giới hạn tần suất chung và giới hạn riêng cho endpoint xác thực (auth).
    * Loại bỏ các header `X-Forwarded-For` giả mạo từ client.
    * Giới hạn kích thước payload tối đa 256KB.

---

## 2. Quản lý Tunnel kết nối

Tunnel (Cloudflare Quick Tunnel hoặc ngrok) **chỉ được phép trỏ tới cổng Gateway `8084`**, tuyệt đối không trỏ tới cổng backend `8083` hay các cổng dịch vụ nội bộ:

* Khởi chạy Gateway:  
  `node public_api_gateway.js` hoặc `./start_public_api_gateway.sh`
* Khởi chạy Quick Tunnel trên Termux:  
  `./start_public_quick_tunnel.sh`
* Dừng Quick Tunnel:  
  `./stop_public_quick_tunnel.sh`

---

## 3. Script Kiểm thử & Build tự động

* `build_backend_test.sh`: Biên dịch JAR backend từ git commit xác định, chạy toàn bộ test và gắn hash SHA-256.
* `build_app_test.sh`: Biên dịch Android APK debug từ git commit xác định.
* `verify_runtime.sh`: Kiểm tra trạng thái các tiến trình Java, PostgreSQL, cổng loopback trên thiết bị.
* `benchmark_qwen.py`: Đo đạc hiệu năng mô hình Qwen2.5-1.5B (tốc độ sinh token, độ trễ).
* `rebind_llama_server.sh`: Cấu hình cô lập `llama-server` chỉ nghe trên `127.0.0.1:8080`.

---

## 4. Tái lập & Kết nối bằng APK Test

1. Tải bản build APK mới nhất từ mục Releases của repository `megatron69-26/fnmf-app-test`.
2. Khởi chạy Backend và Gateway trên máy chủ thử nghiệm / Termux.
3. Trong mục cấu hình Server của app Android:
   * Nếu cùng mạng nội bộ: Nhập địa chỉ IP Gateway nội bộ (ví dụ: `http://192.168.x.x:8084`).
   * Nếu qua Internet: Nhập URL HTTPS do Tunnel cung cấp (ví dụ: `https://<tunnel-id>.trycloudflare.com`).

---

## 5. Trạng thái Thử nghiệm Qwen3.5-4B trên Note 10+

* Đã bổ sung script `start_qwen35.sh` kiểm tra mã băm SHA-256 đối chiếu model 4B và cơ chế rollback tự động về Qwen2.5-1.5B nếu khởi động thất bại.
* **Kết quả kiểm thử thực tế:** Mô hình `Qwen3.5-4B-Q4_K_M.gguf` đã chạy thử nghiệm với `llama-server` trên thiết bị Note 10+ (Exynos 9825).
* **Hạn chế còn lại & Lưu ý vận hành:**
  * Lượt suy luận Forecast trên mô hình 4B vẫn gặp tình trạng timeout do thời gian xử lý kéo dài; chưa được nghiệm thu để chạy thường trực thay thế hoàn toàn 1.5B.
  * Khi thiết bị ấm/nóng liên tục, cơ chế điều tiết nhiệt phần cứng (thermal throttling) của CPU làm suy giảm tốc độ sinh token. Dự án **chưa giải quyết hiện tượng thermal throttling** này trên phần cứng di động và khuyến nghị giữ bản sao lưu rollback 1.5B khi cần độ ổn định cao.

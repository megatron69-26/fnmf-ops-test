# Kiến trúc FNMF test trên Note 10+

```text
[RSS CoinDesk] ───────► [News worker: 00,04,08,12,16,20 giờ VN] ──┐
                                                              │
[Giá/nến Binance] ───► [Forecast worker: 02,06,10,14,18,22] ───┤
                                                              ▼
                                             [llama-cli / Qwen trên Note 10+]
                                                              │ stdout JSON
                                                              ▼
                                             [Backend kiểm định nội dung]
                                                              │ lưu thành phẩm
                                                              ▼
[App Android] ─► [HTTPS tunnel + gateway] ─► [Spring Boot :8083] ⇄ [PostgreSQL]
                    chỉ route cho app          tin/dự báo: chỉ đọc cache
```

- News và forecast luân phiên cách nhau 2 giờ. Mỗi lượt có trần 20 phút; bỏ lượt quá hạn, không chạy bù. News xử lý tối đa 5 bài/lượt.
- Backend lưu bài gốc ở trạng thái chờ; chỉ bản tin tiếng Việt đạt kiểm định mới vào feed. Forecast lỗi thì giữ bản hợp lệ cũ cùng timestamp.
- App mở trang hoặc bấm Làm mới chỉ hỏi PostgreSQL qua backend; không fetch RSS, không gọi Qwen và không trừ quota. Auth, ví và giao dịch giấy vẫn có thể ghi DB theo chức năng riêng.
- Backend gọi `llama-cli` qua tiến trình con, tệp prompt tạm và stdout; không mở HTTP endpoint cho Qwen. Qwen không trực tiếp ghi PostgreSQL.
- Gateway và tunnel chỉ chuyển các route được phép đến backend. URL Quick Tunnel hiện tại là tạm; app chính thức chưa chuyển mặc định sang Note 10+ cho đến khi có URL cố định.

Giới hạn an ninh: bỏ cổng HTTP Qwen ngăn truy cập trực tiếp qua mạng, **không** phải cô lập cấp hệ điều hành. Backend và tiến trình Qwen cùng chạy dưới UID Termux; nếu backend/Termux bị chiếm quyền, người tấn công có thể chạm vào model hoặc tệp. Muốn cách ly tuyệt đối cần một ranh giới OS/UID riêng và kiểm chứng trên thiết bị.

Trạng thái: mã CLI và lịch đang được kiểm thử; không xem sơ đồ này là bằng chứng đã nghiệm thu runtime trên Note 10+.

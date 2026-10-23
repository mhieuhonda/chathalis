# ChatHalis

Trợ lý AI samtale elegante cho Android — trắng, đen, và chỉ một chút xanh.

ChatHalis là ứng dụng chat AI được thiết kế quanh một nguyên tắc duy nhất: **đơn giản đến mức không còn gì để bỏ đi**. Bạn mở app, gõ câu hỏi, Halis trả lời. Không đăng nhập, không cấu hình, không chọn model — mọi thứ chỉ hoạt động.

## Tính năng

- **Chat tức thì** — phản hồi streaming theo từng token, hiển thị đánh máy trực tiếp
- **Khu vực suy nghĩ** — quá trình tư duy của Halis hiển thị riêng, gập/mở được, kèm thời gian suy nghĩ
- **Markdown đẹp** — heading, bảng, danh sách, và code block tối với nút sao chép
- **Lịch sử cục bộ** — mọi cuộc trò chuyện lưu trong SQLite ngay trên máy, không đâu khác
- **Đổi tên / xóa / tạo lại câu trả lời**, dừng giữa dòng và giữ lại phần đã viết
- **Giao diện trắng–đen**, typography Inter, dấu chấm xanh Halis làm điểm nhấn duy nhất

## Yêu cầu

| | |
|---|---|
| Android | 7.1.1 (API 25) trở lên |
| Flutter | 3.47 stable |
| Dart | 3.13 |

## Build & chạy

```bash
flutter pub get
flutter run                 # debug trên máy ảo / thiết bị
flutter build apk --release # APK release
flutter test                # bộ test đơn vị
```

## Kiến trúc

```
lib/
├── core/        design tokens, chuỗi văn bản, tiện ích
├── gateway/     client Kilo Gateway: SSE, phân tích chunk, phân loại lỗi
├── engine/      vòng đời một lượt chat: stream, abort, retry, giới hạn output
├── data/        SQLite: conversations, messages
├── prompt/      system prompt định danh Halis
└── ui/          home, chat, settings — và các widget dùng chung
```

Một lượt chat đi qua bốn lớp: `ui` gởi văn bản tới `engine`, engine gọi `gateway` với lịch sử đã được cắt gọn theo ngân sách token (`context_window.dart`), các sự kiện streaming (văn bản / suy nghĩ / kết thúc) được reduce vào message, rồi chốt xuống `data` khi lượt kết thúc.

Giới hạn đầu ra của mỗi câu trả lời là 32.768 token; khi một câu trả lời bị ngắt vì chạm giới hạn, app hiển thị thông báo ngay dưới tin nhắn.

## Riêng tư

ChatHalis không có tài khoản và không có máy chủ của riêng nó. Lịch sử trò chuyện nằm trong SQLite trên thiết bị, và bạn có thể xóa sạch trong Cài đặt bất cứ lúc nào.

---

Halis · một dự án của Hieu Louis

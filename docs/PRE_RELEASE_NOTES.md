# Đề xuất release notes — 0.2.0-beta.1

**Bản nháp để duyệt, chưa công bố release/tag.** Gói kiểm tra hiện tại là ULP `0.1.0-68`, dùng AudioSnapshotServer2 mod `2.1.1+ulp2`. Khi chốt tên `0.2.0-beta.1`, có thể dùng phiên bản Debian `0.2.0~beta1` để beta được xếp trước `0.2.0` chính thức. Bo góc của bản 68 còn cần kiểm tra trên iPhone; các tính năng của bản 67 đã được nghiệm thu.

---

## UltimateLockscreenPlayer — Beta

ULP mang player Now Playing tùy chỉnh và visualizer phản ứng theo âm thanh đang phát lên màn hình khóa iOS 15 rootless.

### Có trong bản beta

- Player với artwork, tên bài/nghệ sĩ, điều khiển phát nhạc và tiến trình quanh viền; chạm player để mở ứng dụng nhạc qua hệ thống.
- 12 mode: Bar, Equalizer, Line, Dot, Waveform, Mirror, Siri, Circle classic, Spectro, Circular waveform, Smooth spectro và Dotted orbit.
- Settings lưu cấu hình riêng cho từng mode, Preview native và nút Apply.
- Màu đơn, gradient, màu theo artwork và ba kiểu nền artwork.
- Artwork lớn từ catalog hệ thống khi có; giữ ảnh tốt nhất theo bài và có cơ chế thử lại/fallback.
- Center dim image + blur có ảnh giữa bo góc, rộng khoảng 83% màn hình và zoom lên gần 90%; Scaled dim image dùng lại biên độ zoom theo nhạc 8%.
- HUD âm lượng riêng và chuyển cảnh mờ dần sau thời gian chờ 15 giây khi Pause; peak caps được hạ trước khi visualizer dừng cập nhật.
- Kiểm tra/phục hồi player và artwork sau khi đóng/mở lại ứng dụng nhạc.
- Sửa tiến trình khi nhấn Previous để phát lại cùng bài từ 0:00.

### Cài đặt

Cài **AudioSnapshotServer2 mod `2.1.1+ulp2` trước, ULP sau**. Khởi động lại `mediaserverd` và respring sau lần cài cả hai gói. Nếu đã có đúng server mod, cập nhật riêng ULP chỉ cần respring. Xem [README](../README.md) cho hướng dẫn DEB và build từ source.

### Tương thích và giới hạn

- Đã thử trên iPhone 6s, iOS 15.8.5, Dopamine rootless; nghiệm thu phiên nhạc bằng YouTube Music.
- Gói hiện tại là `iphoneos-arm64`; chưa xác nhận tương thích rộng với thiết bị, jailbreak và ứng dụng nhạc khác.
- Đây là beta. Tiếp tục theo dõi phục hồi phiên nhạc, vị trí player, tiến trình, đồng hồ, pin và hiệu năng khi dùng lâu.
- Artwork phụ thuộc dữ liệu ứng dụng/hệ thống cung cấp; không phải bài nào cũng trả ảnh lớn.

### Báo lỗi

Gửi phiên bản ULP/server, thiết bị/iOS/jailbreak, ứng dụng nhạc, chuỗi thao tác và ảnh/video nếu có. Log: `/var/mobile/Library/Logs/ULP.log`. Nếu cần quay lại mốc đã nghiệm thu, giữ DEB ULP `0.1.0-67` và server mod `2.1.1+ulp2`.

### Cảm ơn

Ryan Nair / AudioSnapshotServer2, Theos, Music Visualizer Lab và cộng đồng thử nghiệm jailbreak. Xem [Credits / Special thanks](../README.md#credits--special-thanks).

---

## Tệp dự kiến đính kèm khi phát hành

- DEB ULP với phiên bản đã chốt.
- DEB AudioSnapshotServer2 mod `2.1.1+ulp2`.
- SHA-256 cho cả hai gói.

Bản nháp này không tự đổi metadata phiên bản, tạo tag hay đăng release lên GitHub.

## Gói kiểm tra hiện có

Đã build cả hai lệnh trong README, chạy bộ Tests và giải nén đầy đủ hai archive. Server được rebuild từ nguồn mod hiện tại, không đổi DSP/capture. Chưa đổi tên gói thành phiên bản beta đề xuất.

| Gói | Byte | SHA-256 |
| --- | --- | --- |
| ULP `0.1.0-68` | 21218750 | `809f166f7af77def16607e2934d49398d92848658719b7be21f5730265538ae3` |
| Server `2.1.1+ulp2` | 17926 | `5ac350311f06456779ec3f44abe507cbd3d0db2600bed00f77860cdeb391d0b6` |

Giữ SHA-256 đúng với các tệp thực tế được đăng; build lại có thể tạo checksum khác. Trên iPhone đang có đúng server mod, chỉ cần nghiệm thu gói ULP 68.

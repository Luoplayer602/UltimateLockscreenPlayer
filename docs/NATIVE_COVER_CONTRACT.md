# Native Cover — 0.1.0-70

## Phạm vi

Sau khi người dùng xác nhận Trail 69 hiện ở cả Preview và màn hình khóa, bản 70 thêm Cover từ cùng renderer: Logo / Artwork / Off, Size, vị trí riêng, Opacity, viền, Glow và Spin liên tục khi phát. `ULPCoverView` thay đĩa/chữ ULP cố định và nằm phía trên nét visualizer.

Beat detector và sáu Beat motion (Swell, Flash, Shake, Spin, Bounce, Wobble) là lát tiếp theo. Spin của bản 70 là quay ảnh/logo liên tục, chưa phải Beat motion Spin. Không thêm điều khiển Beat/Rumble/Drift/Glow pulse khi chưa có xử lý tương ứng.

## Cấu hình

Khóa lưu theo schema 1, `v1.<mode>.<key>`. Cover có trên mọi mode; mặc định Logo trên Circle classic, Dotted orbit, Spectro, Circular waveform, Smooth spectro, Off trên các mode còn lại. Settings dùng `ulpDefaultByMode` để giá trị mặc định khớp loader/config.

| Điều khiển | Khóa | Mặc định | Giới hạn |
| --- | --- | --- | --- |
| Cover mode | `CoverMode` | Theo mode | 0 Logo / 1 Artwork / 2 Off |
| Size | `CoverSize` | 0.44 | 0.1–1 |
| Horizontal position | `CoverX` | 0 | −80–80 |
| Vertical position | `CoverY` | 0 | −80–80 |
| Opacity | `CoverOpacity` | 1 | 0–1 |
| Outline thickness | `CoverOutlineThickness` | 3 | 0–10 |
| Outline colour | `CoverOutlineColor` | #FFFFFF | RGB hex |
| Outline opacity | `CoverOutlineOpacity` | 0.4 | 0–1 |
| Glow | `CoverGlow` | 0.2 | 0–1 |
| Spin · °/s | `CoverSpin` | 0 | −90–90 |

Off khóa các điều khiển hình. `Reset cover` chỉ xóa mười khóa Cover của mode đang chọn, đưa góc xoay về 0, giữ vị trí cuộn và cập nhật Preview.

## Hình học và vòng đời

- Tâm dọc 42% trên scene cao, 50% trên Preview ngắn; offset theo hệ 400 đơn vị. Đường kính `min(width × 0.675, height × 0.72) × Size`: mức tối đa 270 đơn vị như demo, có giới hạn để vừa Preview.
- Cover không nhận scale không đều, flip, rotation, offset hay opacity của nét visualizer; hình luôn tròn. Audio zoom của visualizer chưa gán cho Cover trong lát này.
- Dùng UIImage sẵn có của nguồn artwork native, không tạo request/catalog mới hoặc decode lại mỗi frame. Preview dùng ảnh của nền Preview. `ScaleAspectFill` lấp đầy crop tròn, có thể cắt hai bên thumbnail ngang. Thiếu ảnh hiện logo.
- Spin chỉ xoay ảnh/logo bên trong, giữ viền/Glow/vị trí. Tính theo thời gian giữa frame được chấp nhận, hai chiều; dừng ngay khi playbackActive tắt, kể cả lúc tiếp tục nhận frame im lặng hạ peak caps. Sau stall chỉ tiến tối đa 0.1 giây mỗi frame.
- Đổi mode/Cover mode, đổi bài/PID hoặc bắt đầu/lặp mẫu Preview reset góc. Nâng chất lượng ảnh cùng bài không reset. Spin 0 dừng ở góc hiện tại; Reset đưa về 0.
- Trail vẫn chỉ chụp chín shape layer, không chụp Cover. Glow Cover dùng shadowPath tròn, không có history bitmap hoặc timer riêng.

## Kiểm tra

- `make -C Tests test` đạt: kiểm tra hiện có, giới hạn Cover, hình học/offset, độc lập với biến đổi visualizer, Spin theo thời gian ở 15/60 FPS và schema/defaults/dependencies cho 12 mode.
- Build arm64/rootless SDK 15.6 đạt cho tweak và PreferenceBundle.
- `Probe/CoverProbe` trên iPhone 6s đạt hai viewport: full bleed ảnh ngang, Spin/Pause/reset, Cover giữ hình khi visualizer đổi transform, fallback Logo và Off. Probe chạy process riêng; không thay nghiệm thu Settings/Apply hoặc đo FPS/pin SpringBoard.

Gói: `com.luoplayer.ultimatelockscreenplayer_0.1.0-70_iphoneos-arm64.deb`, Version `0.1.0-70`, 21,244,532 bytes. SHA-256 `6305a22a8cf2de28989cf9a3e0a09a0fba7cd5d8369b08f71f26eb3dad2e955e`. Đã đọc hết archive `data.tar`; checksum riêng ở `packages/SHA256SUMS-70`, không đổi checksum các gói pre-release đã chuẩn bị.

## Nghiệm thu

Đóng hẳn Settings khi cập nhật DEB để tải bundle mới. Server mod `2.1.1+ulp2` giữ nguyên; mốc quay lại là DEB ULP 69 đã giữ trong `packages/` và `/var/mobile`.

1. Phát bài có artwork, thử Cover Artwork / Logo / Off. Preview đổi ngay; quay lại đúng offset cuộn. Kiểm tra Off khóa các điều khiển và chuyển lại mở đúng.
2. Thử Size, X/Y, Opacity, Outline thickness 0/6, màu viền, Outline opacity 0/1 và Glow 0/0.8. Artwork kín hình tròn, không méo khi visualizer đổi Width/Height/flip.
3. Spin +30/−30, Pause/phát lại, Reset. Reset khôi phục giá trị mode/góc 0 và giữ Trail/màu/nền/cấu hình visualizer.
4. Đổi mode rồi quay lại, thoát/mở Settings, Apply: cấu hình riêng được giữ và Cover trên màn hình khóa nhận giá trị tương ứng.
5. Đổi bài, đóng/mở YouTube Music, Pause hơn 15 giây, khóa/mở màn hình; kiểm tra player/artwork/tiến trình/chuyển cảnh.
6. Bật Trail: chỉ nét visualizer để lại vệt; Cover không có bóng ảnh cũ. Theo dõi độ mượt, nhiệt và pin khi bật đồng thời Glow/Trail/Spin.

Giao diện thật còn chờ người dùng nghiệm thu. DSP 64/server `2.1.1+ulp2`, nguồn artwork lớn, nền/bo góc, tiến trình và phục hồi player giữ nguyên.

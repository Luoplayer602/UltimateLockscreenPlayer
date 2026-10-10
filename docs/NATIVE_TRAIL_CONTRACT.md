# Native Trail — 0.1.0-69

## Phạm vi

Lát triển khai đầu tiên sau mốc 68: Trail cho cả 12 mode. Preview và màn hình khóa dùng cùng `ULPVisualizerView` và bộ tích lũy `ULPTrail`. Chưa đưa Cover/Beat motion vào gói này.

## Cài đặt

Trong ULP → Visualizer → Effects, các khóa được lưu độc lập theo mode qua schema `v1.<mode>.*`:

| Điều khiển | Khóa | Mặc định | Giới hạn |
| --- | --- | --- | --- |
| Trail | `TrailEnabled` | Off | On/Off |
| Trail length · s | `TrailDuration` | 0.8 s | 0.1–2.0 s |
| Trail opacity | `TrailOpacity` | 0.45 | 0–1 |

Hai slider chỉ bật khi Trail bật. Length là thời gian một footprint cũ giảm còn 1% độ mờ ban đầu, không phải số frame. Thay đổi phản ánh ngay ở Preview; Apply áp dụng trên màn hình khóa.

## Quy tắc vẽ

- Chụp các path/fill/caps của visualizer tại tọa độ màn hình sau scale, zoom, rotation và flip. Hình cũ giữ vị trí đã vẽ, không chạy theo transform của frame tiếp theo.
- Không lưu nền, artwork, player, chữ ULP, halo hay shadow của Glow.
- Mỗi pixel giữ coverage lớn nhất giữa frame mới và footprint cũ đã mờ. Coverage dùng float để tránh sai số mờ phụ thuộc FPS do làm tròn alpha ở mỗi frame.
- Decay theo thời gian thực: `retention = exp(log(0.01) * dt / length)`.
- Renderer vector hiện tại giữ nguyên. Lớp Trail nằm dưới nó và chỉ xuất phần alpha còn thiếu để đạt `max(alpha_current, alpha_history * trailOpacity)`, có xét Visual opacity. Nét/fill đứng yên không bị cộng sáng khi chồng nhiều frame.
- Màu lưu theo footprint, hỗ trợ Solid/Artwork và Gradient. Tại vùng hai màu khác nhau giao nhau, màu cũ được compositing dưới nét hiện tại; không thay màu nét hiện tại để ép khớp pixel với HTML demo.
- Glow vẫn lấy hình hiện tại. Bật/tắt Trail không thay phân tích âm thanh, waveform, peak caps, zoom, nguồn ảnh hay tiến trình player.

## Vòng đời và tài nguyên

- Tối đa 524,288 pixel; chỉ bitmap vệt lưu giảm độ phân giải nếu viewport vượt giới hạn. Nét vector hiện tại vẫn giữ chất lượng gốc.
- Một footprint cố định, không có hàng đợi nhiều frame. Scratch gồm history/current/output, tối đa khoảng 8 MiB; ảnh bất biến gửi Core Animation thêm khoảng 2 MiB mỗi ảnh. Core Animation có thể giữ thêm ảnh trước trong lúc chuyển frame.
- Chụp cùng nhịp frame được renderer chấp nhận. Timer 30 Hz chỉ chạy decay khi ngừng nhận cập nhật; không đưa hình đang đóng băng trở lại history. Timer tự dừng và giải phóng bitmap khi footprint đã tan.
- Xóa history khi đổi mode/số điểm, đổi màu/artwork, bật/tắt, đổi opacity/Fill, đổi viewport, đổi bài/PID, ẩn view hoặc tháo khỏi window. Preview cũng xóa khi bắt đầu/lặp lại mẫu, rời trang hoặc ứng dụng vào background.
- Nếu không tạo được bitmap, ghi NSLog một lần và tiếp tục renderer gốc.
- Chi phí CPU/GPU và độ mượt trên iPhone 6s còn cần nghiệm thu thực tế; giới hạn bộ nhớ không chứng minh FPS đạt.

## Kiểm tra đã thực hiện

`make -C Tests test`: toàn bộ bộ kiểm tra hiện có và Trail đạt. Trail kiểm tra hình/fill đứng yên qua 600 frame, lưu footprint khi di chuyển, compositing không cộng alpha (kể cả Visual opacity thấp), decay 15/60 FPS và tick không đều, pause không nạp lại hình đóng băng, dữ liệu không hữu hạn, giới hạn/overflow bộ nhớ và reset. Settings schema xác nhận cả 12 mode có đủ khóa/default/dependencies.

Build arm64/rootless bằng SDK 15.6 cho cả tweak và PreferenceBundle đạt. AddressSanitizer/UndefinedBehaviorSanitizer kiểm tra phần C; LeakSanitizer không chạy được trong môi trường có ptrace nên tắt riêng kiểm tra leak cho lượt đó.

Gói `com.luoplayer.ultimatelockscreenplayer_0.1.0-69_iphoneos-arm64.deb`: Version `0.1.0-69`, 21,230,360 bytes, SHA-256 `30bf0df6d3c3b6c7b09902b0f368ddc85629d20faa278047a09a663092f330fc`. Đã đọc hết `data.tar` để kiểm tra archive không bị cắt. File checksum riêng `packages/SHA256SUMS-69` giữ tách khỏi checksum các gói pre-release đã chuẩn bị trước.

## Nghiệm thu trên iPhone

Đóng hẳn Settings sau khi cài DEB mới. Respring có thể giữ tiến trình Settings cũ; điều khiển plist mới không chứng minh Preview đã tải renderer mới. Trail lưu theo mode và mặc định Off: chọn đúng mode, bật Trail rồi Apply trước khi đối chiếu màn hình khóa.

1. Waveform hoặc Mirror: đặt Glow = 0, phát Preview; so sánh Trail Off/On. Nét cũ phải nằm lại và tan dần, không chỉ tạo quầng quanh nét mới.
2. Thử Length 0.1/2.0 và opacity 0.2/0.8, sau đó FPS 15/60; thời gian mờ phải gần nhau khi giữ cùng Length. Fill đứng yên không sáng dần.
3. Thử Bar với peak caps, Spectro và một mode Gradient; nét mới/caps/màu vẫn hoạt động như bản 68.
4. Pause: vệt cũ tan hết sau khi renderer ngừng cập nhật. Caps vẫn hạ theo cơ chế đã nghiệm thu; bật phát lại không kéo theo vệt cũ.
5. Đổi mode, thoát/mở lại Settings: cấu hình riêng từng mode được giữ; Trail Off không để lại hình cũ. Apply và kiểm tra tương tự trên màn hình khóa.
6. Đổi bài, đóng/mở YouTube Music, khóa/mở màn hình và mở Control Center; kiểm tra Trail không bám bài cũ, player/artwork/tiến trình vẫn ổn. Đánh giá FPS/nhiệt/pin với Trail On trước khi chốt.

Mốc quay lại: DEB 68 đã giữ trong `packages/` (tên tệp hiện tại `com.luoplayer.ultimatelockscreenplayer_0.1.0-beta.1_68_iphoneos-arm64.deb`, Version bên trong `0.1.0-68`).

## Chẩn đoán sau phản hồi không thấy Trail — 2026-10-10

Người dùng báo không thấy ở Preview và màn hình khóa. Thiết bị đã cài 69; SpringBoard khởi động 20:48 nhưng Settings còn là tiến trình bắt đầu 16:55, trước thời điểm cài dylib 20:43. Đã đóng Settings để lần mở kế tiếp tải bundle mới. Cấu hình đọc từ máy: Waveform có Trail On, Length 0.633 s, Opacity 0.539, Glow 0; mode đang chọn Spectro có Trail mặc định Off. Đây là hai yếu tố cần loại trừ trước khi đổi renderer.

`Probe/TrailProbe` biên dịch trực tiếp renderer và accumulator hiện tại, chạy trong window ẩn riêng trên iPhone, không phát âm thanh hoặc viết preferences. Với `inst.wav`, 180 frame và cấu hình Waveform trên: frame cuối có 3,946 pixel hình hiện tại và 9,520 pixel vệt lưu; ảnh toàn scene có/không lớp Trail cho thấy nét cũ được vẽ và tan theo alpha. Render trung bình 4.58 ms, lớn nhất 11.76 ms trong lần chạy đó (542×965 pixel). Đây là thời gian gọi renderer ở probe, không phải đo FPS/GPU/pin của SpringBoard hay nghiệm thu Preview thực tế.

Giữ nguyên decay: native Length là thời gian tan đến 1%, còn slider demo dùng hằng số suy giảm theo hàm khác, nên cùng giá trị số không có cùng thời gian tan.

Sau khi mở lại Settings, chọn Waveform, bật Trail với Length 1.5 s / Opacity 0.8 và Apply, người dùng xác nhận **đã hiện ở cả Preview và màn hình khóa**. Giữ gói 69, không cần bản sửa renderer cho lỗi không hiện vừa báo. Xác nhận này chốt việc hiển thị ở hai nơi; chưa thay thế kiểm tra các mode còn lại, pause/reset, FPS/nhiệt/pin hoặc độ ổn định khi dùng lâu.

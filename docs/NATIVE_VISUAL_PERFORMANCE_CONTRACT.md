# Giảm tải Cover và quay màn hình — 0.1.0-73

## Phản hồi và phạm vi

Người dùng báo 72 đôi khi có cảm giác tụt FPS; quay màn hình làm giật rõ hơn.
Đã làm rõ máy chỉ hơi ấm, mức ấm này chấp nhận được. Không có bằng chứng máy
đang thermal throttle. Đây là sửa chi phí render, không phải yêu cầu bỏ hiệu ứng
hoặc thay đổi nguồn/DSP âm thanh.

Cấu hình đọc được khi điều tra: Bar, VisualFPS 60, Cover Artwork, Raw reaction 1,
Rumble khoảng 0.136, Drift 0.2, Glow pulse khoảng 0.777; Trail của Bar tắt.
Một lần `ps` ghi Backboardd 39.9% và SpringBoard 14.6%; đây là số CPU của toàn
process, không quy toàn bộ tải cho ULP và không phải số FPS/GPU.

## Quầng sáng

72 thay `shadowRadius` theo envelope mỗi frame. 73 giữ quầng ngoài, nguồn
Raw/Beat, màu Outline và envelope cũ, chuyển sang năm ảnh blur được cache theo
đường kính Cover, hệ tọa độ và màu. Các mức halo là 0.2/0.5/1/1.75/2.5; mức 0
không có ảnh. Chỉ blend tối đa hai ảnh lân cận mỗi frame. Đây là xấp xỉ liên tục
giữa các radius; không hứa đồng nhất pixel của blur động.

Mỗi ảnh tối đa 512×512 px, tổng dữ liệu ảnh tối đa 5 MiB mỗi Cover; mức yếu dùng
quad nhỏ riêng. Các ảnh giữ nguyên khi audio/Spin/Beat/Rumble/Drift chạy và khi
chỉnh cường độ Glow/Glow pulse. Khi tắt pulse dùng shadow tĩnh cũ. Tắt Cover,
ẩn renderer hoặc rời window giải phóng cache; khi trở lại dựng theo cấu hình hiện
tại. Artwork không được render vào ảnh halo, không giảm chất lượng artwork.
Flash vẫn ở trong Cover. Hình ảnh probe so sánh độ loang với 72 được dùng để
hiệu chỉnh blur pixel trong cache.

Bitmap cache dựng ở worker user-initiated bằng context riêng; chỉ gán contents trên
main. Mỗi Cover có tối đa một worker, coalesce thay đổi màu/kích thước và bỏ kết
quả cũ khi scene ẩn hoặc cấu hình đã đổi. Trong lúc chờ dùng Glow tĩnh. Callback
không khôi phục ảnh sau khi đã hidden/rời window. Điều này tránh một lần dựng
toàn bộ blur giữ main thread khoảng 60–70 ms trong bản thử đồng bộ.

Hướng này dựa trên hướng dẫn [Core Animation của Apple](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/ImprovingAnimationPerformance/ImprovingAnimationPerformance.html)
về đo trước tối ưu, giữ hình shadow ổn định để cache và cấp nội dung layer tường
minh. ULP đã có shadowPath; tối ưu lần này tránh thay blur động mỗi frame.

## Ngân sách khi quay/phản chiếu

Khi `UIScreen.isCaptured`, FPS vẽ là `min(FPS đã chọn, 30)` cho nét visualizer,
Cover và bitmap Trail; background zoom cũng giới hạn 30. Khi dừng capture,
khôi phục giới hạn đã chọn, không ghi lại preferences. Background giữ smoothing
theo thời gian và biên độ 8%; các motion dùng clock/dt như trước.

Beat detector tiếp tục phân tích mọi frame âm thanh 60 Hz trước gate vẽ.
Preview vẫn đọc mẫu 60 Hz khi Zoom hoặc Cover dùng Beat; Raw Preview dùng mức
vẽ hiện tại. Timer Drift/settle sẵn có vẫn 30 Hz và dừng khi scene ẩn. Không đổi
DSP64, protocol/server 2.1.1+ulp2, cấu hình detector, Player/artwork/progress hoặc
vòng đời lockscreen. Footer Audio & performance giải thích giới hạn capture.

## Kiểm tra và giới hạn

- C tests: ngân sách capture, FPS thấp hơn 30 được giữ, đầu vào bất thường;
  interpolation opacity hữu hạn, tối đa hai stage và các anchor.
- UIKit BeatProbe: sáu Beat motion, Raw/Beat halo, cache giữ nguyên giữa các
  frame/cường độ chỉnh, kích thước ảnh, timer và ảnh được dọn khi hidden/rời
  window; capture policy giả lập nhận 30 draw trong 60 frame và khi tắt nhận 60,
  vẫn bắt được hit ở cả hai. Fake policy không thay thử notification quay thật.
- CoverPerformance: hai binary cùng workload trên iPhone. CPU software raster
  chỉ phản ánh đường `renderInContext`, không phải GPU/FPS của SpringBoard hoặc
  encoder. Không dùng số đo này để khẳng định hết giật khi quay màn hình.

## Kết quả — 2026-10-10

Build arm64/rootless, toàn bộ C/schema tests và UIKit probe cuối trên iPhone 6s
iOS 15.8.5 đạt. Probe capture giả lập nhận đúng 30/60 và 60/60 draw, mỗi lượt vẫn
có hit. Cache không đổi giữa frame/chỉnh cường độ; đổi màu/kích thước khi worker
đang chạy rồi ẩn scene không phục hồi ảnh cũ. Khi hiện lại dùng cấu hình mới.
Đã so ảnh quầng cache và 72 để hiệu chỉnh độ loang, artwork crop và viền giữ đúng.

So sánh CPU software raster (ms/lượt), baseline 72 là median của ba vòng; bản
73 cuối là một vòng để giới hạn tải probe. Khởi tạo thư viện lạnh cũng nằm trong
chi phí setup đầu tiên, không phải cache mỗi frame.

| Workload | 72 mean / p95 | 73 cuối mean / p95 |
| --- | --- | --- |
| Tĩnh | 13.46 / 22.39 | 12.92 / 16.07 |
| Pulse 0.777 | 35.31 / 66.60 | 20.47 / 24.08 |
| Pulse 0.777 + motion | 49.08 / 90.53 | 26.00 / 33.08 |
| Pulse 1.5 + motion | 113.04 / 227.64 | 27.77 / 33.41 |

Với cache bật, setup foreground cuối khoảng 1.0–1.9 ms; cache sẵn sàng sau
58.7–64.1 ms ở worker. Một lượt thử utility worker trước đó timeout khi chờ 2 s
giữa bài đo dài có tải dao động; đã chuyển user-initiated, coalesce job và giải
phóng autorelease giữa các lượt. Bài đo cuối có giới hạn hoàn tất, nhưng bảng
không thay số GPU/FPS thực hoặc chứng minh encoder hết giật.

DEB cuối đọc toàn bộ thành công: `com.luoplayer.ultimatelockscreenplayer_0.1.0-73_iphoneos-arm64.deb`,
21248080 bytes, SHA-256 `684f5b48ad33d9c83bb70cf8e0c861344cd1fac2276e4113c7a9f36eae3ddc75`.
`packages/SHA256SUMS-73` kiểm tra đạt. Bản chép lên iPhone tại
`/var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-73_iphoneos-arm64.deb`
đã đối chiếu đúng kích thước và SHA-256 ngày 2026-10-11. Đã dọn các executable
probe của đợt này; giữ log và ảnh kiểm tra.

Còn chờ người dùng thử
73 với cùng cấu hình: không quay → quay 10–20 s → dừng quay, thử Preview/lockscreen,
Pause/15 s fade, Player/artwork/progress và quầng Raw/Beat. Không ép bật tối đa
mọi hiệu ứng để nghiệm thu. 72 giữ làm mốc quay lại; độ ổn định dài hạn còn theo dõi.

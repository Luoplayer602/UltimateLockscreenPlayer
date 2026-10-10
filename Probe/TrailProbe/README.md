# Trail renderer probe

Công cụ chẩn đoán arm64/rootless, không đóng gói vào ULP. Biên dịch trực tiếp `ULPVisualizerView` và `ULPTrail` để kiểm tra đường capture/composite/layer bằng UIKit trên iPhone. Tạo window ẩn riêng, không gắn vào giao diện SpringBoard, không phát nhạc và không thay cấu hình.

## Build và chạy

Từ repo, với môi trường Theos đã cấu hình:

```sh
make -C Probe/TrailProbe FINALPACKAGE=1
scp -i ~/.ssh/ulp_iphone Probe/TrailProbe/.theos/obj/ULPTrailProbe \
    mobile@100.65.210.88:/var/jb/var/mobile/ULPTrailProbe-test
ssh -i ~/.ssh/ulp_iphone mobile@100.65.210.88 \
    '/var/jb/var/mobile/ULPTrailProbe-test --audio'
```

Dùng đường dẫn mới nếu đã chép một binary khác vào cùng tên. Trên thiết bị Dopamine đã thử, thực thi từ `/var/mobile` bị SIGKILL; đường dẫn bên trong `/var/jb` chạy được. Không cần cài probe DEB hoặc đổi trust cache thủ công.

- Không có `--audio`: năm frame sóng sin di chuyển, Trail On / Length 2 s / Opacity 1 / Glow 0.
- `--audio`: đọc `inst.wav` của Preferences đã cài; lấy Length/Opacity/Detail/Smooth curve Waveform từ preferences hiện có, dùng PCM 1024 mẫu/64 điểm giống Preview. Chạy 180 frame với khoảng nghỉ 17 ms giữa lần gọi. Màu trắng và viewport 375×667 pt cố định để tách kiểm tra Trail khỏi nền/artwork.
- In mode/Trail đang được loader đọc, số pixel current/history output và thời gian gọi renderer. Không đổi mode đang lưu trên máy.
- Ghi bốn PNG trong `/var/mobile/Library/Caches/ULP/`: `trail-probe-current.png`, `trail-probe-output.png`, `trail-probe-scene-on.png`, `trail-probe-scene-off.png`. Hai ảnh scene render toàn layer tree với nền tối và bật/tắt riêng lớp Trail.

Ảnh scene kiểm tra compositing thực của lớp native. Thời gian renderer ở đây không phải FPS hoặc tải toàn SpringBoard; probe cũng không xác nhận vòng đời Preview/lockscreen đang mở. Đọc `docs/NATIVE_TRAIL_CONTRACT.md` cho kết quả và các bước nghiệm thu thực tế.

Sau khi thu ảnh/log, có thể xóa riêng binary probe đã chép; ULP không cần binary này để chạy.

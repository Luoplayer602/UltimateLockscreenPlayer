# BeatProbe

Probe UIKit chạy process riêng, không attach SpringBoard, không đổi preferences hoặc phát/dừng nhạc. Dùng renderer/cấu hình/Beat detector native chung của Preview và tweak.

```sh
make -C Probe/BeatProbe FINALPACKAGE=1
scp -O -i ~/.ssh/ulp_iphone Probe/BeatProbe/.theos/obj/ULPBeatProbe mobile@100.65.210.88:/var/jb/var/mobile/ULPBeatProbe-test
ssh -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'chmod +x /var/jb/var/mobile/ULPBeatProbe-test && /var/jb/var/mobile/ULPBeatProbe-test'
```

Dopamine cần executable nằm dưới `/var/jb`; dùng tên mới khi thay binary sau lần chạy. Yêu cầu sample `inst.wav` của PreferenceBundle đã cài.

Probe kiểm tra sáu chuyển động, gradient Flash bên trong crop, Raw, nhận hit ở FPS vẽ 15, Pause trả về identity và hủy timer. PNG `beat-<motion>-<preview|lockscreen>.png` trong `/var/mobile/Library/Caches/ULP/`. Thêm chạy detector trên 30 s audio đã cài để kiểm tra có hit hữu hạn, **không** đo độ chính xác ground truth, pin hay FPS/GPU của SpringBoard. Phân tích đoạn sample chỉ phục vụ probe, không có tiền xử lý cả bài trong runtime tweak.

Từ 72 thêm Rumble theo raw, Glow theo Raw/Beat khi reaction strength=0, Drift lúc im lặng/Pause, và timer cleanup khi Off/hidden/rời window. PNG thêm `ambient-raw-<viewport>.png` và `ambient-beat-<viewport>.png`. Đây là kiểm tra renderer riêng, không thay nghiệm thu Settings hoặc hiệu năng SpringBoard.

Từ 73 kiểm tra halo cache giữ nguyên giữa frame/chỉnh cường độ, giới hạn 512 px và giải phóng ảnh khi ẩn/rời window. Gate capture giả lập chấp nhận 30/60 draw với 60 frame phân tích, tắt capture quay về 60/60; cả hai vẫn bắt được hit. Không bật quay màn hình thật trong probe.

# Native Cover probe

Tool arm64/rootless chẩn đoán, không đóng gói vào ULP. Dùng trực tiếp `ULPVisualizerView` và `ULPCoverView` trong window ẩn riêng. Không phát nhạc, gắn vào SpringBoard hoặc ghi preferences.

```sh
make -C Probe/CoverProbe FINALPACKAGE=1
scp -i ~/.ssh/ulp_iphone Probe/CoverProbe/.theos/obj/ULPCoverProbe \
    mobile@100.65.210.88:/var/jb/var/mobile/ULPCoverProbe-test
ssh -i ~/.ssh/ulp_iphone mobile@100.65.210.88 \
    '/var/jb/var/mobile/ULPCoverProbe-test'
```

Dùng tên mới nếu đã chép binary khác vào cùng đường dẫn. Trên Dopamine đã thử, tool chạy từ đường dẫn bên trong `/var/jb`; không cần DEB probe hay thao tác trust cache thủ công.

Kiểm tra hai viewport: 375×667 pt và 343×184 pt. Assertions xác nhận pixel cyan sát mép trên/dưới của crop tròn khi nguồn là ảnh ngang 300×100 px, Spin tiến khi phát và đứng khi Pause, reset góc về 0, visualizer scale/flip/rotation/offset không đổi frame Cover, fallback logo và Off. Ghi các PNG `cover-probe-{art,logo,off}-{lockscreen,preview}.png` trong `/var/mobile/Library/Caches/ULP/` để xem toàn scene. Artwork tổng hợp chỉ dùng cho phép thử full bleed, không thay ảnh của ULP.

Kết quả ban đầu trên iPhone 6s: cả hai viewport PASS, `CoverProbe OK`. Đây là kiểm tra UIKit/compositing và đường cập nhật audio trong process riêng, chưa phải nghiệm thu điều khiển Settings, chất lượng artwork thực, Apply hay hiệu năng SpringBoard. Xóa đúng binary đã chép sau khi thu ảnh/log; ULP không dùng tool này khi chạy.

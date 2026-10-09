# Spectro và vòng đời màn hình khóa — 0.1.0-58

## Hợp đồng cấu hình

Spectro là mode 6 (`spectro`). Cấu hình lưu theo `v1.spectro.<key>`: `VisualPoints`, `InnerRadius`, `RadialBarLength`, `RadialBarThickness`, `RotationSpeed`, `FrequencyRange`, `RadialSymmetry`, `GrowInward`, `RoundedCaps`, `ShowInnerRing`, `RingOpacity`, `PeakCaps`, `PeakCapsType`, `HideVisualizerButPeakCaps`. Cùng một `ULPVisualizerView` được dùng ở Preview và màn hình khóa.

## Hành vi cần nghiệm thu trên iPhone

1. Chọn Spectro, chỉnh Bars, Inner radius, Bar length, Symmetry, Grow inward, Rotation speed; Preview thay đổi và sau Apply màn hình khóa tương ứng.
2. Bật Peak caps, phát nhạc rồi Pause khi peak cao. Peak hạ hẳn về vòng/đường cơ sở trong tối đa khoảng 3 giây, sau đó visualizer đứng yên; Bar cũng phải hạ peak.
3. Sau 15 giây Pause, nền và visualizer mờ dần trong khoảng 0,42 giây, đồng hồ màn hình khóa hiện lại; Player ULP vẫn nằm ở vị trí cũ và điều khiển Play hoạt động. Khi phát lại, nền và visualizer trở lại.
4. Trong lúc visualizer hiện, nhấn phím âm lượng: pill âm lượng xuất hiện rồi tự biến mất. Chạm vùng artwork/tên bài/nền Player: mở ứng dụng nguồn theo cơ chế khóa thông thường; nút Previous/Play/Next vẫn thực hiện lệnh nhạc.
5. Dừng hẳn phiên Now Playing: Player ULP biến mất và media view hệ thống được khôi phục.

Các API ứng dụng nguồn và thông báo âm lượng của SpringBoard là private hoặc phụ thuộc hệ thống. Build không chứng minh được thao tác mở app khi máy khóa hay phản hồi phím âm lượng; hai điểm này cần kiểm tra trực tiếp trên iPhone 6s trước khi coi là hoàn tất.

# Smooth spectro và vị trí Player — 0.1.0-63

## Smooth spectro

Mode 11, ID `smooth-spectro`, khóa `v1.smooth-spectro.*`; schema vẫn là 1. Các ID và cấu hình mode cũ được giữ. Nguồn là spectrum 64 dải của MSH2; Preview phân tích `inst.wav`. Cả hai màn hình dùng cùng `ULPVisualizerView`, hình học và cấu hình; hai nguồn nhạc khác nhau sẽ cho hình khác nhau.

Đường vòng quadratic khép kín nối tiếp tuyến qua điểm cuối/đầu, lấy phổ nội suy và làm mượt attack/release theo thời gian như Spectro. Symmetry 1 chạy phổ theo một vòng; 2–12 gấp phổ thành các đoạn lặp đối xứng. Frequency range chọn tỷ lệ dải từ Visual first/last band.

Bán kính theo cạnh layer: `Size × 0.5 + level × 0.1625 × Reactivity`. Reactivity 0 giữ vòng tĩnh; Zoom vẫn có thể thay đổi kích thước toàn bộ layer. Fill tô bên trong đường vòng; Fill opacity chỉ bật điều khiển khi Fill bật. Rotation speed tính theo thời gian giữa các khung.

| Điều khiển | Khóa | Giới hạn | Mặc định |
| --- | --- | --- | --- |
| Detail | VisualPoints | 12–128, nguyên | 64 |
| Symmetry | RadialSymmetry | 1–12, nguyên | 1 |
| Size | SmoothSpectroSize | 0.1–1 | 0.42 |
| Reactivity | SmoothSpectroReactivity | 0–2 | 0.5 |
| Thickness | Thickness | 0.5–12 pt | 3 |
| Rotation speed | RotationSpeed | -90–90 °/s | 0 |
| Frequency range | FrequencyRange | 0–1 | 1 |
| Fill | SpectrumFill | on/off | off |
| Fill opacity | FillOpacity | 0–1 | 0.2 |

Các nhóm màu, vị trí/kích thước, Zoom, dải âm và FPS hiện có được dùng chung. Waveform smoothing, peak caps, tham số thanh Spectro và đối xứng cũ không hiện trong mode này. Detail trên 64 tăng mật độ nội suy, không tăng độ phân giải nguồn.

## Vị trí Player sau vuốt

Bản 62 quản lý inset nhưng chưa kiểm tra trường hợp UIKit ghi lại offset nghỉ gốc sau chuyển cảnh. Bản 63 ánh xạ offset đó từ `-baseTop` sang `-appliedTop`, trong setter offset, layout, khi CoverSheet xuất hiện xong và lần refresh trình bày tiếp theo. Chỉ áp dụng khi cách offset gốc dưới 2 pt; không hiệu chỉnh lúc tracking/dragging/decelerating và không ép các offset cuộn khác về đầu.

Player vẫn ở native platter và cuộn cùng danh sách. Thêm log `Player list settled` và `CoverSheet settled list` để phân biệt offset chưa phục hồi với thay đổi bố cục native. Log 62 chưa chứa offset nên nguyên nhân này cần xác nhận bằng nghiệm thu 63; nếu còn lỗi, đọc log mới trước khi mở rộng cách hiệu chỉnh.

## Kiểm tra và nghiệm thu

- VisualConfigTests: ID, giới hạn, bán kính im lặng/đỉnh/zero Reactivity và Symmetry. ListPlacementTests: offset nghỉ, không sửa khi tương tác, không sửa offset cuộn, không cộng shift hai lần. SettingsSchemaTests: 12 mode không trùng khóa, đủ loader và điều khiển phụ thuộc.
- Build arm64/rootless cho cả tweak và Preferences; giải nén toàn bộ `.deb`, đối chiếu SHA256 sau khi chép lên iPhone.
- Runtime chờ nghiệm thu: vuốt từ app xuống màn hình khóa, kéo/cuộn và thả, tắt/bật màn hình; Player phải trở lại cùng vị trí nghỉ và vẫn cuộn tự nhiên.
- Chọn Smooth spectro, thử Symmetry 1/2/4, Size/Reactivity (đặt Zoom 0 khi so sánh), Fill/opacity và Rotation speed ±30; đổi qua lại mode để kiểm tra lưu riêng. Apply rồi kiểm tra màn hình khóa, đổi bài, Pause/Resume, seek và đóng/mở YouTube Music.
- Gói quay lại: 0.1.0-62. Lyrics native vẫn chưa tích hợp. Đồng hồ nhấp nháy và tiến trình tiếp tục theo dõi.

## Gói thử đã chuẩn bị

Build arm64/rootless, toàn bộ Tests và `git diff --check` đạt. Đã giải nén đầy đủ archive và chép gói vào `/var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-63_iphoneos-arm64.deb`, đối chiếu SHA256 trên iPhone thành công. Kích thước 21,209,742 byte; SHA256 `d44e88073a06fad64d4652ffc6cb78b52037f5f63201cf1db8dd6b2866006d82`. Chưa cài tự động; chờ người dùng cài và nghiệm thu runtime.

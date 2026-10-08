# Native Bar — hợp đồng cấu hình đợt đầu

Native tiếp tục dùng schema 1 và các khóa hiện có. Chưa cần migration mới vì đợt này không đổi nghĩa hoặc tên khóa. Default, giới hạn và hình học được kiểm tra trong `Tests/`; hành vi Preferences cần xác nhận trên iPhone.

| Trường demo | Khóa native | Mặc định native | Giới hạn native |
| --- | --- | --- | --- |
| `bars` | `v1.bar.VisualPoints` | 32 | 12…128 |
| `barWidth` | `v1.bar.BarWidth` | 0 | 0…24 |
| `spacing` | `v1.bar.BarSpacing` | 0.25 | 0…0.9 |
| `barHeight` | `v1.bar.BarHeight` | 1 | 0.05…1 |
| `cornerRadius` | `v1.bar.BarCornerRadius` | 0 | 0…12 |
| `frequencyRange` | `v1.bar.FrequencyRange` | 1 | 0…1 |
| `mirror` | `v1.bar.SpectrumMirror` | True | on/off |
| `reverse` | `v1.bar.SpectrumReverse` | False | on/off |
| `edgeFade` | `v1.bar.EdgeFade` | 0 | 0…1 |
| `growFrom` | `v1.bar.GrowFrom` | 0 | [0, 1, 2] |
| `minimumHeight` | `v1.bar.MinimumHeight` | 2 | 0…12 |
| `dynamics` | `v1.bar.Dynamics` | 1 | 0.25…4 |
| `peakCaps` | `v1.bar.PeakCaps` | False | on/off |
| `capThickness` | `v1.bar.CapThickness` | 1 | 0.5…6 |
| `horizontalPosition` | `v1.bar.VisualOffsetX` | 0 | -80…80 |
| `verticalPosition` | `v1.bar.VisualOffsetY` | 0 | -80…80 |
| `width` | `v1.bar.VisualWidth` | 1 | 0.25…2 |
| `height` | `v1.bar.VisualHeight` | 1 | 0.25…2 |
| `scale` | `v1.bar.VisualScale` | 1 | 0.5…1.8 |
| `rotation` | `v1.bar.VisualRotation` | 0 | -180…180 |
| `flipHorizontal` | `v1.bar.VisualFlipX` | False | on/off |
| `flipVertical` | `v1.bar.VisualFlipY` | False | on/off |

Giới hạn native hiện được giữ theo renderer hiện có; chưa khẳng định tương đương hoàn toàn với giới hạn demo. `VisualEnabled` và `VisualFPS` dùng chung, còn các khóa trong bảng lưu riêng theo mode.

## Gói thử 0.1.0-54

- Mỗi hàng plist có ID riêng; metadata/điều kiện mode được ghép bằng ID. Không còn phụ thuộc thứ tự mảng specifier do Preferences trả về.
- Modes là hàng điều hướng và được controller xử lý khi chạm.
- Slider dùng UISlider, nhãn, giá trị và mô tả do ULP bố trí; số nguyên được làm tròn trước khi lưu. Phần mô tả nằm dưới thanh trượt.
- Chỉnh thông số gọi refresh preview ngay. Reset position giữ contentOffset của bảng.
- Bar dùng renderer native đang có, chung giữa preview và màn hình khóa. Chưa port các nhóm hiệu ứng mới của demo hoặc Lyrics.

## Cần xác nhận trên iPhone

1. Mở Visualizer và Modes; chọn Bar: chỉ có một Bars, không có Rows/Dot size/Shape.
2. Phát preview, đặt Bars 32, Spacing 0.5, Scale 1.3. Chuyển Equalizer rồi trở lại Bar: giá trị còn nguyên.
3. Mirror và Reverse làm đổi cách phân bố phổ; Peak caps bật/tắt khả năng chỉnh Cap thickness.
4. Cuộn tới Position & size, thay slider và Reset: giữ vị trí cuộn. Apply rồi xem Bar trên màn hình khóa.
5. Kiểm tra Settings không crash và Player vẫn đổi bài/cuộn được.

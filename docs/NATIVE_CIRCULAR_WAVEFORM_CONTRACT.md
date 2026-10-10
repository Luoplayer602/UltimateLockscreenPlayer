# Circular waveform native — 0.1.0-61

## Mốc so sánh

Bản 0.1.0-60 đã đạt nghiệm thu ban đầu; độ ổn định khi dùng lâu vẫn đang theo dõi. Mã nguồn ở commit `14fe988116ca29e91431b9abfa72b81dd1bce721`. Gói quay lại: `packages/com.luoplayer.ultimatelockscreenplayer_0.1.0-60_iphoneos-arm64.deb`, SHA-256 `31681b98966186146e20a9e439eef1b1b77bb06415ecdafb6b2d85fb6d350678`.

## Cấu hình

Giữ schema 1 và các ID cũ. Mode mới có ID số 10, ID lưu `circular-waveform`, khóa `v1.circular-waveform.<setting>`. Loader hiện có đọc các trường tương ứng; chọn mode này không migrate hoặc ghi đè cấu hình của mode khác. VisualEnabled và VisualFPS tiếp tục dùng chung.

| Điều khiển | Khóa | Mặc định | Giới hạn |
| --- | --- | --- | --- |
| Detail | VisualPoints | 64 | 12–128, số nguyên |
| Inner radius | InnerRadius | 0.38 | 0.1–0.8 |
| Amplitude | WaveAmplitude | 1 | 0–2 |
| Thickness | Thickness | 3 pt | 0.5–12 pt |
| Rotation speed | RotationSpeed | 0 | −90 đến +90 °/s |
| Fill ring | SpectrumFill | Off | On/Off |
| Fill opacity | FillOpacity | 0.2 | 0–1; vô hiệu khi Fill ring tắt |
| Waveform smoothing | WaveSmoothing | 0 | 0–1, ở Audio & performance |

Colour, Position & size, Zoom và FPS vẫn có hiệu lực. Không hiện thông số thanh Spectro, đối xứng spectrum, Centre gap hoặc dải Visual vì mode này đọc PCM.

## Hình học và âm thanh

- `ULPVisualizerView` dùng chung trong PreferenceBundle và SpringBoard. Nguồn vòng là 64 mẫu PCM có dấu; Detail trên 64 chỉ nội suy.
- Bán kính cơ sở bằng `Inner radius × cạnh layer / 2`. PCM dương nở ra, âm co vào; biên độ tối đa trước giới hạn bằng `Amplitude × 0.1375 × cạnh layer`. Bán kính được giới hạn từ 0.01 đến 0.49 cạnh để tránh xuyên tâm hoặc vượt layer ở mức cực đại.
- Nội suy tuần hoàn nối mẫu cuối với mẫu đầu. Các đoạn quadratic kín chia sẻ tiếp tuyến tại chỗ nối; không tạo đối xứng hoặc thêm sóng sin.
- Fill ring dùng hai đường kín và quy tắc even-odd để tô phần nằm giữa sóng và vòng cơ sở. Cả hai cùng xấp xỉ đường cong nên PCM im lặng hoặc Amplitude = 0 không để lại vệt màu giả. Cover/ULP nằm trên lớp sóng như các mode tròn hiện có.
- Rotation speed tích lũy theo thời gian giữa các frame, hỗ trợ hai chiều. Các timer và quy tắc Pause/15 giây của bản 0.1.0-60 tiếp tục được dùng.

Preview phát inst.wav; màn hình khóa đọc âm thanh Now Playing. Cùng renderer không có nghĩa hai hình giống từng frame khi nguồn nhạc khác nhau. Chưa đo FPS hoặc tải thực tế của mode mới trên iPhone 6s.

## Kiểm tra cục bộ

`make -C Tests test`: PCM có dấu, nối mẫu qua seam, bán kính ở mức cực đại và im lặng, dữ liệu không hữu hạn, cấu hình/default/giới hạn và hàng Settings của 11 mode. Build cả tweak và PreferenceBundle bằng SDK 15.6 cho arm64/rootless.

Gói 0.1.0-61 đã giải nén kiểm tra toàn bộ archive, chép tới `/var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-61_iphoneos-arm64.deb` và so sánh SHA-256 trên iPhone: `0ba902e001ea95bd6e73445b90c7b317d71131b0f44ed3a471544f2c8e1e895b`. Thiết bị vẫn đang cài 0.1.0-60; bản 61 chờ người dùng cài/nghiệm thu.

## Nghiệm thu trên iPhone

1. Đóng hẳn Settings sau khi cài, mở ULP → Visualizer → Modes → Circular waveform. Phát Preview; chỉnh Detail, Inner radius, Amplitude và Thickness, mỗi điều khiển phải đổi hình rõ ràng. Amplitude = 0 phải về vòng cơ sở.
2. Bật Fill ring, đổi Fill opacity từ 0 đến 1; tâm không bị tô kín. Tắt Fill ring phải bỏ màu fill và vô hiệu slider opacity. Thử Rotation speed −30, 0, +30: ngược chiều, đứng yên, cùng chiều kim đồng hồ.
3. Chỉnh Scale, chuyển sang Spectro/Waveform rồi quay lại; giá trị từng mode phải được giữ riêng. Apply và xem Circular waveform trên màn hình khóa.
4. Thử đoạn yên lặng/nhạc lớn, đổi bài, Pause rồi Play, khóa/tắt/bật màn hình, cuộn Player và phím âm lượng. So sánh Player/artwork/đồng hồ/HUD với bản 0.1.0-60.
5. Theo dõi độ mượt ở FPS 30 và 60, tải khi phát lâu. Nếu lỗi, ghi chuỗi thao tác và đọc `/var/mobile/Library/Logs/ULP.log`; quay lại gói 0.1.0-60 khi cần.

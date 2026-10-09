# Native Waveform và Mirror — 0.1.0-55

0.1.0-54 đã được người dùng nghiệm thu ngày 2026-10-09. Đây là bước tiếp theo của renderer native; Lyrics vẫn tạm dừng.

## Hành vi

- Waveform vẽ mẫu âm thanh có dấu quanh đường giữa. Không dùng spectrum hoặc sóng sin giả khi thiếu waveform.
- Mirror dùng trị tuyệt đối của cùng waveform cho nhánh trên và phản chiếu chính xác xuống nhánh dưới. Centre gap tách hai nhánh; Fill tô vùng giữa hai nhánh.
- Hai mode có Thickness, Amplitude, Detail, Fill, Fill opacity, Waveform smoothing. Waveform có Smooth curve; Mirror luôn dùng đường cong mượt.
- Đường ngang rộng khoảng 85% khung trước khi áp dụng Width/Scale. Thickness, gap và offset cùng quy đổi theo chiều rộng để preview và màn hình khóa giữ tỷ lệ.
- `Visualization/ULPWaveform.c` xử lý lấy mẫu/nội suy/làm mượt cho renderer dùng chung trong SpringBoard và Preferences. Smoothing dùng delta thời gian.

## Cấu hình

Giữ schema 1. Mode Waveform giữ ID số 5 và khóa `v1.waveform.*`. Mirror có ID 9 và khóa `v1.mirror.*`; không đổi ID các mode cũ.

| Thuộc tính | Khóa | Mặc định | Giới hạn |
| --- | --- | --- | --- |
| Thickness | Thickness | 3 | 0.5–12 |
| Amplitude | WaveAmplitude | 1 | 0–2 |
| Detail | VisualPoints | 64 | 12–128 |
| Smooth curve | SmoothCurve | On | Waveform |
| Centre gap | CentreGap | 12 | 0–80, Mirror |
| Fill | SpectrumFill | Off | On/Off |
| Fill opacity | FillOpacity | 0.2 | 0–1 |
| Waveform smoothing | WaveSmoothing | 0 | 0–1 |

Các khóa chung Width/Height/Scale/vị trí/màu được giữ lại. Waveform không còn dùng VisualAnimationScale hoặc VisualSymmetry; khóa cũ vẫn còn để quay lại gói trước. Các thông số mới bắt đầu ở mặc định trên. Dải Visual của spectrum không hiện trong hai mode này vì waveform hiện đọc toàn bộ tín hiệu. Dải Zoom vẫn có tác dụng riêng.

## Giới hạn của lần chuyển này

MSH2 gửi 64 mẫu waveform từ cửa sổ 1024 mẫu PCM. Preview đã dùng cùng cửa sổ và stride. Detail >64 chỉ nội suy, không tạo thêm thông tin âm thanh. Chưa thêm lọc EQ/dải âm waveform của demo vì cần thực hiện trước khi giảm số mẫu ở nguồn capture. Spectrum/Zoom của preview vẫn dùng bộ phân tích hiện có, chưa khẳng định tín hiệu của cả scene giống nhau hoàn toàn.

## Kiểm tra

`make -C Tests test` kiểm tra dấu PCM, nội suy biên, đối xứng Mirror/gap, thiếu waveform, giá trị không hữu hạn, smoothing theo delta thời gian và cấu hình riêng của 10 mode.

Trên iPhone: chọn Waveform, phát preview; đổi Amplitude, Detail, Smooth curve, Fill. Chọn Mirror, đổi Centre gap và Fill. Chuyển mode qua lại để kiểm tra lưu riêng. Apply và phát nhạc trên màn hình khóa; kiểm tra hình, scale, độ mượt, Player và thao tác cuộn. Gói 0.1.0-54 là mốc quay lại đã nghiệm thu.

## Sửa phản ứng sóng — 0.1.0-56

Sau khi cài 0.1.0-55, người dùng báo Waveform phẳng hơn và rung khác trước. Nguyên nhân là lấy trung bình các mẫu PCM của các khung không cùng pha với thời gian làm mượt quá dài. Giá trị mặc định của Waveform smoothing là 0 để giữ đúng chuyển động mẫu hiện tại; khi tăng thanh này, khoảng làm mượt được giới hạn ở mức nhẹ. Không thay đổi dữ liệu PCM từ AudioSnapshotServer2, kích thước đường sóng hay các giá trị đã lưu của người dùng. Sau khi cài gói mới cần đóng hẳn Settings để nạp lại PreferenceBundle.

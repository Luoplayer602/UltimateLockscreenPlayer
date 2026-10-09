# Siri native — 0.1.0-57

Siri (mode ID 4, khóa `v1.siri.*`) dùng 64 mẫu waveform có dấu từ MSH2. Preview lấy mẫu từ cùng cửa sổ PCM 1024 mẫu và dùng cùng `ULPVisualizerView` với màn hình khóa. Khi không có waveform, hình thu về đường giữa; không tổng hợp sóng sin từ spectrum.

Ba lớp dùng cùng mẫu và cùng Detail. Biên độ mỗi lớp lần lượt là 100%, 78%, 56%. Envelope `sin(πu)^0.65` đưa hai đầu đường về đường giữa. Các lớp sau nhạt màu hơn; màu nền tảng lấy từ artwork hoặc màu thủ công như các mode khác. Fill của mỗi lớp nằm giữa sóng và đường giữa.

Siri có Thickness 0.5–12 (mặc định 3), Amplitude 0–2 (1), Detail 12–128 (64), Smooth curve (bật), Fill (tắt), Fill opacity 0–1 (0.2) và Waveform smoothing 0–1 (0). Position, Scale, Zoom, Colour và FPS dùng các điều khiển chung. Các khóa `v1.siri.VisualAnimationScale`, `VisualSymmetry` và dải Visual cũ được giữ trong preferences để quay về bản cũ nhưng không còn điều khiển Siri mới.

Nghiệm thu trên iPhone: trong Modes chọn Siri, phát Preview và kiểm tra ba đường phản ứng với nhạc, thu về hai đầu; chỉnh Amplitude, Detail, Smooth curve, Fill và Scale; Apply rồi so hình trên màn hình khóa. Đổi qua Waveform/Mirror và trở lại để xác nhận mỗi mode giữ giá trị riêng; kiểm tra Player, đổi bài và tạm dừng. Sau khi nâng cấp, đóng hẳn Settings để nạp lại PreferenceBundle. Mốc quay lại đã nghiệm thu là 0.1.0-56.

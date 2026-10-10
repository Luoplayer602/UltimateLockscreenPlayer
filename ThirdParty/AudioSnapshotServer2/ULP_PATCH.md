# ULP mono capture patch

Nguồn gốc: [AudioSnapshotServer2](https://github.com/ryannair05/AudioSnapshotServer2), giấy phép MIT trong `LICENSE`.

Bản `2.1.1+ulp1-1`: `CaptureEngine.cpp` nhận PCM float32 mono khi `mFormatFlags` có hoặc không có `kAudioFormatFlagIsNonInterleaved`. Với một kênh, cả hai trường hợp đều dùng một buffer chứa các mẫu float32 liên tiếp.

Bản thử `2.1.1+ulp2` giữ capture đó và thêm profile spectrum theo Preview của ULP: cùng `../../Audio/ULPPreviewSpectrum.c` (1024 mẫu, 64 tần số Goertzel, gain cố định), bỏ chuẩn hóa dB và smoothing riêng của spectrum. Macro `ULP_PREVIEW_SPECTRUM=0` giữ FFT cũ. Build từ cây UltimateLockscreenPlayer để có DSP chung. Xem `../../docs/NATIVE_COLOUR_BACKGROUND_DSP_CONTRACT.md` cho giới hạn/nghiệm thu. LICENSE upstream được giữ.

Trên iPhone 6s/iOS 15.8.5, AudioUnit của `mediaserverd` báo `subtype=mcmx`, `format=lpcm`, `flags=0x29`, 48 kHz, một kênh, 32 bit, 4 byte/frame, tối đa 4096 frame. Điều kiện upstream loại định dạng này, khiến server có candidate nhưng không có active source và không gửi feature packet.

Đây là gói thử nghiệm thay thế phiên bản Chariz 2.1. Sau khi xác nhận hoạt động, cần quyết định gửi bản vá upstream hoặc duy trì gói tương thích riêng; không gộp mã nguồn server vào gói ULP chính.

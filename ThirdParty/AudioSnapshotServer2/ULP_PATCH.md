# ULP mono capture patch

Nguồn gốc: [AudioSnapshotServer2](https://github.com/ryannair05/AudioSnapshotServer2), giấy phép MIT trong `LICENSE`.

Thay đổi duy nhất trong mã nguồn upstream: `CaptureEngine.cpp` nhận PCM float32 mono khi `mFormatFlags` có hoặc không có `kAudioFormatFlagIsNonInterleaved`. Với một kênh, cả hai trường hợp đều dùng một buffer chứa các mẫu float32 liên tiếp.

Trên iPhone 6s/iOS 15.8.5, AudioUnit của `mediaserverd` báo `subtype=mcmx`, `format=lpcm`, `flags=0x29`, 48 kHz, một kênh, 32 bit, 4 byte/frame, tối đa 4096 frame. Điều kiện upstream loại định dạng này, khiến server có candidate nhưng không có active source và không gửi feature packet.

Đây là gói thử nghiệm thay thế phiên bản Chariz 2.1. Sau khi xác nhận hoạt động, cần quyết định gửi bản vá upstream hoặc duy trì gói tương thích riêng; không gộp mã nguồn server vào gói ULP chính.

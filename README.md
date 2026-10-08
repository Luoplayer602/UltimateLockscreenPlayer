# UltimateLockscreenPlayer

Tweak Theos cho màn hình khóa iOS 15 jailbreak **rootless**. Player preset 01 dựa trên mốc giao diện 0.1.0-33; visualizer và Settings đang được phát triển tiếp.

## Cấu trúc

- `Makefile`: cấu hình build với SDK iOS 15.6, deployment target 15.0 và kiến trúc `arm64`.
- `Tweak.xm`: nối Now Playing, âm thanh, Player, visualizer và nền vào màn hình khóa.
- `Audio/MSH2Protocol.h` và `.c`: mã hóa/giải mã giao thức MSH2 của AudioSnapshotServer2.
- `Audio/MSH2Client.h` và `.m`: client UDP loopback gia hạn lease, nhận và kiểm tra feature packet.
- `Playback/ULPLifecycle.h` và `.c`: trạng thái `playing → pause-pending → hidden` với thời gian chờ 15 giây, độc lập với UI.
- `Playback/ULPNowPlaying.h` và `.m`: adapter MediaRemote đọc metadata, trạng thái phát và gửi lệnh điều khiển Player.
- `Visualization/`: đọc dải phổ tần, cấu hình có giới hạn và tải tùy chọn visualizer; dải visualizer và zoom độc lập.
- `UI/ULPLockScreenView.m`: Player preset 01 trong vùng Player gốc để giữ thao tác cuộn và điều khiển.
- `UI/ULPVisualizerView.m`: Spectrum Bar, Equalizer ô vuông, Line, Dot ma trận; cùng các mode Waveform, Siri, Circle classic, Spectro và Dotted orbit hiện có. Cùng renderer được dùng trong Preview và màn hình khóa.
- `Probe/`: công cụ chẩn đoán MSH2, gồm gói tạm `ServerProbe` cho `mediaserverd`.
- `ThirdParty/AudioSnapshotServer2/`: bản vá nguồn capture mono Float32 cho iPhone 6s; xem `ULP_PATCH.md` trước khi đóng gói.
- `Preferences/`: `Cài đặt → ULP → Visualizer`, picker Modes chia ba nhóm và chỉ hiện thông số của mode đang chọn. Mỗi mode lưu giá trị riêng. Preview nhỏ phát lặp `inst.wav`, cố định khi cuộn, ẩn Pause khi phát và hiện lại khi chạm. Nhấn Apply để Respring; Preview đọc cấu hình mỗi giây.
- `Tests/`: kiểm tra parser, vòng đời phát nhạc, tín hiệu, giới hạn cấu hình, thứ tự tần số mirror/reverse và tính nhất quán của các điều khiển theo mode trên WSL.
- `UltimateLockscreenPlayer.plist`: chỉ nạp tweak vào SpringBoard.
- `control`: metadata cho gói Debian `iphoneos-arm64`.

## Build trên WSL Ubuntu 24.04

Cấu hình visualizer dùng schema 1: `SelectedVisualMode` và các khóa `v1.<mode-id>.<setting>`. Khi mở trang Visualizer lần đầu, các giá trị cũ được chép sang mode đang dùng; khóa cũ vẫn được giữ để có thể cài lại 0.1.0-49. Các mode khác bắt đầu bằng giá trị mặc định riêng. `VisualEnabled` và `VisualFPS` dùng chung.

Yêu cầu biến `THEOS` trỏ đến bản cài Theos có SDK `iPhoneOS15.6.sdk` và toolchain Linux. Đặt tệp nhạc mẫu `inst.wav` trong `demo-ui/audio/` trước khi build; tệp này bị Git bỏ qua và được đóng gói vào Preview. Từ thư mục dự án:

```sh
export THEOS="$HOME/theos"
make package
make -C Tests test
```

Gói `.deb` được tạo trong `packages/`. Cấu hình này xây dựng bản `arm64`; hỗ trợ hook các tiến trình hệ thống `arm64e` trên một số thiết bị iOS 15 có thể cần toolchain ABI mới trên macOS. ULP cần [AudioSnapshotServer2](https://github.com/ryannair05/AudioSnapshotServer2) đã vá và cài riêng trên iPhone; xem `ThirdParty/AudioSnapshotServer2/ULP_PATCH.md`. Bản 2.1 từ Chariz không phát feature packet trên iPhone 6s thử nghiệm. Kết quả hiện đã thử trên iPhone 6s, iOS 15.8.5, Dopamine; chưa xác nhận tương thích rộng.

Trên iPhone 6s thử nghiệm, máy không có tiện ích `log` của Apple (`log` trong `zsh` là shell builtin). Từ ULP `0.1.0-8`, đọc log chẩn đoán bằng `tail -f /var/mobile/Library/Logs/ULP.log` qua SSH. Log chỉ chứa trạng thái và đặc trưng âm thanh, không ghi PCM.

## Kết nối SSH với iPhone Dopamine

1. Jailbreak và cài gói OpenSSH trong Sileo trên iPhone. Đảm bảo iPhone và PC ở cùng mạng Wi-Fi.
2. Xem IP iPhone trong `Cài đặt → Wi-Fi → ⓘ` của mạng đang dùng. Trong WSL, chạy `ssh mobile@<IP-iPhone>`; xác nhận fingerprint ở lần đầu và nhập mật khẩu `mobile` đã đặt trong Dopamine. Mật khẩu không hiện khi gõ.
3. Kiểm tra bằng `uname -a` và `ls /var/jb`; dùng `exit` để thoát. Khi cần cài gói, chuyển `.deb` bằng `scp` vào thư mục của `mobile`, rồi cài trên iPhone bằng `sudo dpkg -i <tên-gói.deb>`.

Đổi mật khẩu SSH mặc định hoặc yếu của `mobile` và `root` trong Dopamine trước khi sử dụng. Nếu kết nối bị từ chối, kiểm tra OpenSSH và dịch vụ SSH; nếu quá thời gian, kiểm tra IP, Wi-Fi và khả năng hai thiết bị nhìn thấy nhau. Dự án chưa tự cài gói lên điện thoại.

Nếu dùng SSH key, tạo bằng `ssh-keygen -t ed25519 -f ~/.ssh/ulp_iphone`, thêm public key bằng `ssh-copy-id -i ~/.ssh/ulp_iphone.pub mobile@<IP-iPhone>` và kiểm tra bằng `ssh -i ~/.ssh/ulp_iphone mobile@<IP-iPhone> 'uname -m'`. Chỉ nhập mật khẩu trên terminal của bạn.

## Demo giao diện trên máy tính

Mở [`demo-ui/index.html`](demo-ui/index.html) trong trình duyệt. Xem [`demo-ui/README.md`](demo-ui/README.md) để nạp nhạc và artwork thử nghiệm.

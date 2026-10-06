# UltimateLockscreenPlayer

Khung tweak Theos cho SpringBoard trên iOS 15 jailbreak **rootless**.

## Cấu trúc

- `Makefile`: cấu hình build với SDK iOS 15.6, deployment target 15.0 và kiến trúc `arm64`.
- `Tweak.xm`: nạp probe âm thanh khi `Enabled` bật; chưa hook giao diện màn hình khóa.
- `Audio/MSH2Protocol.h` và `.c`: mã hóa/giải mã giao thức MSH2 của AudioSnapshotServer2.
- `Audio/MSH2Client.h` và `.m`: client UDP loopback gia hạn lease, nhận và kiểm tra feature packet.
- `Playback/ULPLifecycle.h` và `.c`: trạng thái `playing → pause-pending → hidden` với thời gian chờ 15 giây, độc lập với UI.
- `Playback/ULPNowPlaying.h` và `.m`: adapter MediaRemote đọc metadata và trạng thái phát mỗi giây, chuẩn bị lệnh điều khiển Player.
- `Visualization/ULPSignal.h` và `.c`: đọc hai dải phổ tần độc lập cho visualizer và zoom, có làm mượt attack/release.
- `UI/ULPLockScreenView.h` và `.m`: giao diện thử circle và Player gọn trên CoverSheet iOS 15; đang kiểm tra trực tiếp trên iPhone.
- `Probe/`: công cụ chẩn đoán MSH2, gồm gói tạm `ServerProbe` cho `mediaserverd`.
- `ThirdParty/AudioSnapshotServer2/`: bản vá nguồn capture mono Float32 cho iPhone 6s; xem `ULP_PATCH.md` trước khi đóng gói.
- `Preferences/`: trang `Cài đặt → ULP` tối thiểu với công tắc tổng mặc định tắt. Ở mốc M1, công tắc chỉ bật probe âm thanh và cần respring sau khi đổi.
- `Tests/`: kiểm tra parser trên WSL.
- `UltimateLockscreenPlayer.plist`: chỉ nạp tweak vào SpringBoard.
- `control`: metadata cho gói Debian `iphoneos-arm64`.

## Build trên WSL Ubuntu 24.04

Yêu cầu biến `THEOS` trỏ đến bản cài Theos có SDK `iPhoneOS15.6.sdk` và toolchain Linux. Từ thư mục dự án:

```sh
export THEOS="$HOME/theos"
make package
make -C Tests test
```

Gói `.deb` được tạo trong `packages/`. Cấu hình này xây dựng bản `arm64`; hỗ trợ hook các tiến trình hệ thống `arm64e` trên một số thiết bị iOS 15 có thể cần toolchain ABI mới trên macOS. Probe M1 cần cài [AudioSnapshotServer2](https://github.com/ryannair05/AudioSnapshotServer2) riêng trên iPhone; gói ULP chưa tự mang server này theo. Bản `2.1` từ Chariz đã không phát feature packet trên iPhone 6s thử nghiệm. Bản vá ở `ThirdParty/AudioSnapshotServer2` đã cho phép client nhận đặc trưng âm thanh từ app Nhạc iOS. Đây mới là kết quả thử nghiệm trên một thiết bị, chưa là xác nhận tương thích rộng.

Trên iPhone 6s thử nghiệm, máy không có tiện ích `log` của Apple (`log` trong `zsh` là shell builtin). Từ ULP `0.1.0-8`, đọc log chẩn đoán bằng `tail -f /var/mobile/Library/Logs/ULP.log` qua SSH. Log chỉ chứa trạng thái và đặc trưng âm thanh, không ghi PCM.

## Kết nối SSH với iPhone Dopamine

1. Jailbreak và cài gói OpenSSH trong Sileo trên iPhone. Đảm bảo iPhone và PC ở cùng mạng Wi-Fi.
2. Xem IP iPhone trong `Cài đặt → Wi-Fi → ⓘ` của mạng đang dùng. Trong WSL, chạy `ssh mobile@<IP-iPhone>`; xác nhận fingerprint ở lần đầu và nhập mật khẩu `mobile` đã đặt trong Dopamine. Mật khẩu không hiện khi gõ.
3. Kiểm tra bằng `uname -a` và `ls /var/jb`; dùng `exit` để thoát. Khi cần cài gói, chuyển `.deb` bằng `scp` vào thư mục của `mobile`, rồi cài trên iPhone bằng `sudo dpkg -i <tên-gói.deb>`.

Đổi mật khẩu SSH mặc định hoặc yếu của `mobile` và `root` trong Dopamine trước khi sử dụng. Nếu kết nối bị từ chối, kiểm tra OpenSSH và dịch vụ SSH; nếu quá thời gian, kiểm tra IP, Wi-Fi và khả năng hai thiết bị nhìn thấy nhau. Dự án chưa tự cài gói lên điện thoại.

Nếu dùng SSH key, tạo bằng `ssh-keygen -t ed25519 -f ~/.ssh/ulp_iphone`, thêm public key bằng `ssh-copy-id -i ~/.ssh/ulp_iphone.pub mobile@<IP-iPhone>` và kiểm tra bằng `ssh -i ~/.ssh/ulp_iphone mobile@<IP-iPhone> 'uname -m'`. Chỉ nhập mật khẩu trên terminal của bạn.

## Demo giao diện trên máy tính

Mở [`demo-ui/index.html`](demo-ui/index.html) trong trình duyệt. Xem [`demo-ui/README.md`](demo-ui/README.md) để nạp nhạc và artwork thử nghiệm.

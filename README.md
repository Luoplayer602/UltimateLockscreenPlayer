# UltimateLockscreenPlayer

**UltimateLockscreenPlayer (ULP)** là tweak cho màn hình khóa iOS 15 jailbreak rootless, kết hợp player Now Playing tùy chỉnh với visualizer phản ứng theo âm thanh đang phát.

## Giới thiệu

- Player hiển thị tên bài, nghệ sĩ, artwork, điều khiển phát nhạc và tiến trình chạy quanh viền. Chạm player để mở ứng dụng nhạc qua cơ chế của hệ thống.
- 12 mode: **Bar, Equalizer, Line, Dot, Waveform, Mirror, Siri, Circle classic, Spectro, Circular waveform, Smooth spectro và Dotted orbit**.
- Mỗi mode lưu cấu hình riêng, có các điều khiển màu, nền, kích thước, vị trí và phản ứng âm thanh tương ứng.
- Nền Colour/Gradient và ba kiểu artwork: **Scaled dim image, Center dim image + blur, Blur background**. Ảnh giữa được bo góc, giữ tỷ lệ và zoom theo nhạc; nguồn artwork lớn có fallback khi chưa lấy được ảnh tốt hơn.
- Preview trong Settings dùng chung renderer native với màn hình khóa. Chỉnh tại **Cài đặt → ULP → Visualizer**, nhấn **Apply** để respring và áp dụng.
- HUD âm lượng riêng, chuyển cảnh mờ dần sau thời gian chờ 15 giây khi tạm dừng và cơ chế kiểm tra/phục hồi player khi phiên nhạc thay đổi.

**Trạng thái:** đang chuẩn bị pre-release. Bản 67 đã được nghiệm thu trên iPhone; bản 68 bổ sung bo góc ảnh giữa. Độ ổn định khi dùng lâu vẫn tiếp tục được theo dõi.

**Thiết bị đã thử:** iPhone 6s, iOS 15.8.5, Dopamine; các chuỗi phục hồi được thử với YouTube Music. Gói hiện tại là `iphoneos-arm64`/rootless. Chưa xác nhận tương thích với mọi thiết bị, jailbreak hay ứng dụng nhạc; không có gói rootful hoặc arm64e trong đợt này.

## Cấu trúc

| Thư mục/tệp | Vai trò |
| --- | --- |
| `Tweak.xm` | Gắn ULP vào màn hình khóa, điều phối player, visualizer, nền và HUD. |
| `Audio/` | Client/giao thức MSH2 và DSP spectrum dùng chung giữa Preview với server mod. |
| `Playback/` | Now Playing, vòng đời, tiến trình, vị trí player và nguồn artwork lớn. |
| `Visualization/` | Cấu hình theo mode, tín hiệu, waveform và màu/hình học. |
| `UI/` | Player, visualizer, nền artwork và HUD âm lượng native. |
| `Preferences/` | Trang Cài đặt ULP, chọn mode/màu, slider và Preview. |
| `ThirdParty/AudioSnapshotServer2/` | Nguồn AudioSnapshotServer2 đã vá; build thành **gói riêng**. |
| `demo-ui/` | Prototype HTML/CSS/JavaScript để thử giao diện và hiệu ứng trên trình duyệt. |
| `Tests/` | Kiểm tra giao thức, tín hiệu, cấu hình, tiến trình, artwork và bố cục. |
| `Probe/` | Công cụ chẩn đoán tạm; không cần cài để dùng ULP. |
| `docs/` | Hợp đồng triển khai, nghiệm thu và [bản nháp release notes](docs/PRE_RELEASE_NOTES.md). |
| `Makefile`, `control` | Cấu hình Theos và metadata gói Debian. |

## Cài bằng DEB

### Hai gói cần có

1. **AudioSnapshotServer2 mod `2.1.1+ulp2`** — đọc âm thanh và cung cấp dữ liệu cho visualizer. Có bản vá capture mono và spectrum theo Preview của ULP.
2. **UltimateLockscreenPlayer** — player, hiệu ứng và Settings.

Gói mod dùng cùng package ID `com.ryannair05.audiosnapshotserver2`, nên thay thế bản AudioSnapshotServer2 hiện có. Không cài hai bản server song song. ULP không đóng gói server bên trong; cần cả hai gói cho visualizer trên màn hình khóa.

Gói sau khi build nằm tại `packages/` và `ThirdParty/AudioSnapshotServer2/packages/`. Khi pre-release được đăng, hai DEB sẽ là các tệp đính kèm trên [trang Releases](https://github.com/Luoplayer602/UltimateLockscreenPlayer/releases).

Có thể mở DEB bằng Sileo để cài **server trước, ULP sau**, rồi khởi động lại `mediaserverd` và respring. Hoặc dùng SSH; iPhone cần OpenSSH và tài khoản `mobile` có quyền `sudo`.

Trên máy tính, từ thư mục repo, thay IP ví dụ bằng IP iPhone:

```sh
ULP_IPHONE="192.168.1.100"
scp ThirdParty/AudioSnapshotServer2/packages/com.ryannair05.audiosnapshotserver2_2.1.1+ulp2_iphoneos-arm64.deb \
    packages/com.luoplayer.ultimatelockscreenplayer_0.1.0-68_iphoneos-arm64.deb \
    mobile@"$ULP_IPHONE":/var/mobile/
ssh -t mobile@"$ULP_IPHONE"
```

Trong shell iPhone:

```sh
sudo dpkg -i /var/mobile/com.ryannair05.audiosnapshotserver2_2.1.1+ulp2_iphoneos-arm64.deb \
             /var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-68_iphoneos-arm64.deb && \
sudo killall mediaserverd && \
sudo killall SpringBoard
```

Đóng hẳn Settings và dừng nhạc/Preview trước khi cập nhật. Respring không bảo đảm Settings đang mở sẽ tải lại PreferenceBundle: trang có thể hiện điều khiển mới từ plist nhưng Preview vẫn chạy renderer của bản trước. Nếu đã cập nhật khi Settings còn mở, đóng Settings từ app switcher hoặc chạy `killall Preferences` trong shell iPhone rồi mở lại. Nếu server mod đã đúng phiên bản, chỉ cập nhật DEB ULP rồi respring. Nếu dùng SSH key, thêm `-i ~/.ssh/ulp_iphone` vào `scp`/`ssh`. Với phiên bản khác, thay đúng tên DEB của bản đó.

Sau khi cài, mở **Cài đặt → ULP**, bật tweak/visualizer, chọn mode và Apply. Phát nhạc rồi mở màn hình khóa để kiểm tra. Đọc log trên iPhone:

```sh
tail -f /var/mobile/Library/Logs/ULP.log
```

Nếu cài báo archive bị cắt hoặc lỗi giải nén, chép lại DEB và đối chiếu `sha256sum` trên máy tính/iPhone trước khi cài lại. Để quay về mốc đã nghiệm thu, cài lại ULP `0.1.0-67` rồi respring; server `2.1.1+ulp2` giữ nguyên.

## Build from source

Môi trường đã dùng: **WSL Ubuntu 24.04**, Theos, toolchain iOS cho Linux và **iPhoneOS15.6.sdk**. Cấu hình hiện tại: deployment target iOS 15.0, `ARCHS=arm64`, `THEOS_PACKAGE_SCHEME=rootless`.

1. Cài Theos/toolchain theo [hướng dẫn Linux/WSL chính thức](https://theos.dev/docs/installation-linux), có `iPhoneOS15.6.sdk` trong `$THEOS/sdks/`. Cần Git, Python 3 và C compiler/Make cho bộ kiểm tra.
2. Clone repo:

   ```sh
   git clone https://github.com/Luoplayer602/UltimateLockscreenPlayer.git
   cd UltimateLockscreenPlayer
   export THEOS="$HOME/theos"
   ```

3. Đặt file nhạc mẫu của bạn tại **`demo-ui/audio/inst.wav`**. File này không được Git theo dõi nhưng được đóng gói vào Settings Preview; thiếu file sẽ khiến build Preferences dừng.
4. Kiểm tra và build **cả hai gói** từ cây repo đầy đủ:

   ```sh
   make -C Tests test
   make -C ThirdParty/AudioSnapshotServer2 package FINALPACKAGE=1 THEOS_PACKAGE_BASE_VERSION=2.1.1+ulp2
   make package FINALPACKAGE=1 THEOS_PACKAGE_BASE_VERSION=0.1.0-68
   ```

Server mod biên dịch DSP chung trong `Audio/ULPPreviewSpectrum.c`; không tách thư mục server khỏi repo khi build. Xem [ULP_PATCH.md](ThirdParty/AudioSnapshotServer2/ULP_PATCH.md) cho bản vá, nguồn upstream và giới hạn.

Đầu ra:

```text
ThirdParty/AudioSnapshotServer2/packages/com.ryannair05.audiosnapshotserver2_2.1.1+ulp2_iphoneos-arm64.deb
packages/com.luoplayer.ultimatelockscreenplayer_0.1.0-68_iphoneos-arm64.deb
```

Build/Tests đạt chưa thay thế nghiệm thu trên iPhone. Preview đọc file local, màn hình khóa đọc âm thanh hệ thống; cùng DSP/renderer không bảo đảm hai nguồn PCM giống tuyệt đối.

## Xem demo-ui

Từ thư mục repo:

```sh
python3 demo-ui/server.py
```

Mở URL được in sau `ULP demo UI:`, mặc định **http://127.0.0.1:8765/**. Nếu cổng mặc định bận, server tự chọn cổng trống. Đổi cổng bằng `python3 demo-ui/server.py --port 8766`.

- Nhấn Play để dùng `audio/inst.wav`, hoặc chọn file tại **Nhạc thử**; chọn ảnh tại **Artwork**.
- Nút Home tròn chuyển giữa màn hình khóa giả lập và Cài đặt ULP.
- Chọn mode, thử Preview và Apply để xem thay đổi trên màn hình khóa giả lập.
- `/volume-hud.html` cho phép thử HUD bằng nút +/− hoặc phím ↑/↓.

Demo là prototype có phạm vi tính năng riêng và không đọc Now Playing của iOS. Âm thanh đến từ file trong trình duyệt, Apply chỉ tác động lên demo; dùng bản native để đánh giá hook và hiệu năng trên iPhone. Chi tiết ở [demo-ui/README.md](demo-ui/README.md).

## Credits / Special thanks

- **[luoplayer602](https://github.com/luoplayer602)** — phát triển ULP, thiết kế giao diện, bản vá tích hợp và nghiệm thu trên thiết bị.
- **[Ryan Nair / AudioSnapshotServer2](https://github.com/ryannair05/AudioSnapshotServer2)** — nguồn capture âm thanh và server MSH2. Bản mod giữ [giấy phép MIT và copyright upstream](ThirdParty/AudioSnapshotServer2/LICENSE).
- **[Theos](https://theos.dev/)** và cộng đồng phát triển tweak — công cụ build, Logos và tài liệu.
- **[Music Visualizer Lab](https://musicvisualizerlab.com/editor)** — tham khảo hình dạng waveform/mirror và cách tổ chức trình chỉnh visualizer.
- **Người dùng thử nghiệm và cộng đồng jailbreak** — phản hồi về chuyển cảnh, phục hồi player/artwork, tiến trình và trải nghiệm âm thanh.

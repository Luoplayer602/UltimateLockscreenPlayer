# ULP 64 — Preview làm chuẩn, Colour và Background

## Hướng đã chốt

Người dùng muốn âm thanh thật có hình phổ/nhịp đập gần Preview đã nghiệm thu. Không thay Preview sang phổ FFT cũ. Độ phân giải phổ không đồng nghĩa chất lượng hiệu ứng: server cũ có chuẩn hóa dB tương đối, ngưỡng 36 dB và smoothing 35/180 ms trước khi renderer/Zoom của ULP tiếp tục làm mượt. Preview dùng phổ trực tiếp, gain cố định và thứ tự tần số khác. Đây là các khác biệt có cơ sở trong mã; cảm giác trên nhạc thật vẫn cần nghiệm thu.

## DSP và hai gói thử

- ULP `0.1.0-64`, server `2.1.1+ulp2`; iPhone trước đợt này đang ở ULP 63 và server `2.1.1+ulp1-1`.
- `Audio/ULPPreviewSpectrum.c` tách từ Preview: 1024 mẫu PCM mới nhất, 64 tần số `45 × 1.1^band` Hz, biên độ `sqrt(power) × 24 / 1024`, giới hạn 0–1. Preview và server biên dịch cùng nguồn C.
- Server lấy 1024 mẫu cuối của rolling window hiện có. Profile này không áp dụng Hann, chuẩn hóa dB, ngưỡng tương đối hoặc smoothing riêng cho phổ. Capture, chọn nguồn, activity gate, waveform, RMS/peak và giao thức MSH2 giữ nguyên. Renderer và Zoom của ULP giữ như bản Preview đã chốt.
- Preview giữ kênh đầu tiên của file để bảo toàn mẫu đã nghiệm thu; server vẫn nhận mono hoặc trộn stereo. Khác PCM, thời điểm lấy cửa sổ, sample rate hoặc xử lý hệ thống khiến chưa bảo đảm giống tuyệt đối. Phải cài cả server; renderer không thể phục hồi các dải đã bị loại.
- Thuật toán FFT cũ vẫn build được với `ULP_PREVIEW_SPECTRUM=0`. Profile mới áp dụng cho các subscriber spectrum của server này. Goertzel có 64 × 1024 bước/khung; hiệu năng/pin trên iPhone 6s cần nghiệm thu, không suy ra từ WSL.

## Colour

| Điều khiển | Khóa | Hành vi |
| --- | --- | --- |
| Mode | ColourMode | Solid 0 / Gradient 1 / Artwork 2 |
| Colour 1 | VisualColor | Color picker, bật với Solid/Gradient |
| Colour 2 | VisualColor2 | Color picker, chỉ bật với Gradient |
| Gradient angle | GradientAngle | 0–360°, chỉ bật với Gradient |
| Opacity / Glow | VisualOpacity / VisualGlow | Giữ điều khiển hiện có |

Mỗi mode giữ khóa `v1.<mode-id>.*`, schema 1. Gradient dùng mask các shape native; Artwork dùng màu trung bình artwork. VisualColor cũ được giữ. Khi thiếu ColourMode, loader và Settings suy ra Solid/Artwork từ VisualAutoColor cũ. UIKit color picker lưu #RRGGBB, giữ vị trí cuộn trang.

## Background

- BackgroundMode Colour/Gradient áp dụng khi không có artwork hoặc Artwork background tắt. BackgroundColor1/2 là picker, Colour 2 chỉ bật khi chọn Gradient.
- ArtworkBackground on/off, mặc định on. ArtworkBackgroundType chỉ bật khi switch on.
- Type 0: ảnh dim aspect-fill toàn bộ nền. Type 1: ảnh dim aspect-fit giữa vùng màn hình nhìn thấy, giữ tỷ lệ vuông/ngang/dọc; bản blur aspect-fill phía sau che kín khoảng trống. Type 2 mặc định: chỉ nền blur dim aspect-fill.
- Blur được cache theo ảnh, xử lý kích thước tối đa 512 và clamp mép. Nền di chuyển/nền cố định dùng lại ảnh blur. Ảnh giữa có viewport riêng khỏi overscan để không lệch lên trên.
- Preview và lockscreen dùng cùng ULPBackgroundView. Preview lấy artwork từ MediaRemote hoặc `/var/mobile/Library/Caches/ULP/preview-artwork.jpg` do SpringBoard ghi, giữ ảnh khi phát inst.wav. Cache chỉ chứa artwork hiện tại, xóa lúc khởi động tweak/đổi bài/mất phiên; queue ghi nối tiếp, không chạy trên luồng capture. Khi không có ảnh, Preview dùng Colour/Gradient.

## Kiểm tra / nghiệm thu

- Tests WSL: xung bass lên ngay, cửa sổ im lặng không giữ release tail ở output DSP, bỏ mẫu cũ ngoài 1024, treble nhỏ, dữ liệu không hữu hạn, giới hạn màu/kiểu nền, hướng gradient, đủ loader/dependencies cho 12 mode.
- Đối chiếu với Goertzel trong Preview cũ từ HEAD: sai số lớn nhất 0 trên 16 tín hiệu thử ở 44.1/48 kHz. Chưa phải so sánh nguồn âm trên iPhone.
- Build riêng hai gói arm64/rootless; giải nén toàn bộ archive và đối chiếu SHA256 sau SCP. Chờ người dùng cài qua sudo.
- Log 63 có nhiều lần offset nghỉ -617/inset 617; chưa nghiệm thu bằng ảnh nên tiếp tục thử vị trí sau vuốt. Vòng đời Player/đồng hồ/HUD không đổi trong đợt 64.

Ưu tiên thử cùng đoạn bass/drum, mode Bar và cấu hình sau Apply, so Preview với lockscreen. Sau đó thử mode khác, Pause/Resume, Colour, gradient angle/opacity/glow, ba kiểu nền, ảnh vuông/ngang, bài không artwork, đổi bài và đóng/mở YouTube Music. Log ULP bổ sung band 8/16/32/48/63 để đối chiếu khi phản hồi chưa đạt.

Quay lại: ULP 63 + server `2.1.1+ulp1-1`, khởi động lại mediaserverd và SpringBoard sau cài. Lyrics, Trail, cover và Beat motion chưa triển khai đợt này.

## Cài thử và quay lại

Đóng hẳn Settings và dừng nhạc/Preview trước khi cài. Chạy trên WSL (nhập mật khẩu sudo trong terminal):

```sh
ssh -tt -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'sudo dpkg -i /var/mobile/com.ryannair05.audiosnapshotserver2_2.1.1+ulp2_iphoneos-arm64.deb /var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-64_iphoneos-arm64.deb && sudo killall mediaserverd && sudo killall SpringBoard'
```

Để quay lại cả âm thanh và giao diện:

```sh
ssh -tt -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'sudo dpkg -i /var/mobile/com.ryannair05.audiosnapshotserver2_2.1.1+ulp1-1_iphoneos-arm64.deb /var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-63_iphoneos-arm64.deb && sudo killall mediaserverd && sudo killall SpringBoard'
```

Giữ hai gói server riêng với gói ULP để có thể đối chiếu spectrum cũ/mới trên cùng renderer. Cài lại riêng ULP sẽ không quay lại thuật toán phổ cũ.

## Gói đã chép và kiểm tra

Ba archive đã giải nén đầy đủ và đối chiếu SHA256 trên iPhone thành công, đặt tại `/var/mobile/`. Chưa cài tự động, chờ nghiệm thu runtime.

| Gói | Byte | SHA256 |
| --- | --- | --- |
| ULP 0.1.0-64 | 21216540 | 581a3ad6d7d4ea5cdaa3722c9db99cad13dea5a2ca84ee27c85ed646240fc236 |
| Server 2.1.1+ulp2 | 17928 | 9f96096f43db3110cbfdd4fb4a23b9f46ff0e8e5dc73598d95c78f8a262e65e0 |
| Server quay lại 2.1.1+ulp1-1 | 20004 | 46431d6bd0a3e3bd0b65c9d9b8510f6dff8a2309f523d80811ba5f263330212c |

## Bổ sung 65: điều hướng chọn kiểu và màu

Phản ứng DSP 64 tạm đạt theo nghiệm thu của người dùng. Không đổi nguồn, DSP, renderer, Player hay vòng đời lockscreen trong 65.

Tất cả `PSLinkListCell` và các hàng `ulpColorPicker` của Visualizer chỉ định `ULPStylePickerController` làm `detail`. Mảng lựa chọn được chuyển nguyên vẹn qua `ulpChoiceValues`/`ulpChoiceTitles` theo ID, không phụ thuộc các biến đổi nội bộ của Preferences. Trang riêng gọi `performGetter`/`performSetterWithValue:` trên chính source specifier; khóa đã prefix theo mode được giữ nguyên. Colour dùng editor RGB, palette, hex và swatch riêng thay cho presentation của UIColorPicker. Mã hex không hợp lệ không ghi đè màu đã lưu.

Bộ kiểm tra schema xác nhận tất cả lựa chọn có controller và mảng dữ liệu đầy đủ; build arm64 và giải nén toàn bộ archive đạt. Không có môi trường UIKit iOS trên host, nên kết quả thao tác/presentation, cuộn khi quay lại và persistence cần nghiệm thu trên thiết bị.

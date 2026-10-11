# Beat detector và Beat motion — 0.1.0-71

## Phạm vi

Sau ảnh Cover bản 70, người dùng yêu cầu tiếp tục nhóm Beat detector và đủ sáu Beat motion. Preview và màn hình khóa dùng chung `ULPBeat.c`, `ULPVisualizerView` và `ULPCoverView`. Giữ DSP64/server mod 2.1.1+ulp2, artwork, nền, player, tiến trình, phục hồi và Trail đã đạt.

## Dữ liệu và giới hạn

- Detector đọc phổ DSP64 **trước** smoothing, chọn mode, dải Visual/Zoom và giới hạn FPS vẽ. Bốn vùng tần số 45–180, 180–650, 650–2800, 2800–12000 Hz; bỏ vùng vượt 47% sample rate.
- Log compression + mức nền thích ứng của từng band làm nổi biến đổi tăng; ngưỡng dựa trên trung bình/phương sai novelty trong quá khứ. Tham khảo khái niệm [spectral flux của aubio](https://aubio.org/doc/0.4.6/specdesc_8h.html) và [adaptive whitening](https://aubio.org/doc/latest/awhitening_8h.html). Đây là mã riêng cho dữ liệu DSP64 của ULP, không tích hợp thư viện aubio.
- RMS gate loại im lặng; khởi động/đổi stream/sample rate/gap >0.5 s priming lại, không đánh nhịp vào frame đầu. Mỗi nhịp có cường độ và thời gian tối thiểu giữa hai hit. Bộ nhớ cố định, không request mạng hoặc phân tích trước cả bài trong runtime.
- Đây là bắt **onset**, không khóa BPM và không tự tạo nhịp trong đoạn không có transient. Có thể bắt attack của nhạc cụ khác, hoặc bỏ sót kick bị che/saturation. DSP64 đã clamp ở 1, detector không khôi phục thông tin bị mất và không có khả năng tách riêng stem. Không hứa độ chính xác tương đương bộ phân tích toàn bài.
- Native nhận feature 60 Hz. Khi dùng Beat detect, Preview lấy mẫu 60 Hz dù FPS vẽ thấp hơn; renderer vẫn theo VisualFPS. Cùng thuật toán/cấu hình, nhưng vị trí sample và thời điểm packet khác nhau có thể tạo chênh lệch nhỏ giữa Preview và phát thật.

## Cấu hình

Giữ schema 1, khóa `v1.<mode>.<setting>`; tất cả mode có điều khiển. Giá trị mặc định giữ phản ứng Visualizer/Cover của bản 70 cho đến khi chủ động bật.

| Điều khiển | Khóa | Mặc định | Giới hạn |
| --- | --- | --- | --- |
| Zoom: React to beat type | `VisualReactType` | Raw (0) | Raw (0), Beat detect (1) |
| Zoom strength (cũ) | `VisualZoomStrength` | 0.18 | 0–0.4 |
| Cover: React to beat type | `CoverReactType` | Beat detect (1) | Raw (0), Beat detect (1) |
| Cover: React to beat | `CoverReaction` | 0 | 0–1 |
| Cover: Beat motion | `BeatMotion` | Bounce (4) | Swell 0, Flash 1, Shake 2, Spin 3, Bounce 4, Wobble 5 |
| Beat sensitivity | `BeatSensitivity` | 1 | 0.5–2 |
| Minimum beat interval · s | `BeatInterval` | 0.2 | 0.12–0.5 |
| Beat release · s | `BeatRelease` | 0.2 | 0.08–0.6 |

Zoom Raw dùng mức âm và dải Zoom cũ. Zoom Beat detect dùng envelope của detector; dải Zoom đầu/cuối khóa khi chọn Beat detect. Nét/biên độ waveform và phổ vẫn phản ứng theo âm thanh gốc, không bị thay bằng nhịp giả. Beat release chỉnh envelope Zoom, không kéo dài tùy tiện thời gian của Beat motion.

Cover Raw zoom theo mức âm được làm mượt, Beat motion khóa. Cover Beat detect dùng hit/cường độ chung với Visualizer. Cover Off khóa nguồn/cường độ/motion; các điều kiện kết hợp AND dùng `ulpRequirements`. Thay đổi dependencies giữ content offset. Reset Cover xóa thêm CoverReactType/CoverReaction/BeatMotion, không xóa tham số detector hoặc Zoom/Trail/nền.

## Sáu chuyển động

| Motion | Hành vi |
| --- | --- |
| Swell | Zoom nhanh, attack 45 ms, về cỡ ban đầu trong 320 ms. |
| Flash | Gradient trắng sáng bên **trong** crop tròn, attack 18 ms rồi giảm; không tăng Glow ngoài viền. |
| Shake | Rung X/Y nhanh, biên độ tắt dần, trở về tâm. |
| Spin | Zoom giật nhanh + xoay clockwise nhẹ, trở về góc ban đầu trong 480 ms. |
| Bounce | Zoom lên chậm hơn (190 ms), hạ chậm hơn; tổng 800 ms. |
| Wobble | Rung nhẹ X/Y và xoay nhẹ qua lại, tổng 700 ms. |

Hit mới bắt đầu từ pose hiện tại và nhả pose cũ trong 120 ms để không bật giật về tâm giữa hai kick. Motion tính theo thời gian thực, có giới hạn scale/offset/rotation. Scale Cover giữ hình tròn và viền; Spin liên tục bản 70 chỉ xoay rotor bên trong và vẫn độc lập với Beat motion Spin.

Pause dừng Spin liên tục ngay. Cover hoàn thành motion còn lại rồi về tâm/cỡ gốc, Raw cũng hạ về cỡ gốc. Timer phụ 30 Hz chỉ hoàn tất phản ứng khi audio dừng/stall; tự hủy khi đã settle, khi ẩn hoặc rời window. Không tạo hit mới trong timer. Đổi bài/PID/lặp Preview reset detector/motion; nâng chất lượng artwork cùng bài không reset. Trail chỉ lưu nét visualizer, không chụp Cover hay Flash.

## Kiểm tra và nghiệm thu

- `make -C Tests test`: hồi quy hiện có; onsets dưới lớp âm giữ nguyên, silence/constant input, interval, sensitivity, reset stream/gap/clock, không phụ thuộc FPS vẽ; sáu motion hữu hạn, khác nhau, retrigger liên tục và về identity. Schema/dependencies/defaults kiểm tra cho 12 mode.
- `Probe/BeatProbe` chạy đạt trên iPhone 6s: sáu motion ở viewport Preview/lockscreen, Flash trong crop, Raw, đường nhận audio 60 Hz khi vẽ 15 FPS, Pause settle/Spin dừng/timer hủy. 30 s `inst.wav` có 71 onset, không có giá trị NaN. Con số này chỉ xác nhận đường xử lý trên âm thanh thật, không chứng minh độ chính xác nhịp hoặc FPS/pin SpringBoard.
- Log runtime khi dùng Beat detect: `Beat count=… pulse=… score=… motion=… coverReaction=…`, tối đa một dòng/2 s.

Trên iPhone: đóng Settings sau cập nhật DEB. Cover Artwork, React to beat khoảng 0.6, Beat detect; thử đủ sáu motion trong Preview rồi Apply. Zoom chọn Beat detect, thử sensitivity 0.8/1.5 và interval 0.2/0.3. Raw phải khóa Beat motion và đổi về zoom liên tục. Pause giữa Bounce/Spin phải về tâm/cỡ gốc; đổi bài, khóa/mở, đóng/mở YouTube Music giữ player/artwork/tiến trình. Bật Trail để kiểm tra Cover không lưu bóng cũ. Theo dõi nhiệt/pin khi dùng đồng thời Trail/Glow/motion.

Mốc quay lại của 71: ULP 70; không đổi server. Người dùng đã nghiệm thu các hiệu ứng bước đầu và yêu cầu tiếp tục theo dõi khi dùng lâu.

## Gói thử

`com.luoplayer.ultimatelockscreenplayer_0.1.0-71_iphoneos-arm64.deb`, Version `0.1.0-71`, 21,242,968 bytes. SHA-256 `98fb9cab0fd8f9686c8b31b4270398e1455d4432aef08e1ba674160c45f1a673`. Build tweak/Preferences arm64/rootless đạt, không có warning/error compiler; đã đọc hết `data.tar` và kiểm tra `packages/SHA256SUMS-71`. Giữ gói/checksum 70 và checksum pre-release đã có.

Đã chép vào `/var/mobile` và đối chiếu SHA-256 khớp trước khi đổi tên từ `.part`. Lần SFTP đầu bị ngắt; truyền lại bằng `scp -O` hoàn tất. Người dùng đã cài 71, xác nhận các hiệu ứng nghiệm thu đạt nhưng vẫn cần thời gian kiểm chứng. Không coi đây là kết quả đo pin/FPS hoặc chứng minh detector chính xác với mọi bài.

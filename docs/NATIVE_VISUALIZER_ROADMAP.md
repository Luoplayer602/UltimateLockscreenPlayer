# Lộ trình đưa Visualizer từ demo sang tweak thật

Trạng thái: kế hoạch triển khai sau bản native 0.1.0-51 và prototype `demo-ui/`. **Lyrics tạm dừng; không thêm trang hay mã Lyrics vào gói iPhone trong giai đoạn này.** Player preset 01 và hành vi màn hình khóa đã chốt được giữ làm mốc hồi quy.

## Quyết định triển khai

Chuẩn hóa trang Cài đặt là bước kế tiếp, nhưng bắt đầu từ hợp đồng cấu hình và các điều khiển có tác dụng thật. Native hiện dùng `VisualSchemaVersion=1`, `SelectedVisualMode`, khóa `v1.<mode>.<setting>` và `Visualizer.plist` dài hơn 1.000 dòng. `ULPVisualConfig` và renderer hiện chỉ có một phần thuộc tính của demo. Vì vậy không chép toàn bộ giao diện demo vào plist trước khi renderer hỗ trợ.

## Thứ tự công việc

1. **Khóa baseline native.** Build và chạy bộ `Tests/` hiện có; ghi lại hình Settings, preview và màn hình khóa trên iPhone 6s. Kiểm tra lại mode picker, nhãn trùng và cuộn/Apply, vì bản thử 0.1.0-51 đã từng có lỗi ở các vùng này. Giữ gói cũ để quay lại khi cần.
2. **Chuẩn hóa schema và lưu cấu hình.** Lập bảng ánh xạ `demo-ui/settings-schema.js` ↔ `ULPVisualConfig` ↔ khóa plist. Chỉ giữ mode được renderer native hỗ trợ; thêm khóa/giá trị mặc định/giới hạn cho từng nhóm theo lát triển khai. Migrate từ schema 1 mà không xóa khóa cũ, để cấu hình hiện tại của người dùng không mất. Mỗi mode giữ cấu hình riêng; các mục dùng chung được định nghĩa một lần.
3. **Sửa cấu trúc Settings.** Root: Enabled, Visualizer, GitHub, Apply. Visualizer: preview cố định, Visual enabled, Modes, thông số riêng của mode, rồi Colour, Position & size, Background, Effects, Cover và Audio response khi những nhóm này hoạt động. Loại nhãn trùng, slider quá cao, giá trị bị cắt và thao tác picker không phản hồi. Toggle/select/reset/colour cập nhật preview mà không kéo trang về đầu. Không thêm Lyrics hoặc Merged presets vào native lúc này.
4. **Chuyển renderer theo từng lát.** Ưu tiên Bar, Equalizer, Line, Dot và Waveform/Mirror để kiểm chứng phổ, PCM, đối xứng và hình học. Sau đó Siri, Spectro, Circular waveform, Smooth spectro. Mỗi lát có cấu hình, renderer, preview và Settings đi cùng nhau. Tham số chưa có hiệu lực chưa xuất hiện trong Settings.
5. **Đồng bộ hiệu ứng dùng chung.** Đưa nền artwork, màu, cover, beat detector/6 Beat motion, zoom, Trail, position/size và audio response sang native theo cùng quy tắc của demo. Kiểm tra preview dùng đúng renderer/cấu hình của màn hình khóa; mức zoom và cover phải khớp khi phát cùng dữ liệu âm thanh.
6. **Kiểm tra trên iPhone 6s.** Với mỗi lát: build, unit test cho giới hạn cấu hình, cài gói thử, kiểm tra Settings không crash, Apply/Respring, hình khóa khi phát/đổi bài/tạm dừng, rồi đo FPS và tải khi bật hiệu ứng. Chỉ coi một mode hoàn thành sau khi điều khiển của nó tạo thay đổi nhìn thấy được trên preview lẫn màn hình khóa.

## Bước code đầu tiên

Tạo bảng ánh xạ từ các trường demo sang cấu hình native và chọn một lát nhỏ để triển khai end-to-end. Lát đầu đề xuất **Bar + cấu trúc trang Visualizer**: mode picker hoạt động, Bars/Spacing/Bar height/Mirror/Reverse/Scale lưu riêng, preview phản ứng ngay và màn hình khóa nhận giá trị sau Apply. Đây là phép thử cho schema và luồng Settings trước khi mở rộng sang các mode khác.

## Ngoài phạm vi hiện tại

- Lyrics, API Unison, dịch/phiên âm và trang YouTube Music native.
- Merged presets, import/export và layout Player mới.
- Khẳng định tương thích iPhone khác trước khi kiểm tra thiết bị thực tế.

## Tiến độ — 0.1.0-54

Đã kiểm tra iPhone đang ở 0.1.0-51. Đợt đầu giữ schema 1 và renderer Bar hiện có, chuẩn hóa liên kết hàng Settings bằng ID, mở Modes trực tiếp, thay bố cục slider và refresh preview khi chỉnh. Đã build gói arm64/rootless và chạy bộ Tests thành công; kết quả runtime trên iPhone còn chờ xác nhận. Xem `NATIVE_BAR_SETTINGS_CONTRACT.md` để biết ánh xạ và các bước thử.

## Tiến độ — 0.1.0-55

Người dùng đã nghiệm thu 0.1.0-54. Bước tiếp theo bổ sung Waveform có dấu và Mirror từ cùng dữ liệu, bộ xử lý chung và các điều khiển tương ứng; xem `NATIVE_WAVEFORM_CONTRACT.md`. Đã hoàn thành mã và test cục bộ, đang chuẩn bị thử native trên iPhone.

## Tiến độ — 0.1.0-56

0.1.0-55 đã cài trên iPhone. Trang Mirror và Fill hoạt động sau khi đóng và mở lại Settings, nhưng người dùng báo Waveform phẳng và rung khác trước. Sửa mặc định Waveform smoothing về 0 và giảm thời gian làm mượt khi chủ động tăng slider; cần nghiệm thu lại Preview và màn hình khóa trên iPhone.

## Tiến độ — 0.1.0-57

Người dùng đã nghiệm thu lại Waveform trên 0.1.0-56. Siri chuyển sang cùng nguồn PCM và hình học với Waveform, có ba lớp giảm biên độ từ trước ra sau và envelope thu về đường giữa ở hai đầu. Settings Siri giờ có Thickness, Amplitude, Detail, Smooth curve, Fill và Waveform smoothing; các mục spectrum/Shape cũ không còn hiện với Siri. Preview và màn hình khóa dùng cùng renderer. Chờ kiểm tra bản 0.1.0-57 trên iPhone.

## Tiến độ — 0.1.0-58

Người dùng đã nghiệm thu Siri 0.1.0-57. Spectro native nay có thanh phổ, bán kính trong, chiều dài/độ dày, tốc độ xoay, đối xứng theo đoạn, hướng phát triển, vòng trong và peak caps dạng line/dot. Các điều khiển này có trong Settings và dùng chung renderer với Preview. Khi Pause, một timer cấp khung im lặng tới khi peak caps hạ về đường cơ sở rồi mới đóng băng; sau 15 giây visualizer/nền mờ dần và Player ULP giữ nguyên nếu phiên Now Playing còn tồn tại. Player nhận thao tác chạm để mở ứng dụng phát qua LaunchServices; chỉ báo âm lượng nghe thay đổi hệ thống. Đã build và test cục bộ; các hành vi riêng SpringBoard cần xác nhận trên iPhone. Xem `NATIVE_SPECTRO_LOCKSCREEN_CONTRACT.md`.

## Nghiệm thu 0.1.0-58 và bước kế tiếp

Spectro, peak caps và chuyển cảnh đạt. Còn lỗi đồng hồ sau khi tắt/bật màn hình, Player/artwork sau khi khởi động lại YouTube Music, chạm Player không mở app và HUD âm lượng không hiện. Kế hoạch sửa đồng thời thêm HUD riêng ở `NATIVE_LOCKSCREEN_RECOVERY_PLAN.md`.

## Sau nghiệm thu ban đầu 0.1.0-60

Người dùng xác nhận 0.1.0-60 hoạt động ổn trong lần nghiệm thu đầu. Giữ gói và mã nguồn bản này làm mốc để so sánh; tiếp tục theo dõi khi dùng lâu, nhất là nhiều lần khóa/mở màn hình, đổi bài, đóng/mở ứng dụng nhạc, cuộn Player, thay đổi âm lượng ở hai đầu dải và tiêu thụ tài nguyên. Nếu xuất hiện lỗi, ghi đúng chuỗi thao tác và đọc `/var/mobile/Library/Logs/ULP.log` trước khi thay đổi thêm vòng đời màn hình khóa.

Lát triển khai tiếp theo là **Circular waveform**. Dùng cùng dữ liệu waveform có dấu và cùng `ULPVisualizerView` ở Preview/màn hình khóa. Bổ sung `Detail`, `Inner radius`, `Amplitude`, `Thickness`, `Rotation speed`, `Fill ring`, `Fill opacity` với khóa riêng của mode, giá trị mặc định và giới hạn rõ ràng; Settings chỉ hiện các điều khiển có tác dụng. Cấu hình của các mode hiện tại phải được giữ nguyên khi đổi qua lại và sau Apply. Kiểm tra hình vòng ở đoạn yên lặng, âm lượng lớn, đổi bài và Pause; đo FPS trên iPhone 6s trước khi nghiệm thu.

Sau khi Circular waveform đạt, triển khai **Smooth spectro** từ dữ liệu spectrum. Các nhóm dùng chung như màu, nền, Trail, cover và Beat motion tiếp tục theo lát nhỏ sau hai mode tròn này. Lyrics native vẫn tạm dừng theo quyết định đã chốt.

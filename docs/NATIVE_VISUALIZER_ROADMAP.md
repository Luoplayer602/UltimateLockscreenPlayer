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

## Triển khai — 0.1.0-61

Mốc mã nguồn 0.1.0-60: commit `14fe988116ca29e91431b9abfa72b81dd1bce721`; giữ gói 0.1.0-60 trong `packages/` để quay lại. Circular waveform là mode 10, dùng PCM có dấu và khóa riêng `v1.circular-waveform.*`. Vòng nối mượt qua điểm cuối/đầu; Fill ring tô giữa đường sóng với vòng cơ sở và để tâm trong suốt. Đã thêm đủ bảy điều khiển riêng cùng Waveform smoothing ở Audio & performance; Preview và màn hình khóa cùng dùng renderer native này. Build arm64/rootless và bộ Tests đạt; hình ảnh, FPS và các chuỗi khóa/mở màn hình cần nghiệm thu trên iPhone. Xem `NATIVE_CIRCULAR_WAVEFORM_CONTRACT.md`.

## Ưu tiên phục hồi — 0.1.0-62

Người dùng báo lỗi Player/artwork sau khi đóng/mở ứng dụng nhạc, vị trí và tiến trình không ổn định khi dùng lâu. Ưu tiên sửa các lỗi này trước Smooth spectro; xem `NATIVE_PLAYER_RECOVERY_CONTRACT.md`. Đã có log tái hiện bản 61 xác nhận phiên mới vẫn phát nhưng artwork thiếu, và padding danh sách bám nhầm base tạm. Đồng hồ nhấp nháy được giữ trong danh sách theo dõi.

## Smooth spectro và vị trí sau vuốt — 0.1.0-63

Người dùng tạm nghiệm thu phục hồi Player/artwork của 62 sau nhiều lần đóng/mở YouTube Music. Triển khai Smooth spectro (mode 11) và kiểm tra offset nghỉ khi kết thúc chuyển cảnh, giữ Player trong native host. Đủ 9 điều khiển riêng, Preview và màn hình khóa dùng chung renderer. Xem `NATIVE_SMOOTH_SPECTRO_CONTRACT.md` cho ánh xạ, giới hạn và nghiệm thu. Sau khi bản này đạt, nhóm tiếp theo là màu/nền dùng chung; tiếp tục theo dõi phục hồi, vị trí, tiến trình và đồng hồ.

## Preview làm chuẩn, Colour và Background — 0.1.0-64

Người dùng chốt giữ phản ứng của Preview, chỉnh phần thật về gần Preview. ULP 64 và server 2.1.1+ulp2 dùng cùng DSP tách từ Preview cũ. Hoàn thiện Colour Solid/Gradient/Artwork, Background Colour/Gradient + ba kiểu artwork, color picker và dependencies. Xem `NATIVE_COLOUR_BACKGROUND_DSP_CONTRACT.md`. Nhịp đập thật và hiệu năng còn cần nghiệm thu; sau khi đạt mới triển khai Trail, cover và toàn bộ Beat motion.

## Sửa trang chọn Colour/Background — 0.1.0-65

Người dùng tạm nghiệm thu phản ứng DSP của 64; giữ nguyên DSP và server 2.1.1+ulp2. Các trang Colour, Colour mode và Artwork background type bị đen trên máy thật. Bản 65 gán controller riêng cho tất cả các enum và colour links của Visualizer, thay vì để Preferences tự chọn trang con. Controller hỗ trợ cả đường điều hướng qua `detail` và thao tác table trực tiếp. Các enum có dấu chọn; màu có preview swatch, RGB, palette và mã hex, lưu qua setter của source specifier để giữ schema theo mode và cập nhật dependencies/preview. Khi quay lại, cập nhật hàng và giữ offset cuộn. Build và bộ Tests đạt; còn chờ nghiệm thu UIKit trên iPhone.

Gói: `com.luoplayer.ultimatelockscreenplayer_0.1.0-65_iphoneos-arm64.deb`, 21218740 bytes, SHA-256 `2681edc415c0828e4c0b91cfa4804afbdd517ff4cca9a6cdf6632d2371d2c172`.

Nghiệm thu: mở Colour mode chọn Solid/Gradient/Artwork, kiểm tra Color 1/2 và Gradient angle bật/tắt đúng. Mở Non-artwork songs chọn Colour/Gradient; đổi hai màu bằng RGB/palette/hex. Mở Artwork background type và thử cả ba kiểu với bài có artwork. Quay lại đúng vị trí cuộn, preview phản ánh thay đổi, thoát/mở lại Settings và đổi mode giữ cấu hình, Apply cập nhật màn hình khóa. Thử thêm các enum cũ như Grow from/Peak caps type để tránh hồi quy. Nếu có lỗi cài lại ULP 64; không cần thay server.

## Artwork lớn và tỷ lệ nền — 0.1.0-66

Người dùng nghiệm thu các tính năng của 65, nhưng nền ảnh rõ bị pixel do nguồn 200 px. Probe v4 đã lấy riêng được UIImage 750×750 từ catalog lockscreen; một lần nil được phục hồi bằng lần thử sau. Tích hợp catalog riêng, không đổi catalog của hệ thống, giữ ảnh chất lượng cao theo bài và loại callback cũ. Center dim image giữ 1× theo pixel màn hình, có blur phía sau; Scaled image phủ viewport thực với zoom bổ sung tối đa 2%, không phủ theo overscan cao hơn 30%. Xem `NATIVE_ARTWORK_QUALITY_CONTRACT.md` cho bằng chứng, giới hạn và nghiệm thu. Build và Tests đạt; còn cần nghiệm thu bản 66 trên iPhone. DSP 64/server 2.1.1+ulp2 giữ nguyên. Sau khi artwork đạt, tiếp tục Trail, cover và toàn bộ Beat motion; Lyrics native vẫn tạm dừng.

## Khôi phục zoom nền và sửa tiến trình — 0.1.0-67

Người dùng xác nhận ảnh mới của 66 đã đạt. Center dim image + blur chuyển sang ảnh giữa rộng 83% viewport, zoom lên gần 90%; cả Center và Scaled dùng lại biên độ audio zoom 8% cùng smoothing cũ. Scaled vẫn phủ viewport thực. Sửa tiến trình khi nhấn Previous phát lại cùng bài: nhận timestamp mới ngay cả khi elapsed nguồn vẫn bằng 0, huỷ animation strokeEnd cũ khi reset/tua lùi. Thêm kiểm tra cùng bài reset timestamp, lặp bài, pause/resume/tua/đổi bài; bổ sung timestamp trong log. Xem hai hợp đồng artwork và player recovery. Build/Tests đạt; chờ nghiệm thu iPhone cho zoom và Previous một lần/hai lần. Nguồn ảnh lớn và DSP giữ nguyên.

## Hoàn thiện giao diện và chuẩn bị pre-release — 0.1.0-68

Người dùng đã nghiệm thu 67. Bo góc liên tục ảnh giữa Center dim image + blur, bán kính khoảng 20 pt trên màn 375 pt, giữ kích thước/zoom/nguồn ảnh đã đạt. Viết lại README gồm giới thiệu, cấu trúc, cài DEB/build cả server mod, demo-ui và credits. Release notes `PRE_RELEASE_NOTES.md` là đề xuất `0.2.0-beta.1`, chưa đổi phiên bản/phát hành/tag. README và release notes không đề cập Lyrics theo yêu cầu người dùng. Sau khi bo góc được nghiệm thu có thể chốt gói pre-release, tiếp tục theo dõi độ ổn định lâu dài.

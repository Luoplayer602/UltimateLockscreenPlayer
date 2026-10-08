# ULP Settings: đặc tả đã chốt ngày 2026-10-07

Tài liệu này ghi lại yêu cầu giao diện và điều khiển. Một mục chỉ xuất hiện khi renderer thực sự hỗ trợ nó. `Lyrics` và `Merged presets` là mục dành cho giai đoạn sau.

## Cấu trúc điều hướng

- `Cài đặt → ULP`: thanh điều hướng Back | ULP | Apply (respring). Nhóm `tweak enabled`: Enabled. Nhóm `settings`: Visualizer, Lyrics (sau), Merged presets (sau), Language (vi/en), GitHub: luoplayer.
- `Cài đặt → ULP → Visualizer`: cùng thanh Apply. Preview cố định ở đầu màn hình khi cuộn như `position: sticky`; preview có Play/Pause và phát nhạc mẫu. Nhóm `visual enabled`: Enabled. Nhóm `settings`: Modes.
- Danh sách Modes theo nhóm: Spectrum = Bar, Equalizer (ma trận ô vuông), Line, Dot (ma trận chấm tròn); Waveform = Waveform, Mirror, Siri; Circular = Spectro (line), Circular waveform, Smooth spectro.
- Cài đặt riêng của mode đổi theo mode đang chọn. Các nhóm Colour, Position & size, Background, Effects, Cover, Audio response là phần dùng chung trừ khi mode ghi ngoại lệ. Mô tả ngay dưới điều khiển dùng chữ nhỏ hơn tiêu đề nhóm.
- Với các mục dưới đây không nêu loại điều khiển, dùng slider. Giá trị mặc định và giới hạn cần chọn theo cách render và khả năng iPhone 6s, không mặc nhiên lấy nguyên thông số của web tham khảo.

## Thuộc tính riêng của mode

| Mode | Thuộc tính |
| --- | --- |
| Spectrum Bar | Bars; Bar width (0 = tự động, spacing nới khoảng trống); Spacing (tỷ lệ khe trong một slot); Bar height (1 = đầy lớp); Corner radius; Frequency range (giảm để tập trung bass/low mids); Mirror (bass ở giữa); Reverse (đảo chiều tần số, với Mirror thì treble ở giữa); Edge fade (0–1); Grow from (bottom/center/top); Minimum height (mặc định 2 px); Dynamics (>1 hạ dải nhỏ, nhấn đỉnh; <1 làm đầy); Peak caps; Cap thickness (mặc định 1 px). |
| Equalizer | Position & size, Reset, Flip horizontally/vertically; các thuộc tính Spectrum Bar phù hợp ma trận và toàn bộ nhóm dùng chung. |
| Line | Detail; Thickness; Frequency range; Fill under curve; Fill opacity; Mirror vertically; các nhóm dùng chung. |
| Dot | Bars; Rows; Dot size; Frequency range; Unlit opacity; Grow from (bottom/centre); các nhóm dùng chung. |
| Waveform | Thickness (mặc định 3 px); Amplitude; Detail; Smooth curve; Fill under wave; Fill opacity; các nhóm dùng chung. Dạng sóng ngang cần rõ ở kích thước nhỏ. |
| Mirror | Thickness; Amplitude; Detail; Centre gap; Fill; Fill opacity; các nhóm dùng chung. |
| Siri | Cùng nhóm thuộc tính Waveform và các nhóm dùng chung. |
| Spectro | Bars; Inner radius; Bar length; Bar thickness; Rotation speed; Frequency range (0–1); Symmetry (số đoạn lặp, 1 = không gập); Grow inward; Rounded caps; Show inner ring; Ring opacity; Peak caps; Peak caps type (line/dot); Hide visualizer but peak caps; các nhóm dùng chung. |
| Circular waveform | Detail; Inner radius; Amplitude; Thickness; Rotation speed; Fill ring; Fill opacity; các nhóm dùng chung. |
| Smooth spectro | Detail; Symmetry; Size; Reactivity; Thickness; Rotation speed; Frequency range (phần phổ bao quanh vòng); Fill; Fill opacity; các nhóm dùng chung. |

## Nhóm thuộc tính dùng chung

### Colour

- Mode: solid / gradient / artwork.
- Colour 1: color picker; vô hiệu khi chọn artwork.
- Colour 2: color picker; chỉ có hiệu lực khi chọn gradient.
- Gradient angle; Opacity; Glow (quầng sáng nhẹ, giá trị cao tốn hiệu năng).

### Position & size

- Horizontal position; Vertical position; Width; Height; Scale; Rotation; Flip horizontally; Flip vertically; Reset.
- Scale phóng to phần visualizer, không phóng to UI Player. Zoom theo âm thanh là chuyển động cộng lên tỷ lệ cơ sở này.

### Background

- Non-artwork songs: colour / gradient; Colour 1; Colour 2 (chỉ gradient).
- Artwork background: on/off.
- Artwork background type: scaled dim image; center dim image + blur background; blur background (mặc định). Kiểu center đặt ảnh gốc đúng tỷ lệ ở giữa và làm tối, một bản phóng lớn làm mờ ở sau lấp đầy khoảng trống trên màn dọc. Không chọn type khi artwork background tắt.
- Nền và visualizer cùng phản ứng với zoom; UI Player không zoom. Nền ảnh tĩnh có dim để sóng vẫn rõ. Giữ hai kiểu nền riêng, không phủ nhiều lớp làm nặng máy.

### Effects

- Trail (giữ nét của khung cũ rồi mờ dần theo thời gian, không tăng Glow); Beat reaction (độ phóng visualizer); React to beat type (Raw, Beat detect); Blur (làm mềm lớp visualizer); Grain (hạt trên khung hoàn thiện).

### Cover

- Ảnh tròn ở giữa, phù hợp các mode Circular. Cover mode: logo / artwork.
- Size; Horizontal position; Vertical position; Opacity; Outline thickness (mặc định 3 px); Outline colour; Outline opacity; Glow; React to beat (0 = đứng yên); React to beat type (Raw, Beat detect); Beat motion (swell, flash, shake, spin, bounce [mặc định], wobble; không khả dụng khi chọn Raw); Rumble (0–0.200); Drift (0–0.200); Glow pulse (0–1.500); Spin (-90 đến +90 độ/giây); Reset. Voice/Melody được bỏ theo quyết định của người dùng: tweak phải xử lý âm thanh Now Playing trực tiếp theo thời gian thực.

### Audio response

- Sensitivity; Bass; Mids; Treble; Smoothing (cao hơn ít dao động); Waveform smoothing (cao hơn chuyển khung chậm hơn); Normalise level on/off.
- Dải đọc của zoom phải độc lập với dải đọc của visualizer. Không đưa lại chế độ zoom vượt ngưỡng đã bị loại.

## Ràng buộc tương thích

- Player preset 01 và hành vi cuộn/artwork của bản 0.1.0-33 là mốc ổn định. Thanh tiến trình có độ trễ nhỏ đã được chấp nhận tạm thời.
- Preview và màn hình khóa dùng cùng renderer, cùng cấu hình chuẩn hóa tín hiệu và cùng quy tắc zoom. Preview riêng được xác nhận hoạt động trong 0.1.0-40.
- Chỉ bật các hiệu ứng tốn tài nguyên khi người dùng chọn; mục tiêu là iPhone 6s vẫn vẽ mượt.


## Cập nhật prototype — 2026-10-08

- Giữ Raw và Beat detect cho visualizer/cover; không dùng phân tích trước cả bài.
- Waveform lấy PCM thật; Mirror phản chiếu cùng dữ liệu.
- Một scene chung cho nền, visualizer và cover; preview sao chép kết quả vẽ.
- Beat motion: Swell nhanh, Flash sáng trong cover, Shake rung, Spin giật zoom + xoay thuận rồi về, Bounce phóng/thu chậm, Wobble xoay nhẹ + rung nhẹ. Raw khóa Beat motion.
- Bộ dò beat có độ nhạy, khoảng cách tối thiểu và thời gian nhả; FPS vẽ không làm giảm tần suất phân tích.

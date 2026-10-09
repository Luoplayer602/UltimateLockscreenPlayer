# ULP demo prototype — realtime audio

Chạy từ thư mục repo:

```sh
python3 demo-ui/server.py
```

Mở địa chỉ được in sau `ULP demo UI:` (thường là **http://127.0.0.1:8765/**). Nếu cổng bận, máy chủ tự chọn cổng khác. Nhấn Play để dùng `audio/inst.wav`, hoặc chọn tệp ở **Nhạc thử**. Máy chủ Python cần thiết cho Lyrics và thumbnail; mở HTML bằng `file://` hay `python3 -m http.server` sẽ không có các API này.

## Thao tác

- Mở `volume-hud.html` để thử riêng thiết kế HUD âm lượng 0.1.0-60: nút +/− hoặc phím ↑/↓. Mô phỏng này không thay cấu hình demo hay âm lượng máy.

- Nút Home tròn chuyển giữa màn hình khóa và Settings. Apply lưu cấu hình và trở về màn hình khóa giả lập.
- Visualizer → Modes có 10 mode; mỗi mode lưu cấu hình riêng. Switch, select, colour và reset cập nhật ngay, giữ vị trí cuộn.
- Preview cố định là phần phóng gần của chính khung đang vẽ trên màn hình khóa. Preview toàn cảnh giữ nguyên tỷ lệ màn hình dọc. Cả hai sao chép cùng canvas; nền, cover, waveform và chuyển động không được tính lại riêng.
- Play/Pause ẩn sau khi phát; chạm preview để hiện lại. Nhãn BEAT sáng khi một sự kiện beat được phát hiện.
- Nhập YouTube ID ở thanh bên để lấy lời, tên bài và thumbnail. Nút ♪ trên màn hình khóa bật/tắt lời. Cài đặt → ULP → Lyrics có Enabled, Preset và YouTube Music. Trang Preset có preview phát theo nhạc và Preset 1; trang YouTube Music có Translate, Phiên âm, Display offset và ghi công. Lyrics dùng preset 1: lời xếp dọc trực tiếp trên nền, cuộn tới dòng đang phát, dòng hiện tại phóng nhẹ và sáng lên; lời gốc được tô dần giữa hai mốc thời gian. Dòng trống có mốc thời gian được giữ lại; khoảng nhạc dạo dài hiện nốt nhạc được lấp đầy theo thời gian. Merged presets vẫn là mục dự kiến.
- Lyrics lấy dữ liệu từ Unison; khi dịch lỗi hoặc thiếu phiên âm, máy chủ demo thử đường dự phòng Google Translate như Better Lyrics. Chỉ gửi các dòng lời khi bạn bật chức năng dịch/phiên âm.
- Proxy hiện không gửi `x-key-id` tới Unison. Thumbnail có viền tối được cắt và phóng đầy cover/Player; nền vẫn dùng ảnh gốc. Nốt nhạc dạo lấp đầy trong đúng hình nốt và nhận cùng mức zoom với cover.
- Âm thanh visualizer vẫn lấy từ file local. Để lời chạy đúng nhạc, hãy chọn file âm thanh khớp với YouTube ID. Trình duyệt không cấp PCM của iframe YouTube cho Web Audio trong demo này.

## Âm thanh và hiệu ứng

- Chỉ có **Raw** và **Beat detect**, cho cả visualizer và cover. Cấu hình Voice/Melody cũ được chuyển về lựa chọn hợp lệ. Không phân tích trước cả bài, không tải mô hình nhận diện.
- Waveform lấy PCM có dấu trực tiếp từ Web Audio, lọc theo dải Visual và EQ, rồi lấy mẫu/làm mượt. Mirror phản chiếu cùng đường sóng. Siri dùng các lớp của cùng dữ liệu âm thanh.
- Spectrum dùng các dải tần chia theo thang log. Bass/Mids/Treble, Sensitivity, Normalise và Smoothing tác động lên dữ liệu vẽ. Dải Zoom cấp mức Raw độc lập.
- Beat detector dùng biến động phổ dương trên bốn dải tần, chuẩn hóa theo mức nền của từng bin, ngưỡng thích ứng và khoảng cách tối thiểu giữa hai sự kiện. Nó nhận biết các cú đánh/khởi phát âm thanh; không suy ra chắc chắn nhịp nhạc hoặc BPM. Chỉnh Beat sensitivity khi nhạc bắt thiếu hoặc thừa nhịp.
- Phân tích chạy mỗi khung trình duyệt, độc lập với FPS giới hạn bộ vẽ. Đây là prototype của đường xử lý trực tiếp; độ trễ và tải trên iPhone cần đo ở bản native.
- Beat motion: Swell phóng nhanh rồi thu về; Flash sáng bên trong; Shake rung; Spin giật zoom và xoay thuận rồi về; Bounce phóng/thu chậm hơn; Wobble xoay nhẹ và rung nhẹ. Raw khóa Beat motion và chỉ điều khiển scale liên tục. Spin liên tục chỉ xoay phần ảnh/chữ bên trong cover.
- Visualizer và cover phản ứng độc lập. Scale/rotation/flip của visualizer không kéo cover chuyển động theo.
- Spectro hỗ trợ grow inward, rounded caps, inner ring, symmetry, rotation và peak caps line/dot. Các mode có fill, gradient, opacity, glow và geometry tương ứng.
- Trail lưu hình cũ tại vị trí đã vẽ, làm mờ theo thời gian và dùng độ mờ lớn nhất tại mỗi pixel để không cộng sáng khi hình đứng yên. Glow chỉ lấy nét hiện tại.
- Center dim image giữ artwork đúng tỷ lệ ở giữa màn dọc; một bản blur lấp đầy phía sau. Artwork được dùng chung cho nền, bảng màu, cover và Player.

## Kiểm tra

```sh
node demo-ui/tests/audio-response.test.cjs
```

Mở `http://localhost:8765/tests/browser.html` để chạy kiểm tra các mode, các điều khiển từng bị bỏ sót, sáu Beat motion, migration, Trail và so sánh pixel giữa preview toàn cảnh với scene gốc. Trang kiểm thử dùng vùng lưu riêng, không thay cấu hình demo của bạn.

`tests/live-audio.cjs` là kiểm tra tùy chọn qua Chrome DevTools: phát bài mẫu, ghi RMS/PCM/beat count và kiểm tra lỗi JavaScript. Kết quả có dữ liệu không đồng nghĩa đã chứng minh độ chính xác beat trên mọi thể loại nhạc.

## Tham khảo

- [Music Visualizer Lab: waveform và mirror](https://musicvisualizerlab.com/waveform-generator).
- [Web Audio: lấy PCM trực tiếp](https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getFloatTimeDomainData).
- [Web Audio: lấy phổ theo dB](https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getFloatFrequencyData).

Demo chưa đọc Now Playing của iOS; tệp nhạc trong trình duyệt cung cấp luồng âm thanh thử cho prototype. Apply ở đây không respring thiết bị.

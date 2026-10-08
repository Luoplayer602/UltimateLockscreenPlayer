# ULP demo prototype — realtime audio

Chạy từ thư mục repo:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory demo-ui
```

Mở **http://localhost:8765/**. Nhấn Play để dùng `audio/inst.wav`, hoặc chọn tệp ở **Nhạc thử**. Khi mở `index.html` qua `file://`, hãy dùng nút chọn tệp: một số trình duyệt chặn dữ liệu Web Audio của bài mẫu tải bằng đường dẫn file.

## Thao tác

- Nút Home tròn chuyển giữa màn hình khóa và Settings. Apply lưu cấu hình và trở về màn hình khóa giả lập.
- Visualizer → Modes có 10 mode; mỗi mode lưu cấu hình riêng. Switch, select, colour và reset cập nhật ngay, giữ vị trí cuộn.
- Preview cố định là phần phóng gần của chính khung đang vẽ trên màn hình khóa. Preview toàn cảnh giữ nguyên tỷ lệ màn hình dọc. Cả hai sao chép cùng canvas; nền, cover, waveform và chuyển động không được tính lại riêng.
- Play/Pause ẩn sau khi phát; chạm preview để hiện lại. Nhãn BEAT sáng khi một sự kiện beat được phát hiện.
- Lyrics và Merged presets vẫn là các mục dự kiến theo đặc tả.

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

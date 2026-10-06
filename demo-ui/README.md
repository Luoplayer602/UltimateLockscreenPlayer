# ULP demo UI

Mở `index.html` trực tiếp bằng Chrome, Firefox hoặc Edge. Không cần cài thư viện hay chạy server.

- Nhấn **Nhạc thử** để chọn một hoặc nhiều tệp âm thanh trên máy. Nút trước/sau chuyển giữa các tệp đã chọn; một tệp sẽ tự lặp.
- Nhấn **Artwork** để chọn ảnh bìa. Trình duyệt không tự đọc ảnh bìa nhúng trong MP3/M4A ở demo này.
- Bài mặc định là `demo-ui/audio/inst.wav` do khách hàng cung cấp. Các tệp nhạc trong `audio/` được `.gitignore` loại khỏi Git.
- Tiến trình tách thành hai nhánh: từ giữa cạnh trái, một nhánh đi qua cạnh trên, nhánh kia đi qua cạnh dưới; cả hai gặp tại giữa cạnh phải. Không thể chạm/kéo để tua.
- Demo có mode `circle`, `bar`, `line`, `dot`, `siri`, `wave`; các điều khiển **Points**, **Animation scale**, **Dải âm visualizer**, **Dải âm zoom**, **Đối xứng**, màu tự động/tự chọn, Offset X/Y, FPS, mức blur, mức dim cho artwork tĩnh và tốc độ biến dạng. Hai dải âm độc lập: dải visualizer quyết định điểm vẽ; dải zoom điều khiển cả visualizer và nền artwork. Khung Player và UI đứng yên. Thay đổi thông số được áp dụng sau 1 giây.

Đây là bản thử giao diện trong trình duyệt. Phần âm thanh dùng Web Audio API của trình duyệt, không phải cơ chế lấy mẫu âm thanh của tweak trên iOS.

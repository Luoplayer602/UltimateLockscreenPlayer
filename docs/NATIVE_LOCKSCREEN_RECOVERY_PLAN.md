# Kế hoạch sửa màn hình khóa sau 0.1.0-58

## Nghiệm thu 0.1.0-59: không đạt, hoàn tác

- Người dùng xác nhận đồng hồ thoắt hiện trước khi bị ẩn; Player nổi trên toàn màn hình và không còn cuộn theo media host; artwork sai. HUD quá lớn và hoạt ảnh không tự nhiên.
- Bản gốc 0.1.0-58 vẫn có trong `packages/` và `/var/mobile` để rollback nguyên gói. Thiết bị yêu cầu mật khẩu sudo; không coi việc chép gói là đã rollback thiết bị.
- Bản thử 0.1.0-60 khôi phục Player về `PLPlatterCustomContentView`, bỏ Player độc lập ở CoverSheet, bỏ cache artwork và các thay đổi metadata của 0.1.0-59. Artwork dự phòng chỉ tìm trong media host như trước.
- Đồng hồ dùng `hidden` trực tiếp khi visualizer hoạt động, kể cả khi màn hình tắt; áp trạng thái trước `viewWillAppear`. Chỉ khi visualizer đóng mới chạy chuyển cảnh hiện đồng hồ, không chạy fade-out đồng hồ mỗi lần mở màn hình khóa.

## Thiết kế HUD thay thế — 0.1.0-60

- Khung 54 × 56 pt: diện tích gần 1/4 thẻ 82 × 148 pt trước. Mép trái cách màn hình 6 pt, tâm ở 20% chiều cao màn hình.
- Vòng cung 300° bao quanh số phần trăm; chừa khoảng dưới cho biểu tượng loa. 100% lấp hết cung, 0% không có phần lấp; màu nền tối và nét trắng.
- Trượt từ ngoài mép trái vào trong 0,22 giây, xoay thuận khoảng 8° khi tăng và ngược khi giảm, trở về góc ban đầu trong 0,30 giây. Không dùng spring phóng/nảy toàn thẻ. Vòng mức nội suy trong 0,18 giây, tự ẩn sau 1 giây ngừng thao tác.
- Khung HUD dùng bounds/center để layout không làm biến dạng view đang có transform. Reduced Motion dùng fade và bỏ spin.
- Prototype tương tác: `demo-ui/volume-hud.html`; ảnh tỷ lệ thật: `docs/previews/volume-hud-60.png`. Chrome đã kiểm tra 0/100%, chiều xoay, tăng/giảm liên tiếp, tự ẩn, kích thước và vị trí. Prototype mô phỏng thiết kế, không chứng minh hành vi UIKit trên iPhone.
- Các sửa lỗi ứng dụng nguồn và khôi phục phiên phát mới của 0.1.0-59 đã bị rút lại; chưa coi các lỗi cũ này là đã sửa.

Các mục dưới đây lưu lịch sử kế hoạch và bản 0.1.0-59 đã bị từ chối.

## Kết quả nghiệm thu

- Spectro và peak caps: đạt.
- Chuyển cảnh sau 15 giây: đạt; đồng hồ hiện lại sai khi tắt rồi bật màn hình trong lúc nhạc đang phát.
- Chỉ báo âm lượng: không xuất hiện.
- Sau khi đóng YouTube Music rồi phát lại: Control Center có Now Playing và artwork, ULP mất Player và nền artwork.
- Chạm Player ULP: không mở ứng dụng nguồn.

## Chẩn đoán trước khi đổi cấu trúc

Ghi log có giới hạn cho các sự kiện: màn hình tắt/bật, CoverSheet xuất hiện/biến mất, thay đổi `authenticated`, ngày giờ được tạo lại, media host được tạo/hủy, thay đổi Now Playing client/PID, snapshot có title/artwork, Player gắn/ẩn, volume callback, tap Player, app bundle được giải quyết và kết quả yêu cầu mở app. Không ghi nội dung artwork hay dữ liệu riêng của bài hát. Đối chiếu cùng một lần đóng rồi mở lại YouTube Music với Control Center. Nếu MediaRemote vẫn có dữ liệu nhưng ULP không hiển thị, sửa tầng nhận snapshot/host; nếu snapshot trống, thêm nguồn dự phòng từ bộ điều khiển Now Playing của SpringBoard.

## Gói sửa kế tiếp

1. **Đồng hồ:** tách thao tác chuyển cảnh khỏi đồng bộ trạng thái view. Mỗi lần CoverSheet layout/hiện lại phải áp trạng thái alpha lên date view hiện hành, kể cả khi visualizer vẫn đang ở trạng thái `shown`. Chỉ chạy animation khi trạng thái đích thật sự đổi; lúc ẩn visualizer trả alpha gốc.
2. **Player và artwork:** không để vòng đời Player phụ thuộc vào `CSMediaControlsView` hiện tại. Tạo host ULP riêng trong CoverSheet, cập nhật từ một trạng thái Now Playing duy nhất, gắn lại khi CoverSheet được tạo lại và xóa sau khi phiên Now Playing thật sự kết thúc. Giữ artwork cuối qua khoảng trống metadata ngắn khi ứng dụng nguồn khởi động lại; nhận track/app mới bằng client ID hoặc bundle ID thay vì chỉ dựa vào PID. Thay polling có thể bỏ qua callback chậm bằng một luồng refresh tuần tự và thông báo thay đổi, vẫn giữ polling dự phòng.
3. **Mở ứng dụng:** ghi riêng việc nhận tap, tìm bundle ID và kết quả LaunchServices. Ưu tiên bundle ID của Now Playing client/parent app, chỉ dùng PID làm dự phòng. Kiểm tra cả khi máy đang khóa và đã mở khóa; không bỏ qua xác thực màn hình khóa.
4. **HUD âm lượng riêng:** trước hết xác nhận tín hiệu âm lượng nào được SpringBoard gửi trên iPhone 6s khi visualizer mở. Dùng tín hiệu đó để hiện overlay riêng có biểu tượng loa, thanh mức âm lượng, phần trăm và animation xuất hiện/biến mất; không kích hoạt audio session chỉ để đọc âm lượng. HUD chỉ xuất hiện trong visualizer và không nhận chạm.

## Điều kiện nghiệm thu

- Phát nhạc, tắt/bật màn hình ba lần: đồng hồ luôn ẩn khi visualizer đang hiện; sau Pause 15 giây thì đồng hồ hiện qua chuyển cảnh, Player ULP vẫn còn.
- Đóng YouTube Music trong app switcher, mở lại và phát: ULP Player, artwork nền, nút điều khiển và Spectro trở lại mà không respring; dừng hẳn thì trở về màn hình khóa gốc.
- Chạm vùng ảnh/tên/nền Player mở đúng ứng dụng nguồn theo quy trình khóa bình thường; chạm nút phát/chuyển bài không kích hoạt mở app.
- Nhấn tăng/giảm âm lượng khi visualizer hiện: HUD phản ánh mức mới và tự ẩn; nhấn khi visualizer đã ẩn không hiện HUD ULP.
- Preview, Settings, Apply, Waveform/Mirror/Siri, Spectro và peak caps không bị hồi quy.

## Trạng thái bản thử 0.1.0-59

- Log iPhone 0.1.0-58 xác nhận MediaRemote có tiêu đề và PID trong lúc phát nhưng một số snapshot không có artwork data. Bản 0.1.0-59 lấy thêm artwork từ bộ điều khiển Now Playing của SpringBoard, giữ ảnh cuối theo bài hát và quét artwork của view hệ thống với chu kỳ giới hạn khi các API không trả ảnh.
- Player được gắn trực tiếp vào CoverSheet; media host gốc chỉ cung cấp vị trí khi nó tồn tại. Tên ứng dụng nguồn lấy từ MediaRemote client, MPUNowPlayingController hoặc AVSystemController, sau đó dùng LaunchServices để mở app.
- Đồng hồ được đồng bộ lại khi date view layout hoặc được gắn vào cửa sổ, kể cả sau khi màn hình tắt và bật lại.
- HUD âm lượng dùng thẻ dọc 82 × 148 pt sát mép trái, góc phía ngoài bo 30 pt và góc sát mép bo 8 pt; nền tối, ô biểu tượng, phần trăm và vạch mức màu ấm. HUD trượt vào khi mức âm lượng đổi, tự ẩn và không nhận chạm.
- Gói đã biên dịch, qua bộ test hiện có, giải nén archive và đối chiếu SHA-256 sau khi chép lên iPhone. Các hành vi trên thiết bị vẫn cần nghiệm thu theo danh sách phía trên.

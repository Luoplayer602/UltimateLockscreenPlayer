# Player tự kiểm tra và phục hồi — 0.1.0-62

## Nghiệm thu tạm thời và bước 63

Người dùng xác nhận lặp lại đóng YouTube Music trong App Switcher rồi mở/phát lại vài lần: Player và artwork phục hồi. Log đọc khi bắt đầu bản 63 xác nhận iPhone ở 62 và các lần mở gần nhất có host, Player, artwork. Tiếp tục theo dõi khi dùng lâu. Vẫn còn vị trí sau vuốt màn hình khóa, được xử lý cùng Smooth spectro trong `NATIVE_SMOOTH_SPECTRO_CONTRACT.md`.

## Bằng chứng từ iPhone

Người dùng tái hiện lỗi trên 0.1.0-61 ngay trong phiên triển khai. Log đã lưu ở `/tmp/ulp-recovery-current.log` trên WSL để đối chiếu:

- `NowPlaying state=2 pid=0 titlePresent=0 artworkPresent=0` sau khi đóng ứng dụng.
- Phiên mới `pid=64072`, sau đó `state=1 titlePresent=1 artworkPresent=0`; audio MSH2 tiếp tục nhận mẫu.
- `list moved down ... inset=207→327`, rồi nhiều lần `restored inset=497→327`: base được lưu từ bố cục tạm và không được cập nhật.

Chưa có bằng chứng runtime về parent của Player trên bản 61. Các khả năng được xử lý trong bản 62 là replacement bị tháo, media view đổi host/hierarchy hoặc con trỏ giữ view cũ. Gói 0.1.0-61 và 0.1.0-60 vẫn giữ để quay lại.

## Kiểm tra và phục hồi view

- Player gắn vào `PLPlatterCustomContentView` thuộc CoverSheet hiện hành, đi cùng vùng Now Playing và thao tác cuộn gốc.
- Một replacement được giữ theo từng host. Mỗi lần native media layout/được gắn vào window, ULP kiểm tra parent, bounds, thứ tự sibling và các thành phần card/ảnh/chữ/nút/layer tiến trình; chỉ gắn lại hoặc sửa phần thiếu.
- Khi mở màn hình khóa hoặc PID đổi, quét host hiện hành và áp snapshot gần nhất ngay lên Player mới. Polling một giây cũng kiểm tra Player; khi thiếu host, quét cây view tối đa một lần mỗi hai giây, ghi log lỗi tối đa một lần mỗi năm giây.
- Nếu Player chưa gắn được hoặc host chưa có kích thước hợp lệ, trả alpha cho media view gốc để tránh chỉ ẩn Player hệ thống mà không có replacement.
- Native media view hiện có được giữ để tiếp tục nhận dữ liệu. Không tạo/xóa một view gốc tạm: dữ liệu artwork là bất đồng bộ, một lần dựng rồi xóa không bảo đảm nhận được ảnh. Việc dựng lại controller gốc chỉ xét ở đợt sau nếu log chứng minh không còn host hoặc source không phục hồi.

## Dữ liệu theo phiên phát

- Một request MediaRemote chạy tại một thời điểm; polling không tăng generation để hủy callback đang chờ. Đọc PID trước và sau metadata/trạng thái phát, bỏ snapshot trộn hai PID và đọc lại.
- Timeout ba giây loại callback muộn; lỗi liên tiếp có khoảng chờ tăng dần trước lần thử tiếp. Wake/media attach/nút điều khiển yêu cầu refresh thêm, gộp lại nếu có request đang chạy.
- Identity gồm PID, title và artist; duration không nằm trong identity để tránh reset khi duration thiếu/dao động. Có khoảng giữ metadata tối đa hai giây khi vẫn cùng PID và thiếu title/artist; không giữ artwork từ PID/bài cũ sang identity mới.
- Đổi identity tạo lại observer `MPUNowPlayingController`. Nếu thiếu artwork, thử tạo lại tối đa hai lần với khoảng cách ít nhất năm giây. Bỏ ảnh controller cũ đã nhận diện qua pointer khi observer đổi.
- Ưu tiên artwork từ snapshot MediaRemote. Fallback `SBMediaController` chỉ dùng khi title/artist khớp; nguồn UIImage từ observer và artwork trong native host hiện hành vẫn được hỗ trợ. Dữ liệu thiếu được giữ theo cùng identity; không quét Control Center/toàn cửa sổ để lấy ảnh.
- Nền nhận artwork từ snapshot ngay cả khi Player chưa gắn. Ảnh được giải mã lại khi bytes thay đổi; thay host/Player có thể dùng lại snapshot đã giải mã.

Identity chưa có content ID ổn định từ mọi ứng dụng. Hai bản thu trùng title/artist trong cùng PID chưa phân biệt hoàn toàn. Artwork từ private controller/view không có định danh bài kèm theo; kết quả và ảnh đúng bài cần đối chiếu thực tế trên iPhone.

## Vị trí và tiến trình

- `ULPListPlacement` tách base do hệ thống cấp khỏi padding ULP. Setter nhận base mới sẽ tính lại target; setter lặp lại giá trị đã điều chỉnh không cộng padding lần hai. Ví dụ 207 + 120 → 327; base mới 497 + 120 → 617.
- Không ép contentInset lại trong từng layout. Khi kích hoạt/tắt padding hoặc đổi kích thước, chỉ chỉnh offset về top nếu đang ở top; giữ offset khi đã cuộn. Tránh sửa offset khi dragging/decelerating. Các inset trái/phải/dưới mới của hệ thống được giữ.
- Elapsed thiếu truyền bằng NAN, không phải 0. Đồng hồ monotonic tiếp tục tính khi đang phát, đứng yên khi Pause; nhận tua thật và reset khi identity đổi. Có hỗ trợ playback rate dương và timestamp dạng NSDate khi nguồn trả đúng kiểu.
- Bỏ timestamp/elapsed anchor lặp; không reanchor vì lệch nhỏ ≤1.25 giây khi đang phát. Tua lớn hoặc tua khi Pause nhận ngay. Tua rất ngắn trong lúc phát có thể được xử lý như jitter.

### Sửa mốc tiến trình trong 0.1.0-67

Người dùng báo nhấn Previous một lần trong YouTube Music phát lại từ 0:00 nhưng thanh ULP vẫn chạy tiếp; nhấn hai lần hoặc gần đầu bài sẽ đổi bài. Log bản 66 cho thấy `raw=0.00` lặp lại trong cùng bài, trong khi elapsed ULP tiếp tục tính và có lúc chạm duration dù âm thanh vẫn phát. Trước đây chỉ giá trị elapsed được dùng để nhận mốc mới, bỏ sót timestamp đổi khi phát lại cùng bài.

67 nhận cặp `(source elapsed, source timestamp)`. Timestamp mới làm mốc nguồn đủ điều kiện kiểm tra tua/reset, kể cả giá trị elapsed và giá trị đã hiệu chỉnh đều đúng bằng 0 như mốc đầu tiên. Cặp lặp nguyên trạng vẫn dùng đồng hồ monotonic, tránh áp lại thời gian hệ thống mỗi lần đọc. Giữ ngưỡng chống jitter khi đang phát, hỗ trợ Pause/tua khi Pause, playback rate và reset khi đổi identity. Không giả lập reset bằng cách đặt 0 ngay khi gửi lệnh Previous; đợi metadata của nguồn xác nhận.

Khi UI nhận reset/tua lùi/Pause/đổi bài, xoá animation `strokeEnd` cũ trước khi cập nhật hai nhánh tiến trình. Log bổ sung timestamp, age và lớp giá trị timestamp để kiểm tra trên thiết bị. ProgressClockTests bao gồm phát từ 0 với raw 0 lặp, nhấn Previous vẫn raw 0 nhưng timestamp mới, lặp lại bài khi thanh đã đầy, Pause/Resume/tua về 0, thiếu elapsed và đổi bài. Tests/build kiểm tra được mã; thao tác Previous thực tế trên iPhone còn cần nghiệm thu.
- Đổi bài, tua lớn, Pause/Resume cập nhật layer ngay; các bước phát bình thường dùng animation tuyến tính. Khi layout đổi hình học viền, tắt implicit animation của path để tránh méo/chớp tiến trình.

## Log và kiểm tra

`/var/mobile/Library/Logs/ULP.log` thêm các mục `Player repair`, `Player audit`, `Player list placement`, `Player list system layout changed`, `NowPlaying health`, `NowPlaying identity changed`, `Artwork observer restarted`, `Progress sample` và timeout/client đổi giữa request. Không ghi nội dung bài hay bytes artwork. Progress sample giới hạn khoảng mười giây một lần, trừ khi cần ghi tua lùi.

`make -C Tests test` nay bao gồm ProgressClockTests và ListPlacementTests. Kiểm tra elapsed thiếu, jitter, tua về 0, tua lúc Pause, tốc độ phát, đổi phiên, base đổi đúng như log, setter echo và nhiều vòng kích hoạt/tắt không tích lũy padding. Build arm64/rootless xác nhận liên kết C/C++ và các lớp UIKit; chưa chứng minh private API/runtime trên iPhone.

Build và toàn bộ tests đã đạt. Archive 0.1.0-62 đã giải nén kiểm tra và chép tới `/var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-62_iphoneos-arm64.deb`; SHA-256 cục bộ/iPhone khớp: `d36478390329ffe959508f73a87a34a35d8489d2d1ef7332cc2f5d628f90e03c`. iPhone vẫn cài 0.1.0-61 tại lúc xác nhận checksum; bản 62 chờ người dùng cài và nghiệm thu.

## Nghiệm thu

1. Phát YouTube Music → xóa khỏi app switcher → mở lại/phát → khóa màn hình. Player và artwork phải trở lại, không cần respring. Làm lại với cùng bài rồi bài khác để kiểm tra không dùng ảnh cũ.
2. Tắt/bật màn hình, kéo Player ra ngoài vùng nhìn thấy rồi cuộn lại. Player đi cùng danh sách; không nổi lên trên mọi màn hình, không kéo trang về top ngoài ý muốn.
3. Tua tới giữa bài, tua lùi, Pause/Resume và đổi bài: viền tiến trình reset/tiếp tục đúng, không về 0 vì metadata thiếu.
4. Đối chiếu log audit/repair với ảnh nếu còn lỗi. HUD âm lượng, 15 giây Pause, các mode và Settings tiếp tục được kiểm tra hồi quy. Đồng hồ nhấp nháy vẫn được theo dõi riêng.

Nếu lỗi, quay lại gói 0.1.0-61 đã có tại `/var/mobile`, đọc log trước khi thử sửa thêm. Chỉ coi vấn đề đã sửa sau khi nghiệm thu trực tiếp, rồi theo dõi qua nhiều lần dùng lâu.

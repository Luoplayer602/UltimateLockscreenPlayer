# CoverPerformance

So sánh chi phí CPU của Cover theo cùng workload giữa hai bản. Process riêng,
không attach SpringBoard, đổi preferences, phát/dừng nhạc hoặc quay màn hình.

```sh
make -C Probe/CoverPerformance FINALPACKAGE=1
scp -O -i ~/.ssh/ulp_iphone Probe/CoverPerformance/.theos/obj/ULPCoverPerformance mobile@100.65.210.88:/var/jb/var/mobile/ULPCoverPerformance-test
ssh -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'chmod +x /var/jb/var/mobile/ULPCoverPerformance-test && /var/jb/var/mobile/ULPCoverPerformance-test test'
```

Dùng tên executable mới sau khi đổi binary để tránh trust cache của Dopamine.
Giữ binary baseline trước khi sửa source để có hai chương trình cùng workload.
Có ba vòng mặc định (thêm tham số thứ hai `1` để chạy một vòng): Cover tĩnh, Glow pulse 0.777, Glow pulse 0.777 + Raw/Rumble/Drift/Spin,
và Glow pulse 1.5 + các motion đó. Báo setup foreground, thời gian chờ cache,
cập nhật model và
`renderInContext` vào bitmap 375×667 ở 1×; bỏ 10 lượt raster đầu, lấy 80 lượt.
PNG `cover-perf-<tag>-<pulse>-<ambient>.png` nằm trong cache ULP trên iPhone.

Đây là **CPU software raster**, không đo compositor/GPU, FPS thực, nhiệt độ,
pin hoặc encoder quay màn hình. Các process khác vẫn chạy và làm số đo dao động;
không chuyển phần trăm giảm raster thành phần trăm tăng FPS. Nghiệm thu thực tế
phải thử trên lockscreen, có và không quay màn hình, với cấu hình đã lưu.

# Rung nhẹ, Trôi nhẹ và Quầng sáng theo nhạc — 0.1.0-72

Người dùng xác nhận các hiệu ứng 71 nghiệm thu đạt bước đầu nhưng vẫn cần kiểm chứng lâu dài, đồng thời chỉ ra ba mục Cover trong demo còn thiếu ở native. Bản 72 bổ sung đúng ba mục này; Spin liên tục của 70 và sáu Beat motion của 71 là các điều khiển đã có.

## Ánh xạ demo → native

| Demo | Native / nhãn | Mặc định | Giới hạn |
| --- | --- | --- | --- |
| `rumble` | `CoverRumble` / Rung nhẹ | 0 | 0–0.2 |
| `drift` | `CoverDrift` / Trôi nhẹ | 0 | 0–0.2 |
| `glowPulse` | `CoverGlowPulse` / Quầng sáng theo nhạc | 0 | 0–1.5 |

Giữ schema 1: `v1.<mode>.<key>`. Có trên cả 12 mode, khóa khi Cover Off. Không phụ thuộc cường độ `CoverReaction`: đặt React to beat = 0 vẫn chỉnh được ba hiệu ứng này. Reset Cover xóa thêm ba khóa, giữ cấu hình detector, Zoom, nền, Trail và mode khác. Rumble/Drift hiển thị ba số thập phân; ba hàng có đủ chiều cao cho chữ trợ giúp và dùng cùng cơ chế giữ offset cuộn.

## Hành vi

- **Rung nhẹ:** theo mức âm Raw của dải Zoom hiện tại, kể cả khi Cover chọn Beat detect. Hệ số như demo: X `35 × Rumble × raw × sin(t × 47)`, Y `22 × Rumble × raw × cos(t × 53)`. Mức âm hạ về 0 khi Pause/stall, rung cũng hạ; không tự tạo nhịp.
- **Trôi nhẹ:** chuyển động chậm theo clock: X `25 × Drift × sin(t × 0.63)`, Y `25 × Drift × cos(t × 0.49)`. Độc lập âm thanh nên vẫn chạy khi Pause hoặc Preview chưa Play. Biên độ tối đa 5 đơn vị mỗi trục. Ẩn scene/rời trang thì dừng cập nhật; clock cập nhật lại khi trở về.
- **Quầng sáng theo nhạc:** quầng ngoài Cover, màu theo Outline colour; `halo = CoverGlow + GlowPulse × level`. Nguồn level là Raw hoặc envelope Beat theo `CoverReactType`, có làm mượt ngắn để nhả sáng khi Pause. Bán kính `35 × halo` theo hệ 400 đơn vị, opacity giới hạn 1. `CoverGlow=0` vẫn có quầng sáng động nếu Glow pulse >0. Đây là quầng ngoài, Flash vẫn sáng bên trong hình tròn.
- Drift/Rumble cộng vào offset của Beat motion, theo `viewport.width/400`, độc lập biến đổi nét visualizer. Cover vẫn tròn, ảnh full bleed, viền/shadow cùng Cover. Glow không vào history Trail. Spin liên tục vẫn dừng khi Pause.

`ULPCoverAmbientEvaluate` trong `Visualization/ULPCover.c` dùng cùng hệ số của `demo-ui/renderer.js`; C normalization chặn NaN/Inf/giá trị quá giới hạn. Phase được rút gọn trước nhân để clock hữu hạn rất lớn không sinh NaN. Mức âm/native capture và nền tảng vẽ shadow khác Canvas nên không hứa giống pixel tuyệt đối.

## Vòng đời và tài nguyên

Dùng timer phản ứng 30 Hz sẵn có khi audio không còn cấp frame. Drift là trường hợp timer tiếp tục khi im lặng, đến khi scene bị ẩn. Không cấp frame audio giả, không quay rotor hoặc phát sinh hit từ timer. Live audio vẫn theo FPS vẽ đã chọn. Preview lấy mẫu 60 Hz khi dùng Beat detect cho Zoom, Cover motion **hoặc Glow pulse**, dù giới hạn FPS vẽ thấp hơn.

Khi rời trang Preview, đặt renderer hidden để hủy timer kể cả lúc view còn tạm ở navigation window. Khi vào lại, refresh preferences mở renderer theo Visual enabled. Các effect mới mặc định 0, không đổi detector/DSP/server, nguồn artwork, Player hoặc cơ chế tiến trình/phục hồi. Không thêm request ảnh hay bitmap history cho Cover; vẫn dùng shadowPath tròn đã có. Cần đo GPU/pin với bán kính Glow lớn và Trail bật đồng thời trên SpringBoard.

## Kiểm tra

- Tests: giá trị mặc định/giới hạn, các mode, nguồn âm tăng/giảm, im lặng, Drift không cần âm, Glow nền/cộng thêm, giới hạn offset và đầu vào NaN/Inf/clock lớn; schema/defaults/dependencies/thứ tự hàng và đủ chỗ cho help.
- UIKit probe bổ sung vào `Probe/BeatProbe`: Rumble theo raw và tọa độ viewport, Glow đổi theo Raw/Beat khi React strength=0, Flash không bị bật bởi Glow, Drift chạy khi Pause, timer hủy khi Drift=0/Cover Off/hidden/rời window. Chạy lại sáu Beat motion và đường xử lý sample của 71.

## Nghiệm thu trên iPhone

1. Đóng Settings sau cập nhật DEB. Cover Artwork; đặt React to beat = 0 để nhìn từng hiệu ứng. Rung nhẹ 0/0.2: đoạn mạnh rung rõ hơn đoạn nhẹ; Pause hạ về đứng yên.
2. Trôi nhẹ 0/0.2: tâm ảnh di chuyển chậm, kể cả khi Preview chưa Play hoặc đã Pause. Tắt Drift về tâm cố định. Thử rời trang/quay lại và tắt/mở màn hình.
3. Glow 0, Quầng sáng theo nhạc 0/1.5: thử Raw rồi Beat detect. Quầng sáng ngoài tăng/nhả, Flash bên trong chỉ do Beat motion Flash. Màu Outline điều khiển màu quầng.
4. Kết hợp với Swell/Spin/Bounce và Spin liên tục; Apply kiểm tra màn hình khóa. Mode khác giữ cấu hình riêng, Reset chỉ reset Cover của mode hiện tại và giữ vị trí cuộn.
5. Theo dõi player/artwork/tiến trình, chuyển cảnh Pause >15 s và tài nguyên khi bật Trail/Glow/motion đồng thời. Nghiệm thu ngắn không thay kiểm tra dài hạn.

## Kết quả kiểm tra — 2026-10-10

- `make -C Tests test` đạt toàn bộ test C và schema Settings; build arm64/rootless đạt.
- Probe UIKit trên iPhone 6s iOS 15.8.5 đạt cả viewport 375×667 và 343×184: sáu Beat motion, Rumble, quầng Raw/Beat, Drift khi Pause, Spin không chạy khi Pause và timer cleanup khi Off/hidden/rời window. Ảnh probe xác nhận quầng nằm ngoài Cover và artwork lấp đầy crop tròn. Process probe không thay nghiệm thu Settings/Apply hoặc đo tài nguyên của SpringBoard.
- Đường DSP64/detector xử lý 30 s `inst.wav` có 71 onset hữu hạn; đây là kiểm tra đường dữ liệu, không phải phép đo độ chính xác nhịp.
- Đọc toàn bộ DEB thành công. Gói `com.luoplayer.ultimatelockscreenplayer_0.1.0-72_iphoneos-arm64.deb`, 21245068 bytes, SHA-256 `0909f311f4fb6659331bcfbe9113ee32fc6224581c28cd617fcb42e8560b8a5b`. `packages/SHA256SUMS-72` kiểm tra đạt; bản chép lên iPhone có cùng SHA.

Còn chờ cài/nghiệm thu ba điều khiển mới và theo dõi dài hạn với nhiều hiệu ứng. Mốc quay lại là ULP 71 đã giữ gói local/trên iPhone; server 2.1.1+ulp2 dùng tiếp.

### Phản hồi sau cài 72

Người dùng báo máy chỉ hơi ấm (chấp nhận được), đôi lúc cảm giác tụt FPS và giật rõ khi quay màn hình. Ưu tiên tối ưu chi phí vẽ ở 73; xem `NATIVE_VISUAL_PERFORMANCE_CONTRACT.md`. Các giới hạn nghiệm thu dài hạn vẫn giữ.

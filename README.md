# AVS iOS App

Ứng dụng iOS/iPadOS native xem phim, hỗ trợ từ iOS 14.

## Tính năng
- Trang chủ, phim mới, tìm kiếm gợi ý và danh sách thể loại tự đồng bộ từ domain hiện tại.
- Chi tiết phim, danh sách tập, lịch sử xem, yêu thích và xem tiếp.
- Phát HLS/MP4, Picture in Picture, AirPlay, đổi tốc độ và tự chuyển tập.
- Chọn tập trước/sau, ghi nhớ vị trí phát và tiếp tục xem.
- Giữ lịch sử, yêu thích và tiến độ khi AnimeVietsub đổi domain; đánh dấu phim đã xem xong.
- Hỗ trợ iPhone/iPad, xoay ngang và đa nhiệm trên iPad.
- Nhận `PLAYER_DATA`, iframe và URL stream tuyệt đối/relative/protocol-relative.
- Có unit test cho bộ tách luồng, viết lại playlist HLS và dữ liệu tiến độ xem.

## Hướng dẫn Build ra IPA từ Windows
Vì Apple khóa hệ sinh thái, việc build native Swift trên Windows yêu cầu đường vòng.

**Cách 1: Push lên GitHub Actions (Khuyên dùng)**
1. Push nhánh lên GitHub hoặc chạy workflow `Build iOS IPA` thủ công.
2. Workflow tạo project bằng XcodeGen, chạy unit test trên iOS Simulator rồi build bản Release.
3. Khi tất cả bước đạt, tải artifact `AVS_iOS_App-IPA` trong trang Actions.

**Cách 2: Build qua máy ảo macOS (VMware/VirtualBox)**
1. Dựng máy ảo macOS, tải Xcode.
2. Trong thư mục dự án chạy `xcodegen generate`, sau đó mở `AVS_iOS_App.xcodeproj` bằng Xcode.
3. Chọn simulator để chạy test, hoặc chọn thiết bị thật và Product → Archive để ký/phân phối ứng dụng.

## Build cục bộ không dùng GitHub

Bạn chỉ cần một máy **macOS có Xcode**. Windows không thể tự build hay ký ứng dụng Swift iOS native; nhưng không cần dùng GitHub Actions.

1. Cài Xcode từ App Store và mở Xcode một lần để chấp nhận license.
2. Cài XcodeGen: `brew install xcodegen`.
3. Trên Mac, tại thư mục dự án chạy:

   ```bash
   chmod +x Scripts/build-local.sh
   ./Scripts/build-local.sh
   ```

Script sẽ tạo project, chạy unit test trên iPhone Simulator và tạo IPA Release không ký ở `Builds/AVS_iOS_App-local.ipa`. Kết quả test nằm tại `build-local/TestResults.xcresult`.

IPA không ký chỉ xác nhận build. Để cài lên iPhone/iPad, mở `AVS_iOS_App.xcodeproj` trong Xcode, chọn Team Apple của bạn ở **Signing & Capabilities**, sau đó Archive/Distribute.

Nếu đang dùng Windows nhưng có Mac riêng, có thể chuyển mã nguồn sang Mac qua SSH rồi chạy đúng script trên; không cần tạo repository hay dùng GitHub.

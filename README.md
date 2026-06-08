# AVS iOS App Skeleton

Ứng dụng iOS native xem phim không quảng cáo.

## Trạng thái
- Đã dựng Core Logic cào stream (`Extractor.swift`).
- Đã dựng giao diện trình phát luồng HLS (`PlayerController.swift`).

## Hướng dẫn Build ra IPA từ Windows
Vì Apple khóa hệ sinh thái, việc build native Swift trên Windows yêu cầu đường vòng.

**Cách 1: Push lên GitHub Actions (Khuyên dùng)**
1. Khởi tạo Git ở folder này.
2. Viết file `.github/workflows/build.yml` gọi runner `macos-latest`.
3. Action sẽ dùng `xcodebuild` để compile và xuất artifact là file `.ipa` cho bạn tải về.

**Cách 2: Build qua máy ảo macOS (VMware/VirtualBox)**
1. Dựng máy ảo macOS, tải Xcode.
2. Kéo folder này vào, dựng `xcodeproj`, cắm iPhone vào máy hoặc chọn Product -> Archive để xuất `.ipa`.

**Cách 3: Chuyển hướng sang React Native / Expo**
Nếu muốn code và build test thẳng trên Windows (chạy qua app Expo Go trên iPhone), tôi có thể tạo project Expo thay vì native Swift.

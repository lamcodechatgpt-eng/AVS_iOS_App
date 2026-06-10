import Foundation

/// Ring buffer chứa log gần nhất để hiện trong app (Windows không xem được Console.app).
/// Mỗi call vào Logger.log() vừa in ra stdout vừa lưu vào buffer (giữ 200 dòng cuối).
final class Logger {
    static let shared = Logger()

    private let queue = DispatchQueue(label: "AVS.Logger", attributes: .concurrent)
    private var buffer: [String] = []
    private let capacity = 200

    private init() {}

    func log(_ message: String) {
        let timestamp = Logger.timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line)
        queue.async(flags: .barrier) {
            self.buffer.append(line)
            if self.buffer.count > self.capacity {
                self.buffer.removeFirst(self.buffer.count - self.capacity)
            }
        }
    }

    /// Trả về toàn bộ log gần nhất nối bằng xuống dòng (an toàn cross-thread).
    func snapshot() -> String {
        var copy: [String] = []
        queue.sync { copy = self.buffer }
        return copy.joined(separator: "\n")
    }

    func clear() {
        queue.async(flags: .barrier) { self.buffer.removeAll() }
    }

    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

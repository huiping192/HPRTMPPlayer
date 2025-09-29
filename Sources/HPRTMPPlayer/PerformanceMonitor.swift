import Foundation
import os

// 性能监控工具
public class PerformanceMonitor {
    public static let shared = PerformanceMonitor()

    private let logger = Logger(subsystem: "HPRTMPPlayer", category: "Performance")
    private var startTime: CFAbsoluteTime = 0
    private var frameCount: Int = 0
    private var lastStatsTime: CFAbsoluteTime = 0

    public struct PlaybackStats {
        public let fps: Double
        public let totalFrames: Int
        public let playbackDuration: TimeInterval
        public let averageFrameTime: Double
        public let droppedFrames: Int
    }

    private var droppedFrameCount: Int = 0
    private var frameTimes: [CFAbsoluteTime] = []

    private init() {}

    // 开始监控
    public func startMonitoring() {
        startTime = CFAbsoluteTimeGetCurrent()
        lastStatsTime = startTime
        frameCount = 0
        droppedFrameCount = 0
        frameTimes.removeAll()

        logger.info("性能监控开始")
    }

    // 记录帧处理
    public func recordFrame() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        frameCount += 1
        frameTimes.append(currentTime)

        // 保持最近1000帧的记录
        if frameTimes.count > 1000 {
            frameTimes.removeFirst()
        }

        // 每秒打印一次统计
        if currentTime - lastStatsTime >= 1.0 {
            logCurrentStats()
            lastStatsTime = currentTime
        }
    }

    // 记录丢帧
    public func recordDroppedFrame() {
        droppedFrameCount += 1
        logger.warning("帧丢失，总计: \(self.droppedFrameCount)")
    }

    // 获取当前统计信息
    public func getCurrentStats() -> PlaybackStats {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let duration = currentTime - startTime
        let fps = duration > 0 ? Double(frameCount) / duration : 0

        var averageFrameTime: Double = 0
//        if frameTimes.count > 1 {
//            let recentFrameTimes = frameTimes.suffix(min(60, frameTimes.count))
//            var totalInterval: Double = 0
//            for i in 1..<recentFrameTimes.count {
//                totalInterval += recentFrameTimes[i] - recentFrameTimes[i-1]
//            }
//            averageFrameTime = totalInterval / Double(recentFrameTimes.count - 1)
//        }

        return PlaybackStats(
            fps: fps,
            totalFrames: frameCount,
            playbackDuration: duration,
            averageFrameTime: averageFrameTime,
            droppedFrames: droppedFrameCount
        )
    }

    // 停止监控
    public func stopMonitoring() {
        let finalStats = getCurrentStats()
        logger.info("性能监控结束")
        logger.info("最终统计: FPS=\(String(format: "%.2f", finalStats.fps)), 总帧数=\(finalStats.totalFrames), 丢帧=\(finalStats.droppedFrames)")
    }

    private func logCurrentStats() {
        let stats = getCurrentStats()
        logger.debug("当前FPS: \(String(format: "%.2f", stats.fps)), 帧数: \(stats.totalFrames), 丢帧: \(stats.droppedFrames)")
    }

    // 内存使用监控
    public func logMemoryUsage() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let result: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let memoryMB = Double(memoryInfo.resident_size) / 1024.0 / 1024.0
            logger.info("内存使用: \(String(format: "%.2f", memoryMB)) MB")
        }
    }
}


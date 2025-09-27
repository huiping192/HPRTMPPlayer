import XCTest
@testable import HPRTMPPlayer

// 核心组件测试，不依赖UIKit
final class CoreTests: XCTestCase {


    func testPerformanceMonitor() {
        // 测试性能监控器
        let monitor = PerformanceMonitor.shared
        monitor.startMonitoring()
        monitor.recordFrame()
        monitor.recordDroppedFrame()

        let stats = monitor.getCurrentStats()
        XCTAssertGreaterThanOrEqual(stats.totalFrames, 1)
        XCTAssertGreaterThanOrEqual(stats.droppedFrames, 1)

        monitor.stopMonitoring()
    }

    func testAudioDecoder() throws {
        // 测试音频解码器
        let decoder = AudioDecoder()
        try decoder.setupForAAC(sampleRate: 44100, channels: 2)

        let testData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let expectation = self.expectation(description: "Audio decode completion")

        decoder.decode(audioData: testData) { data, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testMemoryMonitoring() {
        // 测试内存监控
        let monitor = PerformanceMonitor.shared

        // 这个方法应该不会崩溃
        monitor.logMemoryUsage()

        // 验证基本功能
        XCTAssertNotNil(monitor)
    }

}
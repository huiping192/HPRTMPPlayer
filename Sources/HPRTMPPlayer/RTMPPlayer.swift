import Foundation
import AVFoundation
import HPRTMP

// 跨平台的核心RTMP播放器类
public class RTMPPlayer {

    public enum PlaybackState: Equatable {
        case idle
        case connecting
        case playing
        case paused
        case stopped
        case error(Error)

        public static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.connecting, .connecting),
                 (.playing, .playing),
                 (.paused, .paused),
                 (.stopped, .stopped):
                return true
            case (.error(let lhsError), .error(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }

    // MARK: - Public Properties
    public internal(set) var playbackState: PlaybackState = .idle {
        didSet {
            delegate?.rtmpPlayer(self, didChangeState: playbackState)
        }
    }

    public weak var delegate: RTMPPlayerDelegate?
    public var enableAutoReconnect = true

    // MARK: - Private Properties
    private var rtmpPlayerSession: RTMPPlayerSession!
    private var h264Decoder: H264Decoder?
    private var audioDecoder: AudioDecoder?
    private var audioPlayer: AudioPlayer?

    private var currentURL: String?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var reconnectTimer: Timer?

    // MARK: - Initialization
    public init() {
        setupRTMPSession()
    }

    deinit {
        stop()
    }

    // MARK: - Private Setup
    private func setupRTMPSession() {
        rtmpPlayerSession = RTMPPlayerSession()
        let delegateWrapper = RTMPPlayerDelegateWrapper(rtmpPlayer: self)
        Task {
            await rtmpPlayerSession.setDelegate(delegateWrapper)
        }
    }

    // MARK: - Public Methods
    public func play(_ rtmpURLString: String) {
        guard playbackState != .connecting && playbackState != .playing else {
            print("播放器已在运行状态")
            return
        }

        currentURL = rtmpURLString
        playbackState = .connecting
        resetReconnectState()

        Task {
            await rtmpPlayerSession.play(url: rtmpURLString)
        }
    }

    public func stop() {
        guard playbackState != .idle && playbackState != .stopped else {
            print("播放器已停止")
            return
        }

        playbackState = .stopped
        cleanupResources()

        Task {
            await rtmpPlayerSession.invalidate()
        }
    }

    public func pause() {
        guard playbackState == .playing else {
            print("播放器未在播放状态")
            return
        }

        playbackState = .paused
    }

    public func resume() {
        guard playbackState == .paused else {
            print("播放器未在暂停状态")
            return
        }

        playbackState = .playing
    }

    public func restart() {
        guard let url = currentURL else {
            print("没有可重播的URL")
            return
        }

        stop()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.play(url)
        }
    }

    // MARK: - Performance Monitoring
    public func enablePerformanceMonitoring() {
        // 监控性能
        let currentDelegate = delegate
        delegate = RTMPPlayerPerformanceWrapper(originalDelegate: currentDelegate)
    }

    public func getPerformanceStats() -> PerformanceMonitor.PlaybackStats {
        return PerformanceMonitor.shared.getCurrentStats()
    }

    // MARK: - Private Methods
    internal func attemptReconnect() {
        guard enableAutoReconnect,
              reconnectAttempts < maxReconnectAttempts,
              let url = currentURL else {
            print("不满足重连条件，停止重连")
            return
        }

        reconnectAttempts += 1
        let delay = TimeInterval(reconnectAttempts * 2)

        print("尝试第 \(reconnectAttempts) 次重连，延迟 \(delay) 秒")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performReconnect(url: url)
        }
    }

    private func performReconnect(url: String) {
        print("执行重连: \(url)")

        h264Decoder = nil
        audioDecoder = nil

        Task {
            await rtmpPlayerSession.play(url: url)
        }
    }

    internal func resetReconnectState() {
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    private func cleanupResources() {
        resetReconnectState()
        h264Decoder = nil
        audioDecoder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        delegate?.rtmpPlayerDidCleanupResources(self)
    }

    internal func initializeH264Decoder(with videoHeader: Data) {
        do {
            h264Decoder = try H264Decoder(videoHeader: videoHeader)
            print("H264解码器初始化成功")
        } catch {
            print("H264解码器初始化失败: \(error)")
        }
    }

    internal func processVideoFrame(data: Data, timestamp: Int64) {
        guard let decoder = h264Decoder else {
            print("解码器未初始化，跳过视频帧")
            return
        }

        guard let sampleBuffer = createSampleBuffer(from: data, timestamp: timestamp) else {
            print("创建SampleBuffer失败")
            return
        }

        decoder.decodeSampleBuffer(sampleBuffer) { [weak self] decodedSampleBuffer, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("解码失败: \(error)")
                    PerformanceMonitor.shared.recordDroppedFrame()
                    return
                }

                if let decodedSampleBuffer = decodedSampleBuffer {
                    self?.delegate?.rtmpPlayer(self!, didReceiveVideoSampleBuffer: decodedSampleBuffer)
                    PerformanceMonitor.shared.recordFrame()
                }
            }
        }
    }

    private func createSampleBuffer(from data: Data, timestamp: Int64) -> CMSampleBuffer? {
        guard data.count > 5 else { return nil }

        let naluData = data.subdata(in: 5..<data.count)

        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: naluData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: naluData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, let blockBuffer = blockBuffer else {
            return nil
        }

        _ = naluData.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: naluData.count
            )
        }

        let timeScale: CMTimeScale = 1000
        let presentationTime = CMTime(value: CMTimeValue(timestamp), timescale: timeScale)

        guard let decoder = h264Decoder,
              let formatDescription = decoder.formatDescription else {
            return nil
        }

        var sampleBuffer: CMSampleBuffer?
        let sampleTiming = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: CMTime.invalid
        )

        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [sampleTiming],
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return createStatus == noErr ? sampleBuffer : nil
    }

    internal func initializeAudioDecoder(with audioHeader: Data) {
        do {
            audioDecoder = AudioDecoder()
            audioPlayer = try AudioPlayer()

            let sampleRate: Double = 44100
            let channels: UInt32 = 2

            try audioDecoder?.setupForAAC(sampleRate: sampleRate, channels: channels)
            print("音频解码器初始化成功")
        } catch {
            print("音频解码器初始化失败: \(error)")
        }
    }

    internal func processAudioFrame(data: Data, timestamp: Int64) {
        guard let decoder = audioDecoder,
              let player = audioPlayer else {
            print("音频解码器未初始化，跳过音频帧")
            return
        }

        let audioData = data.subdata(in: 2..<data.count)

        decoder.decode(audioData: audioData) { [weak self] pcmData, error in
            if let error = error {
                print("音频解码失败: \(error)")
                return
            }

            if let pcmData = pcmData {
                do {
                    try player.play(pcmData: pcmData)
                    self?.delegate?.rtmpPlayer(self!, didReceiveAudioData: pcmData, timestamp: timestamp)
                } catch {
                    print("音频播放失败: \(error)")
                }
            }
        }
    }

    // MARK: - Internal Methods for Actor Wrapper
    @MainActor
    internal func handleVideoData(data: Data, timestamp: Int64) {
        guard playbackState != .paused else { return }

        if data.count > 0 && data[0] == 0x17 && data[1] == 0x00 {
            initializeH264Decoder(with: data)
            return
        }

        processVideoFrame(data: data, timestamp: timestamp)
    }

    @MainActor
    internal func handleAudioData(data: Data, timestamp: Int64) {
        guard playbackState != .paused else { return }

        print("收到音频数据: \(data.count) bytes, 时间戳: \(timestamp)")

        if data.count > 0 && (data[0] & 0xF0) == 0xA0 {
            initializeAudioDecoder(with: data)
            return
        }

        processAudioFrame(data: data, timestamp: timestamp)
    }

    @MainActor
    internal func handleStatusChange(_ status: RTMPPlayerSession.Status) {
        print("RTMP状态变化: \(status)")

        switch status {
        case .handShakeStart:
            playbackState = .connecting
        case .handShakeDone:
            print("握手完成")
        case .connect:
            print("连接建立")
        case .playStart:
            playbackState = .playing
            resetReconnectState()
        case .failed(let err):
            playbackState = .error(err)
        case .disconnected:
            if playbackState != .stopped {
                playbackState = .idle
            }
        case .unknown:
            break
        }
    }

    @MainActor
    internal func handleError(_ error: RTMPError) {
        print("RTMP错误: \(error)")
        playbackState = .error(error)
        attemptReconnect()
    }

    @MainActor
    internal func handleMetaData(_ meta: MetaDataResponse) {
        print("收到元数据: \(meta)")

        // 简化元数据处理
        print("视频配置信息已收到")

        let config = VideoConfiguration(
            width: 1920,
            height: 1080,
            dataRate: 1000.0
        )

        delegate?.rtmpPlayer(self, didReceiveVideoConfiguration: config)
    }

    @MainActor
    internal func handleStatistics(_ statistics: Any) {
        print("传输统计: \(statistics)")
        // 由于TransmissionStatistics类型不可用，我们传递一个简化的统计信息
    }
}

// MARK: - Internal Actor Wrapper for RTMPPlayerSessionDelegate
private actor RTMPPlayerDelegateWrapper: RTMPPlayerSessionDelegate {
    weak var rtmpPlayer: RTMPPlayer?

    init(rtmpPlayer: RTMPPlayer) {
        self.rtmpPlayer = rtmpPlayer
    }

    func sessionStatusChange(_ session: RTMPPlayerSession, status: RTMPPlayerSession.Status) {
        Task {
            guard let player = rtmpPlayer else { return }
            await player.handleStatusChange(status)
        }
    }

    func sessionError(_ session: RTMPPlayerSession, error: RTMPError) {
        Task {
            guard let player = rtmpPlayer else { return }
            await player.handleError(error)
        }
    }

    func sessionVideo(_ session: RTMPPlayerSession, data: Data, timestamp: Int64) {
        Task {
            guard let player = rtmpPlayer else { return }
            await player.handleVideoData(data: data, timestamp: timestamp)
        }
    }

    func sessionAudio(_ session: RTMPPlayerSession, data: Data, timestamp: Int64) {
        Task {
            guard let player = rtmpPlayer else { return }
            await player.handleAudioData(data: data, timestamp: timestamp)
        }
    }

    func sessionMeta(_ session: RTMPPlayerSession, meta: MetaDataResponse) {
        Task {
            guard let player = rtmpPlayer else { return }
            await player.handleMetaData(meta)
        }
    }

    func sessionTransmissionStatisticsChanged(_ session: RTMPPlayerSession, statistics: TransmissionStatistics) {
        Task {
            guard let player = rtmpPlayer else { return }
            await player.handleStatistics(statistics)
        }
    }
}

// MARK: - Supporting Types
public struct VideoConfiguration {
    public let width: Int
    public let height: Int
    public let dataRate: Double
}

// MARK: - RTMPPlayerDelegate Protocol
public protocol RTMPPlayerDelegate: AnyObject {
    func rtmpPlayer(_ player: RTMPPlayer, didChangeState state: RTMPPlayer.PlaybackState)
    func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoSampleBuffer sampleBuffer: CMSampleBuffer)
    func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioData data: Data, timestamp: Int64)
    func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoConfiguration config: VideoConfiguration)
    func rtmpPlayer(_ player: RTMPPlayer, didUpdateStatistics statistics: Any) // 简化为Any类型
    func rtmpPlayerDidCleanupResources(_ player: RTMPPlayer)
}

// MARK: - Performance Wrapper
private class RTMPPlayerPerformanceWrapper: RTMPPlayerDelegate {
    weak var originalDelegate: RTMPPlayerDelegate?

    init(originalDelegate: RTMPPlayerDelegate?) {
        self.originalDelegate = originalDelegate
    }

    func rtmpPlayer(_ player: RTMPPlayer, didChangeState state: RTMPPlayer.PlaybackState) {
        switch state {
        case .playing:
            PerformanceMonitor.shared.startMonitoring()
        case .stopped, .error:
            PerformanceMonitor.shared.stopMonitoring()
        default:
            break
        }
        originalDelegate?.rtmpPlayer(player, didChangeState: state)
    }

    func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        originalDelegate?.rtmpPlayer(player, didReceiveVideoSampleBuffer: sampleBuffer)
    }

    func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioData data: Data, timestamp: Int64) {
        originalDelegate?.rtmpPlayer(player, didReceiveAudioData: data, timestamp: timestamp)
    }

    func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoConfiguration config: VideoConfiguration) {
        originalDelegate?.rtmpPlayer(player, didReceiveVideoConfiguration: config)
    }

    func rtmpPlayer(_ player: RTMPPlayer, didUpdateStatistics statistics: Any) {
        originalDelegate?.rtmpPlayer(player, didUpdateStatistics: statistics)
    }

    func rtmpPlayerDidCleanupResources(_ player: RTMPPlayer) {
        originalDelegate?.rtmpPlayerDidCleanupResources(player)
    }
}
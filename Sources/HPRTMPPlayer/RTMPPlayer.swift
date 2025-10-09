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

  private var currentURL: String?
  private var reconnectAttempts = 0
  private let maxReconnectAttempts = 3
  private var reconnectTimer: Timer?
  private var streamTasks: [Task<Void, Never>] = []
  
  // 时间戳基准
  private var firstVideoTimestamp: Int64?
  private var firstAudioTimestamp: Int64?
  
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

    // Start listening to all AsyncStreams
    startStreamListeners()
  }

  private func startStreamListeners() {
    // Listen to status changes
    let statusTask = Task { [weak self] in
      guard let self = self else { return }
      for await status in await rtmpPlayerSession.statusStream {
        await self.handleStatusChange(status)
      }
    }

    // Listen to errors
    let errorTask = Task { [weak self] in
      guard let self = self else { return }
      for await error in await rtmpPlayerSession.errorStream {
        await self.handleError(error)
      }
    }

    // Listen to video data
    let videoTask = Task { [weak self] in
      guard let self = self else { return }
      for await (data, timestamp) in await rtmpPlayerSession.videoStream {
        await self.handleVideoData(data: data, timestamp: timestamp)
      }
    }

    // Listen to audio data
    let audioTask = Task { [weak self] in
      guard let self = self else { return }
      for await (data, timestamp) in await rtmpPlayerSession.audioStream {
        await self.handleAudioData(data: data, timestamp: timestamp)
      }
    }

    // Listen to metadata
    let metaTask = Task { [weak self] in
      guard let self = self else { return }
      for await meta in await rtmpPlayerSession.metaStream {
        await self.handleMetaData(meta)
      }
    }

    // Listen to statistics
    let statisticsTask = Task { [weak self] in
      guard let self = self else { return }
      for await statistics in await rtmpPlayerSession.statisticsStream {
        await self.handleStatistics(statistics)
      }
    }

    streamTasks = [statusTask, errorTask, videoTask, audioTask, metaTask, statisticsTask]
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
    
    // 重置时间戳基准
    firstVideoTimestamp = nil
    firstAudioTimestamp = nil
    
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
    let wrapper = RTMPPlayerPerformanceWrapper(originalDelegate: currentDelegate)
    delegate = wrapper
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
    
    // 重置时间戳基准
    firstVideoTimestamp = nil
    firstAudioTimestamp = nil

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

    // Cancel all stream listening tasks
    streamTasks.forEach { $0.cancel() }
    streamTasks.removeAll()

    h264Decoder = nil
    audioDecoder = nil
    
    // 重置时间戳基准
    firstVideoTimestamp = nil
    firstAudioTimestamp = nil
    
    delegate?.rtmpPlayerDidCleanupResources(self)
  }
  
  internal func initializeH264Decoder(with videoHeader: Data) {
    do {
      h264Decoder = try H264Decoder(videoHeader: videoHeader)
      print("H264解码器和缓冲池初始化成功")
    } catch {
      print("H264解码器初始化失败: \(error)")
    }
  }
  
  internal func processVideoFrame(data: Data, timestamp: Int64) {
    guard let decoder = h264Decoder else {
      print("解码器未初始化，尝试从当前数据初始化解码器")

      // 如果是关键帧或配置数据，尝试初始化解码器
      if data.count > 5 && (data[0] == 0x17 || data[0] == 0x27) {
        print("尝试用当前视频数据初始化解码器")
        initializeH264Decoder(with: data)

        // 递归调用，用新初始化的解码器处理
        if h264Decoder != nil {
          processVideoFrame(data: data, timestamp: timestamp)
        }
      }
      return
    }


    // 计算相对时间戳（从0开始）
    guard let sampleBuffer = createSampleBuffer(from: data, timestamp: timestamp) else {
      print("创建SampleBuffer失败")
      return
    }
    
    _ = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

    decoder.decodeSampleBuffer(sampleBuffer) { [weak self] decodedSampleBuffer, error in
      guard let self = self else { return }

      if let error = error {
        print("解码失败: \(error)")
        PerformanceMonitor.shared.recordDroppedFrame()
        return
      }

      if let decodedSampleBuffer = decodedSampleBuffer {
        self.delegate?.rtmpPlayer(self, didReceiveVideoSampleBuffer: decodedSampleBuffer)
        PerformanceMonitor.shared.recordFrame()
      }
    }
  }
  
  private func createSampleBuffer(from data: Data, timestamp: Int64) -> CMSampleBuffer? {
    guard data.count > 5 else { return nil }
    
    // 记录第一帧时间戳作为基准
    if firstVideoTimestamp == nil {
      firstVideoTimestamp = timestamp
      print("设置视频时间戳基准: \(timestamp)")
    }
    
    // 解析CompositionTime (byte 2-4, 24位有符号整数)
    // RTMP格式: [FrameType+CodecID][AVCPacketType][CompositionTime(3 bytes)][Data...]
    let compositionTime: Int32
    if data.count >= 5 {
      let byte2 = Int32(data[2])
      let byte3 = Int32(data[3])
      let byte4 = Int32(data[4])
      
      // 组合成24位整数
      var ct = (byte2 << 16) | (byte3 << 8) | byte4
      
      // 处理有符号数（24位最高位为符号位）
      if ct & 0x800000 != 0 {
        ct = ct | Int32(bitPattern: 0xFF000000)  // 符号扩展到32位
      }
      compositionTime = ct
    } else {
      compositionTime = 0
    }
    
    // DTS是RTMP的timestamp（相对于第一帧）
    let dts = timestamp - (firstVideoTimestamp ?? 0)
    
    // PTS = DTS + CompositionTime
    // CompositionTime表示显示时间与解码时间的差值
    let pts = dts + Int64(compositionTime)
    
    // 打印时间戳信息用于调试
    if dts % 1000 == 0 || dts < 500 { // 每秒打印一次或前几帧
      print("视频帧 - 原始时间戳: \(timestamp), DTS: \(dts)ms, CT: \(compositionTime)ms, PTS: \(pts)ms")
    }
    
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
    let presentationTime = CMTime(value: CMTimeValue(pts), timescale: timeScale)
    let decodeTime = CMTime(value: CMTimeValue(dts), timescale: timeScale)
    
    guard let decoder = h264Decoder,
          let formatDescription = decoder.formatDescription else {
      return nil
    }
    
    var sampleBuffer: CMSampleBuffer?
    let sampleTiming = CMSampleTimingInfo(
      duration: CMTime.invalid,
      presentationTimeStamp: presentationTime,  // 使用PTS作为显示时间
      decodeTimeStamp: decodeTime  // 使用DTS作为解码时间
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
      print("[AAC音频] 初始化音频解码器")
      print("[AAC音频] AudioSpecificConfig 字节: \(audioHeader.map { String(format: "%02X", $0) }.joined(separator: " "))")

      audioDecoder = AudioDecoder()

      // 使用新的方法从 RTMP 音频头解析配置
      try audioDecoder?.setupFromRTMPAudioHeader(audioHeader)
      print("[AAC音频] 音频解码器初始化成功")
    } catch {
      print("[AAC音频] 音频解码器初始化失败: \(error)")
    }
  }
  
  internal func processAudioFrame(data: Data, timestamp: Int64) {
    guard let decoder = audioDecoder else { return }

    // 只处理 AAC 原始数据 (data[1] == 0x01)
    guard data.count > 2 && data[1] == 0x01 else { return }

    // 提取 AAC 原始数据 (跳过 AudioTagHeader 和 AACPacketType)
    let aacData = data.subdata(in: 2..<data.count)

    // 解码 AAC 为 PCM
    let pcmData: Data
    do {
      pcmData = try decoder.decode(aacData: aacData)
    } catch {
      return
    }

    // 用 PCM 数据创建 SampleBuffer
    guard let sampleBuffer = createPCMSampleBuffer(pcmData: pcmData, timestamp: timestamp, decoder: decoder) else {
      return
    }

    delegate?.rtmpPlayer(self, didReceiveAudioSampleBuffer: sampleBuffer)
  }
  
  private func createPCMSampleBuffer(pcmData: Data, timestamp: Int64, decoder: AudioDecoder) -> CMSampleBuffer? {
    guard !pcmData.isEmpty else { return nil }

    // 记录第一帧音频时间戳作为基准
    if firstAudioTimestamp == nil {
      firstAudioTimestamp = timestamp
    }

    // 计算相对时间戳（从0开始）
    let pts = timestamp - (firstAudioTimestamp ?? 0)

    // 创建 BlockBuffer
    var blockBuffer: CMBlockBuffer?
    let status = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: pcmData.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: pcmData.count,
      flags: 0,
      blockBufferOut: &blockBuffer
    )

    guard status == noErr, let blockBuffer = blockBuffer else {
      return nil
    }

    _ = pcmData.withUnsafeBytes { bytes in
      CMBlockBufferReplaceDataBytes(
        with: bytes.baseAddress!,
        blockBuffer: blockBuffer,
        offsetIntoDestination: 0,
        dataLength: pcmData.count
      )
    }

    // 使用与视频相同的 timeScale (1000 = 毫秒)
    let timeScale: CMTimeScale = 1000
    let presentationTime = CMTime(value: CMTimeValue(pts), timescale: timeScale)

    // 计算音频帧的 duration
    // AAC 每帧 1024 samples，duration = 1024 / sampleRate
    let samplesPerFrame: Int64 = 1024
    let sampleRate = Int64(decoder.currentSampleRate)
    let durationValue = (samplesPerFrame * Int64(timeScale)) / sampleRate
    let duration = CMTime(value: durationValue, timescale: timeScale)

    guard let formatDescription = decoder.formatDescription else {
      return nil
    }

    var sampleBuffer: CMSampleBuffer?
    let sampleTiming = CMSampleTimingInfo(
      duration: duration,  // 设置正确的 duration
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

    // 静默创建，不打印日志（减少性能开销）

    return createStatus == noErr ? sampleBuffer : nil
  }
  
  // MARK: - Internal Methods for Actor Wrapper
  @MainActor
  internal func handleVideoData(data: Data, timestamp: Int64) {
    guard playbackState != .paused else { return }

    // 收到视频数据说明连接和流传输正常
    if playbackState == .connecting {
      playbackState = .playing
      resetReconnectState()
    }

    // 检查是否为H264配置数据 (AVC sequence header)
    if data.count > 1 && data[0] == 0x17 && data[1] == 0x00 {
      initializeH264Decoder(with: data)
      return
    }

    processVideoFrame(data: data, timestamp: timestamp)
  }
  
  @MainActor
  internal func handleAudioData(data: Data, timestamp: Int64) {
    guard playbackState != .paused else { return }

    // 收到音频数据说明连接和流传输正常
    if playbackState == .connecting {
      playbackState = .playing
      resetReconnectState()
    }

    // 检测音频配置包 (SoundFormat=10, AACPacketType=0)
    if data.count > 1 && (data[0] & 0xF0) == 0xA0 && data[1] == 0x00 {
      if audioDecoder?.formatDescription == nil {
        initializeAudioDecoder(with: data)
        return
      }
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
      print("握手完成，开始建立连接")
    case .connect:
      print("连接建立成功，开始播放")
      // 连接成功后立即设置为播放状态
      playbackState = .playing
      resetReconnectState()
    case .playStart:
      print("收到playStart信号")
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
  func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioSampleBuffer sampleBuffer: CMSampleBuffer)
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
  
  func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
    originalDelegate?.rtmpPlayer(player, didReceiveAudioSampleBuffer: sampleBuffer)
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

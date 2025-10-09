import Foundation
import AudioToolbox
import AVFoundation

class AudioDecoder {

  enum AudioDecoderError: Error {
    case unsupportedFormat
    case setupFailed
    case decodeFailed
    case invalidAudioSpecificConfig
    case converterCreationFailed(OSStatus)
    case conversionFailed(OSStatus)
  }

  // 音频配置
  private(set) var currentSampleRate: Double = 44100.0
  private(set) var currentChannels: UInt32 = 2
  private var aacProfile: UInt8 = 2 // AAC-LC

  // AudioConverter
  private var audioConverter: AudioConverterRef?

  // 格式描述
  private(set) var formatDescription: CMAudioFormatDescription?

  // 输入输出格式
  private var inputFormat = AudioStreamBasicDescription()
  private var outputFormat = AudioStreamBasicDescription()

  // AudioSpecificConfig (用作 Magic Cookie)
  private var audioSpecificConfig: Data?

  // 解码缓冲区
  fileprivate var inputData: Data?
  fileprivate var inputDataOffset: Int = 0

  init() {}

  deinit {
    if let converter = audioConverter {
      AudioConverterDispose(converter)
    }
  }

  /// 从 RTMP AudioSpecificConfig 初始化解码器
  /// RTMP AAC Sequence Header 格式: [AudioTagHeader(1)][AACPacketType(1)][AudioSpecificConfig(2+)]
  func setupFromRTMPAudioHeader(_ header: Data) throws {
    guard header.count >= 4 else {
      throw AudioDecoderError.invalidAudioSpecificConfig
    }

    // 跳过 AudioTagHeader 和 AACPacketType，从 byte[2] 开始是 AudioSpecificConfig
    // 标准的 AudioSpecificConfig 对于 AAC-LC 只需要 2 字节
    // 格式: 5 bits audioObjectType + 4 bits samplingFrequencyIndex + 4 bits channelConfiguration + 1 bit frameLengthFlag + 2 bits dependsOnCoreCoder + 1 bit extensionFlag
    let ascStartIndex = 2
    let ascLength = min(2, header.count - ascStartIndex) // 只取前 2 字节

    guard ascLength >= 2 else {
      throw AudioDecoderError.invalidAudioSpecificConfig
    }

    let asc = header.subdata(in: ascStartIndex..<(ascStartIndex + ascLength))

    // 保存 AudioSpecificConfig（只保存有效的 2 字节）
    audioSpecificConfig = asc

    // 解析 AudioSpecificConfig
    // 格式: 5 bits audioObjectType + 4 bits samplingFrequencyIndex + 4 bits channelConfiguration
    let byte0 = asc[0]
    let byte1 = asc[1]

    print("[AAC音频] AudioSpecificConfig 原始字节: \(asc.map { String(format: "%02X", $0) }.joined(separator: " "))")

    // audioObjectType (5 bits)
    aacProfile = (byte0 & 0xF8) >> 3

    // samplingFrequencyIndex (4 bits)
    let sampleRateIndex = ((byte0 & 0x07) << 1) | ((byte1 & 0x80) >> 7)

    // channelConfiguration (4 bits)
    let channelConfig = (byte1 & 0x78) >> 3

    // 转换采样率索引为实际采样率
    currentSampleRate = sampleRateForIndex(sampleRateIndex)
    currentChannels = UInt32(channelConfig)

    print("[AAC音频] 解析结果:")
    print("[AAC音频]   - AAC Profile: \(aacProfile) (2=AAC-LC)")
    print("[AAC音频]   - Sample Rate Index: \(sampleRateIndex) → \(currentSampleRate) Hz")
    print("[AAC音频]   - Channels: \(currentChannels)")

    // 配置输入格式 (AAC-LC)
    inputFormat.mSampleRate = currentSampleRate
    inputFormat.mFormatID = kAudioFormatMPEG4AAC
    inputFormat.mFormatFlags = 0 // AAC 格式不需要特殊标志
    inputFormat.mBytesPerPacket = 0 // 可变
    inputFormat.mFramesPerPacket = 1024 // AAC 标准帧大小
    inputFormat.mBytesPerFrame = 0
    inputFormat.mChannelsPerFrame = currentChannels
    inputFormat.mBitsPerChannel = 0
    inputFormat.mReserved = 0

    // 配置输出格式 (PCM)
    outputFormat.mSampleRate = currentSampleRate
    outputFormat.mFormatID = kAudioFormatLinearPCM
    outputFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
    outputFormat.mBytesPerPacket = currentChannels * 2 // 16-bit per sample
    outputFormat.mFramesPerPacket = 1
    outputFormat.mBytesPerFrame = currentChannels * 2
    outputFormat.mChannelsPerFrame = currentChannels
    outputFormat.mBitsPerChannel = 16
    outputFormat.mReserved = 0

    // 创建 AudioConverter
    var converter: AudioConverterRef?
    let status = AudioConverterNew(&inputFormat, &outputFormat, &converter)

    guard status == noErr, let converter = converter else {
      throw AudioDecoderError.converterCreationFailed(status)
    }

    audioConverter = converter

    // 注意：对于 kAudioFormatMPEG4AAC，AudioConverter 不需要通过 kAudioConverterDecompressionMagicCookie 设置 Magic Cookie
    // AudioConverter 会直接从 AudioStreamBasicDescription (mSampleRate, mChannelsPerFrame) 获取解码所需的配置信息
    // AudioSpecificConfig 已经被解析并用于配置 ASBD，这对解码来说已经足够了
    print("[AAC音频] AudioConverter 将使用 ASBD 配置进行解码 (采样率: \(currentSampleRate) Hz, 声道: \(currentChannels))")

    // 创建 CMAudioFormatDescription
    var formatDesc: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      asbd: &outputFormat,
      layoutSize: 0,
      layout: nil,
      magicCookieSize: 0,
      magicCookie: nil,
      extensions: nil,
      formatDescriptionOut: &formatDesc
    )

    guard formatStatus == noErr, let formatDesc = formatDesc else {
      AudioConverterDispose(converter)
      audioConverter = nil
      throw AudioDecoderError.setupFailed
    }

    formatDescription = formatDesc

    print("[AAC音频] ✅ AudioConverter 和 FormatDescription 创建成功")
  }

  /// 解码 AAC 数据为 PCM
  /// - Parameter aacData: 纯 AAC 帧数据（不带 ADTS 头）
  /// - Returns: PCM 数据
  func decode(aacData: Data) throws -> Data {
    guard let converter = audioConverter else {
      throw AudioDecoderError.setupFailed
    }

    // 设置输入数据（纯 AAC 帧，AudioConverter 使用 Magic Cookie 解码）
    inputData = aacData
    inputDataOffset = 0

    // 准备输出缓冲区
    // AAC 解码后通常是 1024 帧，每帧 currentChannels * 2 字节
    let outputBufferSize = 1024 * Int(currentChannels) * 2
    var outputBuffer = Data(count: outputBufferSize)

    var actualSize = 0
    let outputStatus = outputBuffer.withUnsafeMutableBytes { outputPtr -> OSStatus in
      var audioBufferList = AudioBufferList()
      audioBufferList.mNumberBuffers = 1
      audioBufferList.mBuffers.mNumberChannels = currentChannels
      audioBufferList.mBuffers.mDataByteSize = UInt32(outputBufferSize)
      audioBufferList.mBuffers.mData = outputPtr.baseAddress

      var ioOutputDataPacketSize: UInt32 = 1024 // 期望输出的帧数

      let status = AudioConverterFillComplexBuffer(
        converter,
        audioConverterCallback,
        Unmanaged.passUnretained(self).toOpaque(),
        &ioOutputDataPacketSize,
        &audioBufferList,
        nil
      )

      if status == noErr {
        actualSize = Int(audioBufferList.mBuffers.mDataByteSize)
      }

      return status
    }

    guard outputStatus == noErr else {
      throw AudioDecoderError.conversionFailed(outputStatus)
    }

    // 调整输出数据大小
    outputBuffer = outputBuffer.prefix(actualSize)

    return outputBuffer
  }

  // MARK: - Private Helper

  private func sampleRateForIndex(_ index: UInt8) -> Double {
    switch index {
    case 0: return 96000
    case 1: return 88200
    case 2: return 64000
    case 3: return 48000
    case 4: return 44100
    case 5: return 32000
    case 6: return 24000
    case 7: return 22050
    case 8: return 16000
    case 9: return 12000
    case 10: return 11025
    case 11: return 8000
    case 12: return 7350
    default: return 44100
    }
  }
}

// MARK: - AudioConverter Callback

private func audioConverterCallback(
  inAudioConverter: AudioConverterRef,
  ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
  ioData: UnsafeMutablePointer<AudioBufferList>,
  outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
  inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let userData = inUserData else {
    return kAudioConverterErr_InvalidInputSize
  }

  let decoder = Unmanaged<AudioDecoder>.fromOpaque(userData).takeUnretainedValue()

  guard let inputData = decoder.inputData,
        decoder.inputDataOffset < inputData.count else {
    ioNumberDataPackets.pointee = 0
    return noErr
  }

  // 提供输入数据 - 整个 AAC 帧作为一个包
  let remainingBytes = inputData.count - decoder.inputDataOffset

  inputData.withUnsafeBytes { bytes in
    let ptr = bytes.baseAddress!.advanced(by: decoder.inputDataOffset)
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: ptr)
    ioData.pointee.mBuffers.mDataByteSize = UInt32(remainingBytes)
  }

  decoder.inputDataOffset += remainingBytes
  ioNumberDataPackets.pointee = 1 // 一个 AAC 帧 = 一个包

  // 设置包描述
  if let packetDesc = outDataPacketDescription {
    var description = AudioStreamPacketDescription()
    description.mStartOffset = 0
    description.mVariableFramesInPacket = 1024 // AAC 标准帧大小
    description.mDataByteSize = UInt32(remainingBytes)

    let descPointer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
    descPointer.pointee = description
    packetDesc.pointee = descPointer
  }

  return noErr
}

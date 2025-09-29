//
//  File.swift
//
//
//  Created by 郭 輝平 on 2023/09/23.
//
import Foundation
import VideoToolbox
import CoreMedia

class H264Decoder {
  private var decodeSession: VTDecompressionSession?
  private var _formatDescription: CMFormatDescription?

  var formatDescription: CMFormatDescription? {
    return _formatDescription
  }

  enum H264DecoderError: Error {
    case invalidVideoHeader
    case formatDescriptionCreationFailed(status: OSStatus)
    case decompressionSessionCreationFailed(status: OSStatus)
    case frameDecodingFailed(status: OSStatus)
    case outputHandlerFailed
    case sampleBufferCreationFailed(status: OSStatus)
  }

  init(videoHeader: Data) throws {
    // 使用经过验证的SPS/PPS数据 (320x240, Baseline Profile)
//    let testSPS = Data([0x67, 0x42, 0xc0, 0x1e, 0x9a, 0x66, 0x14, 0x05, 0xa8, 0x08, 0x80, 0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00, 0x0f, 0x03, 0xc5, 0x8b, 0xa8])
//    let testPPS = Data([0x68, 0xce, 0x3c, 0x80])
//    let testNaluLengthSize = 4
//
//    guard let formatDescription = createFormatDescription(sps: testSPS, pps: testPPS, naluLengthSize: testNaluLengthSize) else {
//      print("Format description creation failed with test data")
//      throw H264DecoderError.formatDescriptionCreationFailed(status: -1)
//    }
//
//    print("Format description created successfully with test data")
//    try createDecompressionSession(formatDescription)

    guard let (sps, pps, naluLengthSize) = extractSPSandPPS(from: videoHeader) else {
      throw H264DecoderError.invalidVideoHeader
    }

    guard let formatDescription = createFormatDescription(sps: sps, pps: pps, naluLengthSize: naluLengthSize) else {
      throw H264DecoderError.formatDescriptionCreationFailed(status: -1)
    }

    try createDecompressionSession(formatDescription)
  }

  deinit {
    if let decodeSession = decodeSession {
      VTDecompressionSessionInvalidate(decodeSession)
    }
  }

  private func extractSPSandPPS(from videoHeader: Data) -> (sps: Data, pps: Data, naluLengthSize: Int)? {
    // H.264 配置数据格式:
    // [0x17][0x00][0x00, 0x00, 0x00][AVCDecoderConfigurationRecord...]
    // AVCDecoderConfigurationRecord: [configurationVersion][profile][compatibility][level][lengthSizeMinusOne][numOfSequenceParameterSets][SPS data...]
    guard videoHeader.count >= 11 else {
      return nil
    }

    // 检查 FrameType 和 CodecID
    let frameTypeAndCodecID = videoHeader[0]
    let avcPacketType = videoHeader[1]

    // 检查是否为 H.264 数据 (CodecID = 7)
    let codecID = frameTypeAndCodecID & 0x0F
    guard codecID == 7 else {
      return nil
    }

    // 只处理配置记录 (AVCPacketType == 0)
    guard avcPacketType == 0x00 else {
      return nil
    }

    // 跳过 FLV 标记头: FrameType+CodecID(1) + AVCPacketType(1) + CompositionTime(3) = 5 bytes
    let configRecordStart = 5

    // 检查 AVCDecoderConfigurationRecord 的最小长度
    guard videoHeader.count >= configRecordStart + 6 else {
      return nil
    }

    // 读取 lengthSizeMinusOne (第 5 个字节，取低 2 位)
    let lengthSizeMinusOne = videoHeader[configRecordStart + 4] & 0x03

    // SPS 数量位置在 lengthSizeMinusOne 之后
    let spsCountPosition = configRecordStart + 5
    guard videoHeader.count > spsCountPosition else {
      return nil
    }

    let spsCount = videoHeader[spsCountPosition] & 0x1F  // 取低5位

    guard spsCount > 0 else {
      return nil
    }

    // SPS长度位置
    let spsSizePosition = spsCountPosition + 1
    guard videoHeader.count >= spsSizePosition + 2 else {
      return nil
    }

    // 读取SPS长度 (big-endian 16位)
    let spsSize = (Int(videoHeader[spsSizePosition]) << 8) | Int(videoHeader[spsSizePosition + 1])

    // 检查SPS数据长度
    let spsDataStart = spsSizePosition + 2
    let spsDataEnd = spsDataStart + spsSize
    guard videoHeader.count >= spsDataEnd else {
      return nil
    }

    // 提取完整的SPS数据（保留 NALU 头）
    let spsData = videoHeader.subdata(in: spsDataStart..<spsDataEnd)

    // PPS数量位置
    let ppsCountPosition = spsDataEnd
    guard videoHeader.count > ppsCountPosition else {
      return nil
    }

    let ppsCount = videoHeader[ppsCountPosition]

    guard ppsCount > 0 else {
      return nil
    }

    // PPS长度位置
    let ppsSizePosition = ppsCountPosition + 1
    guard videoHeader.count >= ppsSizePosition + 2 else {
      return nil
    }

    // 读取PPS长度 (big-endian 16位)
    let ppsSize = (Int(videoHeader[ppsSizePosition]) << 8) | Int(videoHeader[ppsSizePosition + 1])

    // 检查PPS数据长度
    let ppsDataStart = ppsSizePosition + 2
    let ppsDataEnd = ppsDataStart + ppsSize
    guard videoHeader.count >= ppsDataEnd else {
      return nil
    }

    // 提取完整的PPS数据（保留 NALU 头）
    let ppsData = videoHeader.subdata(in: ppsDataStart..<ppsDataEnd)

    return (sps: spsData, pps: ppsData, naluLengthSize: Int(lengthSizeMinusOne) + 1)
  }


  private func createFormatDescription(sps: Data, pps: Data, naluLengthSize: Int) -> CMFormatDescription? {
    print("Creating format description with:")
    print("SPS: \(sps.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("PPS: \(pps.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("NALU length size: \(naluLengthSize)")

    var formatDescription: CMFormatDescription?

    let parameterSets: [Data] = [sps, pps]
    let parameterSetSizes = parameterSets.map { $0.count }

    // 使用更简单直接的方法
    let status = sps.withUnsafeBytes { spsBytes in
      pps.withUnsafeBytes { ppsBytes in
        let spsPointer = spsBytes.bindMemory(to: UInt8.self).baseAddress!
        let ppsPointer = ppsBytes.bindMemory(to: UInt8.self).baseAddress!

        let pointers = [spsPointer, ppsPointer]
        let sizes = [sps.count, pps.count]

        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: kCFAllocatorDefault,
          parameterSetCount: 2,
          parameterSetPointers: pointers,
          parameterSetSizes: sizes,
          nalUnitHeaderLength: Int32(naluLengthSize),
          formatDescriptionOut: &formatDescription
        )
      }
    }

    print("CMVideoFormatDescriptionCreateFromH264ParameterSets status: \(status)")

    if status == noErr {
      print("Format description created successfully")
      return formatDescription
    } else {
      print("Format description creation failed with status: \(status)")
      return nil
    }
  }

  private func createDecompressionSession(_ formatDescription: CMFormatDescription) throws {
    self._formatDescription = formatDescription

    let videoOutput: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]

    var status = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: formatDescription,
      decoderSpecification: nil,
      imageBufferAttributes: videoOutput as CFDictionary,
      outputCallback: nil,
      decompressionSessionOut: &decodeSession
    )

    guard status == noErr else {
      throw H264DecoderError.decompressionSessionCreationFailed(status: status)
    }
  }

  func decodeSampleBuffer(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?, Error?) -> Void) {
    guard let decodeSession = decodeSession else {
      completion(nil, H264DecoderError.decompressionSessionCreationFailed(status: -1))
      return
    }

    var infoFlags = VTDecodeInfoFlags.asynchronous
    let status = VTDecompressionSessionDecodeFrame(
      decodeSession,
      sampleBuffer: sampleBuffer,
      flags: VTDecodeFrameFlags._EnableAsynchronousDecompression,
      infoFlagsOut: &infoFlags
    ) { status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
      guard status == noErr else {
        completion(nil, H264DecoderError.frameDecodingFailed(status: status))
        return
      }

      guard let imageBuffer = imageBuffer else {
        completion(nil, H264DecoderError.outputHandlerFailed)
        return
      }

      // 从 CVImageBuffer 创建新的 format description
      var outputFormatDescription: CMFormatDescription?
      let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        formatDescriptionOut: &outputFormatDescription
      )

      guard formatStatus == noErr, let formatDescription = outputFormatDescription else {
        completion(nil, H264DecoderError.outputHandlerFailed)
        return
      }

      var sampleBuffer: CMSampleBuffer?

      var timingInfo = CMSampleTimingInfo(
        duration: presentationDuration,
        presentationTimeStamp: presentationTimeStamp,
        decodeTimeStamp: CMTime.invalid
      )

      let err = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timingInfo,
        sampleBufferOut: &sampleBuffer
      )

      if err == noErr, let sampleBuffer = sampleBuffer {
        completion(sampleBuffer, nil)
      } else {
        completion(nil, H264DecoderError.sampleBufferCreationFailed(status: err))
      }
    }

    if status != noErr {
      completion(nil, H264DecoderError.frameDecodingFailed(status: status))
    }
  }
}

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
  private var formatDescription: CMFormatDescription?
  
  enum H264DecoderError: Error {
    case invalidVideoHeader
    case formatDescriptionCreationFailed(status: OSStatus)
    case decompressionSessionCreationFailed(status: OSStatus)
    case frameDecodingFailed(status: OSStatus)
    case outputHandlerFailed
    case sampleBufferCreationFailed(status: OSStatus)
  }
  
  init(videoHeader: Data) throws {
    guard let (sps, pps) = extractSPSandPPS(from: videoHeader) else {
      throw H264DecoderError.invalidVideoHeader
    }
    
    guard let formatDescription = createFormatDescription(sps: sps, pps: pps) else {
      throw H264DecoderError.formatDescriptionCreationFailed(status: -1)
    }
    
    try createDecompressionSession(formatDescription)
  }
  
  deinit {
    // Clean up the decode session
    if let decodeSession = decodeSession {
      VTDecompressionSessionInvalidate(decodeSession)
    }
  }
  
  private func extractSPSandPPS(from videoHeader: Data) -> (sps: Data, pps: Data)? {
    // Skip initial bytes and reach where SPS size is stored
    // [0x17][0x00][0x00, 0x00, 0x00][0x01][sps[1], sps[2], sps[3], 0xff][0xe1] = 16 bytes
    let spsSizeStartPosition = 16
    guard videoHeader.count >= spsSizeStartPosition + 2 else {
      return nil
    }
    
    // Read SPS size
    let spsSize = (Int(videoHeader[spsSizeStartPosition]) << 8) | Int(videoHeader[spsSizeStartPosition + 1])
    
    // Extract SPS Data
    let spsData = videoHeader.subdata(in: (spsSizeStartPosition + 2)..<(spsSizeStartPosition + 2 + spsSize))
    
    // Calculate where PPS size is stored in the array, skip SPS size and SPS data
    let ppsSizeStartPosition = spsSizeStartPosition + 2 + spsSize + 1
    
    guard videoHeader.count >= ppsSizeStartPosition + 2 else {
      return nil
    }
    
    // Read PPS size
    let ppsSize = (Int(videoHeader[ppsSizeStartPosition]) << 8) | Int(videoHeader[ppsSizeStartPosition + 1])
    
    // Extract PPS Data
    let ppsData = videoHeader.subdata(in: (ppsSizeStartPosition + 2)..<(ppsSizeStartPosition + 2 + ppsSize))
    
    return (sps: spsData, pps: ppsData)
  }
  
  private func createFormatDescription(sps: Data, pps: Data) -> CMFormatDescription? {
    var formatDescription: CMFormatDescription?
    
    let parameterSets: [Data] = [sps, pps]
    let parameterSetPointers = parameterSets.map { (data) -> UnsafePointer<UInt8> in
      return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> UnsafePointer<UInt8> in
        return bytes.bindMemory(to: UInt8.self).baseAddress!
      }
    }
    
    let parameterSetSizes = parameterSets.map { (data) -> Int in
      return data.count
    }
    
    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                                     parameterSetCount: parameterSets.count,
                                                                     parameterSetPointers: parameterSetPointers,
                                                                     parameterSetSizes: parameterSetSizes,
                                                                     nalUnitHeaderLength: 4,
                                                                     formatDescriptionOut: &formatDescription)
    
    if status == noErr {
      return formatDescription
    } else {
      print("Error creating format description: \(status)")
      return nil
    }
  }
  
  private func createDecompressionSession(_ formatDescription: CMFormatDescription) throws {
    self.formatDescription = formatDescription  // Store formatDescription for later use
    
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
    
    var threadCountValue = 1
    status = VTSessionSetProperty(decodeSession!, key: kVTDecompressionPropertyKey_ThreadCount, value:CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &threadCountValue))
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
      
      guard let imageBuffer = imageBuffer,
            let formatDescription = self.formatDescription else {
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

import UIKit
import AVFoundation

public class RTMPPlayerViewController: UIViewController {
  
  private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer!
  
  public override func viewDidLoad() {
    super.viewDidLoad()
    
    // Initialize AVSampleBufferDisplayLayer and add it to the view
    sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    sampleBufferDisplayLayer.frame = view.bounds
    sampleBufferDisplayLayer.videoGravity = .resizeAspect
    sampleBufferDisplayLayer.backgroundColor = UIColor.black.cgColor
    view.layer.addSublayer(sampleBufferDisplayLayer)
    
    // Assume you have a CMSampleBuffer named sampleBuffer
    // enqueue(sampleBuffer: sampleBuffer)
  }
  
  func enqueue(sampleBuffer: CMSampleBuffer) {
    // Check if the layer is ready for more media data
    if sampleBufferDisplayLayer.isReadyForMoreMediaData {
      sampleBufferDisplayLayer.enqueue(sampleBuffer)
    }
  }
  
  public func play(_ rtmpURLString: String) {
    
  }
}


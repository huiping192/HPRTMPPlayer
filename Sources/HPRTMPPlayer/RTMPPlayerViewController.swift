import UIKit
import AVFoundation

public class RTMPPlayerViewController: UIViewController {
  
  private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer!
  
  public override func viewDidLoad() {
    super.viewDidLoad()
    
    configureLayer()
  }
  
  private func configureLayer() {
    sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    sampleBufferDisplayLayer.frame = view.bounds
    sampleBufferDisplayLayer.videoGravity = .resizeAspect
    sampleBufferDisplayLayer.backgroundColor = UIColor.black.cgColor
    view.layer.addSublayer(sampleBufferDisplayLayer)
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


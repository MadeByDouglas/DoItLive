//
//  Preview.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import AVFoundation

class Preview: UIView {

    private var _session: AVCaptureSession?
    
    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var session: AVCaptureSession! {
        get {
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            return previewLayer.session
        }
        
        set(session) {
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            previewLayer.session = session
        }
    }
}

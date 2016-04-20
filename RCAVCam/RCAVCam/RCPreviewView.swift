//
//  RCPreviewView.swift
//  RCAVCam
//
//  Created by Robin on 4/20/16.
//  Copyright © 2016 Robin. All rights reserved.
//


import UIKit
import AVFoundation

class RCPreviewView: UIView {
    
    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    } 
    
    
    var session: AVCaptureSession {
        get {
            let previewLayer: AVCaptureVideoPreviewLayer = self.layer as! AVCaptureVideoPreviewLayer
            return previewLayer.session
        }
        set{
            let previewLayer: AVCaptureVideoPreviewLayer = self.layer as! AVCaptureVideoPreviewLayer
            previewLayer.session = newValue
        }
    }
}

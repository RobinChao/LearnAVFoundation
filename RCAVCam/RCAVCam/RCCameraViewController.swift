//
//  RCCameraViewController.swift
//  RCAVCam
//
//  Created by Robin on 4/20/16.
//  Copyright © 2016 Robin. All rights reserved.
//

import UIKit
import Photos


enum RCAVCamSetupResult {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}


class RCCameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    @IBOutlet weak var previewView: RCPreviewView!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var stillButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    
    //KVO Context Var
    private var CapturingStillImageContext: UInt8 = 1
    private var SessionRunningContext: UInt8 = 2
    
    //Session Management Var
    //Communicate with the session and other session objects on this queue.
    private var sessionQueue: dispatch_queue_t!
    
    //Create the AVCaptureSession.
    private var session: AVCaptureSession!
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    
    //Utilities
    private var setupResult: RCAVCamSetupResult = .Success
    private var sessionRunning: Bool = false
    private var backgroundRecordingID: UIBackgroundTaskIdentifier = 0
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Disable UI. The UI is enable if and only if the session starts running
        cameraButton.enabled = false
        recordButton.enabled = false
        stillButton.enabled = false
        
        // Create the session
        self.session = AVCaptureSession()
        
        //Setup the Preview view
        previewView.session = self.session
        
        // Communicate with the session and other session objects on this queue.
        self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
        
        
        
        //Check video authorization status. Video access is required and audio access is optional
        let status = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
        switch status {
        case .Authorized:
            print("The user has previously granted access to the camera")
        case .NotDetermined:
            //The user has not yet been presented with the option to grant video access
            dispatch_suspend(self.sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (granted) in
                if granted == false {
                    self.setupResult = .CameraNotAuthorized
                }
                dispatch_resume(self.sessionQueue)
            })
        default:
            //The user has previously denied access
            self.setupResult = .CameraNotAuthorized
            break
        }
        
        
        // Setup the capture session
        
        // Video input
        dispatch_async(self.sessionQueue) { 
            if  self.setupResult != .Success {
                return
            }
            
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            
            let videoDevice: AVCaptureDevice = self.dynamicType.deviceWithMediaType(AVMediaTypeVideo, position: .Back)
            let videoDeviceInput: AVCaptureDeviceInput = try! AVCaptureDeviceInput(device: videoDevice)
            
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(videoDeviceInput) {
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue(), { 
                    let statusBarOrientation: UIInterfaceOrientation = UIApplication.sharedApplication().statusBarOrientation
                    var initialVideoOrientation = AVCaptureVideoOrientation.Portrait
                    
                    if statusBarOrientation != UIInterfaceOrientation.Unknown {
                        initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                    }
                    
                    let previewLayer: AVCaptureVideoPreviewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection.videoOrientation = initialVideoOrientation
                })
            } else {
                print("Cound not load video device input to the session")
                self.setupResult = .SessionConfigurationFailed
            }
            
            
            // Audio input
            
            let audioDevice: AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            let audioDeviceInput = try! AVCaptureDeviceInput(device: audioDevice)
            
            if self.session.canAddInput(audioDeviceInput) {
                self.session.addInput(audioDeviceInput)
            } else {
                print("Cound not add audio device inout to the session")
            }
            
            // Movie file output
            let movieFileoutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
            
            if self.session.canAddOutput(movieFileoutput) {
                self.session.addOutput(movieFileoutput)
                
                let connection: AVCaptureConnection = movieFileoutput.connectionWithMediaType(AVMediaTypeVideo)
                if connection.supportsVideoStabilization {
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
                }
                self.movieFileOutput = movieFileoutput
            } else {
                print("Cound not add movie file output to the session")
                self.setupResult = .SessionConfigurationFailed
            }
            
            // Still Image output
            let stillImageOutput: AVCaptureStillImageOutput = AVCaptureStillImageOutput()
            
            if self.session.canAddOutput(stillImageOutput) {
                stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            } else {
                print("Cound not add still image output to the session")
                self.setupResult = .SessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
        }
        
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        dispatch_async(self.sessionQueue) { 
            switch self.setupResult {
            case .Success:
                self.addObserver()
                self.session.startRunning()
                self.sessionRunning = self.session.running
            case .CameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue(), { 
                    let message = NSLocalizedString("RCAVCam doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camaera")
                    let alertController = UIAlertController(title: "RCAVCam", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .Default, handler: { (action) in
                        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                    })
                    alertController.addAction(settingsAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                })
            case .SessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue(), { 
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "RCAVCam", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                })
            }
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        dispatch_async(self.sessionQueue) { 
            if self.setupResult == .Success {
                self.session.stopRunning()
                self.removeObserver()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    
    // Orientation
    override func shouldAutorotate() -> Bool {
        // Disable autorotation of the interface when recording is in progress
        return !(self.movieFileOutput?.recording ?? true)
    }
    
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return .All
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        
        let deviceOrientation = UIDevice.currentDevice().orientation
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            let previewLayer: AVCaptureVideoPreviewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            previewLayer.connection.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        }
    }


    //KVO and Notifications
    private func addObserver() {
        self.session.addObserver(self, forKeyPath: "running", options: .New, context: &SessionRunningContext)
        self.stillImageOutput?.addObserver(self, forKeyPath: "capturingStillImage", options: .New, context: &CapturingStillImageContext)
        
        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.addObserver(self, selector: #selector(self.dynamicType.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput!.device)
        notificationCenter.addObserver(self, selector: #selector(self.dynamicType.sessionRuntimeError(_:)), name: AVCaptureSessionRuntimeErrorNotification, object: self.session)
        
        
        notificationCenter.addObserver(self, selector: #selector(self.dynamicType.sessionWasInterrupted(_:)), name: AVCaptureSessionWasInterruptedNotification, object: self.session)
        notificationCenter.addObserver(self, selector: #selector(self.dynamicType.sessionInterruptionEnded(_:)), name: AVCaptureSessionInterruptionEndedNotification, object: self.session)
    }
    
    private func removeObserver() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        
        self.session.removeObserver(self, forKeyPath: "running", context: &SessionRunningContext)
        self.stillImageOutput?.removeObserver(self, forKeyPath: "capturingStillImage", context: &CapturingStillImageContext)
    }
    
    
    internal override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &CapturingStillImageContext {
            let isCapturingStillImage: Bool = change![NSKeyValueChangeNewKey]!.boolValue
            if isCapturingStillImage {
                dispatch_async(dispatch_get_main_queue(), {
                    self.previewView.layer.opacity = 0.0
                    UIView.animateWithDuration(0.25, animations: { 
                        self.previewView.layer.opacity = 1.0
                    })
                })
            }
        } else if  context == &SessionRunningContext {
            let isSessionRunning: Bool = change![NSKeyValueChangeNewKey]!.boolValue
            dispatch_async(dispatch_get_main_queue(), { 
                self.cameraButton.enabled = isSessionRunning && (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1)
                self.recordButton.enabled = isSessionRunning
                self.stillButton.enabled = isSessionRunning
            })
            
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposureMode: AVCaptureExposureMode.ContinuousAutoExposure, point: devicePoint, monitorSubjectAreaChange: false)
    }
    
    func sessionRuntimeError(notification: NSNotification) {
        let error: NSError = notification.userInfo![AVCaptureSessionErrorKey] as! NSError
        print("Capture session runtime error: \(error.description)")
        
        // Automatically try to restart the session running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if error.code == AVError.MediaServicesWereReset.rawValue {
             dispatch_async(self.sessionQueue, { 
                if self.sessionRunning {
                    self.session.startRunning()
                    self.sessionRunning = self.session.running
                } else {
                    dispatch_async(dispatch_get_main_queue(), { 
                        self.resumeButton.hidden = false
                    })
                }
             })
        } else {
            self.resumeButton.hidden = false
        }
    }
    
    
    func sessionWasInterrupted(notification: NSNotification) {
        // In some scenarios we want to enable the user to resume the session running.
        // For example, if music playback is initiated via control center while using AVCam,
        // then the user can let AVCam resume the session running, which will stop music playback.
        // Note that stopping music playback in control center will not automatically resume the session running.
        // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
        var showResumeButton = false
        
        
        
        guard let value = notification.userInfo![AVCaptureSessionInterruptionReasonKey]!.integerValue else {
            return
        }
        
        let reason: AVCaptureSessionInterruptionReason = AVCaptureSessionInterruptionReason(rawValue: value)!
        
        print("Capture session was interrupted with reason :\(reason)")
        
        if reason == AVCaptureSessionInterruptionReason.AudioDeviceInUseByAnotherClient || reason == AVCaptureSessionInterruptionReason.VideoDeviceInUseByAnotherClient {
            showResumeButton = true
        } else if reason == AVCaptureSessionInterruptionReason.VideoDeviceNotAvailableWithMultipleForegroundApps {
            self.cameraUnavailableLabel.hidden = false
            self.cameraUnavailableLabel.alpha = 0.0
            UIView.animateWithDuration(0.25, animations: { 
                self.cameraUnavailableLabel.alpha = 1.0
            })
        }
        
        if  showResumeButton {
            self.resumeButton.hidden = false
            self.resumeButton.alpha = 0.0
            UIView.animateWithDuration(0.25, animations: { 
                self.resumeButton.alpha = 1.0
            })
        }
    }
    
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !self.resumeButton.hidden {
            UIView.animateWithDuration(0.25, animations: { 
                self.resumeButton.alpha = 0.0
                }, completion: { (finished) in
                    self.resumeButton.hidden = true
            })
        }
        
        if !self.cameraUnavailableLabel.hidden {
            UIView.animateWithDuration(0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
                }, completion: { (finished) in
                    self.cameraUnavailableLabel.hidden = true
            })
        }
    }
    
    
    // Actions
    @IBAction func resumeInterruptedSession(sender: UIButton) {
        dispatch_async(self.sessionQueue) { 
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            
            
            self.session.startRunning()
            self.sessionRunning = self.session.running
            if !self.session.running {
                dispatch_async(dispatch_get_main_queue(), { 
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "RCAVCam", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                })
            } else {
                dispatch_async(dispatch_get_main_queue(), { 
                    self.resumeButton.hidden = true
                })
            }
        }
    }
    
    @IBAction func toggleMovieRecording(button: UIButton) {
        // Disable the Camera button until recording finishes, and disable the Record button until recording starts or finishes. See the
        // AVCaptureFileOutputRecordingDelegate methods.
        
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        
        dispatch_async(self.sessionQueue) { 
            if !self.movieFileOutput!.recording {
                if UIDevice.currentDevice().multitaskingSupported {
                    // Setup background task. This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
                    // callback is not received until AVCam returns to the foreground unless you request background execution time.
                    // This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                    // To conclude this background execution, -endBackgroundTask is called in
                    // -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
                    self.backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler(nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let connect: AVCaptureConnection = self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo)
                let previewLayer: AVCaptureVideoPreviewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                connect.videoOrientation = previewLayer.connection.videoOrientation
                
                
                // Turn OFF flash for video recording.
                self.dynamicType.setFlashMode(AVCaptureFlashMode.Off, device: self.videoDeviceInput!.device)
                
                
                // Start recording to a temporary file.
                let outputFileName = NSProcessInfo.processInfo().globallyUniqueString
                let outputFilePath: NSURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(outputFileName).URLByAppendingPathExtension("mov")
                self.movieFileOutput?.startRecordingToOutputFileURL(outputFilePath, recordingDelegate: self)
            } else {
                self.movieFileOutput?.stopRecording()
            }
        }
    }
    
    @IBAction func changeCamera(button: UIButton) {
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false
        
        
        dispatch_async(self.sessionQueue) { 
            let currentVideoDevice: AVCaptureDevice = self.videoDeviceInput!.device
            var preferredPosition: AVCaptureDevicePosition = AVCaptureDevicePosition.Unspecified
            let currentPosition: AVCaptureDevicePosition = currentVideoDevice.position
            
            switch currentPosition{
            case .Unspecified, .Front:
                preferredPosition = .Back
            case .Back:
                preferredPosition = .Front
            }
            
            
            let videoDevice: AVCaptureDevice = self.dynamicType.deviceWithMediaType(AVMediaTypeVideo, position: preferredPosition)
            let videoDeviceInput: AVCaptureDeviceInput = try! AVCaptureDeviceInput(device: videoDevice)
            
            self.session.beginConfiguration()
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
            self.session.removeInput(self.videoDeviceInput)
            
            if self.session.canAddInput(videoDeviceInput) {
                
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)
                
                self.dynamicType.setFlashMode(.Auto, device: videoDevice)
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.dynamicType.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDevice)
                
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                self.session.addInput(self.videoDeviceInput)
            }
            
            let connection: AVCaptureConnection = self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo)
            if connection.supportsVideoStabilization {
                connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
            }
            
            self.session.commitConfiguration()
            
            dispatch_async(dispatch_get_main_queue(), { 
                self.cameraButton.enabled = true
                self.recordButton.enabled = true
                self.stillButton.enabled = true
            })
        }
    }
    
    @IBAction func snapStillImage(sender: UIButton) {
        dispatch_async(self.sessionQueue) { 
            let connection: AVCaptureConnection = self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)
            let previewLayer: AVCaptureVideoPreviewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            
            // Update the orientation on the still image output video connection before capturing.
            connection.videoOrientation = previewLayer.connection.videoOrientation
            
            
            // Flash set to Auto for Still Capture.
            self.dynamicType.setFlashMode(.Auto, device: self.videoDeviceInput!.device)
            
            
            // Capture a still image.
            self.stillImageOutput?.captureStillImageAsynchronouslyFromConnection(connection, completionHandler: { (imageDataSampleBuffer, error) in
                // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                let iamgeData: NSData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                PHPhotoLibrary.requestAuthorization({ (status) in
                    if status == PHAuthorizationStatus.Authorized {
                        // To preserve the metadata, we create an asset from the JPEG NSData representation.
                        // Note that creating an asset from a UIImage discards the metadata.
                        // In iOS 9, we can use -[PHAssetCreationRequest addResourceWithType:data:options].
                        // In iOS 8, we save the image to a temporary file and use +[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:].
                        PHPhotoLibrary.sharedPhotoLibrary().performChanges({ 
                            PHAssetCreationRequest.creationRequestForAsset().addResourceWithType(PHAssetResourceType.Photo, data: iamgeData, options: nil)
                            }, completionHandler: { (success, error) in
                                if !success {
                                    print("Error occurred while saving image to photo library: \(error?.description)")
                                }
                        })
                    } else {
                        print("Could not capture still image: \(error.description)")
                    }
                }) 
            })
        }
    }
    
    @IBAction func focusAndExposeTap(gestureRecognizer: UIGestureRecognizer) {
        let devicePoint: CGPoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        focusWithMode(.AutoFocus, exposureMode: .AutoExpose, point: devicePoint, monitorSubjectAreaChange: true)
    }
    
    
    // File Output Recording Delegate
    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        
        // Enable the Record button to let the user stop the recording.
        dispatch_async(dispatch_get_main_queue()) { 
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), forState: .Normal)
        }
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
        // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
        // is back to NO — which happens sometime after this method returns.
        // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
        
        let currentBackgroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        let cleanup = {
            if (try? NSFileManager.defaultManager().removeItemAtURL(outputFileURL)) == nil {
                print("Error removing temporary file")
            }
            if (currentBackgroundRecordingID != UIBackgroundTaskInvalid) {
                UIApplication.sharedApplication().endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        
        var success = true
        
        if (error != nil) {
            print("Movie file finishing error: \(error)")
            success = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey]?.boolValue ?? false
        }
        if (success) {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization() { status in
                if (status == .Authorized) {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.sharedPhotoLibrary().performChanges(
                        {
                            // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                            // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
//                            if #available(iOS 9.0, *) {
                                let options = PHAssetResourceCreationOptions()
                                options.shouldMoveFile = true
                                let changeRequest = PHAssetCreationRequest.creationRequestForAsset()
                                changeRequest.addResourceWithType(.Video, fileURL: outputFileURL, options: options)
//                            } else {
//                                PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(outputFileURL)
//                            }
                        }, completionHandler: { success, error in
                            if (!success) {
                                NSLog("Could not save movie to photo library: \(error)")
                            }
                            cleanup()
                        }
                    )
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        // Enable teh Camera and Record buttons to let the user switch camera and start another recording.
        dispatch_async(dispatch_get_main_queue()) {
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.enabled = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), forState: .Normal)
        }
    }
    
    
    
    //Device
    func focusWithMode(focusMode: AVCaptureFocusMode, exposureMode: AVCaptureExposureMode, point: CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(self.sessionQueue) { 
            let device = self.videoDeviceInput?.device!
            do {
                try device!.lockForConfiguration()
                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                
                if (device!.focusPointOfInterestSupported) && (device!.isFocusModeSupported(focusMode)) {
                    device?.focusPointOfInterest = point
                    device?.focusMode = focusMode
                }
                
                if (device!.exposurePointOfInterestSupported) && (device!.isExposureModeSupported(exposureMode)) {
                    device?.exposurePointOfInterest = point
                    device?.exposureMode = exposureMode
                }
                
                device?.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device?.unlockForConfiguration()
                
            } catch let error as NSError {
                print("Could not lock device for configuration: \(error.description)")
            }
        }
    }
    
    
    static func setFlashMode(flashMode: AVCaptureFlashMode, device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch let error as NSError {
                print("Could not lock device for configuration: \(error.description)")
            }
        }
    }
    
    
    static func deviceWithMediaType(mediaType: String, position: AVCaptureDevicePosition) -> AVCaptureDevice {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType) as! [AVCaptureDevice]
        var captureDevice = devices.first
        
        for device: AVCaptureDevice in devices {
            if  device.position == position {
                captureDevice = device
                break
            }
        }
        return captureDevice!
    }
    
}


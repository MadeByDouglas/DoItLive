//
//  CameraViewController.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import TwitterKit
import FBSDKShareKit
import SwiftyJSON
import SAConfettiView
import JFMinimalNotifications

private var CapturingStillImageContext = UnsafeMutablePointer<Void>.alloc(1)
private var SessionRunningContext = UnsafeMutablePointer<Void>.alloc(1)

private enum AVCamSetupResult: Int {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}

protocol CameraViewControllerDelegate: class {
    func cameraControllerDidSendAssetAndTweet(controller: CameraViewController, asset: PHAsset, tweet: String)
}

class CameraViewController: UIViewController, /*AVCaptureFileOutputRecordingDelegate,*/ UITextViewDelegate {

    weak var delegate: CameraViewControllerDelegate?
    
    @IBOutlet weak var previewView: Preview!
    
    @IBOutlet weak var feedButton: UIButton!
    
    @IBOutlet weak var userNameLabel: UILabel!
    @IBOutlet weak var postTextView: UITextView!
    @IBOutlet weak var postTapLabel: UILabel!
    @IBOutlet weak var postCountLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var networkIndicator: UIActivityIndicatorView!
    
    @IBOutlet weak var shutterButton: UIButton!
    @IBOutlet weak var switchButton: UIButton!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    
    // Session management.
    private var sessionQueue: dispatch_queue_t!
    private var session: AVCaptureSession!
    private var videoDeviceInput: AVCaptureDeviceInput!
    private var movieFileOutput: AVCaptureMovieFileOutput!
    private var stillImageOutput: AVCaptureStillImageOutput!
    
    // Utilities.
    private var setupResult: AVCamSetupResult = .CameraNotAuthorized
    private var sessionRunning: Bool = false
    private var backgroundRecordingID: UIBackgroundTaskIdentifier = 0
    let toggleAnimation = CATransition()
    var blurView: UIVisualEffectView!
    //    var cameraIsReady: Bool! //handled by KVO now
    
    //instant mode
    var newPhotoReady: Bool!
    var didSendPhoto: Bool!
    
    let defaults = NSUserDefaults.standardUserDefaults()
    let firstInstantSwitch = "firstInstantSwitch"
    
    // Photos
    var photosData = Photos()
   
    // Visual Effects
    lazy var confettiView: SAConfettiView = {
      let view = SAConfettiView(frame: self.view.bounds)
        view.userInteractionEnabled = false
        return view
    }()
    
    lazy var successNotify: JFMinimalNotification = {
        let notify = JFMinimalNotification(style: .Success, title: "Success!", subTitle: "Your photo is now LIVE", dismissalDelay: 1.5)
        return notify
    }()
    
    lazy var errorNotify: JFMinimalNotification = {
        let notify = JFMinimalNotification(style: .Error, title: "Whoops!", subTitle: "Something went wrong, check your network connection", dismissalDelay: 1.5)
        return notify
    }()
    
    var timer: NSTimer?
    
    //Sound Effects
    var player: AVAudioPlayer?
    
    func playSoundFile(name: String) {
        let url = NSBundle.mainBundle().URLForResource(name, withExtension: "mp3")!
        
        do {
            player = try AVAudioPlayer(contentsOfURL: url)
            guard let player = player else { return }
            
            player.prepareToPlay()
            player.play()
        } catch let error as NSError {
            print(error.description)
        }
    }
    
    //MARK: Loading View
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(confettiView)
        self.view.addSubview(successNotify)
        self.view.addSubview(errorNotify)
        
        postTextView.delegate = self

        newPhotoReady = false
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        enableUI(false)
        setupAnimations()
        
        createSession()
        setupCamerasAndConfigureSession()
        
        // Photos
//        PHPhotoLibrary.sharedPhotoLibrary().registerChangeObserver(self)
        
        //display user info
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate

        if Twitter.sharedInstance().sessionStore.session()?.userID != nil {
            if let userName = appDelegate.twitterUserName {
                userNameLabel.text = "@\(userName)"
            }
        }
        if FBSDKAccessToken.currentAccessToken() != nil {
            if let name = appDelegate.facebookUserName {
                userNameLabel.text = name
            }
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        didSendPhoto = false
        activateCamera()
        authorizePhotos()
        
        //tweet
        if let savedTweet = NSUserDefaults.standardUserDefaults().stringForKey(UserDefaultsKeys.savedTweet.rawValue) {
            if savedTweet == "" || savedTweet == " " {
                postTextView.text = ""
            } else {
                postTextView.text = savedTweet
            }
        } else {
            postTextView.text = ""
        }
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        blurPreview(false)
        
    }
    
    //MARK: Unloading View
    
    override func viewWillDisappear(animated: Bool) {
        blurPreview(true)

        super.viewWillDisappear(animated)
    }
    
    override func viewDidDisappear(animated: Bool) {
        dispatch_async(self.sessionQueue) {
            if self.setupResult == AVCamSetupResult.Success {
                self.session.stopRunning()
                self.removeCamObservers()
            }
        }
        super.viewDidDisappear(animated)
    }
    
//    deinit {
////        PHPhotoLibrary.sharedPhotoLibrary().unregisterChangeObserver(self)
//        print("camera was deinit")
//    }
    
    //MARK: View Preferences
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    func blurPreview(sender: Bool) {
        if self.setupResult == AVCamSetupResult.Success {
            guard let _ = blurView else {
                return
            }
            
            UIView.animateWithDuration(0.3) { () -> Void in
                if sender == true {
                    self.blurView.alpha = 1
                } else {
                    self.blurView.alpha = 0
                }
            }
        }
    }
    
    func showOptionsMenu() {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.ActionSheet)
        alertController.modalPresentationStyle = UIModalPresentationStyle.Popover
        
        if let twitterUser = Twitter.sharedInstance().sessionStore.session()?.userID {
            alertController.addAction(UIAlertAction(title: "Twitter Feed", style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction) -> Void in
                
                if UIApplication.sharedApplication().canOpenURL(NSURL(string: "twitter://")!) {
                    let twitterProfileURL = NSURL(string: "twitter:///\(twitterUser)")
                    UIApplication.sharedApplication().openURL(twitterProfileURL!)
                    
                } else {
                    let twitterProfileURL = NSURL(string: "https://twitter.com/\(twitterUser)")
                    UIApplication.sharedApplication().openURL(twitterProfileURL!)
                }
            }))
        }
        
        if let facebookUser = FBSDKAccessToken.currentAccessToken()?.userID {
            alertController.addAction(UIAlertAction(title: "Facebook Wall", style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction) -> Void in

                if UIApplication.sharedApplication().canOpenURL(NSURL(string: "fb://")!) {
                    let facebookProfileURL = NSURL(string: "fb://profile?app_scoped_user_id=\(facebookUser)")
                    UIApplication.sharedApplication().openURL(facebookProfileURL!)
                } else {
                    let facebookProfileURL = NSURL(string: "https://facebook.com/\(facebookUser)")
                    UIApplication.sharedApplication().openURL(facebookProfileURL!)
                }
            }))
        }

        alertController.addAction(UIAlertAction(title: "Log Out", style: UIAlertActionStyle.Destructive, handler: { (action: UIAlertAction ) -> Void in
            NSUserDefaults.standardUserDefaults().setBool(false, forKey: UserDefaultsKeys.firstView.rawValue)
            self.dismissViewControllerAnimated(true) {
                //log out notification
                NSNotificationCenter.defaultCenter().postNotificationName(Notify.Logout.rawValue, object: nil)
            }
        }))

        alertController.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: { (action: UIAlertAction) -> Void in
            
        }))
        
        if self.presentedViewController == nil {
            self.presentViewController(alertController, animated: true, completion: nil)
        } else {
            print("\(classForCoder).alertController something already presented")
        }
    }
    
    //MARK: Buttons
    
    @IBAction func didTapShutter(sender: UIButton) {
        captureStillImage()
    }
    
    @IBAction func didTapSwitchCamera(sender: UIButton) {
        switchCameras()
    }
    
    @IBAction func didTapFeed(sender: UIButton) {
        
        showOptionsMenu()
        
//        NSUserDefaults.standardUserDefaults().setBool(false, forKey: UserDefaultsKeys.firstView.rawValue)
//        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    @IBAction func didTapResume(sender: UIButton) {
        resumeSession()
    }
    
    @IBAction func focusAndExposeTap(gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        self.focusWithMode(AVCaptureFocusMode.AutoFocus, exposeWithMode: AVCaptureExposureMode.AutoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }
    
    @IBAction func didTapInstantSwitch(sender: UISwitch) {
        if !defaults.boolForKey(firstInstantSwitch) {
            dispatch_async(dispatch_get_main_queue()) {
                let message = NSLocalizedString("Photo gets posted as soon as you tap the shutter", comment: "One time alert explaining Instant Mode")
                let alertController = UIAlertController(title: "Instant Mode", message: message, preferredStyle: UIAlertControllerStyle.Alert)
                let cancelAction = UIAlertAction(title: NSLocalizedString("Sweet", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
                alertController.addAction(cancelAction)
                self.presentViewController(alertController, animated: true, completion: nil)
            }
            defaults.setBool(true, forKey: firstInstantSwitch)
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
//    func photoLibraryDidChange(changeInstance: PHChange) {
//        // Check if there are changes to the assets we are showing.
//        guard let
//            assetsFetchResults = self.photosData.assetsFetchResults,
//            collectionChanges = changeInstance.changeDetailsForFetchResult(assetsFetchResults)
//            else {return}
//        
//        //Instant publish
//        if self.newPhotoReady == true {
//            dispatch_async(dispatch_get_main_queue()) {
//                self.newPhotoReady = false
//
//                self.activityIndicator.startAnimating()
//                self.enableUI(false)
//                if let asset = collectionChanges.fetchResultAfterChanges[0] as? PHAsset {
//                    self.delegate?.cameraControllerDidSendAssetAndTweet(self, asset: asset, tweet: self.postTextView.text)
//                    self.didSendPhoto = true
//                    
//                    self.activityIndicator.stopAnimating()
//                    self.enableUI(true)
//                    self.postTextView.text.removeAll()
//                    self.postTextView.text = App.Hashtag.rawValue
//                    if let currentText = self.postTextView.text {
//                        let remainingCharacters = 140 - currentText.characters.count
//                        self.postCountLabel.text = "Characters left: \(remainingCharacters.description)"
//                        NSUserDefaults.standardUserDefaults().setObject(currentText, forKey: UserDefaultsKeys.savedTweet.rawValue)
//                    }
//                }
//            }
//        }
//    }
    
    // MARK: - TextView Delegate
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        self.view.endEditing(true)
        super.touchesBegan(touches, withEvent: event)
    }
    
    func textViewDidBeginEditing(textView: UITextView) {
        postTapLabel.hidden = true
        if let currentText = textView.text {
            let remainingCharacters = 140 - currentText.characters.count
            postCountLabel.text = "Characters left: \(remainingCharacters.description)"
        }
    }
    
    func textViewDidEndEditing(textView: UITextView) {
        if textView.text == nil || textView.text == "" {
            postTapLabel.hidden = false
        }
        textView.resignFirstResponder()
        let tweet = textView.text
        NSUserDefaults.standardUserDefaults().setObject(tweet, forKey: UserDefaultsKeys.savedTweet.rawValue)
    }
    
    func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool {
        //enable tab
        if text == "\t" {
            textView.endEditing(true)
            return false
        }
        
        //also check when deleting
        if range.length==1 && text.isEmpty {
            if let currentText = textView.text {
                let remainingCharacters = 140 - (currentText.characters.count - 1)
                postCountLabel.text = "Characters left: \(remainingCharacters.description)"
            }
            return true
        }
        
        if let textErrors = Helper.isValidTweetWithErrors(textView.text, possibleNewCharacter: text) {
            print(textErrors)
            return false
        } else {
            if let currentText = textView.text {
                let remainingCharacters = 140 - (currentText.characters.count + text.characters.count)
                postCountLabel.text = "Characters left: \(remainingCharacters.description)"
            }
            return true
        }
    }
    
}


//MARK: - Facebook Delegate

extension CameraViewController: FBSDKSharingDelegate {
    func sharer(sharer: FBSDKSharing!, didCompleteWithResults results: [NSObject : AnyObject]!) {
        networkIndicator.stopAnimating()
        celebrate()
    }
    
    func sharer(sharer: FBSDKSharing!, didFailWithError error: NSError!) {
        networkIndicator.stopAnimating()
        showNetworkError()
        print(error)
    }
    
    func sharerDidCancel(sharer: FBSDKSharing!) {
        //probably shouldn't ever happen
        networkIndicator.stopAnimating()
    }
    
    func celebrate() {

        successNotify.show()
        playSoundFile("yay")
        
        if confettiView.isActive() {
            confettiView.stopConfetti()
        }
        
        if timer != nil {
            timer?.invalidate()
        }
        
        self.confettiView.startConfetti()
        timer = NSTimer.scheduledTimerWithTimeInterval(1.5, target: self, selector: #selector(endCelebrate(_:)), userInfo: nil, repeats: false)
    }
    
    func endCelebrate(sender: NSTimer) {
        self.confettiView.stopConfetti()
        sender.invalidate()
    }
    
    func showNetworkError() {
        errorNotify.show()
    }
    

    //MARK: - Twitter Methods

    func tweetWithContent(tweetString: String, tweetImage: NSData) {
        
        let uploadUrl = "https://upload.twitter.com/1.1/media/upload.json"
        let updateUrl = "https://api.twitter.com/1.1/statuses/update.json"
        let imageString = tweetImage.base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
        
        let client = TWTRAPIClient.clientWithCurrentUser()
        
        let request = client.URLRequestWithMethod("POST", URL: uploadUrl, parameters: ["media": imageString], error: nil)
        client.sendTwitterRequest(request, completion: { (urlResponse, data, connectionError) -> Void in
            
            if let dictionary = JSON(data: data!).dictionaryObject {
            
                let message: [NSObject:AnyObject] = ["status": tweetString, "media_ids": dictionary["media_id_string"]!]
                let request = client.URLRequestWithMethod("POST",
                    URL: updateUrl, parameters: message, error:nil)
                
                client.sendTwitterRequest(request, completion: { (response, data, connectionError) -> Void in
                    self.networkIndicator.stopAnimating()
                    if connectionError == nil {
                        self.celebrate()
                    } else {
                        self.showNetworkError()
                    }
                
                })
            } else {
                self.networkIndicator.stopAnimating()
            }
        })
    }
    
//    func nsdataToJSON (data: NSData) -> AnyObject? {
//        do {
//            return try NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers)
//        } catch let myJSONError {
//            print(myJSONError)
//        }
//        return nil
//    }
}

extension CameraViewController {
    
    //MARK: Initial Setup
    
    func enableUI(sender: Bool) {
        shutterButton.enabled = sender
        //        recordButton.enabled = sender
        // Only enable the ability to change camera if the device has more than one camera.
        switchButton.enabled = sender && (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1)
        
    }
    
    func setupAnimations() {
        toggleAnimation.duration = 0.5
        toggleAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
        toggleAnimation.type = "oglFlip"
    }
    
    func createSession() {
        
        // Create the AVCaptureSession.
        self.session = AVCaptureSession()
        
        // Setup the preview view.
        self.previewView.session = self.session
        
        // Communicate with the session and other session objects on this queue.
        self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
        
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        switch AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo) {
        case .Authorized:
            // The user has previously granted access to the camera.
            self.setupResult = AVCamSetupResult.Success
            
            break
        case .NotDetermined:
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            dispatch_suspend(self.sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo) {granted in
                if granted {
                    self.setupResult = AVCamSetupResult.Success
                } else {
                    self.setupResult = AVCamSetupResult.CameraNotAuthorized
                }
                dispatch_resume(self.sessionQueue)
            }
        default:
            // The user has previously denied access.
            self.setupResult = AVCamSetupResult.CameraNotAuthorized
        }
        
    }
    
    func setupCamerasAndConfigureSession() {
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        dispatch_async(self.sessionQueue) {
            guard self.setupResult == AVCamSetupResult.Success else {
                return
            }
            
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            let videoDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            let videoDeviceInput: AVCaptureDeviceInput!
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                
            } catch let error as NSError {
                videoDeviceInput = nil
                NSLog("Could not create video device input: %@", error)
            } catch _ {
                fatalError()
            }
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(videoDeviceInput) {
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue()) {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for AAPLPreviewView and UIView
                    // can only be manipulated on the main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                    // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                    
                    // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
                    // -[viewWillTransitionToSize:withTransitionCoordinator:].
                    let statusBarOrientation = UIApplication.sharedApplication().statusBarOrientation
                    var initialVideoOrientation = AVCaptureVideoOrientation.Portrait
                    if statusBarOrientation != UIInterfaceOrientation.Unknown {
                        initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                    }
                    
                    let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection.videoOrientation = initialVideoOrientation
                    
                    let preview = self.previewView
                    let blur = UIBlurEffect(style: UIBlurEffectStyle.Dark)
                    self.blurView = UIVisualEffectView(effect: blur)
                    self.blurView.frame = CGRectMake(0, 0, preview.frame.width, preview.frame.height)
                    self.blurView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
                    self.blurView.alpha = 0
                    preview.insertSubview(self.blurView, aboveSubview: preview)
                    
                    
                }
            } else {
                NSLog("Could not add video device input to the session")
                self.setupResult = AVCamSetupResult.SessionConfigurationFailed
            }
            
            let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            let audioDeviceInput: AVCaptureDeviceInput!
            do {
                audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                
            } catch let error as NSError {
                audioDeviceInput = nil
                NSLog("Could not create audio device input: %@", error)
            } catch _ {
                fatalError()
            }
            
            if self.session.canAddInput(audioDeviceInput) {
                self.session.addInput(audioDeviceInput)
            } else {
                NSLog("Could not add audio device input to the session")
            }
            
            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.addOutput(movieFileOutput)
                let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                if connection?.supportsVideoStabilization ?? false {
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                NSLog("Could not add movie file output to the session")
                self.setupResult = AVCamSetupResult.SessionConfigurationFailed
            }
            
            let stillImageOutput = AVCaptureStillImageOutput()
            if self.session.canAddOutput(stillImageOutput) {
                self.session.sessionPreset = AVCaptureSessionPresetPhoto
                stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            } else {
                NSLog("Could not add still image output to the session")
                self.setupResult = AVCamSetupResult.SessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
        }
    }
    
    //MARK: Recurring Setup
    
    func activateCamera() {
        //Handle iOS authorization and activate camera as appropriate
        guard let queue = sessionQueue else {
            self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
            activateCamera()
            return
        }
        
        dispatch_async(queue) {
            switch self.setupResult {
            case .Success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.running
                break
            case .CameraNotAuthorized:
                self.showNoAccessMessage()
                break
            case .SessionConfigurationFailed:
                self.showCameraFailMessage()
                break
            }
        }
        
    }
    
    // MARK: - Handle Authorization
    
    func authorizePhotos() {
        //Photos status check
        switch PHPhotoLibrary.authorizationStatus() {
        case .Authorized:
            print("photos authorized")
            break
        case .Denied:
            print("photos denied")
            // if camera is not authorized we already showed no access message
            if setupResult != .CameraNotAuthorized {
                showNoAccessMessage()
            }
            break
        case .Restricted:
            print ("photos restricted")
            // if camera is not authorized we already showed no access message
            if setupResult != .CameraNotAuthorized {
                showNoAccessMessage()
            }
            break
        case .NotDetermined:
            print ("photos not determined")
            dispatch_suspend(self.sessionQueue)
            PHPhotoLibrary.requestAuthorization({ (status: PHAuthorizationStatus) -> Void in
                if status == PHAuthorizationStatus.Authorized {
                    
                    self.photosData.setupPhotos()
                    
                } else {
                    // call method again to check and use denied / restricted messages we already have made
                    self.authorizePhotos()
                }
                
                dispatch_resume(self.sessionQueue)
            })
        }
    }
    
    func showNoAccessMessage () {
        dispatch_async(dispatch_get_main_queue()){
            let message = NSLocalizedString("We need permission to your Photos and Camera to snap savory selfies", comment: "Alert message when the user has denied access to the camera or photos" )
            let alertController = UIAlertController(title: "No Photos or Camera", message: message, preferredStyle: UIAlertControllerStyle.Alert)
            let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
            alertController.addAction(cancelAction)
            // Provide quick access to Settings.
            let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: UIAlertActionStyle.Default) {action in
                UIApplication.sharedApplication().openURL(NSURL(string:UIApplicationOpenSettingsURLString)!)
            }
            alertController.addAction(settingsAction)
            self.presentViewController(alertController, animated: true, completion: nil)
        }
    }
    
    func showCameraFailMessage() {
        dispatch_async(dispatch_get_main_queue()) {
            let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
            let alertController = UIAlertController(title: App.Name.rawValue, message: message, preferredStyle: UIAlertControllerStyle.Alert)
            let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
            alertController.addAction(cancelAction)
            self.presentViewController(alertController, animated: true, completion: nil)
        }
    }
    
    //MARK: Actions
    
    func captureStillImage() {
        activityIndicator.startAnimating()
        enableUI(false)
        dispatch_async(self.sessionQueue) {
            let connection = self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            // Update the orientation on the still image output video connection before capturing.
            connection.videoOrientation = previewLayer.connection.videoOrientation
            
            // Flash set to Auto for Still Capture.
            CameraViewController.setFlashMode(AVCaptureFlashMode.Auto, forDevice: self.videoDeviceInput.device)
            
            // Capture a still image.
            self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(connection) { imageDataSampleBuffer, error in
                if imageDataSampleBuffer != nil {
                    // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    
                    self.networkIndicator.startAnimating()

                    //MARK: - Post Tweet
                    if Twitter.sharedInstance().sessionStore.session() != nil {
                        self.tweetWithContent(self.postTextView.text, tweetImage: imageData)
                    }
                    
                    //MARK: - Post to Facebook
                    if FBSDKAccessToken.currentAccessToken() != nil {
                        let image = UIImage(data: imageData)
                        
                        let fbContent = FBSDKSharePhotoContent()
                        
                        let fbPhoto = FBSDKSharePhoto(image: image, userGenerated: true)
                        fbPhoto.caption = self.postTextView.text
                        
                        fbContent.photos = [fbPhoto]
                        FBSDKShareAPI.shareWithContent(fbContent, delegate: self)
                    }

                    
                    dispatch_async(dispatch_get_main_queue()) {
                        self.postTextView.text.removeAll()
                        self.postTextView.text = ""
                        if let currentText = self.postTextView.text {
                            let remainingCharacters = 140 - currentText.characters.count
                            self.postCountLabel.text = "Characters left: \(remainingCharacters.description)"
                            NSUserDefaults.standardUserDefaults().setObject(currentText, forKey: UserDefaultsKeys.savedTweet.rawValue)
                        }
                    }
                    
                    //save to disk
                    PHPhotoLibrary.requestAuthorization {status in
                        if status == PHAuthorizationStatus.Authorized {
                            // To preserve the metadata, we create an asset from the JPEG NSData representation.
                            // Note that creating an asset from a UIImage discards the metadata.
                            // In iOS 9, we can use -[PHAssetCreationRequest addResourceWithType:data:options].
                            // In iOS 8, we save the image to a temporary file and use +[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:].
                            if #available(iOS 9.0, *) {
                                PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                                    PHAssetCreationRequest.creationRequestForAsset().addResourceWithType(.Photo, data: imageData, options: nil)
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occurred while saving image to photo library: %@", error!)
                                        } else {
                                            self.newPhotoReady = true
                                        }
                                        dispatch_async(dispatch_get_main_queue()) {
                                            self.activityIndicator.stopAnimating()
                                            self.enableUI(true)
                                        }
                                })
                            } else {
                                let temporaryFileName = NSProcessInfo().globallyUniqueString as NSString
                                let temporaryFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(temporaryFileName.stringByAppendingPathExtension("jpg")!)
                                let temporaryFileURL = NSURL(fileURLWithPath: temporaryFilePath)
                                
                                PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                                    do {
                                        try imageData.writeToURL(temporaryFileURL, options: .AtomicWrite)
                                        PHAssetChangeRequest.creationRequestForAssetFromImageAtFileURL(temporaryFileURL)
                                    } catch let error as NSError {
                                        NSLog("Error occured while writing image data to a temporary file: %@", error)
                                    } catch _ {
                                        fatalError()
                                    }
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occurred while saving image to photo library: %@", error!)
                                        } else {
                                            self.newPhotoReady = true
                                        }
                                        
                                        dispatch_async(dispatch_get_main_queue()) {
                                            self.activityIndicator.stopAnimating()
                                            self.enableUI(true)
                                        }
                                        
                                        // Delete the temporary file.
                                        do {
                                            try NSFileManager.defaultManager().removeItemAtURL(temporaryFileURL)
                                        } catch _ {}
                                })
                            }
                        }
                    }
                } else {
                    NSLog("Could not capture still image: %@", error)
                }
            }
        }
        
    }
    
    func switchCameras() {
        self.enableUI(false)
        blurPreview(true)
        
        dispatch_async(self.sessionQueue) {
            let currentVideoDevice = self.videoDeviceInput.device
            var preferredPosition = AVCaptureDevicePosition.Unspecified
            let currentPosition = currentVideoDevice.position
            
            switch currentPosition {
            case AVCaptureDevicePosition.Unspecified, AVCaptureDevicePosition.Front:
                preferredPosition = AVCaptureDevicePosition.Back
                self.toggleAnimation.subtype = kCATransitionFromRight
            case AVCaptureDevicePosition.Back:
                preferredPosition = AVCaptureDevicePosition.Front
                self.toggleAnimation.subtype = kCATransitionFromLeft
            }
            
            let videoDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo,  preferringPosition: preferredPosition)
            
            let videoDeviceInput: AVCaptureDeviceInput!
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                
            } catch let error as NSError {
                videoDeviceInput = nil
                NSLog("Could not create video device input: %@", error)
            } catch _ {
                fatalError()
            }
            
            //            //animate switching cameras
            //            dispatch_async(dispatch_get_main_queue()) {
            //                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            //                previewLayer.addAnimation(self.toggleAnimation, forKey: nil)
            //            }
            
            self.session.beginConfiguration()
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
            self.session.removeInput(self.videoDeviceInput)
            
            if self.session.canAddInput(videoDeviceInput) {
                //remove notifications for old camera input
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)
                //start notifications for new camera input
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.subjectAreaDidChange),  name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDevice)
                
                CameraViewController.setFlashMode(AVCaptureFlashMode.Auto, forDevice: videoDevice!)
                
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            } else {
                //reload previous camera as fallback
                self.session.addInput(self.videoDeviceInput)
            }
            
            let connection = self.movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
            if connection.supportsVideoStabilization {
                connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
            }
            
            self.session.commitConfiguration()
            
            dispatch_async(dispatch_get_main_queue()) {
                self.enableUI(true)
                self.blurPreview(false)
            }
        }
    }
    
    func resumeSession() {
        guard let queue = sessionQueue else {
            self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
            resumeSession()
            return
        }
        dispatch_async(queue) {
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            self.session.startRunning()
            self.sessionRunning = self.session.running
            if !self.session.running {
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: UIAlertControllerStyle.Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            } else {
                dispatch_async(dispatch_get_main_queue()) {
                    self.resumeButton.hidden = true
                }
            }
        }
    }
    
    
    
    //MARK: Device Configuration
    
    func focusWithMode(focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode, atDevicePoint point:CGPoint, monitorSubjectAreaChange: Bool) {
        if self.setupResult == AVCamSetupResult.Success {
            dispatch_async(self.sessionQueue) {
                let device = self.videoDeviceInput.device
                do {
                    try device.lockForConfiguration()
                    defer {device.unlockForConfiguration()}
                    // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                    // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                    if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = point
                        device.focusMode = focusMode
                    }
                    
                    if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                        device.exposurePointOfInterest = point
                        device.exposureMode = exposureMode
                    }
                    
                    device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                } catch let error as NSError {
                    NSLog("Could not lock device for configuration: %@", error)
                } catch _ {}
            }
        }
    }
    
    class func setFlashMode(flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            do {
                try device.lockForConfiguration()
                defer {device.unlockForConfiguration()}
                device.flashMode = flashMode
            } catch let error as NSError {
                NSLog("Could not lock device for configuration: %@", error)
            }
        }
    }
    
    class func deviceWithMediaType(mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType)
        var captureDevice = devices.first as! AVCaptureDevice?
        
        for device in devices as! [AVCaptureDevice] {
            if device.position == position {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    //MARK: Orientation
    
    override func shouldAutorotate() -> Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !(self.movieFileOutput?.recording ?? false)
    }
    
    override func preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
        return UIInterfaceOrientation.Portrait
    }
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.AllButUpsideDown
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        
        if setupResult == .Success {
            // Note that the app delegate controls the device orientation notifications required to use the device orientation.
            let deviceOrientation = UIDevice.currentDevice().orientation
            if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                previewLayer.connection.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
            }
        }
    }
    
    //MARK: KVO and Notifications
    
    private func addObservers() {
        self.session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.New, context: SessionRunningContext)
        self.stillImageOutput.addObserver(self, forKeyPath: "capturingStillImage", options:NSKeyValueObservingOptions.New, context: CapturingStillImageContext)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.subjectAreaDidChange), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput.device)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.sessionRuntimeError(_:)), name: AVCaptureSessionRuntimeErrorNotification, object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.sessionWasInterrupted(_:)), name: AVCaptureSessionWasInterruptedNotification, object: self.session)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.sessionInterruptionEnded(_:)), name: AVCaptureSessionInterruptionEndedNotification, object: self.session)
    }
    
    private func removeCamObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        
        self.session.removeObserver(self, forKeyPath: "running", context: SessionRunningContext)
        self.stillImageOutput.removeObserver(self, forKeyPath: "capturingStillImage", context: CapturingStillImageContext)
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        switch context {
        case CapturingStillImageContext:
            
            let isCapturingStillImage = change![NSKeyValueChangeNewKey]! as! Bool
            
            if isCapturingStillImage {
                dispatch_async(dispatch_get_main_queue()) {
                    self.previewView.layer.opacity = 0.0
                    UIView.animateWithDuration(0.25) {
                        self.previewView.layer.opacity = 1.0
                    }
                }
            }
            
//            dispatch_async(dispatch_get_main_queue()) {
//                self.enableUI(!isCapturingStillImage)
//            }
            
        case SessionRunningContext:
            let isSessionRunning = change![NSKeyValueChangeNewKey]! as! Bool
            
            dispatch_async(dispatch_get_main_queue()) {
                self.enableUI(isSessionRunning && PHPhotoLibrary.authorizationStatus() == .Authorized)
            }
        default:
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    func subjectAreaDidChange() {
        let devicePoint = CGPointMake(0.5, 0.5)
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposeWithMode: AVCaptureExposureMode.ContinuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    func sessionRuntimeError(notification: NSNotification) {
        let error = notification.userInfo![AVCaptureSessionErrorKey]! as! NSError
        NSLog("Capture session runtime error: %@", error)
        
        // Automatically try to restart the session running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if error.code == AVError.MediaServicesWereReset.rawValue {
            dispatch_async(self.sessionQueue) {
                if self.sessionRunning {
                    self.session.startRunning()
                    self.sessionRunning = self.session.running
                } else {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.resumeButton.hidden = false
                    }
                }
            }
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
        
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if #available(iOS 9.0, *) {
            let reason = notification.userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int
            NSLog("Capture session was interrupted with reason %ld", reason)
            
            if reason == AVCaptureSessionInterruptionReason.AudioDeviceInUseByAnotherClient.rawValue ||
                reason == AVCaptureSessionInterruptionReason.VideoDeviceInUseByAnotherClient.rawValue {
                    showResumeButton = true
            } else if reason == AVCaptureSessionInterruptionReason.VideoDeviceNotAvailableWithMultipleForegroundApps.rawValue {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                self.cameraUnavailableLabel.hidden = false
                self.cameraUnavailableLabel.alpha = 0.0
                UIView.animateWithDuration(0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            }
        } else {
            NSLog("Capture session was interrupted")
            showResumeButton = (UIApplication.sharedApplication().applicationState == UIApplicationState.Inactive)
        }
        
        if showResumeButton {
            // Simply fade-in a button to enable the user to try to resume the session running.
            self.resumeButton.hidden = false
            self.resumeButton.alpha = 0.0
            UIView.animateWithDuration(0.25) {
                self.resumeButton.alpha = 1.0
            }
        }
    }
    
    func sessionInterruptionEnded(notification: NSNotification) {
        NSLog("Capture session interruption ended")
        
        if !self.resumeButton.hidden {
            UIView.animateWithDuration(0.25, animations: {
                self.resumeButton.alpha = 0.0
                }, completion: {finished in
                    self.resumeButton.hidden = true
            })
        }
        if !self.cameraUnavailableLabel.hidden {
            UIView.animateWithDuration(0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
                }, completion: {finished in
                    self.cameraUnavailableLabel.hidden = true
            })
        }
    }

}

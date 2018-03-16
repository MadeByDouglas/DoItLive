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

let alignment = MemoryLayout<Int>.alignment

private var CapturingStillImageContext = UnsafeMutableRawPointer.allocate(bytes: 1, alignedTo: alignment)
private var SessionRunningContext = UnsafeMutableRawPointer.allocate(bytes: 1, alignedTo: alignment)

private enum AVCamSetupResult: Int {
    case success
    case cameraNotAuthorized
    case sessionConfigurationFailed
}

protocol CameraViewControllerDelegate: class {
    func cameraControllerDidSendAssetAndTweet(_ controller: CameraViewController, asset: PHAsset, tweet: String)
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
    fileprivate var sessionQueue: DispatchQueue!
    fileprivate var session: AVCaptureSession!
    fileprivate var videoDeviceInput: AVCaptureDeviceInput!
    fileprivate var movieFileOutput: AVCaptureMovieFileOutput!
    fileprivate var photoOutput: AVCapturePhotoOutput!
    
    // Utilities.
    fileprivate var setupResult: AVCamSetupResult = .cameraNotAuthorized
    fileprivate var sessionRunning: Bool = false
    fileprivate var backgroundRecordingID: UIBackgroundTaskIdentifier = 0
    let toggleAnimation = CATransition()
    var blurView: UIVisualEffectView!
    //    var cameraIsReady: Bool! //handled by KVO now
    
    //instant mode
    var newPhotoReady: Bool!
    var didSendPhoto: Bool!
    
    let defaults = UserDefaults.standard
    let firstInstantSwitch = "firstInstantSwitch"
    
    // Photos
    var photosData = Photos()
   
    // Visual Effects
    lazy var confettiView: SAConfettiView = {
      let view = SAConfettiView(frame: self.view.bounds)
        view.isUserInteractionEnabled = false
        return view
    }()
    
    lazy var successNotify: JFMinimalNotification = {
        let notify = JFMinimalNotification(style: .success, title: "Success!", subTitle: "Your photo is now LIVE", dismissalDelay: 1.5)
        return notify!
    }()
    
    lazy var errorNotify: JFMinimalNotification = {
        let notify = JFMinimalNotification(style: .error, title: "Whoops!", subTitle: "Something went wrong, check your network connection", dismissalDelay: 1.5)
        return notify!
    }()
    
    var timer: Timer?
    
    //Sound Effects
    var player: AVAudioPlayer?
    
    func playSoundFile(_ name: String) {
        let url = Bundle.main.url(forResource: name, withExtension: "mp3")!
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
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
        let appDelegate = UIApplication.shared.delegate as! AppDelegate

        if TWTRTwitter.sharedInstance().sessionStore.session()?.userID != nil {
            if let userName = appDelegate.twitterUserName {
                userNameLabel.text = "@\(userName)"
            }
        }
        if FBSDKAccessToken.current() != nil {
            if let name = appDelegate.facebookUserName {
                userNameLabel.text = name
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        didSendPhoto = false
        activateCamera()
        authorizePhotos()
        
        //tweet
        if let savedTweet = UserDefaults.standard.string(forKey: UserDefaultsKeys.savedTweet.rawValue) {
            if savedTweet == "" || savedTweet == " " {
                postTextView.text = ""
            } else {
                postTextView.text = savedTweet
            }
        } else {
            postTextView.text = ""
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        blurPreview(false)
        
    }
    
    //MARK: Unloading View
    
    override func viewWillDisappear(_ animated: Bool) {
        blurPreview(true)

        super.viewWillDisappear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.sessionQueue.async {
            if self.setupResult == AVCamSetupResult.success {
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
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    func blurPreview(_ sender: Bool) {
        if self.setupResult == AVCamSetupResult.success {
            guard let _ = blurView else {
                return
            }
            
            UIView.animate(withDuration: 0.3, animations: { () -> Void in
                if sender == true {
                    self.blurView.alpha = 1
                } else {
                    self.blurView.alpha = 0
                }
            }) 
        }
    }
    
    func showOptionsMenu() {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        alertController.modalPresentationStyle = UIModalPresentationStyle.popover
        
        if let twitterUser = TWTRTwitter.sharedInstance().sessionStore.session()?.userID {
            alertController.addAction(UIAlertAction(title: "Twitter Feed", style: UIAlertActionStyle.default, handler: { (action: UIAlertAction) -> Void in
                
                if UIApplication.shared.canOpenURL(URL(string: "twitter://")!) {
                    let twitterProfileURL = URL(string: "twitter:///\(twitterUser)")
                    UIApplication.shared.open(twitterProfileURL!, options: [:], completionHandler: nil)
                    
                } else {
                    let twitterProfileURL = URL(string: "https://twitter.com/\(twitterUser)")
                    UIApplication.shared.open(twitterProfileURL!, options: [:], completionHandler: nil)
                }
            }))
        }
        
        if let facebookUser = FBSDKAccessToken.current()?.userID {
            alertController.addAction(UIAlertAction(title: "Facebook Wall", style: UIAlertActionStyle.default, handler: { (action: UIAlertAction) -> Void in

                if UIApplication.shared.canOpenURL(URL(string: "fb://")!) {
                    let facebookProfileURL = URL(string: "fb://profile?app_scoped_user_id=\(facebookUser)")
                    UIApplication.shared.open(facebookProfileURL!, options: [:], completionHandler: nil)
                } else {
                    let facebookProfileURL = URL(string: "https://facebook.com/\(facebookUser)")
                    UIApplication.shared.open(facebookProfileURL!, options: [:], completionHandler: nil)
                }
            }))
        }

        alertController.addAction(UIAlertAction(title: "Log Out", style: UIAlertActionStyle.destructive, handler: { (action: UIAlertAction ) -> Void in
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.firstView.rawValue)
            self.dismiss(animated: true) {
                //log out notification
                NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Logout.rawValue), object: nil)
            }
        }))

        alertController.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (action: UIAlertAction) -> Void in
            
        }))
        
        if self.presentedViewController == nil {
            self.present(alertController, animated: true, completion: nil)
        } else {
            print("\(classForCoder).alertController something already presented")
        }
    }
    
    //MARK: Buttons
    
    @IBAction func didTapShutter(_ sender: UIButton) {
        captureStillImage()
    }
    
    @IBAction func didTapSwitchCamera(_ sender: UIButton) {
        switchCameras()
    }
    
    @IBAction func didTapFeed(_ sender: UIButton) {
        
        showOptionsMenu()
        
//        NSUserDefaults.standardUserDefaults().setBool(false, forKey: UserDefaultsKeys.firstView.rawValue)
//        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    @IBAction func didTapResume(_ sender: UIButton) {
        resumeSession()
    }
    
    @IBAction func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        self.focusWithMode(AVCaptureDevice.FocusMode.autoFocus, exposeWithMode: AVCaptureDevice.ExposureMode.autoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }
    
    @IBAction func didTapInstantSwitch(_ sender: UISwitch) {
        if !defaults.bool(forKey: firstInstantSwitch) {
            DispatchQueue.main.async {
                let message = NSLocalizedString("Photo gets posted as soon as you tap the shutter", comment: "One time alert explaining Instant Mode")
                let alertController = UIAlertController(title: "Instant Mode", message: message, preferredStyle: UIAlertControllerStyle.alert)
                let cancelAction = UIAlertAction(title: NSLocalizedString("Sweet", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
                alertController.addAction(cancelAction)
                self.present(alertController, animated: true, completion: nil)
            }
            defaults.set(true, forKey: firstInstantSwitch)
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
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
        super.touchesBegan(touches, with: event)
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        postTapLabel.isHidden = true
        if let currentText = textView.text {
            let remainingCharacters = 140 - currentText.count
            postCountLabel.text = "Characters left: \(remainingCharacters.description)"
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text == nil || textView.text == "" {
            postTapLabel.isHidden = false
        }
        textView.resignFirstResponder()
        let tweet = textView.text
        UserDefaults.standard.set(tweet, forKey: UserDefaultsKeys.savedTweet.rawValue)
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        //enable tab
        if text == "\t" {
            textView.endEditing(true)
            return false
        }
        
        //also check when deleting
        if range.length==1 && text.isEmpty {
            if let currentText = textView.text {
                let remainingCharacters = 140 - (currentText.count - 1)
                postCountLabel.text = "Characters left: \(remainingCharacters.description)"
            }
            return true
        }
        
        if let textErrors = Helper.isValidTweetWithErrors(textView.text, possibleNewCharacter: text) {
            print(textErrors)
            return false
        } else {
            if let currentText = textView.text {
                let remainingCharacters = 140 - (currentText.count + text.count)
                postCountLabel.text = "Characters left: \(remainingCharacters.description)"
            }
            return true
        }
    }
    
}


//MARK: - Facebook Delegate

extension CameraViewController: FBSDKSharingDelegate {
    func sharer(_ sharer: FBSDKSharing!, didCompleteWithResults results: [AnyHashable: Any]!) {
        networkIndicator.stopAnimating()
        celebrate()
    }
    
    func sharer(_ sharer: FBSDKSharing!, didFailWithError error: Error!) {
        networkIndicator.stopAnimating()
        showNetworkError()
        print(error)
    }
    
    func sharerDidCancel(_ sharer: FBSDKSharing!) {
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
        timer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(endCelebrate(_:)), userInfo: nil, repeats: false)
    }
    
    @objc func endCelebrate(_ sender: Timer) {
        self.confettiView.stopConfetti()
        sender.invalidate()
    }
    
    func showNetworkError() {
        errorNotify.show()
    }
    

    //MARK: - Twitter Methods

    func tweetWithContent(_ tweetString: String, tweetImage: Data) {
        
        let uploadUrl = "https://upload.twitter.com/1.1/media/upload.json"
        let updateUrl = "https://api.twitter.com/1.1/statuses/update.json"
        let imageString = tweetImage.base64EncodedString(options: NSData.Base64EncodingOptions())
        
        let client = TWTRAPIClient.withCurrentUser()
        
        let request = client.urlRequest(withMethod: "POST", urlString: uploadUrl, parameters: ["media": imageString], error: nil)
        client.sendTwitterRequest(request, completion: { (urlResponse, data, connectionError) -> Void in
            
            if let dictionary = try! JSON(data: data!).dictionaryObject {
            
                let message: [AnyHashable: Any] = ["status": tweetString, "media_ids": dictionary["media_id_string"]!]
                let request = client.urlRequest(withMethod: "POST",
                                                urlString: updateUrl, parameters: message, error:nil)
                
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


//MARK: AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        cleanUI()

        guard let photoData = photo.fileDataRepresentation() else { return }

        postToSocialMedia(photoData: photoData)
        savePhotoToDisk(photoData: photoData)


    }

    func cleanUI() {
        DispatchQueue.main.async {
            self.postTextView.text.removeAll()
            self.postTextView.text = ""
            if let currentText = self.postTextView.text {
                let remainingCharacters = 140 - currentText.count
                self.postCountLabel.text = "Characters left: \(remainingCharacters.description)"
                UserDefaults.standard.set(currentText, forKey: UserDefaultsKeys.savedTweet.rawValue)
            }
        }
    }

    func savePhotoToDisk(photoData: Data) {
//        let requestedPhotoSettings = AVCapturePhotoSettings()
        PHPhotoLibrary.requestAuthorization { status in

            if status == .authorized {

                PHPhotoLibrary.shared().performChanges({

                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
//                    options.uniformTypeIdentifier = requestedPhotoSettings.processedFileType.map { $0.rawValue }

                    creationRequest.addResource(with: .photo, data: photoData, options: options)


                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving image to photo library: %@", error)
                    } else {
                        self.newPhotoReady = true
                    }

                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                        self.enableUI(true)
                    }
                })
            }
        }
    }

    func postToSocialMedia(photoData: Data) {
        self.networkIndicator.startAnimating()

        //MARK: - Post Tweet
        if TWTRTwitter.sharedInstance().sessionStore.session() != nil {
            self.tweetWithContent(self.postTextView.text, tweetImage: photoData)
        }

        //MARK: - Post to Facebook
        if FBSDKAccessToken.current() != nil {
            let image = UIImage(data: photoData)

            let fbContent = FBSDKSharePhotoContent()

            let fbPhoto = FBSDKSharePhoto(image: image, userGenerated: true)
            fbPhoto?.caption = self.postTextView.text

            fbContent.photos = [fbPhoto!]
            FBSDKShareAPI.share(with: fbContent, delegate: self)
        }
    }
}

extension CameraViewController {
    
    //MARK: Initial Setup
    
    func enableUI(_ sender: Bool) {
        shutterButton.isEnabled = sender
        //        recordButton.enabled = sender
        // Only enable the ability to change camera if the device has more than one camera.
        // all ios 10 devices do
        switchButton.isEnabled = sender
        
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
        self.sessionQueue = DispatchQueue(label: "session queue", attributes: [])
        
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            // The user has previously granted access to the camera.
            self.setupResult = AVCamSetupResult.success
            
            break
        case .notDetermined:
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            self.sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video) {granted in
                if granted {
                    self.setupResult = AVCamSetupResult.success
                } else {
                    self.setupResult = AVCamSetupResult.cameraNotAuthorized
                }
                self.sessionQueue.resume()
            }
        default:
            // The user has previously denied access.
            self.setupResult = AVCamSetupResult.cameraNotAuthorized
        }
        
    }
    
    func setupCamerasAndConfigureSession() {
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        self.sessionQueue.async {
            guard self.setupResult == AVCamSetupResult.success else {
                return
            }
            
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            let videoDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
            let videoDeviceInput: AVCaptureDeviceInput!
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice!)
                
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
                
                DispatchQueue.main.async {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for AAPLPreviewView and UIView
                    // can only be manipulated on the main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                    // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                    
                    // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
                    // -[viewWillTransitionToSize:withTransitionCoordinator:].
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation = AVCaptureVideoOrientation.portrait
                    if statusBarOrientation != UIInterfaceOrientation.unknown {
                        initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                    }
                    
                    let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection?.videoOrientation = initialVideoOrientation
                    
                    let preview = self.previewView
                    let blur = UIBlurEffect(style: UIBlurEffectStyle.dark)
                    self.blurView = UIVisualEffectView(effect: blur)
                    self.blurView.frame = CGRect(x: 0, y: 0, width: (preview?.frame.width)!, height: (preview?.frame.height)!)
                    self.blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    self.blurView.alpha = 0
                    preview?.insertSubview(self.blurView, aboveSubview: preview!)
                    
                    
                }
            } else {
                NSLog("Could not add video device input to the session")
                self.setupResult = AVCamSetupResult.sessionConfigurationFailed
            }
            
            let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
            let audioDeviceInput: AVCaptureDeviceInput!
            do {
                audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
                
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
                let connection = movieFileOutput.connection(with: AVMediaType.video)
                if connection?.isVideoStabilizationSupported ?? false {
                    connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                NSLog("Could not add movie file output to the session")
                self.setupResult = AVCamSetupResult.sessionConfigurationFailed
            }
            
            let photoOutput = AVCapturePhotoOutput()
            if self.session.canAddOutput(photoOutput) {
                self.session.sessionPreset = AVCaptureSession.Preset.photo
                self.session.addOutput(photoOutput)
                self.photoOutput = photoOutput
            } else {
                NSLog("Could not add still image output to the session")
                self.setupResult = AVCamSetupResult.sessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
        }
    }
    
    //MARK: Recurring Setup
    
    func activateCamera() {
        //Handle iOS authorization and activate camera as appropriate
        guard let queue = sessionQueue else {
            self.sessionQueue = DispatchQueue(label: "session queue", attributes: [])
            activateCamera()
            return
        }
        
        queue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.isRunning
                break
            case .cameraNotAuthorized:
                self.showNoAccessMessage()
                break
            case .sessionConfigurationFailed:
                self.showCameraFailMessage()
                break
            }
        }
        
    }
    
    // MARK: - Handle Authorization
    
    func authorizePhotos() {
        //Photos status check
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            print("photos authorized")
            break
        case .denied:
            print("photos denied")
            // if camera is not authorized we already showed no access message
            if setupResult != .cameraNotAuthorized {
                showNoAccessMessage()
            }
            break
        case .restricted:
            print ("photos restricted")
            // if camera is not authorized we already showed no access message
            if setupResult != .cameraNotAuthorized {
                showNoAccessMessage()
            }
            break
        case .notDetermined:
            print ("photos not determined")
            self.sessionQueue.suspend()
            PHPhotoLibrary.requestAuthorization({ (status: PHAuthorizationStatus) -> Void in
                if status == PHAuthorizationStatus.authorized {
                    
                    self.photosData.setupPhotos()
                    
                } else {
                    // call method again to check and use denied / restricted messages we already have made
                    self.authorizePhotos()
                }
                
                self.sessionQueue.resume()
            })
        }
    }
    
    func showNoAccessMessage () {
        DispatchQueue.main.async{
            let message = NSLocalizedString("We need permission to your Photos and Camera to snap savory selfies", comment: "Alert message when the user has denied access to the camera or photos" )
            let alertController = UIAlertController(title: "No Photos or Camera", message: message, preferredStyle: UIAlertControllerStyle.alert)
            let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
            alertController.addAction(cancelAction)
            // Provide quick access to Settings.
            let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: UIAlertActionStyle.default) {action in
                UIApplication.shared.open(URL(string:UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
            }
            alertController.addAction(settingsAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func showCameraFailMessage() {
        DispatchQueue.main.async {
            let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
            let alertController = UIAlertController(title: App.Name.rawValue, message: message, preferredStyle: UIAlertControllerStyle.alert)
            let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    //MARK: Actions
    
    func captureStillImage() {
        activityIndicator.startAnimating()
        enableUI(false)
        self.sessionQueue.async {
            let connection = self.photoOutput.connection(with: AVMediaType.video)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            // Update the orientation on the still image output video connection before capturing.
            connection?.videoOrientation = (previewLayer.connection?.videoOrientation)!
            
            // Flash set to Auto for Still Capture.
            let captureSettings = CameraViewController.getFlashSettings(camera: self.videoDeviceInput.device, flashMode: .auto)

            self.photoOutput.capturePhoto(with: captureSettings, delegate: self)
        }

    }
    
    func switchCameras() {
        self.enableUI(false)
        blurPreview(true)
        
        self.sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            var preferredPosition = AVCaptureDevice.Position.unspecified
            let currentPosition = currentVideoDevice.position
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                self.toggleAnimation.subtype = kCATransitionFromRight
            case .back:
                preferredPosition = .front
                self.toggleAnimation.subtype = kCATransitionFromLeft
            }
            
            let videoDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: preferredPosition)
            
            let videoDeviceInput: AVCaptureDeviceInput!
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice!)
                
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
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                //start notifications for new camera input
                NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.subjectAreaDidChange),  name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: videoDevice)
                
//                CameraViewController.setFlashMode(AVCaptureFlashMode.auto, forDevice: videoDevice!)

                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            } else {
                //reload previous camera as fallback
                self.session.addInput(self.videoDeviceInput)
            }
            
            let connection = self.movieFileOutput.connection(with: AVMediaType.video)
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
            }
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.enableUI(true)
                self.blurPreview(false)
            }
        }
    }
    
    func resumeSession() {
        guard let queue = sessionQueue else {
            self.sessionQueue = DispatchQueue(label: "session queue", attributes: [])
            resumeSession()
            return
        }
        queue.async {
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            self.session.startRunning()
            self.sessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: UIAlertControllerStyle.alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    
    
    //MARK: Device Configuration
    
    func focusWithMode(_ focusMode: AVCaptureDevice.FocusMode, exposeWithMode exposureMode: AVCaptureDevice.ExposureMode, atDevicePoint point:CGPoint, monitorSubjectAreaChange: Bool) {
        if self.setupResult == AVCamSetupResult.success {
            self.sessionQueue.async {
                let device = self.videoDeviceInput.device
                do {
                    try device.lockForConfiguration()
                    defer {device.unlockForConfiguration()}
                    // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                    // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                    if (device.isFocusPointOfInterestSupported) && (device.isFocusModeSupported(focusMode)) {
                        device.focusPointOfInterest = point
                        device.focusMode = focusMode
                    }
                    
                    if (device.isExposurePointOfInterestSupported) && (device.isExposureModeSupported(exposureMode)) {
                        device.exposurePointOfInterest = point
                        device.exposureMode = exposureMode
                    }
                    
                    device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                } catch let error as NSError {
                    NSLog("Could not lock device for configuration: %@", error)
                } catch _ {}
            }
        }
    }
    
    class func getFlashSettings(camera: AVCaptureDevice, flashMode: AVCaptureDevice.FlashMode) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        if camera.hasFlash {
            settings.flashMode = flashMode
        }
        return settings
    }
    
    //MARK: Orientation
    
    override var shouldAutorotate : Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !(self.movieFileOutput?.isRecording ?? false)
    }
    
    override var preferredInterfaceOrientationForPresentation : UIInterfaceOrientation {
        return UIInterfaceOrientation.portrait
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.allButUpsideDown
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if setupResult == .success {
            // Note that the app delegate controls the device orientation notifications required to use the device orientation.
            let deviceOrientation = UIDevice.current.orientation
            if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
            }
        }
    }
    
    //MARK: KVO and Notifications
    
    fileprivate func addObservers() {
        self.session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: SessionRunningContext)
        self.photoOutput.addObserver(self, forKeyPath: "capturingStillImage", options:NSKeyValueObservingOptions.new, context: CapturingStillImageContext)
        
        NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.subjectAreaDidChange), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: self.videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.sessionRuntimeError(_:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.sessionWasInterrupted(_:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: self.session)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.sessionInterruptionEnded(_:)), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: self.session)
    }
    
    fileprivate func removeCamObservers() {
        NotificationCenter.default.removeObserver(self)
        
        self.session.removeObserver(self, forKeyPath: "running", context: SessionRunningContext)
        self.photoOutput.removeObserver(self, forKeyPath: "capturingStillImage", context: CapturingStillImageContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch context {
        case CapturingStillImageContext?:
            
            let isCapturingStillImage = change![NSKeyValueChangeKey.newKey]! as! Bool
            
            if isCapturingStillImage {
                DispatchQueue.main.async {
                    self.previewView.layer.opacity = 0.0
                    UIView.animate(withDuration: 0.25, animations: {
                        self.previewView.layer.opacity = 1.0
                    }) 
                }
            }
            
//            dispatch_async(dispatch_get_main_queue()) {
//                self.enableUI(!isCapturingStillImage)
//            }
            
        case SessionRunningContext?:
            let isSessionRunning = change![NSKeyValueChangeKey.newKey]! as! Bool
            
            DispatchQueue.main.async {
                self.enableUI(isSessionRunning && PHPhotoLibrary.authorizationStatus() == .authorized)
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc func subjectAreaDidChange() {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(AVCaptureDevice.FocusMode.continuousAutoFocus, exposeWithMode: AVCaptureDevice.ExposureMode.continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo![AVCaptureSessionErrorKey]! as! NSError
        NSLog("Capture session runtime error: %@", error)
        
        // Automatically try to restart the session running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if error.code == AVError.Code.mediaServicesWereReset.rawValue {
            self.sessionQueue.async {
                if self.sessionRunning {
                    self.session.startRunning()
                    self.sessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            self.resumeButton.isHidden = false
        }
    }
    
    @objc func sessionWasInterrupted(_ notification: Notification) {
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
            
            if reason == AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue ||
                reason == AVCaptureSession.InterruptionReason.videoDeviceInUseByAnotherClient.rawValue {
                    showResumeButton = true
            } else if reason == AVCaptureSession.InterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps.rawValue {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                self.cameraUnavailableLabel.isHidden = false
                self.cameraUnavailableLabel.alpha = 0.0
                UIView.animate(withDuration: 0.25, animations: {
                    self.cameraUnavailableLabel.alpha = 1.0
                }) 
            }
        } else {
            NSLog("Capture session was interrupted")
            showResumeButton = (UIApplication.shared.applicationState == UIApplicationState.inactive)
        }
        
        if showResumeButton {
            // Simply fade-in a button to enable the user to try to resume the session running.
            self.resumeButton.isHidden = false
            self.resumeButton.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 1.0
            }) 
        }
    }
    
    @objc func sessionInterruptionEnded(_ notification: Notification) {
        NSLog("Capture session interruption ended")
        
        if !self.resumeButton.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 0.0
                }, completion: {finished in
                    self.resumeButton.isHidden = true
            })
        }
        if !self.cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
                }, completion: {finished in
                    self.cameraUnavailableLabel.isHidden = true
            })
        }
    }

}

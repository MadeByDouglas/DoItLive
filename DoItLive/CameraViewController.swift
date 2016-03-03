//
//  CameraViewController.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

// camera icon: <div>Icons made by <a href="http://www.flaticon.com/authors/designmodo" title="Designmodo">Designmodo</a> from <a href="http://www.flaticon.com" title="Flaticon">www.flaticon.com</a> is licensed by <a href="http://creativecommons.org/licenses/by/3.0/" title="Creative Commons BY 3.0" target="_blank">CC 3.0 BY</a></div>
// shutter icon: <div>Icons made by <a href="http://www.flaticon.com/authors/bogdan-rosu" title="Bogdan Rosu">Bogdan Rosu</a> from <a href="http://www.flaticon.com" title="Flaticon">www.flaticon.com</a> is licensed by <a href="http://creativecommons.org/licenses/by/3.0/" title="Creative Commons BY 3.0" target="_blank">CC 3.0 BY</a></div>


import UIKit
import AVFoundation
import Photos

private var CapturingStillImageContext = UnsafeMutablePointer<Void>.alloc(1)
private var SessionRunningContext = UnsafeMutablePointer<Void>.alloc(1)

private enum AVCamSetupResult: Int {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}

protocol CameraViewControllerDelegate: class {
    func cameraControllerDidSendAsset(controller: CameraViewController, asset: PHAsset)
}

class CameraViewController: UIViewController, /*AVCaptureFileOutputRecordingDelegate,*/ UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPhotoLibraryChangeObserver {

    weak var delegate: CameraViewControllerDelegate?
    
    @IBOutlet weak var redBar: UIView!
    @IBOutlet weak var previewView: Preview!
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var doneButton: UIButton!
    
    @IBOutlet weak var isInstantSwitch: UISwitch!
    
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
    
    // CollectionView Variables
    @IBOutlet weak var pictureCollectionView: UICollectionView!
    
    var selectedIndexPath: NSIndexPath? = nil
    
    
    
    //MARK: Loading View
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        newPhotoReady = false
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        enableUI(false)
        setupAnimations()
        
        createSession()
        setupCamerasAndConfigureSession()
        
        // Photos
        PHPhotoLibrary.sharedPhotoLibrary().registerChangeObserver(self)
        
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        didSendPhoto = false
        activateCamera()
        
        // Photos
        // Determine the size of the thumbnails to request from the PHCachingImageManager
        let scale = UIScreen.mainScreen().scale
        Photos.AssetGridThumbnailSize = CGSizeMake(self.pictureCollectionView.frame.height * scale, self.pictureCollectionView.frame.height * scale)
        //        print("the asset thumbnail height is \(RVPhotosDataSource.AssetGridThumbnailSize.height.description)")
        //        print("the collectionView height is \(self.pictureCollectionView.frame.height.description)")
        authorizePhotos()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        blurPreview(false)
        
        // Begin caching assets in and around collection view's visible rect.
        if PHPhotoLibrary.authorizationStatus() == .Authorized {
            photosData.updateCachedAssetsForCollectionView(self.pictureCollectionView, view: self.view, isLoaded: self.isViewLoaded())
        }
    }
    
    //MARK: Unloading View
    
    override func viewWillDisappear(animated: Bool) {
        blurPreview(true)
        //reset selection
        if let indexPath = self.selectedIndexPath {
            self.pictureCollectionView?.cellForItemAtIndexPath(indexPath)?.selected = false
            self.pictureCollectionView?.reloadItemsAtIndexPaths([indexPath])
            self.selectedIndexPath = nil
        }
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
    
    deinit {
        PHPhotoLibrary.sharedPhotoLibrary().unregisterChangeObserver(self)
        //        print("camera was deinit")
    }
    
    //MARK: View Preferences
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    func blurPreview(sender: Bool) {
        if self.setupResult == AVCamSetupResult.Success {
            UIView.animateWithDuration(0.3) { () -> Void in
                if sender == true {
                    self.blurView.alpha = 1
                } else {
                    self.blurView.alpha = 0
                }
            }
        }
    }
    
    //MARK: Buttons
    
    @IBAction func didTapShutter(sender: UIButton) {
        captureStillImage()
    }
    
    @IBAction func didTapSwitchCamera(sender: UIButton) {
        switchCameras()
    }
    
    @IBAction func didTapCancel(sender: UIButton) {
        dismissViewControllerAnimated(true, completion: nil)
    }
    
    @IBAction func didTapDone(sender: UIButton) {
        if didSendPhoto == true {
            if let indexPath = self.selectedIndexPath {
                if let fetchedImages = photosData.assetsFetchResults {
                    if let asset = fetchedImages[indexPath.item] as? PHAsset {
                        //print("In \(self.classForCoder).didTapDone didSendPhoto is true, sending asset to Camera controller")
                        self.delegate?.cameraControllerDidSendAsset(self, asset: asset)
                        dismissViewControllerAnimated(true, completion: nil)
                    } else {
                        print("In \(self.classForCoder).didTapDone, didSendPhoto is true; no asset")
                    }
                } else {
                    print("In \(self.classForCoder).didTapDone, Did send Photo is true, no fetched Image")
                }
            } else {
                print("In \(self.classForCoder).didTapDone DiD send photo is true no selectedIndex Path")
                dismissViewControllerAnimated(true, completion: nil)
            }
        } else {
            if let indexPath = self.selectedIndexPath {
                if let fetchedImages = photosData.assetsFetchResults {
                    if let asset = fetchedImages[indexPath.item] as? PHAsset {
                        // print("In \(self.classForCoder).didTapDone didSendPhoto is false, sending asset to Camera controller")
                        self.delegate?.cameraControllerDidSendAsset(self, asset: asset)
                        dismissViewControllerAnimated(true, completion: nil)
                    } else {
                        print("In \(self.classForCoder).didTapDone, didSendPhoto is flase; no asset")
                    }
                } else {
                    print("In \(self.classForCoder).didTapDone, didSendPhoto is false; no fetched Image")
                }
            } else {
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("Tap on a thumbnail below and you'll be all set", comment: "Explain how to select photo")
                    let alertController = UIAlertController(title: "No Photo Selected", message: message, preferredStyle: UIAlertControllerStyle.Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            }
        }
        
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
    
    // MARK: - CollectionView
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // print("number of collection view items is \(photosData.numberOfItems().description)")
        return photosData.numberOfItems()
    }
    
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(PhotoCollectionViewCell.identifier, forIndexPath: indexPath)
        if let cell = cell as? PhotoCollectionViewCell {
            if let fetchedImages = photosData.assetsFetchResults {
                if let asset = fetchedImages[indexPath.item] as? PHAsset {
                    cell.representedAssetIdentifier = asset.localIdentifier
                    cell.configureWithAsset(asset)
                    print("In \(self.classForCoder).cellForItemAtIndexPath, the cell height is \(cell.frame.height.description)")
                }
            }
        }
        return cell
    }
    
    
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        let cell = collectionView.cellForItemAtIndexPath(indexPath)
        if let cell = cell as? PhotoCollectionViewCell {
            print("selection Mark active")
            self.selectedIndexPath = indexPath
            cell.contentView.layer.sublayers?.last?.hidden = false
            
        } else {
            print("no cell")
        }
    }
    
    func collectionView(collectionView: UICollectionView, didDeselectItemAtIndexPath indexPath: NSIndexPath) {
        let cell = collectionView.cellForItemAtIndexPath(indexPath)
        if let cell = cell as? PhotoCollectionViewCell {
            cell.contentView.layer.sublayers?.last?.hidden = true
        }
    }
    
    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        let availableHeight = self.view.frame.height - self.previewView.frame.height - self.redBar.frame.height
        //        print("Dear Douglas. You are going to drive us all crazy without including information about the source of each print statement. I've added: ...\(self.classForCoder).sizeForItemAtIndexPath....\n to this statement. Please do so with all of yours. frame height \(self.view.frame.height.description) preview height \(self.previewView.frame.height.description) redbar height \(self.redBar.frame.height.description) ")
        let size = CGSizeMake(availableHeight, availableHeight)
        return size
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    func photoLibraryDidChange(changeInstance: PHChange) {
        // Check if there are changes to the assets we are showing.
        guard let
            assetsFetchResults = self.photosData.assetsFetchResults,
            collectionChanges = changeInstance.changeDetailsForFetchResult(assetsFetchResults)
            else {return}
        
        //Instant publish
        if self.isInstantSwitch.on && self.newPhotoReady == true {
            
            if let asset = collectionChanges.fetchResultAfterChanges[0] as? PHAsset {
                self.delegate?.cameraControllerDidSendAsset(self, asset: asset)
                self.newPhotoReady = false
                self.didSendPhoto = true
            }
        }
        
        /*
        Change notifications may be made on a background queue. Re-dispatch to the
        main queue before acting on the change as we'll be updating the UI.
        */
        dispatch_async(dispatch_get_main_queue()) {
            //reset selection
            if let indexPath = self.selectedIndexPath {
                self.pictureCollectionView?.cellForItemAtIndexPath(indexPath)?.selected = false
                self.pictureCollectionView?.reloadItemsAtIndexPaths([indexPath])
                self.selectedIndexPath = nil
            }
            
            
            
            let collectionView = self.pictureCollectionView!
            let lastItem = self.photosData.fetchLimit
            
            // Reload the collection view if the incremental diffs are not available or iOS 8 which checks entire libary and sees large changes to prevent collectionView from trying to make all the incremental changes
            if !collectionChanges.hasIncrementalChanges || collectionChanges.hasMoves || collectionChanges.removedIndexes?.count >= self.photosData.fetchLimit || collectionChanges.insertedIndexes?.count >= self.photosData.fetchLimit {
                // Get the new fetch result.
                self.photosData.assetsFetchResults = collectionChanges.fetchResultAfterChanges
                collectionView.reloadData()
                
            } else {
                /*
                Tell the collection view to animate insertions and deletions if we
                have incremental diffs.
                */
                collectionView.performBatchUpdates({
                    if let removedIndexes = collectionChanges.removedIndexes
                        where removedIndexes.count > 0 {
                            // Get the new fetch result.
                            self.photosData.assetsFetchResults = collectionChanges.fetchResultAfterChanges
                            
                            
                            let lastIndexes = NSIndexSet(indexesInRange: NSMakeRange(lastItem - removedIndexes.count, removedIndexes.count))
                            
                            collectionView.deleteItemsAtIndexPaths(removedIndexes.aapl_indexPathsFromIndexesWithSection(0))
                            // only balance out the collectionView if there are more than 10 items in fetchResult
                            if collectionChanges.fetchResultAfterChanges.count > self.photosData.fetchLimit {
                                collectionView.insertItemsAtIndexPaths(lastIndexes.aapl_indexPathsFromIndexesWithSection(0))
                            }
                    }
                    
                    if let insertedIndexes = collectionChanges.insertedIndexes
                        where insertedIndexes.count > 0 {
                            // Get the new fetch result.
                            self.photosData.assetsFetchResults = collectionChanges.fetchResultAfterChanges
                            
                            let lastIndexes = NSIndexSet(indexesInRange: NSMakeRange(lastItem - insertedIndexes.count, insertedIndexes.count))
                            
                            // only balance out the collectionView if there are more than 10 items in fetchResult
                            if collectionChanges.fetchResultAfterChanges.count > self.photosData.fetchLimit {
                                collectionView.deleteItemsAtIndexPaths(lastIndexes.aapl_indexPathsFromIndexesWithSection(0))
                            }
                            collectionView.insertItemsAtIndexPaths(insertedIndexes.aapl_indexPathsFromIndexesWithSection(0))
                    }
                    
                    // Causes problems with iOS 8
                    
                    //                    if let changedIndexes = collectionChanges.changedIndexes
                    //                        where changedIndexes.count > 0 {
                    //                            // Get the new fetch result.
                    //                            self.photosData.assetsFetchResults = collectionChanges.fetchResultAfterChanges
                    //
                    //                            let safeIndexes = NSMutableIndexSet()
                    //                            changedIndexes.enumerateIndexesUsingBlock({ (index, stop) -> Void in
                    //                                if index != removeIndex {
                    //                                    safeIndexes.addIndex(index)
                    //                                }
                    //                            })
                    //                            collectionView.reloadItemsAtIndexPaths(safeIndexes.aapl_indexPathsFromIndexesWithSection(0))
                    //                    }
                    }, completion: nil)
            }
            
            //            self.resetCachedAssets() //causes the empty cells
        }
    }
    
}



extension CameraViewController {
    
    //MARK: Initial Setup
    
    func enableUI(sender: Bool) {
        shutterButton.enabled = sender
        //        recordButton.enabled = sender
        // Only enable the ability to change camera if the device has more than one camera.
        switchButton.enabled = sender && (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1)
        isInstantSwitch.enabled = sender
        doneButton.enabled = sender
        
        // photos UI
        self.pictureCollectionView.allowsSelection = sender
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
        
        dispatch_async(self.sessionQueue) {
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
            PHPhotoLibrary.requestAuthorization({ (status: PHAuthorizationStatus) -> Void in
                if status == PHAuthorizationStatus.Authorized {
                    
                    self.photosData.setupPhotos()
                    self.photosData.updateCachedAssetsForCollectionView(self.pictureCollectionView, view: self.view, isLoaded: self.isViewLoaded())
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.pictureCollectionView.reloadData()
                        self.enableUI(true)
                    })
                } else {
                    // call method again to check and use denied / restricted messages we already have made
                    self.authorizePhotos()
                }
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
            let alertController = UIAlertController(title: "Do It Live", message: message, preferredStyle: UIAlertControllerStyle.Alert)
            let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
            alertController.addAction(cancelAction)
            self.presentViewController(alertController, animated: true, completion: nil)
        }
    }
    
    //MARK: Actions
    
    func captureStillImage() {
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
                NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange:",  name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDevice)
                
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
        dispatch_async(self.sessionQueue) {
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
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange:", name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput.device)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "sessionRuntimeError:", name: AVCaptureSessionRuntimeErrorNotification, object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "sessionWasInterrupted:", name: AVCaptureSessionWasInterruptedNotification, object: self.session)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "sessionInterruptionEnded:", name: AVCaptureSessionInterruptionEndedNotification, object: self.session)
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
            
            dispatch_async(dispatch_get_main_queue()) {
                self.enableUI(!isCapturingStillImage)
            }
            
        case SessionRunningContext:
            let isSessionRunning = change![NSKeyValueChangeNewKey]! as! Bool
            
            dispatch_async(dispatch_get_main_queue()) {
                self.enableUI(isSessionRunning && PHPhotoLibrary.authorizationStatus() == .Authorized)
            }
        default:
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    func subjectAreaDidChange(notification: NSNotification) {
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

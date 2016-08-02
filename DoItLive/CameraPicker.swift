//
//  CameraPicker.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import Photos
import PhotosUI

protocol CameraPickerDelegate: class {
    func implementReceivedImageAndText(image: UIImage, text: String)
}

class CameraPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    weak var delegate: CameraPickerDelegate? = nil
    
    // MARK: - ImagePicker
    
    //confiure imagePicker
    func configureImagePickerController() -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.PhotoLibrary) {
            imagePicker.sourceType = UIImagePickerControllerSourceType.PhotoLibrary
        }
        return imagePicker
    }
    
    //send asset
    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
        if let url = info[UIImagePickerControllerReferenceURL] as? NSURL {
            if let asset = PHAsset.fetchAssetsWithALAssetURLs([url], options: nil).lastObject as? PHAsset {
                sendImageForAssetAndTweet(asset, tweet: App.Hashtag.rawValue)
                picker.dismissViewControllerAnimated(true, completion: nil)
            }
        } else {
            print("error getting photo from UIImagePicker")
        }
    }
    
}
extension  CameraPicker: CameraViewControllerDelegate {
    
    // MARK: - CameraController
    
    //configure camera
    func getCameraVC() -> CameraViewController {
        let storyboard = UIStoryboard(name: StoryboardID.Main.rawValue, bundle: nil)
        let cameraVC = storyboard.instantiateViewControllerWithIdentifier(ViewControllerID.Camera.rawValue) as! CameraViewController
        cameraVC.delegate = self
        cameraVC.playHawkCry()
        return cameraVC
    }
    
    //send asset
    func cameraControllerDidSendAssetAndTweet(controller: CameraViewController, asset: PHAsset, tweet: String) {
        sendImageForAssetAndTweet(asset, tweet: tweet)
    }

    
//    func sendDataForAsset(asset: PHAsset) {
//        let data = NSData(contentsOfURL: asset.request)
//
//    }
    
    // MARK: - convert asset to image
    func sendImageForAssetAndTweet(asset: PHAsset, tweet: String) {
        let options = PHImageRequestOptions()
        options.synchronous = true
        options.resizeMode = PHImageRequestOptionsResizeMode.Exact
        PHImageManager.defaultManager().requestImageForAsset(asset, targetSize: asset.getAdjustedSize(Helper.PhotoSize.Rendevu.value), contentMode: .AspectFit, options: options,
            resultHandler: { (result, _) -> Void in
                if let image = result {
                    //print("In \(self.classForCoder).sendImageForAsset asset width: \(asset.getAdjustedSize(RVConstants.PhotoSize.Rendevu.value).width) asset height: \(asset.getAdjustedSize(RVConstants.PhotoSize.Rendevu.value).height)")
                    // print("In \(self.classForCoder).image width: \(image.size.width) image height: \(image.size.height)")
                    if let delegate = self.delegate {
                        delegate.implementReceivedImageAndText(image, text: tweet)
                    }
                } else {
                    print("In \(self.classForCoder).sendImageForAsset... failed to fetch image")
                }
        })
    }
}

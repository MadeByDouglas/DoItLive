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
    func implementReceivedImageAndText(_ image: UIImage, text: String)
}

class CameraPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    weak var delegate: CameraPickerDelegate? = nil
    
    // MARK: - ImagePicker
    
    //confiure imagePicker
    func configureImagePickerController() -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.photoLibrary) {
            imagePicker.sourceType = UIImagePickerControllerSourceType.photoLibrary
        }
        return imagePicker
    }
    
    //send asset
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {

        if let asset = info[UIImagePickerControllerPHAsset] as? PHAsset {
            sendImageForAssetAndTweet(asset, tweet: App.Hashtag.rawValue)
            picker.dismiss(animated: true, completion: nil)
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
        let cameraVC = storyboard.instantiateViewController(withIdentifier: ViewControllerID.Camera.rawValue) as! CameraViewController
        cameraVC.delegate = self
        cameraVC.playSoundFile("hawk")
        return cameraVC
    }
    
    //send asset
    func cameraControllerDidSendAssetAndTweet(_ controller: CameraViewController, asset: PHAsset, tweet: String) {
        sendImageForAssetAndTweet(asset, tweet: tweet)
    }

    
//    func sendDataForAsset(asset: PHAsset) {
//        let data = NSData(contentsOfURL: asset.request)
//
//    }
    
    // MARK: - convert asset to image
    func sendImageForAssetAndTweet(_ asset: PHAsset, tweet: String) {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.resizeMode = PHImageRequestOptionsResizeMode.exact
        PHImageManager.default().requestImage(for: asset, targetSize: asset.getAdjustedSize(Helper.PhotoSize.rendevu.value), contentMode: .aspectFit, options: options,
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

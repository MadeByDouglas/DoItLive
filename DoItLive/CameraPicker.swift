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
    func implementReceivedImage(image: UIImage)
}

class CameraPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    weak var delegate: CameraPickerDelegate? = nil
    
    //confiure imagePicker
    func configureImagePickerController() -> UIImagePickerController? {
        let imagePicker = UIImagePickerController()
        
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.PhotoLibrary) {
            imagePicker.sourceType = UIImagePickerControllerSourceType.PhotoLibrary
            imagePicker.navigationBar.translucent = false
            imagePicker.navigationBar.barStyle = UIBarStyle.Black
            imagePicker.navigationBar.barTintColor = UIColor.redColor()
            imagePicker.navigationBar.tintColor = UIColor.whiteColor()
            
            return imagePicker
        }
        return nil
    }
    
    //send asset
    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
        if let url = info[UIImagePickerControllerReferenceURL] as? NSURL {
            if let asset = PHAsset.fetchAssetsWithALAssetURLs([url], options: nil).lastObject as? PHAsset {
                sendImageForAsset(asset)
                picker.dismissViewControllerAnimated(true, completion: nil)
            }
        } else {
            print("error getting photo from UIImagePicker")
        }
    }
    
}
extension  CameraPicker: CameraViewControllerDelegate {
    
    //configure camera
    func getCameraVC() -> CameraViewController? {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let cameraVC = storyboard.instantiateViewControllerWithIdentifier("CameraViewController") as? CameraViewController {
            cameraVC.delegate = self
            return cameraVC
        }
        return nil
    }
    
    //send asset
    func cameraControllerDidSendAsset(controller: CameraViewController, asset: PHAsset) {
        sendImageForAsset(asset)
    }
    
    //take asset and get image
    func sendImageForAsset(asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.synchronous = true
        options.resizeMode = PHImageRequestOptionsResizeMode.Exact
        PHImageManager.defaultManager().requestImageForAsset(asset, targetSize: asset.getAdjustedSize(Helper.PhotoSize.Rendevu.value), contentMode: .AspectFit, options: options,
            resultHandler: { (result, _) -> Void in
                if let image = result {
                    //print("In \(self.classForCoder).sendImageForAsset asset width: \(asset.getAdjustedSize(RVConstants.PhotoSize.Rendevu.value).width) asset height: \(asset.getAdjustedSize(RVConstants.PhotoSize.Rendevu.value).height)")
                    // print("In \(self.classForCoder).image width: \(image.size.width) image height: \(image.size.height)")
                    if let delegate = self.delegate {
                        delegate.implementReceivedImage(image)
                    }
                } else {
                    print("In \(self.classForCoder).sendImageForAsset... failed to fetch image")
                }
        })
    }
}

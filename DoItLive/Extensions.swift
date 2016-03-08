//
//  Extensions.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import Photos

extension UIBarButtonItem {
    func hide(sender: Bool) {
        self.enabled = !sender
        if sender == true {
            self.tintColor = UIColor.clearColor()
        } else {
            self.tintColor = UIColor.whiteColor()
        }
    }
}

extension UINavigationController {
    
    //New implementation to prevent autorotate yet allow camera to rotate for proper pictures
    //works across the app because everything is embedded in the UINavigationController
    override public func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Portrait
    }
    
}

extension PHAsset {
    
    func getAdjustedSize(maxDimension: CGFloat)-> CGSize {
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)
        var newWidth: CGFloat = 0
        var newHeight: CGFloat = 0
        
        if height > width {
            newHeight = maxDimension
            newWidth = maxDimension * (width / height )
        } else {
            newWidth = maxDimension
            newHeight = maxDimension * ( height / width )
        }
        return CGSize(width: newWidth, height: newHeight)
    }
}

extension UIImage {
    func getAdjustedSize(maxDimension: CGFloat)-> CGSize {
        let height = size.height
        let width = size.width
        var newHeight: CGFloat = 0
        var newWidth: CGFloat = 0
        if height > width {
            newHeight = maxDimension
            newWidth = maxDimension * (width / height )
        } else {
            newWidth = maxDimension
            newHeight = maxDimension * ( height / width )
        }
        return CGSize(width: newWidth, height: newHeight)
    }
}

extension NSIndexSet {
    
    func aapl_indexPathsFromIndexesWithSection(section: Int) -> [NSIndexPath] {
        var indexPaths: [NSIndexPath] = []
        indexPaths.reserveCapacity(self.count)
        self.enumerateIndexesUsingBlock{idx, stop in
            indexPaths.append(NSIndexPath(forItem: idx, inSection: section))
        }
        return indexPaths
    }
    
}

extension UICollectionView {
    
    //### returns empty Array, rather than nil, when no elements in rect.
    func aapl_indexPathsForElementsInRect(rect: CGRect) -> [NSIndexPath] {
        guard let allLayoutAttributes = self.collectionViewLayout.layoutAttributesForElementsInRect(rect)
            else {return []}
        let indexPaths = allLayoutAttributes.map{$0.indexPath}
        return indexPaths
    }
    
}

extension UICollectionViewFlowLayout {
    func cellsFitAcrossScreen(numberOfCells: Int, labelHeight: CGFloat) -> CGSize {
        //using information from flowLayout get proper spacing for cells across entire screen
        let insideMargin = self.minimumInteritemSpacing
        let outsideMargins = self.sectionInset.left + self.sectionInset.right
        let numberOfDivisions: Int = numberOfCells - 1
        let subtractionForMargins: CGFloat = insideMargin * CGFloat(numberOfDivisions) + outsideMargins
        
        let fittedWidth = (UIScreen.mainScreen().bounds.width - subtractionForMargins) / CGFloat(numberOfCells)
        return CGSize(width: fittedWidth, height: fittedWidth + labelHeight)
    }
}

extension UIView {
    func makeCircle() {
        self.layer.cornerRadius = self.frame.size.width / 2
        self.clipsToBounds = true
    }
    
    func makeRoundCorners() {
        self.layer.cornerRadius = self.frame.size.width / 32
        self.clipsToBounds = true
    }
    
    func addSelectionLayer() {
        let select = Selection()
        select.frame = self.bounds
        select.addBadge()
        self.layer.addSublayer(select)
    }
    
    func gradientDarkToClear() {
        let colorTop = UIColor.clearColor().CGColor
        let colorBottom = UIColor.blackColor().colorWithAlphaComponent(0.7).CGColor
        
        let gl: CAGradientLayer
        
        gl = CAGradientLayer()
        gl.colors = [ colorTop, colorBottom]
        gl.locations = [ 0.0, 1.0]
        gl.frame = self.bounds
        self.layer.addSublayer(gl)
    }
    
    
    // MARK: Toast via MBProgressHUD
//    func quickToast(title: String) {
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            let hud = MBProgressHUD.showHUDAddedTo(self, animated: true)
//            hud.mode = MBProgressHUDMode.Text
//            hud.labelText = title
//            NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "hudTimerDidFire:", userInfo: hud, repeats: false)
//        })
//    }
//    
//    func detailToast(title: String, details: String) {
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            let hud = MBProgressHUD.showHUDAddedTo(self, animated: true)
//            hud.mode = MBProgressHUDMode.Text
//            hud.labelText = title
//            hud.detailsLabelText = details
//            NSTimer.scheduledTimerWithTimeInterval(3, target: self, selector: "hudTimerDidFire:", userInfo: hud, repeats: false)
//        })
//    }
//    
//    func imageToast(title: String, image: UIImage) {
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            let hud = MBProgressHUD.showHUDAddedTo(self, animated: true)
//            hud.mode = MBProgressHUDMode.CustomView
//            hud.labelText = title
//            hud.customView = UIImageView(image: image)
//            NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: "hudTimerDidFire:", userInfo: hud, repeats: false)
//        })
//    }
//    
//    func showSimpleLoading() {
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            MBProgressHUD.showHUDAddedTo(self, animated: true)
//        })
//    }
//    
//    func hideSimpleLoading() {
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            MBProgressHUD.hideHUDForView(self, animated: true)
//        })
//    }
//    
//    func showPieLoading() -> MBProgressHUD {
//        let hud = MBProgressHUD(view: self)
//        hud.mode = MBProgressHUDMode.Determinate
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            self.addSubview(hud)
//            hud.show(true)
//        })
//        return hud
//    }
//    
//    func hidePieLoading(hud: MBProgressHUD, percent: Float) {
//        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//            hud.progress = percent
//            if hud.progress == 1.0 {
//                hud.hide(true)
//            }
//        })
//    }
//    
//    func hudTimerDidFire(sender: NSTimer) {
//        if let hud = sender.userInfo as? MBProgressHUD {
//            dispatch_async(dispatch_get_main_queue(), { () -> Void in
//                hud.hide(true)
//            })
//        }
//    }
}
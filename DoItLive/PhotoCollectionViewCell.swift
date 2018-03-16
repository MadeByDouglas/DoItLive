//
//  PhotoCollectionViewCell.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import Photos

class PhotoCollectionViewCell: UICollectionViewCell {
    
    static let identifier = "PhotoCollectionViewCell"
    
    var representedAssetIdentifier: String?
    
    @IBOutlet weak var imageCellView: UIImageView!
    
    var thumbnailImage: UIImage? {
        didSet {
            didSetThumbnailImage(oldValue)
        }
    }
    //    var livePhotoBadgeImage: UIImage? {
    //        didSet {
    //            didSetLivePhotoBadgeImage(oldValue)
    //        }
    //    }
    
    fileprivate func didSetThumbnailImage(_: UIImage?) {
        imageCellView.image = thumbnailImage
    }
    
    //    @IBOutlet private weak var imageView: UIImageView!
    //    @IBOutlet private weak var livePhotoBadgeImageView: UIImageView!
    //
    //    override func prepareForReuse() {
    //        super.prepareForReuse()
    //        self.imageView.image = nil
    //        self.livePhotoBadgeImageView.image = nil
    //    }
    
    
    
    //    private func didSetLivePhotoBadgeImage(_: UIImage?) {
    //        self.livePhotoBadgeImageView.image = livePhotoBadgeImage
    //    }
    
    func imageRequestOptions(_ asset: PHAsset) -> PHImageRequestOptions {
        let cropToSquareOptions = PHImageRequestOptions()
        cropToSquareOptions.resizeMode = PHImageRequestOptionsResizeMode.exact
        let cropSideLength = CGFloat(min(asset.pixelWidth, asset.pixelHeight))
        var square = CGRect()
        
        if cropSideLength == CGFloat(asset.pixelWidth) {
            //portrait
            let startPoint = CGFloat(asset.pixelHeight / 2) - (cropSideLength / 2)
            square = CGRect(x: 0, y: startPoint, width: cropSideLength, height: cropSideLength)
            
        } else {
            //landscape
            let startPoint = CGFloat(asset.pixelWidth / 2) - (cropSideLength / 2)
            square = CGRect(x: startPoint, y: 0, width: cropSideLength, height: cropSideLength)
        }
        
        let cropRect = square.applying(CGAffineTransform(scaleX: CGFloat(1 / asset.pixelWidth), y: CGFloat(1 / asset.pixelHeight)))
        cropToSquareOptions.normalizedCropRect = cropRect
        return cropToSquareOptions
    }
    
    
    
    
    
    func configureWithAsset(_ asset: PHAsset) {
        
        self.layoutIfNeeded()
        
        Photos.imageManager?.requestImage(for: asset, targetSize: Photos.AssetGridThumbnailSize, contentMode: .aspectFill, options: imageRequestOptions(asset), resultHandler: { (result, _) -> Void in
            
            // Set the cell's thumbnail image if it's still showing the same asset.
            if self.representedAssetIdentifier == asset.localIdentifier {
                self.thumbnailImage = result
            }
        })
        
        self.contentView.addSelectionLayer()
        
        if self.isSelected {
            self.contentView.layer.sublayers?.last?.isHidden = false
        } else {
            self.contentView.layer.sublayers?.last?.isHidden = true
        }
        
    }
    
    override func  prepareForReuse() {
        super.prepareForReuse()
        self.contentView.layer.sublayers?.removeLast()
    }
}

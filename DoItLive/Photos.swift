//
//  Photos.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import Photos

class Photos: NSObject {
    // Photos fetch
    let fetchLimit = 10
    
    var assetsFetchResults: PHFetchResult<AnyObject>?
    static var imageManager: PHCachingImageManager?
    
    var previousPreheatRect: CGRect = CGRect()
    static var AssetGridThumbnailSize: CGSize = CGSize()
    
    
    override init() {
        super.init()
        
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            setupPhotos()
        } else {
            //will be handled in viewWillAppear
        }
    }
    
    
    func setupPhotos() {
        // fetch Photos
        
        let fetchOptions = PHFetchOptions()
        if #available(iOS 9.0, *) {
            fetchOptions.fetchLimit = fetchLimit
        }
        
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        
        Photos.imageManager = PHCachingImageManager()
        self.resetCachedAssets()
        self.assetsFetchResults = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions) as? PHFetchResult<AnyObject>
        
        
    }
    
    
    func numberOfItems() -> Int {
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            if let images = self.assetsFetchResults?.count {
                if #available(iOS 9.0, *) {
                    return images
                } else {
                    // Fallback on earlier versions
                    print("iOS 9 not detected using fetchLimit for collectionVIew")
                    if images <= fetchLimit {
                        return images
                    } else {
                        return fetchLimit
                    }
                }
                
            } else {
                print("imageFetchResults failed to pull any images")
                return 0
            }
        } else {
            print("photos not authorized")
            return 0
        }
    }
    
    //MARK: - Asset Caching
    
    func resetCachedAssets() {
        Photos.imageManager?.stopCachingImagesForAllAssets()
        self.previousPreheatRect = CGRect.zero
    }
    
    func updateCachedAssetsForCollectionView(_ collectionView: UICollectionView, view: UIView, isLoaded: Bool) {
        guard isLoaded && view.window != nil else {
            return
        }
        
        // The preheat window is twice the height of the visible rect.
        var preheatRect = collectionView.bounds
        preheatRect = preheatRect.insetBy(dx: 0.0, dy: -0.5 * preheatRect.height)
        
        /*
        Check if the collection view is showing an area that is significantly
        different to the last preheated area.
        */
        let delta = abs(preheatRect.midY - self.previousPreheatRect.midY)
        if delta > collectionView.bounds.height / 3.0 {
            
            // Compute the assets to start caching and to stop caching.
            var addedIndexPaths: [IndexPath] = []
            var removedIndexPaths: [IndexPath] = []
            
            self.computeDifferenceBetweenRect(self.previousPreheatRect, andRect: preheatRect, removedHandler: {removedRect in
                let indexPaths = collectionView.aapl_indexPathsForElementsInRect(removedRect)
                removedIndexPaths += indexPaths
                }, addedHandler: {addedRect in
                    let indexPaths = collectionView.aapl_indexPathsForElementsInRect(addedRect)
                    addedIndexPaths += indexPaths
            })
            
            let assetsToStartCaching = self.assetsAtIndexPaths(addedIndexPaths)
            let assetsToStopCaching = self.assetsAtIndexPaths(removedIndexPaths)
            
            // Update the assets the PHCachingImageManager is caching.
            Photos.imageManager?.startCachingImages(for: assetsToStartCaching,
                targetSize: Photos.AssetGridThumbnailSize,
                contentMode: PHImageContentMode.aspectFill,
                options: nil)
            Photos.imageManager?.stopCachingImages(for: assetsToStopCaching,
                targetSize: Photos.AssetGridThumbnailSize,
                contentMode: PHImageContentMode.aspectFill,
                options: nil)
            
            // Store the preheat rect to compare against in the future.
            self.previousPreheatRect = preheatRect
        }
    }
    
    fileprivate func computeDifferenceBetweenRect(_ oldRect: CGRect, andRect newRect: CGRect, removedHandler: (CGRect)->Void, addedHandler: (CGRect)->Void) {
        if newRect.intersects(oldRect) {
            let oldMaxY = oldRect.maxY
            let oldMinY = oldRect.minY
            let newMaxY = newRect.maxY
            let newMinY = newRect.minY
            
            if newMaxY > oldMaxY {
                let rectToAdd = CGRect(x: newRect.origin.x, y: oldMaxY, width: newRect.size.width, height: (newMaxY - oldMaxY))
                addedHandler(rectToAdd)
            }
            
            if oldMinY > newMinY {
                let rectToAdd = CGRect(x: newRect.origin.x, y: newMinY, width: newRect.size.width, height: (oldMinY - newMinY))
                addedHandler(rectToAdd)
            }
            
            if newMaxY < oldMaxY {
                let rectToRemove = CGRect(x: newRect.origin.x, y: newMaxY, width: newRect.size.width, height: (oldMaxY - newMaxY))
                removedHandler(rectToRemove)
            }
            
            if oldMinY < newMinY {
                let rectToRemove = CGRect(x: newRect.origin.x, y: oldMinY, width: newRect.size.width, height: (newMinY - oldMinY))
                removedHandler(rectToRemove)
            }
        } else {
            addedHandler(newRect)
            removedHandler(oldRect)
        }
    }
    
    fileprivate func assetsAtIndexPaths(_ indexPaths: [IndexPath]) -> [PHAsset] {
        
        let assets = indexPaths.map{self.assetsFetchResults![$0.item] as! PHAsset}
        
        return assets
    }
}

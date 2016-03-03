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
    
    var assetsFetchResults: PHFetchResult?
    static var imageManager: PHCachingImageManager?
    
    var previousPreheatRect: CGRect = CGRect()
    static var AssetGridThumbnailSize: CGSize = CGSize()
    
    
    override init() {
        super.init()
        
        if PHPhotoLibrary.authorizationStatus() == .Authorized {
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
        self.assetsFetchResults = PHAsset.fetchAssetsWithMediaType(PHAssetMediaType.Image, options: fetchOptions)
        
        
    }
    
    
    func numberOfItems() -> Int {
        if PHPhotoLibrary.authorizationStatus() == .Authorized {
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
        self.previousPreheatRect = CGRectZero
    }
    
    func updateCachedAssetsForCollectionView(collectionView: UICollectionView, view: UIView, isLoaded: Bool) {
        guard isLoaded && view.window != nil else {
            return
        }
        
        // The preheat window is twice the height of the visible rect.
        var preheatRect = collectionView.bounds
        preheatRect = CGRectInset(preheatRect, 0.0, -0.5 * CGRectGetHeight(preheatRect))
        
        /*
        Check if the collection view is showing an area that is significantly
        different to the last preheated area.
        */
        let delta = abs(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect))
        if delta > CGRectGetHeight(collectionView.bounds) / 3.0 {
            
            // Compute the assets to start caching and to stop caching.
            var addedIndexPaths: [NSIndexPath] = []
            var removedIndexPaths: [NSIndexPath] = []
            
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
            Photos.imageManager?.startCachingImagesForAssets(assetsToStartCaching,
                targetSize: Photos.AssetGridThumbnailSize,
                contentMode: PHImageContentMode.AspectFill,
                options: nil)
            Photos.imageManager?.stopCachingImagesForAssets(assetsToStopCaching,
                targetSize: Photos.AssetGridThumbnailSize,
                contentMode: PHImageContentMode.AspectFill,
                options: nil)
            
            // Store the preheat rect to compare against in the future.
            self.previousPreheatRect = preheatRect
        }
    }
    
    private func computeDifferenceBetweenRect(oldRect: CGRect, andRect newRect: CGRect, removedHandler: (CGRect)->Void, addedHandler: (CGRect)->Void) {
        if CGRectIntersectsRect(newRect, oldRect) {
            let oldMaxY = CGRectGetMaxY(oldRect)
            let oldMinY = CGRectGetMinY(oldRect)
            let newMaxY = CGRectGetMaxY(newRect)
            let newMinY = CGRectGetMinY(newRect)
            
            if newMaxY > oldMaxY {
                let rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY))
                addedHandler(rectToAdd)
            }
            
            if oldMinY > newMinY {
                let rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY))
                addedHandler(rectToAdd)
            }
            
            if newMaxY < oldMaxY {
                let rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY))
                removedHandler(rectToRemove)
            }
            
            if oldMinY < newMinY {
                let rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY))
                removedHandler(rectToRemove)
            }
        } else {
            addedHandler(newRect)
            removedHandler(oldRect)
        }
    }
    
    private func assetsAtIndexPaths(indexPaths: [NSIndexPath]) -> [PHAsset] {
        
        let assets = indexPaths.map{self.assetsFetchResults![$0.item] as! PHAsset}
        
        return assets
    }
}

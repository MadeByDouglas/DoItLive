//
//  Selection.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit

class Selection: CALayer {
    override init() {
        super.init()
        self.backgroundColor = UIColor.white.withAlphaComponent(0.4).cgColor
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addBadge() {
        let badgeLayer = CALayer()
        badgeLayer.frame = CGRect(x: self.bounds.width - 30, y: self.bounds.height - 30, width: 25, height: 25)
        // print("In \(self.classForCoder).addBadge  \(self.bounds.height.description)")
        // print("In \(self.classForCoder).addBadge \(self.frame.height.description)")
        // print("In \(self.classForCoder).addBadge \(badgeLayer.frame.height.description)")
        badgeLayer.contents = UIImage(named: "check_icon")?.cgImage
        
        self.addSublayer(badgeLayer)
    }
}

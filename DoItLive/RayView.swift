//
//  RayView.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 8/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit

@IBDesignable

class RayView: UIView {

    
    // Only override drawRect: if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func drawRect(rect: CGRect) {
        // Drawing code
        let oval = UIBezierPath(ovalInRect: rect)
        UIColor.greenColor().setFill()
        oval.fill()
        
        let center = CGPoint(x:bounds.width/2, y: bounds.height/2)
        let Pi = CGFloat(M_PI)
        
        let line = UIBezierPath()
        line.moveToPoint(center)
        
        let x = center.x + center.x * cos(3 * Pi / 4)
        let y = center.y + center.x * sin(3 * Pi / 4)
        
        let edgePoint = CGPoint(x: x, y: y)
        line.addLineToPoint(edgePoint)
        UIColor.whiteColor().setStroke()
        line.stroke()

    }
 

}

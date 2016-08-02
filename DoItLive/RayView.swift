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
        UIColor.clearColor().setFill()
        oval.fill()
        
        let center = CGPoint(x:bounds.width/2, y: bounds.height/2)
        let Pi = CGFloat(M_PI)
        
        let line = UIBezierPath()
        var edgePoints = [CGPoint]()
        for i in 0...15 {
            let multiplier = CGFloat(2 - (CGFloat(i) * 0.125))
            
            let x = center.x + center.x * cos(multiplier * Pi)
            let y = center.y + center.x * sin(multiplier * Pi)
            let point = CGPoint(x: x, y: y)
            edgePoints.append(point)
        }

        for (i, point) in edgePoints.enumerate() {
            line.moveToPoint(center)
            line.addLineToPoint(point)
            line.lineWidth = 3
            UIColor.twitterBlue().setStroke()
            line.stroke()
            if i % 2 != 0 {
                line.addQuadCurveToPoint(edgePoints[i-1], controlPoint: point)
                line.closePath()
                UIColor.twitterBlue().setFill()
                line.fill()
            }

        }

    }
 

}

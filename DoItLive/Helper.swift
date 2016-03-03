//
//  Helper.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit

class Helper: NSObject {
    enum PhotoSize: Int {
        //        case Chat
        //        case Profile
        case Rendevu
        //        case RendevuCover
        var value: CGFloat {
            switch self {
                //            case .Chat: return 400
                //            case .Profile: return 200
            case .Rendevu: return 800
                //            case .RendevuCover: return 600
            }
        }
    }
    
    enum PasswordMessage: String {
        case MismatchTitle = "Passwords don't match"
        case MismatchDetails = "Try again or press 'Reset Password'"
        case Empty = "Password cannot be empty"
        case Spaces = "Password cannot have spaces"
        case Nothing = "Need to provide a password"
        case ChangeError = "Password failed to save"
        case ChangeSuccess = "Password successfully updated"
        case MinLength = "Password must have at least 6 characters"
    }
    
    enum EmailMessage: String {
        case Spaces = "Email cannot have spaces"
        case Nothing = "Need to provide an email"
        case Error = "Server error, please try again"
        case InvalidTitle = "Invalid Email"
        case InvalidDetails = "Check your @'s and dot your .coms"
    }
    
    static func textIsValid(textField: UITextField, sender: Bool) {
        textField.layer.borderWidth = 3.0
        
        if sender == true {
            textField.layer.borderColor = UIColor.redColor().CGColor
        } else {
            textField.layer.borderColor = UIColor.greenColor().CGColor
        }
    }
    
    static func invalidCharacterMessage(character: String) -> String {
        return "Can't use '\(character)'"
    }
    
    static func cellsFitAcrossScreen(numberOfCells: Int, labelHeight: CGFloat, itemSpacing: CGFloat, sectionInsetLeft: CGFloat, sectionInsetRight: CGFloat) -> CGSize {
        //using hardwired info get proper spacing for cells across entire screen
        let insideMargin = itemSpacing
        let outsideMargins = sectionInsetLeft + sectionInsetRight
        let numberOfDivisions: Int = numberOfCells - 1
        let subtractionForMargins: CGFloat = insideMargin * CGFloat(numberOfDivisions) + outsideMargins
        
        let fittedWidth = (UIScreen.mainScreen().bounds.width - subtractionForMargins) / CGFloat(numberOfCells)
        return CGSize(width: fittedWidth, height: fittedWidth + labelHeight)
    }
}

//
//  LoginViewController.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import TwitterKit
import FBSDKLoginKit
import QuickLook

class LoginViewController: UIViewController, QLPreviewControllerDataSource, FBSDKLoginButtonDelegate {
    
    @IBOutlet weak var termsButton: UIButton!
    @IBOutlet weak var acceptSwitch: UISwitch!
    var logInButton: TWTRLogInButton!
    var logInButtonFacebook: FBSDKLoginButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        
        logInButtonFacebook = FBSDKLoginButton()
        logInButtonFacebook.delegate = self
        logInButtonFacebook.readPermissions = ["public_profile", "email", "user_friends"] //could be handy in the future to grab more info like this, public profile is default setting
        

        logInButton = TWTRLogInButton { (session, error) in
            if let unwrappedSession = session {
                
                //set bool true so if user logs out and logs back in during same session it pushes camera immediately
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: UserDefaultsKeys.firstView.rawValue)
                
                //log in notification
                NSNotificationCenter.defaultCenter().postNotificationName(Notify.Login.rawValue, object: nil, userInfo: ["TWTRSession":unwrappedSession])
            } else {
                NSLog("In \(self.classForCoder.description()) Login error: %@", error!.localizedDescription);
            }
        }
        
        // TODO: Change where the log in button is positioned in your view
        logInButton.center = self.view.center
        self.view.addSubview(logInButton)
        
        logInButtonFacebook.frame = logInButton.frame
        logInButtonFacebook.titleLabel?.font = logInButton.titleLabel?.font
        logInButtonFacebook.center.y = self.view.center.y - 60
        self.view.addSubview(logInButtonFacebook)
    }
    
    override func viewWillAppear(animated: Bool) {
        logInButton.enabled = acceptSwitch.on
        logInButtonFacebook.enabled = acceptSwitch.on
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override internal func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Portrait
    }
    
    //MARK: - QuickLook
    func numberOfPreviewItemsInPreviewController(controller: QLPreviewController) -> Int{
        return 1
    }
    
    func previewController(controller: QLPreviewController, previewItemAtIndex index: Int) -> QLPreviewItem {
        let termsPath = NSBundle.mainBundle().pathForResource("App EULA", ofType: "pdf")
        let termsFile = NSURL(fileURLWithPath: termsPath!)
        return termsFile
    }
    
    //MARK:  - IBActions
    @IBAction func didTapSwitch(sender: UISwitch) {
        logInButton.enabled = acceptSwitch.on
        logInButtonFacebook.enabled = acceptSwitch.on
    }
    
    @IBAction func didTapTerms(sender: UIButton) {
        let quickLook = QLPreviewController()
        quickLook.dataSource = self
        presentViewController(quickLook, animated: true, completion: nil)
    }
    
    func loginButton(loginButton: FBSDKLoginButton!, didCompleteWithResult result: FBSDKLoginManagerLoginResult!, error: NSError!) {
        if let error = error {
            print(error)
        } else if result.isCancelled {
            print("facebook login cancelled")
        } else {
            //set bool true so if user logs out and logs back in during same session it pushes camera immediately
            //TODO: test moving the setting of the key inside login/logout notification for more consise code
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: UserDefaultsKeys.firstView.rawValue)

            NSNotificationCenter.defaultCenter().postNotificationName(Notify.Login.rawValue, object: nil, userInfo: ["FBSDKLoginResult":result])
        }
    }
    
    func loginButtonDidLogOut(loginButton: FBSDKLoginButton!) {
        NSUserDefaults.standardUserDefaults().setBool(false, forKey: UserDefaultsKeys.firstView.rawValue)
        NSNotificationCenter.defaultCenter().postNotificationName(Notify.Logout.rawValue, object: nil)

    }

}

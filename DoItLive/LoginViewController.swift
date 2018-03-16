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
    @IBOutlet weak var spinningView: RayView!
    @IBOutlet weak var logoImageView: UIImageView!
    
    var logInButton: TWTRLogInButton!
    var logInButtonFacebook: FBSDKLoginButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        
        logInButtonFacebook = FBSDKLoginButton()
        logInButtonFacebook.delegate = self
        logInButtonFacebook.readPermissions = ["public_profile", "email", "user_friends"] //could be handy in the future to grab more info like this, public profile is default setting
        logInButtonFacebook.publishPermissions =  ["publish_actions"] //so we can post

        logInButton = TWTRLogInButton { (session, error) in
            if let unwrappedSession = session {
                
                //set bool true so if user logs out and logs back in during same session it pushes camera immediately
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.firstView.rawValue)
                
                //log in notification
                NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Login.rawValue), object: nil, userInfo: ["TWTRSession":unwrappedSession])
            } else {
                NSLog("In \(self.classForCoder.description()) Login error: %@", error!.localizedDescription);
            }
        }
        
        logInButton.center = self.view.center
        logInButton.center.y = self.view.center.y + 80
        self.view.addSubview(logInButton)
        
        logInButtonFacebook.frame = logInButton.frame
        logInButtonFacebook.titleLabel?.font = logInButton.titleLabel?.font
        logInButtonFacebook.center.y = logInButton.center.y + 60
        self.view.addSubview(logInButtonFacebook)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        spinningView.rotate360Degrees()

        logInButton.isEnabled = acceptSwitch.isOn
        logInButtonFacebook.isEnabled = acceptSwitch.isOn
        spinningView.isHidden = !acceptSwitch.isOn
        logoImageView.isHidden = !acceptSwitch.isOn
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        spinningView.stopRotating()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override internal var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
    
    //MARK: - QuickLook
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int{
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let termsPath = Bundle.main.path(forResource: "App EULA", ofType: "pdf")
        let termsFile = URL(fileURLWithPath: termsPath!)
        return termsFile as QLPreviewItem
    }
    
    //MARK:  - IBActions
    @IBAction func didTapSwitch(_ sender: UISwitch) {
        logInButton.isEnabled = acceptSwitch.isOn
        logInButtonFacebook.isEnabled = acceptSwitch.isOn
        spinningView.isHidden = !acceptSwitch.isOn
        logoImageView.isHidden = !acceptSwitch.isOn
    }
    
    @IBAction func didTapTerms(_ sender: UIButton) {
        let quickLook = QLPreviewController()
        quickLook.dataSource = self
        spinningView.stopRotating()
        present(quickLook, animated: true, completion: nil)
    }
    
    func loginButton(_ loginButton: FBSDKLoginButton!, didCompleteWith result: FBSDKLoginManagerLoginResult!, error: Error!) {
        if let error = error {
            print(error)
        } else if result.isCancelled {
            print("facebook login cancelled")
        } else {
            //set bool true so if user logs out and logs back in during same session it pushes camera immediately
            //TODO: test moving the setting of the key inside login/logout notification for more consise code
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.firstView.rawValue)

            NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Login.rawValue), object: nil, userInfo: ["FBSDKLoginResult":result])
        }
    }
    
    func loginButtonDidLogOut(_ loginButton: FBSDKLoginButton!) {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.firstView.rawValue)
        NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Logout.rawValue), object: nil)

    }

}

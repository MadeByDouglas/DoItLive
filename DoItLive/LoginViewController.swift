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

                //log in notification
                let sessionDict: [String: TWTRAuthSession] = ["TWTRSession": unwrappedSession]
                NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Login.rawValue), object: nil, userInfo: sessionDict)
                
            } else {
                NSLog("In \(self.classForCoder.description()) Login error: %@", error!.localizedDescription);
            }
        }
        
        self.view.addSubview(logInButton)
        logInButton.translatesAutoresizingMaskIntoConstraints = false

        logInButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        logInButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        logInButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: 80).isActive = true

        logInButtonFacebook.titleLabel?.font = logInButton.titleLabel?.font
        self.view.addSubview(logInButtonFacebook)

        logInButtonFacebook.translatesAutoresizingMaskIntoConstraints = false
        for constraint in logInButtonFacebook.constraints {
            logInButtonFacebook.removeConstraint(constraint)
        }
        logInButtonFacebook.centerXAnchor.constraint(equalTo: logInButton.centerXAnchor).isActive = true
        logInButtonFacebook.centerYAnchor.constraint(equalTo: logInButton.centerYAnchor, constant: 60).isActive = true
        logInButtonFacebook.heightAnchor.constraint(equalTo: logInButton.heightAnchor).isActive = true
        logInButtonFacebook.widthAnchor.constraint(equalTo: logInButton.widthAnchor).isActive = true
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
        let termsPath = Bundle.main.path(forResource: "AppEULA", ofType: "pdf")
        let termsFile = URL(fileURLWithPath: termsPath!) as QLPreviewItem
        return termsFile
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
            NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Login.rawValue), object: nil, userInfo: ["FBSDKLoginResult": result])
        }
    }
    
    func loginButtonDidLogOut(_ loginButton: FBSDKLoginButton!) {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.firstView.rawValue)
        NotificationCenter.default.post(name: Notification.Name(rawValue: Notify.Logout.rawValue), object: nil)

    }

}

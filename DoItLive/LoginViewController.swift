//
//  LoginViewController.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import TwitterKit
import QuickLook

class LoginViewController: UIViewController, QLPreviewControllerDataSource {
    
    @IBOutlet weak var termsButton: UIButton!
    @IBOutlet weak var acceptSwitch: UISwitch!
    var logInButton: TWTRLogInButton!
    

    override func viewDidLoad() {
        super.viewDidLoad()

        logInButton = TWTRLogInButton { (session, error) in
            if let unwrappedSession = session {
                
                //set bool true so if user logs out and logs back in during same session it pushes camera immediately
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: UserDefaultsKeys.firstView.rawValue)
                
                //log in notification
                NSNotificationCenter.defaultCenter().postNotificationName(Notify.Login.rawValue, object: unwrappedSession)
            } else {
                NSLog("In \(self.classForCoder.description()) Login error: %@", error!.localizedDescription);
            }
        }
        
        // TODO: Change where the log in button is positioned in your view
        logInButton.center = self.view.center
        self.view.addSubview(logInButton)
    }
    
    override func viewWillAppear(animated: Bool) {
        logInButton.enabled = acceptSwitch.on
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
    }
    
    @IBAction func didTapTerms(sender: UIButton) {
        let quickLook = QLPreviewController()
        quickLook.dataSource = self
        presentViewController(quickLook, animated: true, completion: nil)
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}

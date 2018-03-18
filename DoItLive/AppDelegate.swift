//
//  AppDelegate.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit
import Fabric
import TwitterKit
import Crashlytics
import FBSDKCoreKit
import FBSDKLoginKit
import SwiftyJSON

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var twitterUserName: String?
    var facebookUserName: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {

        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        TWTRTwitter.sharedInstance().start(withConsumerKey: "uaghEjF7QkEgpj9A2Qsrjv1Zr", consumerSecret: "sUVqTHSlNJHzQkgPc0do5FjCl2E72N5Pe7LvYSZeIgJkULPzCn")
        Fabric.with([Crashlytics.self, Answers.self])
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: Notify.Login.rawValue), object: nil, queue: nil) { (notification) -> Void in
            
            if let twitterSession = notification.userInfo?["TWTRSession"] as? TWTRSession {
                self.appLogin(twitterSession, facebookResult: nil)
            } else if let facebookResult = notification.userInfo?["FBSDKLoginResult"] as? FBSDKLoginManagerLoginResult {
                self.appLogin(nil, facebookResult: facebookResult)
            } else {
                fatalError("Returned from login flow but has no twitter session or facebook login result") //probably should never get here
            }

        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: Notify.Logout.rawValue), object: nil, queue: nil) { (notification) -> Void in
            self.appLogout()
        }
        
        handleAuth()

        return true
    }

    // MARK: application redirect facebook
    func loginRedirect(app: UIApplication, url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.scheme == "twitterkit-uaghEjF7QkEgpj9A2Qsrjv1Zr" {
            return TWTRTwitter.sharedInstance().application(app, open: url, options: options)
        } else {
            return FBSDKApplicationDelegate.sharedInstance().application(app, open: url, sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String, annotation: options[UIApplicationOpenURLOptionsKey.annotation])
        }
    }

    // MARK: application redirect twitter
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        return loginRedirect(app: app, url: url, options: options)
    }
    
    func appLogin(_ twitterSession: TWTRSession?, facebookResult: FBSDKLoginManagerLoginResult?) {
        //login handled by twitter and fb buttons

        //set bool true so if user logs out and logs back in during same session it pushes camera immediately
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.firstView.rawValue)

        //Answers and Crashlytics Track login
        if let session = twitterSession {
            Answers.logLogin(withMethod: "Twitter", success: true, customAttributes: ["UserID":session.userID, "UserName":session.userName])
            logUser(session.userID, userName: session.userName, userEmail: nil)
            twitterUserName = session.userName
            UserDefaults.standard.set(session.userName, forKey: "twitterUserName")
            
            handleAuth()
        }
        
        if let loginResult = facebookResult {
            Answers.logLogin(withMethod: "Facebook", success: true, customAttributes: ["UserID":loginResult.token.userID])
            logUser(loginResult.token.userID, userName: nil, userEmail: nil)
            
            let parameters = ["fields":"id, first_name, email"]
            FBSDKGraphRequest.init(graphPath: "me", parameters: parameters).start(completionHandler: { (connection, result, error) in
                
                if let error = error {
                    print(error)
                    
                } else if let result = result {
                    if let firstName = (result as AnyObject).value(forKey: "first_name") as? String {
                        self.facebookUserName = firstName
                        UserDefaults.standard.set(firstName, forKey: "facebookUserName")
                    }
                }
                
                self.handleAuth()
            })
        }
    }
    
    func appLogout() {
        if let userID = TWTRTwitter.sharedInstance().sessionStore.session()?.userID {
            TWTRTwitter.sharedInstance().sessionStore.logOutUserID(userID)
            UserDefaults.standard.removeObject(forKey: "twitterUserName")
        }
        
        if FBSDKAccessToken.current() != nil {
            FBSDKLoginManager().logOut()
            UserDefaults.standard.removeObject(forKey: "facebookUserName")
        }
        
        logUser(nil, userName: nil, userEmail: nil)

        handleAuth()
    }
    
    func handleAuth() {
        
        if TWTRTwitter.sharedInstance().sessionStore.session() == nil && FBSDKAccessToken.current() == nil {
            //login root
            window?.rootViewController = UIStoryboard(name: StoryboardID.Main.rawValue, bundle: nil).instantiateViewController(withIdentifier: ViewControllerID.Login.rawValue)
        } else {
            //main root
            if let userName = UserDefaults.standard.object(forKey: "twitterUserName") as? String {
                twitterUserName = userName
            }
            
            if let firstName = UserDefaults.standard.object(forKey: "facebookUserName") as? String {
                facebookUserName = firstName
            }
            
            window?.rootViewController = UIStoryboard(name: StoryboardID.Main.rawValue, bundle: nil).instantiateViewController(withIdentifier: ViewControllerID.NavFeed.rawValue)

        }
    }
    
    func logUser(_ userID: String?, userName: String?, userEmail: String?) {
        Crashlytics.sharedInstance().setUserIdentifier(userID)
        Crashlytics.sharedInstance().setUserName(userName)
        Crashlytics.sharedInstance().setUserEmail(userEmail)
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        FBSDKAppEvents.activateApp()
        
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.firstView.rawValue)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        
        //clear userDefaults, aparently not called not needed
//        NSUserDefaults.standardUserDefaults().removeObjectForKey(UserDefaultsKeys.firstView.rawValue)
//        NSUserDefaults.standardUserDefaults().removeObjectForKey(UserDefaultsKeys.savedTweet.rawValue)
    }


}


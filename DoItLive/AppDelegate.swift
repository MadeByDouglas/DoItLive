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

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {

        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        
        Fabric.with([Twitter.self, Crashlytics.self, Answers.self])
        
        NSNotificationCenter.defaultCenter().addObserverForName(Notify.Login.rawValue, object: nil, queue: nil) { (notification) -> Void in
            if let twitterSession = notification.userInfo?["TWTRSession"] as? TWTRSession {
                self.appLogin(twitterSession)
            } else {
                self.appLogin(nil) //probably should never get here
            }

        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(Notify.Logout.rawValue, object: nil, queue: nil) { (notification) -> Void in
            self.appLogout()
        }
        
        handleAuth()

        return true
    }
    
    func application(application: UIApplication, openURL url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
        return FBSDKApplicationDelegate.sharedInstance().application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation)
    }
    
    func appLogin(twitterSession: TWTRSession?) {
        //login handled by twitter and fb buttons

        //Answers and Crashlytics Track login
        if let session = twitterSession {
            Answers.logLoginWithMethod("Twitter", success: true, customAttributes: ["UserID":session.userID, "UserName":session.userName])
            logUser(session.userID, userName: session.userName, userEmail: nil)
            twitterUserName = session.userName
            NSUserDefaults.standardUserDefaults().setObject(session.userName, forKey: "twitterUserName")
            
            let client = TWTRAPIClient.clientWithCurrentUser()
            let request = client.URLRequestWithMethod("GET",
                                                      URL: "https://api.twitter.com/1.1/account/verify_credentials.json",
                                                      parameters: ["include_email": "true", "skip_status": "true"],
                                                      error: nil)
            client.sendTwitterRequest(request) { (response, data, error) in
                if let error = error {
                    print(error.description)
                } else if let data = data {
                    let dictionary = JSON(data: data).dictionaryObject
                    let email = dictionary!["email"]
                    print(email)
                }
            }
        }
        
        //TODO: get facebook userID
        
        handleAuth()
    }
    
    func appLogout() {
        if let userID = Twitter.sharedInstance().sessionStore.session()?.userID {
            Twitter.sharedInstance().sessionStore.logOutUserID(userID)
            NSUserDefaults.standardUserDefaults().removeObjectForKey("twitterUserName")
        }
        FBSDKLoginManager().logOut()
        
        logUser(nil, userName: nil, userEmail: nil)

        handleAuth()
    }
    
    func handleAuth() {

        
        if Twitter.sharedInstance().sessionStore.session() == nil {
            //login root
            window?.rootViewController = UIStoryboard(name: StoryboardID.Main.rawValue, bundle: nil).instantiateViewControllerWithIdentifier(ViewControllerID.Login.rawValue)
        } else {
            //main root
            if let userName = NSUserDefaults.standardUserDefaults().objectForKey("twitterUserName") as? String {
                twitterUserName = userName
            }
            window?.rootViewController = UIStoryboard(name: StoryboardID.Main.rawValue, bundle: nil).instantiateViewControllerWithIdentifier(ViewControllerID.NavFeed.rawValue)

        }
    }
    
    func logUser(userID: String?, userName: String?, userEmail: String?) {
        Crashlytics.sharedInstance().setUserIdentifier(userID)
        Crashlytics.sharedInstance().setUserName(userName)
        Crashlytics.sharedInstance().setUserEmail(userEmail)
    }
    
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        FBSDKAppEvents.activateApp()
        
        NSUserDefaults.standardUserDefaults().setBool(true, forKey: UserDefaultsKeys.firstView.rawValue)
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        
        //clear userDefaults, aparently not called not needed
//        NSUserDefaults.standardUserDefaults().removeObjectForKey(UserDefaultsKeys.firstView.rawValue)
//        NSUserDefaults.standardUserDefaults().removeObjectForKey(UserDefaultsKeys.savedTweet.rawValue)
    }


}


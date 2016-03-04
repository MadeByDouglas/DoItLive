//
//  FeedTableViewController.swift
//  DoItLive
//
//  Created by Douglas Hewitt on 3/2/16.
//  Copyright © 2016 madebydouglas. All rights reserved.
//

import UIKit

class FeedTableViewController: UITableViewController, CameraPickerDelegate {

    @IBOutlet weak var logoutBarButton: UIBarButtonItem!
    @IBOutlet weak var newPostBarButton: UIBarButtonItem!
    
    @IBAction func didTapLogout(sender: UIBarButtonItem) {
        CurrentUser.sharedInstance.session = nil
        presentLogin()
    }
    
    @IBAction func didTapNewPost(sender: UIBarButtonItem) {
        showCameraMenu()
    }
    
    let camera = CameraPicker()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        camera.delegate = self

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        if CurrentUser.sharedInstance.session == nil {
            presentLogin()
        }
    }
    
    func presentLogin() {
        let loginVC = UIStoryboard(name: StoryboardID.Main.rawValue, bundle: nil).instantiateViewControllerWithIdentifier(ViewControllerID.Login.rawValue)
        presentViewController(loginVC, animated: true, completion: nil)
    }
    
    func implementReceivedImage(image: UIImage) {
        // TODO: post to twitter
        print("in \(classForCoder.description()) post to twitter")
        
    }
    
    // MARK: - Camera Menu
    func showCameraMenu() {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.ActionSheet)
        alertController.modalPresentationStyle = UIModalPresentationStyle.Popover
        
        alertController.addAction(UIAlertAction(title: "Photo Album", style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction) -> Void in
            let imagePickerVC = self.camera.configureImagePickerController()
            self.presentViewController(imagePickerVC, animated: true, completion: nil)
        }))
        
        alertController.addAction(UIAlertAction(title: "Camera", style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction ) -> Void in
            let cameraVC = self.camera.getCameraVC()
            self.presentViewController(cameraVC, animated: true, completion: nil)
            
        }))
        //        alertController.addAction(UIAlertAction(title: "Video", style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction ) -> Void in
        //
        //        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: { (action: UIAlertAction) -> Void in
            
        }))
        
        if self.presentedViewController == nil {
            self.presentViewController(alertController, animated: true, completion: nil)
        } else {
            print("\(classForCoder).alertController something already presented")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 0
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return 0
    }

    /*
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("reuseIdentifier", forIndexPath: indexPath)

        // Configure the cell...

        return cell
    }
    */

    /*
    // Override to support conditional editing of the table view.
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(tableView: UITableView, moveRowAtIndexPath fromIndexPath: NSIndexPath, toIndexPath: NSIndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}

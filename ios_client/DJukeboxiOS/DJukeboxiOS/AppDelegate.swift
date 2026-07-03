//
//  AppDelegate.swift
//  DJukeboxiOS
//
//  Created by Brian Martin on 5/7/20.
//  Copyright © 2020 Brian Martin. All rights reserved.
//

import UIKit
import AVFoundation
import DJukeboxCommon
import DJukeboxClient

// @main replaces the deprecated @UIApplicationMain (an error under Swift 6);
// UIApplicationDelegate supplies the synthesized entry point.
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

#if DEBUG
        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .debug),
            .file   : FileLogHandler(at: .debug),
            .alert  : AlertLogHandler(at: .warn),
          ]
#else
        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .warn),
          ]
#endif

        Log.i("Application Starting")

        // make sure that the app can play audio in the background
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(AVAudioSession.Category.playback,
                                    mode: AVAudioSession.Mode.default,
                                    options: [])
        } catch let error as NSError {
            Log.e("Failed to set the audio session category and mode: \(error.localizedDescription)")
        }

        configureBarAppearance()

        return true
    }

    // Theme the tab bar and navigation bars to match the dark neon look: a dark
    // translucent background (so the screen gradient shows through) with cyan
    // selected / lavender unselected items and bright titles.
    private func configureBarAppearance() {
        let cyan     = UIColor(red: 0x12/255.0, green: 0xDB/255.0, blue: 0xFF/255.0, alpha: 1)
        let lavender = UIColor(red: 0xB9/255.0, green: 0xA8/255.0, blue: 0xE0/255.0, alpha: 1)
        let bright   = UIColor(red: 0xF3/255.0, green: 0xE9/255.0, blue: 0xFF/255.0, alpha: 1)
        let barTint  = UIColor(red: 0x0B/255.0, green: 0x06/255.0, blue: 0x20/255.0, alpha: 0.55)

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundColor = barTint
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = lavender
            item.normal.titleTextAttributes = [.foregroundColor: lavender]
            item.selected.iconColor = cyan
            item.selected.titleTextAttributes = [.foregroundColor: cyan]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = barTint
        nav.titleTextAttributes = [.foregroundColor: bright]
        nav.largeTitleTextAttributes = [.foregroundColor: bright]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = cyan
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

func resignFirstResponders() {

}

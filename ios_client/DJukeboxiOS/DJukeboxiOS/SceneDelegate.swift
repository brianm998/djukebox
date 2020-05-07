//
//  SceneDelegate.swift
//  DJukeboxiOS
//
//  Created by Brian Martin on 5/7/20.
//  Copyright © 2020 Brian Martin. All rights reserved.
//

import UIKit
import SwiftUI
import DJukeboxClient
import DJukeboxCommon

let serverURL = "http://127.0.0.1:8080"
let password = "foobar"


class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    var contentView: some View {
        // the server connection for tracks and history 
        let server = ServerConnection(toUrl: serverURL, withPassword: password)

        // an observable view object for showing lots of track based info
        let trackFetcher = TrackFetcher(withServer: server)

        // an observable object for keeping the history up to date from the server
        let historyFetcher = HistoryFetcher(withServer: server, trackFetcher: trackFetcher)

        /*
        server.listTracks { tracks, error in
            print("got tracks \(tracks?.count ?? -1)")
        }*/

        let trackFinder = TrackFinder(trackFetcher: trackFetcher, serverConnection: server)
        let player = NetworkAudioPlayer(trackFinder: trackFinder,
                                        historyWriter: ServerHistoryWriter(server: server))
        let audioPlayer = AsyncAudioPlayer(player: player, fetcher: trackFetcher, history: historyFetcher)

        return ContentView(trackFetcher: trackFetcher,
                           historyFetcher: historyFetcher,
                           serverConnection: server,
                           audioPlayer: ViewObservableAudioPlayer(player: audioPlayer))
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        // Create the SwiftUI view that provides the window contents.
        let contentView = self.contentView

        // Use a UIHostingController as window root view controller.
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}


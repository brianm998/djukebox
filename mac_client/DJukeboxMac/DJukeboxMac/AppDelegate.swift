//
//  AppDelegate.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import Cocoa
import SwiftUI
import CryptoKit
import DJukeboxCommon
import DJukeboxClient

// The server is discovered on the local network via mDNS / Bonjour (see
// ServerBrowser), and there's no shared password anymore: a daemon on this same
// machine is reached over loopback (trusted, no pairing), and a server on the
// WiFi requires this device to pair (see PairingClient / PairingStore).

// @MainActor: window handle only ever touched from the main-actor app lifecycle.
@MainActor var theWindow: NSWindow!

// @main replaces the deprecated @NSApplicationMain (an error under Swift 6);
// NSApplicationDelegate supplies the synthesized entry point.
@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    var window: NSWindow!

    // Set false to fall back to the classic single fixed-layout ContentView.
    private let useDockablePanels = true
    private var panelController: PanelWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {

#if DEBUG
        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .info),
            .file   : FileLogHandler(at: .error),
//          .alert  : AlertLogHandler(at: .warn),
          ]
#else
        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .warn),
          ]
#endif

        // Try a daemon on this machine (127.0.0.1) first — it's trusted over
        // loopback and needs no pairing. If there isn't one, browse the WiFi and
        // pair as needed. Default to playing locally, and quietly drop into
        // local-only mode (cached tracks) when no server is found.
        let browser = ServerBrowser(initialQueueType: .local,
                                    autoFallbackToLocal: true,
                                    tryLoopbackFirst: true)
        browser.start()

        if useDockablePanels {
            // Dockable, rearrangeable, multi-window workspace. The window layer
            // lives in the shared library (PanelWindowController); it needs a
            // factory that builds each panel kind's view — supplied here so the
            // mac control bar (BigButtonView, app target) can be composed too.
            let controller = PanelWindowController(browser: browser) { panel, client in
                AppDelegate.panelView(panel, client: client, browser: browser)
            }
            panelController = controller
            controller.restoreWindows()
            theWindow = controller.primaryWindow
            installMenuCommands()
        } else {
            // Classic single fixed-layout window (fallback).
            window = NSWindow(
              contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
              styleMask: [.titled, .closable, .miniaturizable, .resizable],
              backing: .buffered, defer: false)
            window.title = "DJukebox"
            window.center()
            window.setFrameAutosaveName("Main Window")
            window.contentView = NSHostingView(rootView: ContentView(browser))
            window.makeKeyAndOrderFront(nil)
            theWindow = window
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keypress in
            // Only intercept space when a window is key and nothing (e.g. a text
            // field) has grabbed first responder.
            guard let keyWindow = NSApp.keyWindow, keyWindow.firstResponder === keyWindow else {
                return keypress
            }
            if keypress.characters == " ",
               let player = browser.currentClient?.trackFetcher.audioPlayer.player
            {
                if player.isPaused {
                    player.resumePlaying() { success, error in
                        
                    }
                } else {
                    player.pausePlaying() { success, error in
                        
                    }
                }
                return nil
            } else {
                return keypress
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // MARK: - Panel factory

    /// Builds the view for a panel kind, bound to the given client. Lives in the
    /// app target so it can compose the app's control bar (BigButtonView) with the
    /// shared library panels.
    static func panelView(_ panel: Panel, client: Client, browser: ServerBrowser) -> AnyView {
        switch panel.kind {
        case .artists:  return AnyView(ArtistList(client))
        case .albums:
            if case .artist(let artist) = panel.binding {
                return AnyView(BoundAlbumList(client, artist: artist))
            }
            return AnyView(AlbumList(client))
        case .songs:
            if case .album(let artist, let album) = panel.binding {
                return AnyView(BoundTrackList(client, artist: artist, album: album))
            }
            return AnyView(TrackList(client))
        case .playingControls:
            // Transport buttons + master volume only.
            return AnyView(
                BigButtonView(trackFetcher: client.trackFetcher,
                              onScan: { browser.start() },
                              onGoOffline: browser.rememberCurrentPlayLocal)
            )
        case .playingList:
            // Now-playing (track + progress) atop the up-next queue.
            return AnyView(
                VStack(spacing: 0) {
                    PlayingTrackView(trackFetcher: client.trackFetcher)
                    PlayingQueueView(trackFetcher: client.trackFetcher)
                }
            )
        case .allSearch:
            return AnyView(SearchView(client))
        case .history:
            return AnyView(HistoryView(client))
        }
    }

    // MARK: - Menu commands

    private func installMenuCommands() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let viewMenu: NSMenu
        if let item = mainMenu.items.first(where: { $0.title == "View" }), let sub = item.submenu {
            viewMenu = sub
        } else {
            let menu = NSMenu(title: "Panels")
            let item = NSMenuItem(title: "Panels", action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.addItem(item)
            viewMenu = menu
        }

        viewMenu.addItem(.separator())

        let newPanelItem = NSMenuItem(title: "New Panel", action: nil, keyEquivalent: "")
        let newPanelMenu = NSMenu(title: "New Panel")
        for kind in PanelKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(newPanel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.image = NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil)
            newPanelMenu.addItem(item)
        }
        newPanelItem.submenu = newPanelMenu
        viewMenu.addItem(newPanelItem)

        let newWindowItem = NSMenuItem(title: "New Panel Window",
                                       action: #selector(newPanelWindow(_:)), keyEquivalent: "n")
        newWindowItem.keyEquivalentModifierMask = [.command, .option]
        newWindowItem.target = self
        viewMenu.addItem(newWindowItem)

        let resetItem = NSMenuItem(title: "Reset Layout to Default",
                                   action: #selector(resetLayout(_:)), keyEquivalent: "")
        resetItem.target = self
        viewMenu.addItem(resetItem)
    }

    @objc private func newPanel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = PanelKind(rawValue: raw) else { return }
        panelController?.addPanel(kind)
    }

    @objc private func newPanelWindow(_ sender: Any?) {
        panelController?.newWindow(root: .defaultLayout())
    }

    @objc private func resetLayout(_ sender: Any?) {
        panelController?.resetToDefault()
        theWindow = panelController?.primaryWindow
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newPanel(_:)), #selector(newPanelWindow(_:)):
            return panelController?.isConnected ?? false
        case #selector(resetLayout(_:)):
            return panelController != nil
        default:
            return true
        }
    }
}



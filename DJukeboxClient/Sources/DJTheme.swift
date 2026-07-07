//
//  DJTheme.swift
//  DJukeboxClient
//
//  Dark "neon jukebox" theme shared by the macOS and iOS clients. The palette is
//  sampled from app_icon.png (the neon jukebox): a deep navy-purple background
//  with magenta / violet / indigo / cyan neon accents and bright lavender text.
//

import SwiftUI

public enum DJTheme {

    // MARK: - Palette (sampled from app_icon.png)

    /// Deepest background, used at the edges of the screen gradient.
    public static let deepBackground = Color(djHex: 0x05010F)
    /// Base screen background.
    public static let background     = Color(djHex: 0x0B0620)
    /// A panel/surface sitting on the background.
    public static let panel          = Color(djHex: 0x160C34)
    /// A raised panel / selected row.
    public static let panelElevated  = Color(djHex: 0x211149)

    public static let neonMagenta = Color(djHex: 0xEF0FFD)
    public static let neonViolet  = Color(djHex: 0xC131F0)
    public static let neonIndigo  = Color(djHex: 0x351DCA)
    public static let neonBlue    = Color(djHex: 0x2E6BFF)
    public static let neonCyan    = Color(djHex: 0x12DBFF)

    /// Bright primary text.
    public static let textPrimary   = Color(djHex: 0xF3E9FF)
    /// Dimmer secondary text (lavender-grey).
    public static let textSecondary = Color(djHex: 0xB9A8E0)

    // MARK: - Local-cache indicators
    //
    // Browse lists tint each row by how much of it is cached locally for offline
    // play: green when everything is cached, amber when only some is, and the
    // normal near-white text when none is. Songs are all-or-nothing, so only
    // `cacheFull` / `cacheNone` ever apply to them. See `CacheStatus`.
    /// Fully cached locally.
    public static let cacheFull    = Color(djHex: 0x2BFF88)
    /// Partially cached locally.
    public static let cachePartial = Color(djHex: 0xFFD54A)
    /// Not cached — the normal row text colour (near-white).
    public static let cacheNone    = textPrimary

    /// Default control tint — cyan reads best against the dark background.
    public static let accent = neonCyan

    // MARK: - Gradients

    /// The signature neon sweep used for borders and dividers (mirrors the
    /// magenta→violet→indigo→cyan run of the jukebox arch in the icon).
    public static let neonGradient = LinearGradient(
        colors: [neonMagenta, neonViolet, neonIndigo, neonCyan],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Horizontal variant for thin dividers between stacked sections.
    public static let neonGradientHorizontal = LinearGradient(
        colors: [neonMagenta, neonViolet, neonIndigo, neonCyan],
        startPoint: .leading, endPoint: .trailing)

    /// Vertical variant for thin dividers between side-by-side columns.
    public static let neonGradientVertical = LinearGradient(
        colors: [neonMagenta, neonViolet, neonIndigo, neonCyan],
        startPoint: .top, endPoint: .bottom)

    /// Full-screen background: a subtle top-to-bottom deepening of the navy-purple.
    public static let screenGradient = LinearGradient(
        colors: [Color(djHex: 0x140838), background, deepBackground],
        startPoint: .top, endPoint: .bottom)

    // MARK: - Corner rounding

    /// Resolve the corner radius that a UI element should actually use.
    ///
    /// On macOS the *only* rounded corners in the UI are the window's own corners
    /// (drawn/clipped by the OS), so every in-window element is squared off — an
    /// element flush in a window corner still reads as rounded because the window
    /// itself clips it. iOS keeps its rounded treatment, so the requested radius
    /// passes through untouched there.
    public static func cornerRadius(_ requested: CGFloat) -> CGFloat {
        #if os(macOS)
        return 0
        #else
        return requested
        #endif
    }
}

// MARK: - Hex color initializer

public extension Color {
    /// Build a Color from a 0xRRGGBB integer (opaque).
    init(djHex hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Reusable view treatments

public extension View {
    /// Paint the neon-jukebox screen gradient behind this view, edge to edge.
    func djScreenBackground() -> some View {
        background(DJTheme.screenGradient.ignoresSafeArea())
    }

    /// Wrap the content in a dark panel with a neon gradient border.
    func djPanel(cornerRadius: CGFloat = 14, lineWidth: CGFloat = 1.5) -> some View {
        let radius = DJTheme.cornerRadius(cornerRadius)
        return background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DJTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(DJTheme.neonGradient, lineWidth: lineWidth))
    }

    /// Add just the neon gradient border (no fill).
    func djNeonBorder(cornerRadius: CGFloat = 14, lineWidth: CGFloat = 1.5) -> some View {
        overlay(RoundedRectangle(cornerRadius: DJTheme.cornerRadius(cornerRadius), style: .continuous)
            .strokeBorder(DJTheme.neonGradient, lineWidth: lineWidth))
    }

    /// Make a `List` blend into the neon background: transparent scroll area and
    /// subtle neon row separators. (Apply to the List itself.)
    func djListChrome() -> some View {
        scrollContentBackground(.hidden)
            .listRowSeparatorTint(DJTheme.neonViolet.opacity(0.45))
    }

    /// Wrap a section of UI as a translucent dark "jukebox panel": padded, a neon
    /// gradient border, and a soft magenta glow. The fill is semi-transparent so
    /// the screen gradient shows through.
    func djCard(cornerRadius: CGFloat = 16, lineWidth: CGFloat = 1.5, padding: CGFloat = 10) -> some View {
        let radius = DJTheme.cornerRadius(cornerRadius)
        return self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DJTheme.panel.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DJTheme.neonGradient, lineWidth: lineWidth))
            .shadow(color: DJTheme.neonMagenta.opacity(0.18), radius: 8)
    }

    /// Neon-bordered text-field chrome. Use with `.textFieldStyle(.plain)`.
    func djField(cornerRadius: CGFloat = 10) -> some View {
        let radius = DJTheme.cornerRadius(cornerRadius)
        return padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DJTheme.panel.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DJTheme.neonViolet.opacity(0.8), lineWidth: 1))
            .foregroundStyle(DJTheme.textPrimary)
            .tint(DJTheme.neonCyan)
    }
}

/// A thin horizontal neon rule for separating stacked sections of the UI.
public struct DJNeonDivider: View {
    private let height: CGFloat
    public init(height: CGFloat = 2) { self.height = height }
    public var body: some View {
        DJTheme.neonGradientHorizontal
            .frame(height: height)
            .shadow(color: DJTheme.neonMagenta.opacity(0.6), radius: 3)
    }
}

/// A thin vertical neon rule for separating side-by-side columns.
public struct DJNeonVDivider: View {
    private let width: CGFloat
    public init(width: CGFloat = 2) { self.width = width }
    public var body: some View {
        DJTheme.neonGradientVertical
            .frame(width: width)
            .shadow(color: DJTheme.neonMagenta.opacity(0.6), radius: 3)
    }
}

/// Branding bar for the top of the iPad and macOS windows: the app-icon badge
/// beside a neon "DJukebox" wordmark.
public struct DJHeaderBar: View {
    private let title: String
    public init(title: String = "DJukebox") { self.title = title }
    public var body: some View {
        HStack(spacing: 12) {
            DJIconBadge(size: 34)
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(DJTheme.neonGradientHorizontal)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// The app-icon artwork as a small rounded badge with a neon border — used in the
/// upper-left corner of the iPad and macOS windows. Loads the app's "SplashIcon"
/// asset from the main bundle (present in both app targets).
public struct DJIconBadge: View {
    private let size: CGFloat
    public init(size: CGFloat = 40) { self.size = size }
    public var body: some View {
        let radius = DJTheme.cornerRadius(size * 0.22)
        return Image("SplashIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DJTheme.neonGradient, lineWidth: 1))
            .shadow(color: DJTheme.neonMagenta.opacity(0.5), radius: 5)
    }
}

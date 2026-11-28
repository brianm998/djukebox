// The single source of truth for the DJukebox version. The server and (through
// scripts/version.sh) the app builds both read it, so bump it here and nowhere
// else, except the Xcode MARKETING_VERSION settings that CI checks against it.
public enum DJukeboxVersion {
    // scripts/version.sh parses this line: keep it a plain "X.Y.Z" literal.
    public static let current = "0.1.0"

    // the name the server announces, both over Bonjour and from GET /version
    public static let serverName = "DJukebox"
}

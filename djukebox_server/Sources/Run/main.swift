import App
import Vapor
#if canImport(Darwin)
@preconcurrency import Darwin
#else
@preconcurrency import Glibc
#endif

// line-buffer stdout so logs reach a redirected file promptly
setLineBuffered()

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = try await Application.make(env)
do {
    try configure(app)
    try await app.execute()
} catch {
    app.logger.report(error: error)
    try? await app.asyncShutdown()
    // exit with a status rather than rethrow, which traps and leaves a crash report
    exit(1)
}
try await app.asyncShutdown()

func setLineBuffered() {
    setvbuf(stdout, nil, _IOLBF, 0)
}

import Vapor
import DJukeboxCommon

class AuthController {
    let config: Config
    let trackFinder: TrackFinderType
    
    init(config: Config, trackFinder: TrackFinderType) {
        self.config = config
        self.trackFinder = trackFinder
    }

    // curl -H "Authorization: 0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425" http://localhost:8080/rand
    func headerAuth<T>(request req: Request, closure: () throws -> T) throws -> T {
        for header in req.headers {
            if header.name == "Authorization" {
                if SHA512.hash(data: Data(config.Password.utf8)).hexEncodedString() == header.value {
                    return try closure()
                }
            }
        }
        throw Abort(.unauthorized)
    }

    func pathAuth<T>(request req: Request, closure: () throws -> T) throws -> T {
        if let auth = req.parameters.get("auth") {
            if SHA512.hash(data: Data(config.Password.utf8)).hexEncodedString() == auth {
                return try closure()
            }
        }
        throw Abort(.unauthorized)
    }

    func trackFromPath<T>(from req: Request, // XXX reame this
                          closure: (AudioTrack, String) throws -> T) throws -> T
    {
        return try self.pathAuth(request: req) {
            if let hash = req.parameters.get("sha1"),
               let (track, path) = trackFinder.track(forHash: hash),
               let audioTrack = track as? AudioTrack
            {
                return try closure(audioTrack, path.path)
            } else {
                throw Abort(.notFound)
            }
        }
    }

    func track<T>(from req: Request,
                  closure: (AudioTrack, String) throws -> T) throws -> T
    {
        return try self.headerAuth(request: req) {
            if let hash = req.parameters.get("sha1"),
               let (track, path) = trackFinder.track(forHash: hash),
               let audioTrack = track as? AudioTrack
            {
                return try closure(audioTrack, path.path)
            } else {
                throw Abort(.notFound)
            }
        }
    }
}


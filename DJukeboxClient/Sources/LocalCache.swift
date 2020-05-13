import Foundation
import DJukeboxCommon

// abstract super class for stuff that needs to be saved in local flash
public class LocalCache {
    
    internal static var libDir: URL? {
        if let libraryPathURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return libraryPathURL
        }
        return nil
    }

    //Creating a folder 
    internal static func urlForLibrary(appending: [String]) -> URL? {

        if let libDir = self.libDir {

            var path: URL = libDir

            for subdir in appending {
                path = path.appendingPathComponent(subdir)
            }
            
            if !FileManager.default.fileExists(atPath: path.path) {
                do {
                    try FileManager.default.createDirectory(at: path,
                                                            withIntermediateDirectories: true,
                                                            attributes: nil)
                    
                } catch let err {
                    Log.e(err.localizedDescription)
                }
            }

            return path
        }
        return nil
    }
}


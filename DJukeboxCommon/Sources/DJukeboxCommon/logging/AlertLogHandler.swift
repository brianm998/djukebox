import Foundation

#if !os(macOS)
import UIKit
public extension UIViewController {
    // nonisolated: a plain Sendable DispatchQueue used purely for scheduling/gating
    // alert presentation, not for touching UIKit itself.
    nonisolated static let alertDispatchQueue = DispatchQueue(label: "alerts")

    @discardableResult
    func show(alert: UIAlertController,
              animated: Bool = true,
              tryNumber: Int = 0,
              maxTries: Int = 10,
              completion: (() -> Void)? = nil) -> Bool
    {
        guard tryNumber < maxTries else { return false }

        if let _ = self.presentedViewController {
            UIViewController.alertDispatchQueue.asyncAfter(deadline: .now() + 0.5) {
                UIViewController.alertDispatchQueue.suspend()
                Task { @MainActor in
                    if !self.show(alert: alert, //on: selfviewController,
                                  animated: animated, tryNumber: tryNumber + 1)
                    {
                        UIViewController.alertDispatchQueue.resume()
                    }
                }
            }
            return false
        } else {
            if Thread.isMainThread {
                self.present(alert, animated: animated, completion: completion)
            } else {
                DispatchQueue.main.async {
                    self.present(alert, animated: animated, completion: completion)
                }
            }
            return true
        }
    }
}

// @unchecked: the non-Sendable DateFormatter is only ever touched inside the
// serial alert `dispatchQueue`, so the class synchronizes its own state.
public final class AlertLogHandler: LogHandler, @unchecked Sendable {

    public var dispatchQueue: DispatchQueue { return UIViewController.alertDispatchQueue }
    public let level: Log.Level?
    private let dateFormatter = DateFormatter()

    public init(at level: Log.Level) {
        self.level = level
        dateFormatter.dateFormat = "H:mm:ss.SSSS"
    }
    
    public func log(message: String,
                    at fileLocation: String,
                    with data: LogData?,
                    at logLevel: Log.Level)
    {
        dispatchQueue.async {
            let dateString = self.dateFormatter.string(from: Date())

            var logString = "" 
            if let data = data {
                logString = "\(dateString)\n\(fileLocation)\n\(message)\n\(data.description)"
            } else {
                logString = "\(dateString)\n\(fileLocation)\n\(message)"
            }

            let threeEmos = logLevel.emo + logLevel.emo + logLevel.emo
            let alertTitle = "\(threeEmos)  \(logLevel)  \(threeEmos)"

            // Building/showing the alert touches UIKit, which is main-actor-isolated;
            // hop over from this background dispatchQueue closure to do it.
            Task { @MainActor in
                let alert = UIAlertController(title: alertTitle,
                                              message: logString,
                                              preferredStyle: .alert)
                let okAction = UIAlertAction(title: "Ok", style: .cancel) { action in
                    // un-pause the dispatch queue
                    self.dispatchQueue.resume()
                }
                alert.addAction(okAction)
                // pause the alert dispatch queue
                self.dispatchQueue.suspend()

                if let vc = UIApplication.shared.keyWindow?.rootViewController {
                    // we have a view controller to show it on
                    if !vc.show(alert: alert) {
                        // if now alert was shown, resume the dispatch queue
                        self.dispatchQueue.resume()
                    }
                } else {
                    // can't show it now, try again in two seconds
                    self.dispatchQueue.asyncAfter(deadline: .now() + 2.0) {
                        self.log(message: message, at: fileLocation, with: data, at: logLevel)
                    }
                    self.dispatchQueue.resume()
                }
            }
        }
    }
}

#endif

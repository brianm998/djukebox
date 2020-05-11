#if !os(macOS)
import UIKit

private let maxNumberOfTasks = 100

public class BackgroundTask {
    let name: String
    var id: UIBackgroundTaskIdentifier

    init(name: String, id: UIBackgroundTaskIdentifier) {
        self.name = name
        self.id = id
    }
    
    public func end() {
        if id != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(id)
            BackgroundTask.markDone(task: self)
            id = UIBackgroundTaskIdentifier.invalid
        }
    }

    public static func start(named name: String, closure: (()-> Void)? = nil) -> BackgroundTask? {
        if activeTasks.count > maxNumberOfTasks  {
            let removedTask = activeTasks.removeFirst()
            removedTask.end()
            markDone(task: removedTask)
        }
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask(withName: name) {
            closure?()
            if id != UIBackgroundTaskIdentifier.invalid {
                BackgroundTask.markDone(id: id)
                UIApplication.shared.endBackgroundTask(id)
            }
        }
        if id == UIBackgroundTaskIdentifier.invalid {
            // we weren't given a task by iOS 
            return nil
        } else {
            let task = BackgroundTask(name: name, id: id)
            activeTasks.append(task)
            return task
        }
    }
 
    public static var activeTasks: [BackgroundTask] = []

    public static func markDone(id: UIBackgroundTaskIdentifier) {
        activeTasks = activeTasks.filter() { $0.id != id }
    }
    
    public static func markDone(task: BackgroundTask) {
        activeTasks = activeTasks.filter() { $0.id != task.id }
    }
}

#endif

import Foundation

let service = HelperService()
let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.machServiceName)
listener.delegate = service
listener.resume()

RunLoop.main.run()

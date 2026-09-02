import AppKit

@main
struct PestyMain {
    static func main() {
        let app = NSApplication.shared
        AppController.claimSingleInstance()
        let delegate = AppController.shared
        app.delegate = delegate
        app.run()
    }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Bridge for Dart-side checks of iOS-only platform state. Currently
    // exposes:
    //   - "backgroundRefreshStatus" → Int (UIBackgroundRefreshStatus.rawValue)
    //       0 = restricted (parental controls / MDM)
    //       1 = denied (user toggled off)
    //       2 = available
    // The Dart side (`AppLifecycleService.backgroundRefreshAllowed`) reads
    // this before scheduling background-driven notifications so users who
    // disabled the OS toggle aren't pinged via locally-scheduled paths.
    // The pluginRegistry creates a registrar on demand for any plugin
    // name, so requesting "havenkeep_lifecycle" gives us a real messenger
    // to attach the channel to. Modern Flutter dropped the
    // `engineBridge.binaryMessenger` shortcut in favour of going through
    // the per-plugin registrar.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "havenkeep_lifecycle")!
    let lifecycleChannel = FlutterMethodChannel(
      name: "havenkeep/lifecycle",
      binaryMessenger: registrar.messenger()
    )
    lifecycleChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "backgroundRefreshStatus":
        result(UIApplication.shared.backgroundRefreshStatus.rawValue)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

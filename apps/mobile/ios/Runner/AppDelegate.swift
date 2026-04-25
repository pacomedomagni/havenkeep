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
    let lifecycleChannel = FlutterMethodChannel(
      name: "havenkeep/lifecycle",
      binaryMessenger: engineBridge.pluginRegistry.registrar(forPlugin: "havenkeep_lifecycle")?.messenger() ?? engineBridge.binaryMessenger
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

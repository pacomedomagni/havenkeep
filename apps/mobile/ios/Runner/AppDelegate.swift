import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // S-HI-06: blur overlay shown during applicationWillResignActive so the
  // iOS app-switcher / recents thumbnail doesn't capture sensitive screen
  // contents (item names, addresses, gift codes, receipts). Removed when
  // the app returns to the foreground. Equivalent to FLAG_SECURE on Android.
  private var privacyBlurView: UIVisualEffectView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    if let window = self.window, privacyBlurView == nil {
      let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
      blur.frame = window.bounds
      blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      blur.tag = 999
      window.addSubview(blur)
      privacyBlurView = blur
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    privacyBlurView?.removeFromSuperview()
    privacyBlurView = nil
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

package app.havenkeep.mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/**
 * S-HI-06: every screen in HavenKeep carries some PII (item names,
 * addresses, serial numbers, gift codes, receipts). FLAG_SECURE prevents
 * the OS from including the screen contents in:
 *   - automatic system screenshots (recents thumbnail / app switcher)
 *   - manual screenshots and screen recordings (user-triggered)
 *   - mirroring to external displays / Chromecast
 *
 * Apple's iOS equivalent is implemented at the scene-lifecycle level
 * (overlay a blur view in `applicationWillResignActive`) — see the
 * iOS counterpart in the AppDelegate / SceneDelegate.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}

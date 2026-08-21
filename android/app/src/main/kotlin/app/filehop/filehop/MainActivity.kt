package app.filehop.filehop

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nativePlugin: FileHopNativePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativePlugin = FileHopNativePlugin.registerWith(flutterEngine, this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nativePlugin?.detach()
        nativePlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

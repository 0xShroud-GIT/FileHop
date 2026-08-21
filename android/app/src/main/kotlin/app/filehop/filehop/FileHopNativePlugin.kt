package app.filehop.filehop

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native command/event boundary.
 * Mission 07 adds LAN NSD browse only. No Wi-Fi Direct/Aware, no Mission 10 sockets.
 * Native adapters never own PeerIdentity/trust policy.
 *
 * Threading invariant (D-07-16): Flutter platform-channel method calls
 * arrive on the Android main thread, which is exactly the serialized
 * state authority owned by FileHopLanDiscovery. `startBrowse()` /
 * `stopBrowse()` verify that invariant explicitly.
 */
class FileHopNativePlugin(
    context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val identityStore = FileHopIdentitySecretStore(context)
    private val lanDiscovery =
        FileHopLanDiscovery(context) { payload -> emitEvent(payload) }
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        const val BRIDGE_VERSION = 1
        const val COMMANDS = "app.filehop.native.commands"
        const val EVENTS = "app.filehop.native.events"

        /**
         * Engine detach is one-way, but NSD stop confirmation is asynchronous.
         * Keep a bounded retry window so an onStopDiscoveryFailed callback can
         * transition the discovery owner to UNCERTAIN and a later main-thread
         * retry can request the authoritative stop again.
         */
        private const val DETACH_STOP_RETRY_COUNT = 12
        private const val DETACH_STOP_RETRY_INTERVAL_MS = 500L

        fun registerWith(engine: FlutterEngine, context: Context): FileHopNativePlugin {
            val plugin = FileHopNativePlugin(context.applicationContext)
            MethodChannel(engine.dartExecutor.binaryMessenger, COMMANDS)
                .setMethodCallHandler(plugin)
            EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
                .setStreamHandler(plugin)
            return plugin
        }
    }

    private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments
        if (args != null && args !is Map<*, *>) {
            result.error("invalidArgument", "payload must be a map", null)
            return
        }
        val map = (args as? Map<*, *>) ?: emptyMap<Any, Any>()
        val version = map["bridgeVersion"]
        if (version != null && version != BRIDGE_VERSION) {
            result.error(
                "invalidArgument",
                "incompatible bridgeVersion $version",
                null,
            )
            return
        }

        when (call.method) {
            "ping" ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "ok" to true,
                    ),
                )
            "observeAvailability" -> {
                val kind = map["kind"] as? String ?: "unknown"
                if (kind == "lan") {
                    result.success(lanDiscovery.availability())
                } else {
                    result.success(
                        mapOf(
                            "bridgeVersion" to BRIDGE_VERSION,
                            "kind" to kind,
                            "status" to "UNSUPPORTED",
                            "detail" to "Mission 02 skeleton: transport not implemented",
                        ),
                    )
                }
            }
            "startDiscovery" -> {
                val kind = map["kind"] as? String ?: "unknown"
                if (kind != "lan") {
                    result.error(
                        "unsupported",
                        "Mission 02 skeleton: startDiscovery is not implemented",
                        null,
                    )
                    return
                }
                val failure = lanDiscovery.startBrowse()
                if (failure != null) {
                    result.error("nativeFailure", failure, null)
                } else {
                    result.success(
                        mapOf(
                            "bridgeVersion" to BRIDGE_VERSION,
                            "ok" to true,
                        ),
                    )
                }
            }
            "stopDiscovery" -> {
                val kind = map["kind"] as? String ?: "unknown"
                if (kind != "lan") {
                    result.error(
                        "unsupported",
                        "Mission 02 skeleton: stopDiscovery is not implemented",
                        null,
                    )
                    return
                }
                lanDiscovery.stopBrowse()
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "ok" to true,
                    ),
                )
            }
            "connect",
            "disconnect",
            "openEndpoint",
            ->
                result.error(
                    "unsupported",
                    "Mission 10 owns LAN connect/openEndpoint; ${call.method} is not implemented",
                    null,
                )
            "identitySecret.store" -> handleIdentityStore(map, result)
            "identitySecret.load" -> handleIdentityLoad(map, result)
            "identitySecret.delete" -> handleIdentityDelete(map, result)
            "identitySecret.status" -> handleIdentityStatus(map, result)
            "identitySecret.hasAny" -> handleIdentityHasAny(result)
            "identitySecret.deleteAll" -> handleIdentityDeleteAll(result)
            else -> result.notImplemented()
        }
    }

    private fun handleIdentityStore(map: Map<*, *>, result: MethodChannel.Result) {
        val bytes = asByteArray(map["privateKeyBytes"])
        if (bytes == null) {
            result.error("invalidArgument", "privateKeyBytes must be exactly 32 bytes", null)
            return
        }
        when (val outcome = identityStore.store(bytes)) {
            is FileHopIdentitySecretStore.Failure ->
                result.error(outcome.code, outcome.message, null)
            is String ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "reference" to outcome,
                    ),
                )
            else -> result.error("nativeFailure", "failed to protect identity secret", null)
        }
    }

    private fun handleIdentityLoad(map: Map<*, *>, result: MethodChannel.Result) {
        val reference = map["reference"] as? String
        if (reference.isNullOrEmpty()) {
            result.error("invalidArgument", "reference must be a non-empty string", null)
            return
        }
        when (val outcome = identityStore.load(reference)) {
            is FileHopIdentitySecretStore.Failure ->
                result.error(outcome.code, outcome.message, null)
            is ByteArray ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "privateKeyBytes" to outcome,
                    ),
                )
            else -> result.error("nativeFailure", "failed to load identity secret", null)
        }
    }

    private fun handleIdentityDelete(map: Map<*, *>, result: MethodChannel.Result) {
        val reference = map["reference"] as? String
        if (reference.isNullOrEmpty()) {
            result.error("invalidArgument", "reference must be a non-empty string", null)
            return
        }
        when (val outcome = identityStore.delete(reference)) {
            is FileHopIdentitySecretStore.Failure ->
                result.error(outcome.code, outcome.message, null)
            else ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "ok" to true,
                    ),
                )
        }
    }

    private fun handleIdentityStatus(map: Map<*, *>, result: MethodChannel.Result) {
        val reference = map["reference"] as? String
        if (reference.isNullOrEmpty()) {
            result.error("invalidArgument", "reference must be a non-empty string", null)
            return
        }
        when (val outcome = identityStore.status(reference)) {
            is FileHopIdentitySecretStore.Failure ->
                result.error(outcome.code, outcome.message, null)
            is String ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "status" to outcome,
                    ),
                )
            else -> result.error("nativeFailure", "failed to query identity secret", null)
        }
    }

    private fun handleIdentityHasAny(result: MethodChannel.Result) {
        when (val outcome = identityStore.hasAny()) {
            is FileHopIdentitySecretStore.Failure ->
                result.error(outcome.code, outcome.message, null)
            is Boolean ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "any" to outcome,
                    ),
                )
            else -> result.error("nativeFailure", "failed to query identity secrets", null)
        }
    }

    private fun handleIdentityDeleteAll(result: MethodChannel.Result) {
        when (val outcome = identityStore.deleteAll()) {
            is FileHopIdentitySecretStore.Failure ->
                result.error(outcome.code, outcome.message, null)
            else ->
                result.success(
                    mapOf(
                        "bridgeVersion" to BRIDGE_VERSION,
                        "ok" to true,
                    ),
                )
        }
    }

    private fun asByteArray(value: Any?): ByteArray? {
        return when (value) {
            is ByteArray -> value
            is List<*> -> {
                if (value.size != FileHopIdentitySecretStore.PRIVATE_KEY_LEN) {
                    return null
                }
                val out = ByteArray(value.size)
                for (index in value.indices) {
                    val number = value[index] as? Number ?: return null
                    out[index] = number.toByte()
                }
                out
            }
            else -> null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    fun detach() {
        // First stop is immediate. Follow-up calls are harmless while STOPPING
        // or STOPPED and become meaningful only if NSD reports an asynchronous
        // stop failure and FileHopLanDiscovery moves to UNCERTAIN.
        lanDiscovery.detach()
        for (attempt in 1..DETACH_STOP_RETRY_COUNT) {
            mainHandler.postDelayed(
                { lanDiscovery.detach() },
                attempt * DETACH_STOP_RETRY_INTERVAL_MS,
            )
        }
        eventSink = null
    }
}

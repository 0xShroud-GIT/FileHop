package app.filehop.filehop

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import java.net.InetAddress
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.LinkedHashMap
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Browse lifecycle for the Android NSD discovery adapter.
 *
 * `stopServiceDiscovery()` returning normally is NOT stop confirmation:
 * NSD stop completion arrives asynchronously through `onDiscoveryStopped`
 * (or fails through `onStopDiscoveryFailed`). A new browse may start only
 * from STOPPED; it is blocked while STOPPING and while UNCERTAIN, and a
 * retry stop that returns normally still does not clear UNCERTAIN.
 */
enum class BrowseLifecycle {
    STOPPED,
    STARTING,
    BROWSING,
    STOPPING,
    UNCERTAIN,
}

/**
 * Multicast-lock prerequisite result for legacy platforms without the
 * mainline mDNS backend. Discovery may start only on NOT_REQUIRED or
 * ACQUIRED; FAILED is fail-closed and discoverServices is never called.
 */
enum class MulticastPreparation {
    NOT_REQUIRED,
    ACQUIRED,
    FAILED,
}

/**
 * Ownership outcome of a native NSD path registration (mirrors the shared
 * Dart `LanPathOutcome` reference model, D-07-10).
 */
enum class PathOutcome {
    FIRST_OWNER,
    ADDITIONAL_OWNER,
    DUPLICATE_PATH,
    PATH_LIMIT_REACHED,
}

/**
 * Registration-level path binding outcome (D-07-15): each native path is
 * independently bound to the FileHop discovery instance ID advertised on
 * that path.
 */
enum class PathBindOutcome {
    NEW_INSTANCE,
    EXISTING_INSTANCE,
    DUPLICATE_BINDING,
    PATH_LIMIT_REACHED,
}

/**
 * Pathless (no-argument) service-loss outcome for a registration (D-07-15).
 * The modern `ServiceInfoCallback.onServiceLost()` does not identify which
 * network path disappeared, so FileHop fails closed instead of guessing.
 */
enum class PathlessLossOutcome {
    STALE,
    REMOVED_ONE,
    AMBIGUOUS,
}

/**
 * Thin Android LAN browse adapter. Mission 07 discovery only.
 * Does not own the Mission 10 control/data listener.
 * NsdServiceInfo never leaves this class.
 *
 * Lifecycle (final native-lifecycle fix):
 * - STOPPED -> start -> STARTING -> onDiscoveryStarted -> BROWSING
 * - STARTING -> onStartDiscoveryFailed -> STOPPED (full cleanup)
 * - BROWSING -> stop request -> STOPPING -> onDiscoveryStopped -> STOPPED
 * - STOPPING -> onStopDiscoveryFailed -> UNCERTAIN (fail closed)
 * - UNCERTAIN -> retry stop (still asynchronous) -> STOPPING / UNCERTAIN
 * - startBrowse() is rejected while STOPPING or UNCERTAIN, so two native
 *   browse generations can never overlap by FileHop policy.
 *
 * Single serialized state authority (D-07-16): ALL mutable LAN discovery
 * state (lifecycle, tracked registrations, pathOwners bindings,
 * instanceToKeys global owners, listener bookkeeping, multicast ownership
 * metadata) is mutated ONLY on the main looper, entered via
 * [dispatchState]. Every native callback (DiscoveryListener,
 * ResolveListener, ServiceInfoCallback) dispatches to that queue FIRST;
 * generation checks happen AFTER dispatch, so a stale callback queued
 * while generation N was valid is dropped at execution time when the
 * current generation has moved on. Public entry points (startBrowse,
 * stopBrowse, detach) are invoked by the bridge on the main thread and
 * verify that invariant explicitly. No blocking waits and no giant
 * synchronized locks across framework calls.
 *
 * Stale FAILURE-callback guards (D-07-17): every asynchronous callback
 * that can mutate state or emit a shared error validates ownership FIRST,
 * INSIDE the dispatched state block (guard-before-mutation ordering):
 * - A (guarded mutation): onDiscoveryStarted, onDiscoveryStopped,
 *   onStartDiscoveryFailed, onStopDiscoveryFailed (generation + listener
 *   generation + listener identity guards), onServiceFound/onServiceLost
 *   (live(gen) inside handlers), onServiceResolved (publishResolved
 *   live(gen) check), onServiceInfoCallbackRegistrationFailed
 *   (live(gen) + entry generation + tracked identity + callback ownership
 *   before any legacy fallback).
 * - B (current-only effects): the guarded set above; legitimate
 *   current-generation failures keep their frozen behavior.
 * - C (notification-only): onResolveFailed, onServiceInfoCallbackUnregistered.
 * A stale failure callback therefore produces ZERO state mutation, ZERO
 * cleanup of the current generation, ZERO stale error emission, and ZERO
 * launched native work.
 *
 * Same-generation entry identity (D-07-18): generation validity is
 * necessary but NOT sufficient. An asynchronous callback carrying a
 * `Tracked entry` must prove BOTH generation ownership AND current object
 * identity (`tracked[entry.registrationKey] === entry`) before it may
 * mutate FileHop state — a registration removed or replaced under the
 * same key in the SAME browse generation is a different native lifecycle,
 * and its stale callbacks are dropped (no path binding, no global owner,
 * no candidate event, no loss duplication).
 *
 * Multicast rule (frozen, D-07-06 + final fix): a manual
 * `WifiManager.MulticastLock` is required only while browsing on platforms
 * WITHOUT the modern mainline mDNS backend. Acquisition failure is
 * fail-closed: startBrowse fails, `discoverServices` is never called.
 * The lock is released on confirmed stop and on start failure, never on a
 * merely requested stop.
 *
 * Tracking identity: entries are keyed by a platform-local correlation key
 * (network handle + NSD service name), never by the human-visible service
 * name alone. After valid TXT parsing the authoritative shared candidate
 * identity is the FileHop ephemeral instance ID.
 *
 * One-to-many native path ownership (D-07-10) + path→instance bindings
 * (D-07-15): one instance ID may be visible through multiple simultaneous
 * native paths/interfaces, and ONE NSD registration may bind several
 * native paths — each INDEPENDENTLY to the FileHop instance advertised on
 * that path (`Tracked.pathOwners` is a Map<NativePathKey, InstanceId>; a
 * path update never migrates unrelated paths). `instanceToKeys` maps an
 * instance ID to the SET of owning path keys; `candidateLost` is emitted
 * only when the FINAL owner disappears. Cleanup and loss operate on the
 * actual bindings (never the stale registration seed key); duplicate path
 * callbacks are idempotent; the per-instance and per-registration path
 * bound is `MAX_NATIVE_PATHS_PER_INSTANCE` with deterministic bounded
 * drops.
 *
 * API gating (frozen rule, D-07-06): the modern NSD path
 * (`registerServiceInfoCallback`, `getHostAddresses`) is used when
 * `SDK_INT >= 34` OR (`SDK_INT == 33` AND T extension version >= 7),
 * because those APIs shipped in API 34 and were backported through the
 * Android T (Tiramisu) Tethering-module extension release 7.
 */
class FileHopLanDiscovery(
    context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        const val SERVICE_TYPE = "_filehop._tcp"
        const val SCHEMA_VERSION = 1
        const val MAX_TXT_KEYS = 8
        const val MAX_TXT_KEY_BYTES = 32
        const val MAX_TXT_VALUE_BYTES = 128
        const val MAX_TXT_PAYLOAD = 512
        const val MAX_ADDRESSES = 8
        const val MAX_ACTIVE = 128
        const val INSTANCE_HEX_LEN = 32

        /** D-07-10 bound: maximum simultaneous native paths per LAN instance. */
        const val MAX_NATIVE_PATHS_PER_INSTANCE = 8
        private val INSTANCE_RE = Regex("^[0-9a-f]{32}$")

        /** API level that ships the modern NSD service-info APIs. */
        private const val API_MODERN_NSD = 34

        /** Android T (33) SDK extension that backports the modern NSD APIs. */
        private const val T_EXTENSION_MODERN_NSD = 7

        /**
         * True when `registerServiceInfoCallback` / `getHostAddresses` and the
         * mainline mDNS backend are present: API 34+, or API 33 with
         * Tiramisu extension >= 7. Never keyed on SDK_INT alone.
         */
        fun modernNsdAvailable(): Boolean {
            if (Build.VERSION.SDK_INT >= API_MODERN_NSD) return true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                return try {
                    SdkExtensions.getExtensionVersion(Build.VERSION_CODES.TIRAMISU) >=
                        T_EXTENSION_MODERN_NSD
                } catch (_: RuntimeException) {
                    false
                }
            }
            return false
        }
    }

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { runnable -> main.post(runnable) }

    /**
     * Enters the single serialized state authority (D-07-16). Runs the
     * block inline when already on the state thread; otherwise posts it.
     * No blocking waits, no latches, no recursive double-post: blocks
     * posted from the state thread would simply run on a later queue pass,
     * but callers only post from native callback threads.
     */
    private fun dispatchState(block: () -> Unit) {
        if (Looper.myLooper() == main.looper) {
            block()
        } else {
            main.post(block)
        }
    }

    /** Hard invariant: public state-mutating entry points run on the state thread. */
    private fun checkStateThread() {
        check(Looper.myLooper() == main.looper) {
            "FileHop LAN discovery state must be mutated on the serialized state thread"
        }
    }
    private val nsd: NsdManager? =
        appContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val wifi: WifiManager? =
        appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val modernNsd = modernNsdAvailable()

    /**
     * Native ownership state machine. Mutated ONLY on the serialized state
     * authority (D-07-16); @Volatile so availability() reads a coherent
     * snapshot without blocking.
     */
    @Volatile
    private var lifecycle = BrowseLifecycle.STOPPED

    /** Logical browse active: candidate events are accepted. */
    private val browsing = AtomicBoolean(false)

    private val generation = AtomicInteger(0)
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var discoveryListenerGen = 0

    /** Listener whose stop failed; session state is uncertain until cleared. */
    private var uncertainStopListener: NsdManager.DiscoveryListener? = null

    private var multicastLock: WifiManager.MulticastLock? = null
    private var multicastLockGen = 0

    /**
     * Keyed by registration seed key, never by bare service name.
     * Owned exclusively by the serialized state authority (D-07-16).
     */
    private val tracked = LinkedHashMap<String, Tracked>()

    /**
     * FileHop instance ID -> SET of owning native path keys (one-to-many,
     * D-07-10). Owned exclusively by the serialized state authority
     * (D-07-16); never mutated from native callback threads.
     */
    private val instanceToKeys = HashMap<String, MutableSet<String>>()

    data class Tracked(
        val registrationKey: String,
        val serviceName: String,
        var callback: Any? = null,
        var resolveListener: NsdManager.ResolveListener? = null,
        val generation: Int,
    ) {
        /**
         * D-07-15: each native path is INDEPENDENTLY bound to the FileHop
         * discovery instance ID advertised on that path. One registration
         * may therefore represent `{NetworkA → X, NetworkB → Y}`
         * simultaneously; a path update never migrates unrelated paths.
         *
         * The registration key is ONLY callback/registration correlation
         * and never substitutes for a bound path during cleanup: cleanup
         * iterates these bindings, never the seed.
         */
        val pathOwners: MutableMap<String, String> = LinkedHashMap()
    }

    /**
     * Temporary platform-local registration correlation (seed key) before
     * TXT resolution: attached network handle (API 33+) + NSD service name,
     * with `-` when the network is unknown. Used ONLY to correlate
     * found/lost callbacks and registration bookkeeping (D-07-15); real
     * resolved native paths live as keys of [Tracked.pathOwners]. The
     * visible service name is never identity. Two services
     * indistinguishable at every callback stage (same name, null networks)
     * are a recorded physical C limitation; FileHop never fabricates a
     * fake network identity to split them.
     */
    private fun trackKey(service: NsdServiceInfo): String? {
        val name = service.serviceName ?: return null
        val network =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                try {
                    service.network?.toString() ?: "-"
                } catch (_: RuntimeException) {
                    "-"
                }
            } else {
                "-"
            }
        return "$network|$name"
    }

    fun availability(): Map<String, Any?> {
        // Read-only snapshot for the bridge (invoked on the main thread).
        // lifecycle is @Volatile; the maps are only mutated on this same
        // serialized authority, so no blocking cross-thread wait exists.
        val status =
            when {
                nsd == null -> "UNSUPPORTED"
                lifecycle == BrowseLifecycle.UNCERTAIN ||
                    lifecycle == BrowseLifecycle.STOPPING -> "SUPPORTED_UNAVAILABLE"
                else -> "SUPPORTED_AVAILABLE"
            }
        val detail =
            when (lifecycle) {
                BrowseLifecycle.UNCERTAIN ->
                    "FileHop LAN NSD browse (Mission 07); previous stop failed, session uncertain"
                BrowseLifecycle.STOPPING ->
                    "FileHop LAN NSD browse (Mission 07); previous stop pending, restart blocked"
                else -> "FileHop LAN NSD browse (Mission 07)"
            }
        return mapOf(
            "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
            "kind" to "lan",
            "status" to status,
            "detail" to detail,
        )
    }

    fun startBrowse(): String? {
        checkStateThread()
        val manager = nsd ?: return "NSD is unavailable"
        when (lifecycle) {
            BrowseLifecycle.STOPPED -> Unit
            BrowseLifecycle.STARTING, BrowseLifecycle.BROWSING -> return null
            BrowseLifecycle.STOPPING ->
                return "previous LAN discovery stop is still pending"
            BrowseLifecycle.UNCERTAIN -> {
                // onStopDiscoveryFailed arrived; uncertainStopListener owns
                // the unresolved session. A retry stop stays asynchronous,
                // so a new browse remains blocked until onDiscoveryStopped
                // confirms cleanup.
                if (uncertainStopListener != null) {
                    return "previous LAN discovery session is still stopping"
                }
                return "previous LAN discovery session is still stopping"
            }
        }
        val gen = generation.incrementAndGet()
        val preparation = acquireMulticastLockIfRequired(gen)
        if (preparation == MulticastPreparation.FAILED) {
            // Fail closed: the required legacy multicast prerequisite is
            // missing, so NSD discovery must not start.
            emitError(
                "multicastLockFailed",
                "required multicast lock unavailable; NSD discovery not started",
                gen,
            )
            return "multicast lock required but unavailable"
        }
        val listener =
            object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(regType: String) {
                    // D-07-16/17: dispatch FIRST; guard ownership BEFORE any
                    // mutation on the serialized state authority.
                    dispatchState {
                        if (generation.get() != gen) return@dispatchState
                        if (discoveryListenerGen != gen) return@dispatchState
                        if (discoveryListener !== this) return@dispatchState
                        if (lifecycle == BrowseLifecycle.STARTING) {
                            lifecycle = BrowseLifecycle.BROWSING
                            browsing.set(true)
                        }
                    }
                }

                override fun onStartDiscoveryFailed(regType: String, errorCode: Int) {
                    dispatchState {
                        // D-07-17: guard FIRST — a stale start-failure from
                        // generation N must not disable generation N+1,
                        // clean its state, or emit a stale error.
                        if (generation.get() != gen) return@dispatchState
                        if (discoveryListenerGen != gen) return@dispatchState
                        if (discoveryListener !== this) return@dispatchState
                        // Full generation cleanup: listener state, tracking,
                        // multicast lock. Never only `browsing = false`.
                        browsing.set(false)
                        if (lifecycle == BrowseLifecycle.STARTING ||
                            lifecycle == BrowseLifecycle.STOPPING
                        ) {
                            lifecycle = BrowseLifecycle.STOPPED
                        }
                        cleanupBrowseGeneration(
                            gen,
                            emitLostForResolved = false,
                            releaseNativeOwnership = true,
                        )
                        emitError(
                            "discoveryStartFailed",
                            "NSD start failed (code $errorCode)",
                            gen,
                        )
                    }
                }

                override fun onDiscoveryStopped(serviceType: String) {
                    dispatchState {
                        // D-07-16/17: guard ownership BEFORE mutation.
                        if (generation.get() != gen) return@dispatchState
                        if (discoveryListenerGen != gen) return@dispatchState
                        if (discoveryListener !== this) return@dispatchState
                        if (uncertainStopListener === this) {
                            uncertainStopListener = null
                        }
                        // Authoritative stop confirmation: only this callback
                        // may release native ownership for the stopping
                        // generation.
                        if (lifecycle == BrowseLifecycle.STOPPING) {
                            lifecycle = BrowseLifecycle.STOPPED
                            cleanupBrowseGeneration(
                                gen,
                                emitLostForResolved = false,
                                releaseNativeOwnership = true,
                            )
                        }
                    }
                }

                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                    dispatchState {
                        // D-07-17: guard FIRST — a stale stop-failure must
                        // not emit a stale error or push STOPPING/UNCERTAIN
                        // onto a newer generation.
                        if (generation.get() != gen) return@dispatchState
                        if (discoveryListenerGen != gen) return@dispatchState
                        if (discoveryListener !== this) return@dispatchState
                        // The underlying session may still be active. Fail
                        // closed: keep listener + multicast lock, block
                        // restarts, surface uncertainty via availability().
                        emitError("discoveryStopFailed", "NSD stop failed (code $errorCode)", gen)
                        if (lifecycle == BrowseLifecycle.STOPPING ||
                            lifecycle == BrowseLifecycle.BROWSING
                        ) {
                            lifecycle = BrowseLifecycle.UNCERTAIN
                            uncertainStopListener = this
                        }
                    }
                }

                override fun onServiceFound(service: NsdServiceInfo) {
                    dispatchState { handleFound(service, gen) }
                }

                override fun onServiceLost(service: NsdServiceInfo) {
                    dispatchState { handleLost(service, gen) }
                }
            }
        lifecycle = BrowseLifecycle.STARTING
        discoveryListener = listener
        discoveryListenerGen = gen
        return try {
            manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            null
        } catch (_: RuntimeException) {
            browsing.set(false)
            lifecycle = BrowseLifecycle.STOPPED
            cleanupBrowseGeneration(
                gen,
                emitLostForResolved = false,
                releaseNativeOwnership = true,
            )
            "NSD discoverServices failed"
        }
    }

    fun stopBrowse() {
        checkStateThread()
        val gen = generation.get()
        browsing.set(false)
        // Logical candidate visibility ends now; native ownership is
        // released only by the confirmed onDiscoveryStopped callback.
        cleanupBrowseGeneration(
            gen,
            emitLostForResolved = true,
            releaseNativeOwnership = false,
        )
        requestStopAfterCleanup()
    }

    fun detach() {
        stopBrowse()
    }

    /**
     * Requests the asynchronous NSD stop for the current lifecycle.
     * A normal return from stopServiceDiscovery is NOT stop confirmation;
     * onDiscoveryStopped remains the authoritative confirmed-stop callback.
     * Never issues competing stop requests while one is already pending.
     */
    private fun requestStopAfterCleanup() {
        val manager = nsd
        when (lifecycle) {
            BrowseLifecycle.STOPPED -> {
                // Idempotent stop success: nothing is owned.
            }
            BrowseLifecycle.STOPPING -> {
                // Idempotent pending stop: never a competing request.
            }
            BrowseLifecycle.UNCERTAIN -> {
                val listener = uncertainStopListener ?: discoveryListener ?: return
                lifecycle = BrowseLifecycle.STOPPING
                try {
                    manager?.stopServiceDiscovery(listener)
                } catch (_: RuntimeException) {
                    // Retry threw synchronously: uncertainty remains.
                    lifecycle = BrowseLifecycle.UNCERTAIN
                }
            }
            BrowseLifecycle.STARTING, BrowseLifecycle.BROWSING -> {
                val listener = discoveryListener ?: run {
                    lifecycle = BrowseLifecycle.UNCERTAIN
                    return
                }
                lifecycle = BrowseLifecycle.STOPPING
                try {
                    manager?.stopServiceDiscovery(listener)
                } catch (_: RuntimeException) {
                    lifecycle = BrowseLifecycle.UNCERTAIN
                    uncertainStopListener = listener
                }
            }
        }
    }

    /**
     * Central idempotent cleanup for browse generation [gen].
     * Candidate visibility (tracking maps, per-service callbacks) is always
     * released. Native ownership (discovery listener + multicast lock) is
     * released only when [releaseNativeOwnership] is true: after the
     * confirmed onDiscoveryStopped callback or after a start failure where
     * browsing never became active. Never touches resources owned by a
     * newer generation.
     */
    private fun cleanupBrowseGeneration(
        gen: Int,
        emitLostForResolved: Boolean,
        releaseNativeOwnership: Boolean,
    ) {
        if (releaseNativeOwnership) {
            if (discoveryListener != null && discoveryListenerGen <= gen) {
                discoveryListener = null
            }
            releaseMulticastLock(gen)
        }
        for (entry in tracked.values.toList()) {
            if (entry.generation > gen) continue
            tracked.remove(entry.registrationKey)
            unregisterTracking(nsd, entry)
            // D-07-15: cleanup removes EVERY path→instance binding of the
            // registration, never the stale seed registrationKey. The
            // final removal of an instance emits lost (when requested)
            // exactly once per instance.
            cleanupRegistration(entry, emitLostForResolved)
        }
    }

    private fun handleFound(service: NsdServiceInfo, gen: Int) {
        if (!live(gen)) return
        if (!serviceTypeMatches(service.serviceType)) return
        val key = trackKey(service) ?: return
        if (tracked.size >= MAX_ACTIVE && !tracked.containsKey(key)) {
            emitError("candidateLimitExceeded", "active LAN candidate limit exceeded", gen)
            return
        }
        val existing = tracked[key]
        if (existing != null && existing.generation == gen) {
            // Duplicate found callback: idempotent. On the modern path the
            // registered ServiceInfoCallback keeps delivering updates, so
            // re-registering would overwrite a live callback. The legacy
            // path re-resolves to refresh metadata.
            if (modernNsd && existing.callback != null) return
            resolve(service, existing, gen)
            return
        }
        val entry =
            Tracked(
                registrationKey = key,
                serviceName = service.serviceName ?: return,
                generation = gen,
            )
        tracked[key] = entry
        resolve(service, entry, gen)
    }

    /**
     * DiscoveryListener loss correlation (D-07-15/16). Runs on the
     * serialized state authority (dispatched by the callback).
     *
     * Correlation order:
     * 1. direct registration lookup by the seed/lookup key;
     * 2. if the lookup key is a CONCRETE resolved path key and the direct
     *    lookup missed (the registration may still be indexed under its
     *    seed), a bounded search over current-generation registrations
     *    that OWN that path in `pathOwners`;
     * 3. weak null-network loss: bounded name disambiguation.
     *
     * Zero matches → stale/unknown, ignore. More than one match →
     * `lossCorrelationAmbiguous`, remove NOTHING. Never choose
     * arbitrarily.
     */
    private fun handleLost(service: NsdServiceInfo, gen: Int) {
        if (!live(gen)) return
        val lookupKey = trackKey(service) ?: return
        val direct = tracked[lookupKey]
        if (direct != null) {
            handleCorrelatedLoss(direct, service, gen)
            return
        }
        if (!lookupKey.startsWith("-|")) {
            // D-07-16: a concrete resolved-path loss whose direct
            // registration lookup missed must not be dropped.
            correlateResolvedPathLoss(lookupKey, gen)
            return
        }
        // Weak null-network loss: bounded name disambiguation (D-07-12,
        // physical C limitation). Only exactly ONE same-name registration
        // of the generation may be correlated; otherwise fail safe.
        val name = service.serviceName ?: return
        val candidates =
            tracked.values.filter { it.generation == gen && it.serviceName == name }
        if (candidates.size != 1) {
            if (candidates.size > 1) {
                emitError(
                    "lossCorrelationAmbiguous",
                    "null-network loss callback matches multiple registrations",
                    gen,
                )
            }
            return
        }
        handleCorrelatedLoss(candidates.single(), service, gen)
    }

    /**
     * Bounded ownership-based correlation for a concrete resolved path
     * loss (D-07-16). Exactly one owning registration → remove only that
     * binding; zero → stale/unknown, ignore; more than one (defensive:
     * duplicate correlation) → `lossCorrelationAmbiguous`, remove none.
     */
    private fun correlateResolvedPathLoss(pathKey: String, gen: Int) {
        val candidates =
            tracked.values.filter { it.generation == gen && it.pathOwners.containsKey(pathKey) }
        when {
            candidates.size == 1 -> removeBinding(candidates.single(), pathKey)
            candidates.size > 1 ->
                emitError(
                    "lossCorrelationAmbiguous",
                    "concrete path loss matches multiple registrations; remove none",
                    gen,
                )
            else -> Unit // Unknown concrete path loss: stale, ignored.
        }
    }

    /**
     * Loss handling once the owning registration is correlated (D-07-15/16).
     *
     * The frozen compile SDK exposes `DiscoveryListener.onServiceLost(
     * NsdServiceInfo)`, whose NsdServiceInfo may carry the concrete
     * `android.net.Network` (API 33+): when it does, exactly the identified
     * native path is unbound (partial loss semantics — other bindings of
     * the registration stay). When the network is unavailable, the loss is
     * pathless-conservative: one binding → remove it; multiple bindings →
     * bounded `lossCorrelationAmbiguous` diagnostic and remove NOTHING.
     * Unknown paths are stale no-ops and never remove a different path.
     */
    private fun handleCorrelatedLoss(entry: Tracked, service: NsdServiceInfo, gen: Int) {
        val network = resolvedNetwork(service)
        if (network != null) {
            removeBinding(entry, "$network|${entry.serviceName}")
            return
        }
        when (entry.pathOwners.size) {
            0 -> removeEmptyRegistration(entry)
            1 -> removeBinding(entry, entry.pathOwners.keys.single())
            else -> emitError(
                "lossCorrelationAmbiguous",
                "null-network loss callback with multiple owned paths; remove none",
                gen,
            )
        }
    }

    /**
     * Removes exactly ONE path→instance binding (D-07-15/16). candidateLost
     * emits only when the instance loses its FINAL global owner; a partial
     * loss keeps the shared candidate alive. Unknown paths are stale
     * no-ops. An empty registration is then dropped from the bookkeeping.
     */
    private fun removeBinding(entry: Tracked, pathKey: String) {
        val instanceId = entry.pathOwners.remove(pathKey) ?: return
        if (removeOwner(instanceId, pathKey)) emitLost(instanceId)
        if (entry.pathOwners.isEmpty()) {
            removeEmptyRegistration(entry)
        }
    }

    /** Drops an empty registration's bookkeeping (state-thread only). */
    private fun removeEmptyRegistration(entry: Tracked) {
        tracked.remove(entry.registrationKey)
        unregisterTracking(nsd, entry)
    }

    /**
     * Pathless service-loss handling for the modern `ServiceInfoCallback`
     * (D-07-15). The no-argument `onServiceLost()` does not identify which
     * network path disappeared: zero bindings → stale no-op; exactly one
     * binding → remove that path (candidateLost only on final global
     * owner); more than one binding → bounded `lossCorrelationAmbiguous`
     * diagnostic, remove NONE, no candidateLost. This is distinct from
     * FileHop-owned lifecycle cleanup, which may deliberately remove the
     * whole registration.
     */
    private fun handlePathlessLoss(entry: Tracked, gen: Int): PathlessLossOutcome {
        if (!live(gen)) return PathlessLossOutcome.STALE
        if (entry.generation != gen) return PathlessLossOutcome.STALE
        // D-07-18: defensive identity guard — a detached/replaced entry may
        // not remove bindings or emit loss even while the generation is
        // still current.
        if (tracked[entry.registrationKey] !== entry) return PathlessLossOutcome.STALE
        if (entry.pathOwners.isEmpty()) return PathlessLossOutcome.STALE
        if (entry.pathOwners.size > 1) {
            emitError(
                "lossCorrelationAmbiguous",
                "pathless loss with multiple owned paths; remove none",
                gen,
            )
            return PathlessLossOutcome.AMBIGUOUS
        }
        val path = entry.pathOwners.keys.single()
        val instanceId = entry.pathOwners.remove(path) ?: return PathlessLossOutcome.STALE
        if (removeOwner(instanceId, path)) emitLost(instanceId)
        return PathlessLossOutcome.REMOVED_ONE
    }

    /**
     * Removes EVERY path→instance binding of [entry] from the global owner
     * index and clears the registration's bindings (D-07-15). Used only by
     * FileHop-owned lifecycle cleanup (stop / confirmed generation stop /
     * detach / terminal failure): candidateLost emits exactly once per
     * instance that loses its FINAL global owner when
     * [emitLostForResolved] is true. Never removes by the stale
     * registration seed key.
     */
    private fun cleanupRegistration(entry: Tracked, emitLostForResolved: Boolean) {
        for ((path, instanceId) in entry.pathOwners.toList()) {
            entry.pathOwners.remove(path)
            if (removeOwner(instanceId, path) && emitLostForResolved) {
                emitLost(instanceId)
            }
        }
    }

    /**
     * Registers [pathKey] as an owner of [instanceId] (one-to-many,
     * D-07-10). Duplicate callbacks are idempotent; a full per-instance
     * owner set deterministically drops the additional path.
     */
    private fun addOwner(instanceId: String, pathKey: String): PathOutcome {
        val existing = instanceToKeys[instanceId]
        if (existing != null) {
            if (existing.contains(pathKey)) return PathOutcome.DUPLICATE_PATH
            if (existing.size >= MAX_NATIVE_PATHS_PER_INSTANCE) {
                return PathOutcome.PATH_LIMIT_REACHED
            }
        }
        val set = existing ?: HashSet<String>().also { instanceToKeys[instanceId] = it }
        val wasEmpty = set.isEmpty()
        set.add(pathKey)
        return if (wasEmpty) PathOutcome.FIRST_OWNER else PathOutcome.ADDITIONAL_OWNER
    }

    /**
     * Removes [pathKey] from [instanceId]. Returns true only when the FINAL
     * owner was removed (the only case where candidateLost may emit).
     * Unknown/stale path removals return false and change nothing.
     */
    private fun removeOwner(instanceId: String, pathKey: String): Boolean {
        val set = instanceToKeys[instanceId] ?: return false
        if (!set.remove(pathKey)) return false
        if (set.isEmpty()) {
            instanceToKeys.remove(instanceId)
            return true
        }
        return false
    }

    private fun resolve(service: NsdServiceInfo, entry: Tracked, gen: Int) {
        val manager = nsd ?: return
        if (modernNsd) {
            registerModern(manager, service, entry, gen)
        } else {
            registerLegacy(manager, service, entry, gen)
        }
    }

    /**
     * Modern official path: `NsdManager.registerServiceInfoCallback`.
     * Available on API 34+ and API 33 with T extension >= 7 (D-07-06).
     */
    private fun registerModern(
        manager: NsdManager,
        service: NsdServiceInfo,
        entry: Tracked,
        gen: Int,
    ) {
        if (!modernNsd) return
        val callback =
            object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                    // D-07-17: guard FIRST, inside the serialized state
                    // authority — a stale registration failure from a
                    // disposed generation must start NO native work, mutate
                    // no map entry, and emit nothing. Only a CURRENT
                    // generation/entry/callback may fall back to legacy
                    // resolution.
                    dispatchState {
                        if (!live(gen)) return@dispatchState
                        if (entry.generation != gen) return@dispatchState
                        if (tracked[entry.registrationKey] !== entry) return@dispatchState
                        if (entry.callback !== this) return@dispatchState
                        entry.callback = null
                        // Bounded fallback to the legacy official resolve
                        // path (frozen design).
                        registerLegacy(manager, service, entry, gen)
                    }
                }

                override fun onServiceUpdated(info: NsdServiceInfo) {
                    // D-07-16: dispatch FIRST; publishResolved re-checks
                    // the generation after dispatch on the state authority.
                    dispatchState { publishResolved(info, entry, gen) }
                }

                override fun onServiceLost() {
                    // D-07-15/16: no-argument pathless loss — fail closed.
                    dispatchState { handlePathlessLoss(entry, gen) }
                }

                override fun onServiceInfoCallbackUnregistered() {}
            }
        entry.callback = callback
        try {
            manager.registerServiceInfoCallback(service, mainExecutor, callback)
        } catch (_: RuntimeException) {
            entry.callback = null
        }
    }

    /** Legacy official path for API 24..33 without T extension 7. */
    @Suppress("DEPRECATION")
    private fun registerLegacy(
        manager: NsdManager,
        service: NsdServiceInfo,
        entry: Tracked,
        gen: Int,
    ) {
        val listener =
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    // No state mutation; dispatch kept for one obvious
                    // ownership pattern (D-07-16).
                    dispatchState { }
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    // D-07-16: dispatch FIRST; publishResolved re-checks
                    // the generation after dispatch.
                    dispatchState { publishResolved(serviceInfo, entry, gen) }
                }
            }
        entry.resolveListener = listener
        try {
            manager.resolveService(service, listener)
        } catch (_: RuntimeException) {
        }
    }

    private fun unregisterTracking(manager: NsdManager?, entry: Tracked) {
        if (manager != null && modernNsd) {
            val callback = entry.callback as? NsdManager.ServiceInfoCallback
            if (callback != null) {
                try {
                    manager.unregisterServiceInfoCallback(callback)
                } catch (_: RuntimeException) {
                }
            }
        }
        entry.callback = null
        entry.resolveListener = null
    }

    private fun publishResolved(
        info: NsdServiceInfo,
        entry: Tracked,
        gen: Int,
    ) {
        if (!live(gen)) return
        if (entry.generation != gen) return
        // D-07-18: generation validity is NOT sufficient — the browse
        // generation may still be current while this Tracked registration
        // was removed or replaced under the same key. Object identity
        // proves the entry still owns a live registration; a detached or
        // replaced entry cannot bind a path, add a global owner, or emit
        // candidate events.
        if (tracked[entry.registrationKey] !== entry) return
        if (!serviceTypeMatches(info.serviceType)) return
        val instanceId = parseTxt(info.attributes) ?: return
        val port = info.port
        if (port < 1 || port > 65535) return
        val addresses = collectAddresses(info)
        if (addresses.isEmpty()) return
        val hint = "port=$port addrs=${addresses.joinToString(",")}"
        val resolved = resolvedPathKey(info, entry)
        if (entry.pathOwners.size == 1 &&
            entry.pathOwners[entry.registrationKey] == instanceId &&
            resolved != entry.registrationKey
        ) {
            // Seed refinement: the registration's seed stand-in for its
            // only path is replaced by the real resolved key. Same physical
            // path, better correlation: never a candidateFound/
            // candidateLost restart (D-07-15).
            refineSeedBinding(entry, instanceId, resolved)
            return
        }
        when (bindPath(entry, resolved, instanceId, gen)) {
            PathBindOutcome.NEW_INSTANCE -> {
                emitCandidate(
                    eventKind = "candidateFound",
                    candidateId = instanceId,
                    displayLabel = entry.serviceName,
                    locatorHint = hint,
                )
            }
            PathBindOutcome.EXISTING_INSTANCE -> {
                // Idempotent metadata refresh: one shared candidate identity.
                emitCandidate(
                    eventKind = "candidateUpdated",
                    candidateId = instanceId,
                    displayLabel = entry.serviceName,
                    locatorHint = hint,
                )
            }
            PathBindOutcome.DUPLICATE_BINDING -> {
                // Duplicate native callback for an already-bound path: no
                // ownership inflation, no emission.
            }
            PathBindOutcome.PATH_LIMIT_REACHED -> {
                // Deterministically dropped; never evicts an existing owner.
            }
        }
    }

    /**
     * Binds [pathKey] to [instanceId] on [entry] and in the global owner
     * index (D-07-15). Each native path is INDEPENDENTLY bound to the
     * instance advertised on that path: a path whose TXT instance changed
     * unbinds only itself from the old instance (candidateLost(old) only
     * when old loses its FINAL global owner) before binding the new one.
     * Other bindings of the registration are never migrated. Duplicate
     * bindings are idempotent; the per-registration bound mirrors the
     * frozen global per-instance bound (MAX_NATIVE_PATHS_PER_INSTANCE).
     */
        private fun bindPath(
        entry: Tracked,
        pathKey: String,
        instanceId: String,
        gen: Int,
    ): PathBindOutcome {
        val existingInstance = entry.pathOwners[pathKey]
        if (existingInstance == instanceId) return PathBindOutcome.DUPLICATE_BINDING
        if (existingInstance != null) {
            // This path switched its TXT instance: unbind old, bind new.
            entry.pathOwners.remove(pathKey)
            if (removeOwner(existingInstance, pathKey)) emitLost(existingInstance)
        } else if (entry.pathOwners.size >= MAX_NATIVE_PATHS_PER_INSTANCE) {
            emitError(
                "pathLimitExceeded",
                "native path limit per LAN instance exceeded",
                gen,
            )
            return PathBindOutcome.PATH_LIMIT_REACHED
        }
        return when (addOwner(instanceId, pathKey)) {
            PathOutcome.FIRST_OWNER -> {
                entry.pathOwners[pathKey] = instanceId
                PathBindOutcome.NEW_INSTANCE
            }
            PathOutcome.ADDITIONAL_OWNER -> {
                entry.pathOwners[pathKey] = instanceId
                PathBindOutcome.EXISTING_INSTANCE
            }
            PathOutcome.DUPLICATE_PATH -> PathBindOutcome.DUPLICATE_BINDING
            PathOutcome.PATH_LIMIT_REACHED -> {
                emitError(
                    "pathLimitExceeded",
                    "native path limit per LAN instance exceeded",
                    gen,
                )
                PathBindOutcome.PATH_LIMIT_REACHED
            }
        }
    }

    /**
     * Silent seed-refinement for the registration's ONLY binding (D-07-15).
     * Replaces the seed stand-in with a real resolved key in both the
     * registration bindings and the global index WITHOUT any candidate
     * emission: the same physical path merely became better correlated.
     */
    private fun refineSeedBinding(entry: Tracked, instanceId: String, resolvedKey: String) {
        val seed = entry.registrationKey
        if (entry.pathOwners.size != 1 ||
            entry.pathOwners[seed] != instanceId ||
            seed == resolvedKey
        ) {
            return
        }
        entry.pathOwners.remove(seed)
        val set = instanceToKeys[instanceId]
        if (set != null) {
            set.remove(seed)
        }
        entry.pathOwners[resolvedKey] = instanceId
        instanceToKeys.getOrPut(instanceId) { HashSet() }.add(resolvedKey)
    }

    /**
     * Strongest resolved native path key for a resolved [NsdServiceInfo]
     * (D-07-12/14). Prefers the concrete [android.net.Network] (API 33+);
     * falls back to the legacy resolved host when the legacy resolve path
     * provided one; otherwise the registration's own seed key is the honest
     * stand-in for its single indistinguishable path (documented physical C
     * limitation). Never fabricates a network identity.
     */
    private fun resolvedPathKey(info: NsdServiceInfo, entry: Tracked): String {
        val name = entry.serviceName
        resolvedNetwork(info)?.let { return "$it|$name" }
        @Suppress("DEPRECATION")
        val host =
            try {
                info.host?.hostAddress
            } catch (_: RuntimeException) {
                null
            }
        if (!host.isNullOrBlank()) return "$host|$name"
        // Android supplied no stronger correlation for this callback stage.
        return entry.registrationKey
    }

    /** Concrete resolved [android.net.Network], API 33+ only (bounded). */
    private fun resolvedNetwork(info: NsdServiceInfo): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
        return try {
            info.network?.toString()
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun collectAddresses(info: NsdServiceInfo): List<String> {
        val out = LinkedHashSet<String>()
        if (modernNsd) {
            try {
                // Official modern API: API 34+ / T extension 7+.
                for (item in info.hostAddresses) {
                    addAddress(out, item)
                }
            } catch (_: RuntimeException) {
            }
        } else {
            @Suppress("DEPRECATION")
            val host = info.host
            if (host != null) {
                addAddress(out, host)
            }
        }
        return out.take(MAX_ADDRESSES)
    }

    private fun addAddress(out: MutableSet<String>, address: InetAddress) {
        val host = address.hostAddress ?: return
        if (host.isBlank()) return
        out.add(formatHost(host))
    }

    private fun formatHost(host: String): String {
        return if (host.contains(':')) "[$host]" else host
    }

    private fun parseTxt(attributes: Map<String, ByteArray>?): String? {
        if (attributes == null) return null
        if (attributes.size > MAX_TXT_KEYS) return null
        var total = 0
        val utf8: Charset = StandardCharsets.UTF_8
        var version: String? = null
        var instance: String? = null
        for ((key, value) in attributes) {
            val keyBytes = key.toByteArray(utf8)
            if (keyBytes.isEmpty() || keyBytes.size > MAX_TXT_KEY_BYTES) return null
            if (value.size > MAX_TXT_VALUE_BYTES) return null
            total += keyBytes.size + value.size
            if (total > MAX_TXT_PAYLOAD) return null
            val text =
                try {
                    String(value, utf8)
                } catch (_: Exception) {
                    return null
                }
            when (key) {
                "v" -> version = text
                "i" -> instance = text
            }
        }
        if (version != SCHEMA_VERSION.toString()) return null
        if (instance == null || !INSTANCE_RE.matches(instance)) return null
        return instance
    }

    private fun serviceTypeMatches(raw: String?): Boolean {
        if (raw == null) return false
        var type = raw.trim()
        while (type.endsWith('.')) {
            type = type.dropLast(1)
        }
        if (type.endsWith(".local")) {
            type = type.removeSuffix(".local")
        }
        while (type.endsWith('.')) {
            type = type.dropLast(1)
        }
        return type == SERVICE_TYPE
    }

    private fun live(gen: Int): Boolean =
        browsing.get() && lifecycle == BrowseLifecycle.BROWSING && generation.get() == gen

    /**
     * Multicast lock rule (frozen, D-07-06 + final fix): required only while
     * browsing on platforms without the mainline mDNS backend, i.e. when
     * `modernNsdAvailable()` is false (API 24..33 without T extension 7).
     * The lock is owned by the acquiring browse generation.
     *
     * Fail-closed: when the lock is required, any acquisition failure
     * (missing WifiManager, create failure, acquire exception) returns
     * [MulticastPreparation.FAILED] and startBrowse must not call
     * discoverServices.
     */
        private fun acquireMulticastLockIfRequired(gen: Int): MulticastPreparation {
        if (modernNsd) {
            return MulticastPreparation.NOT_REQUIRED
        }
        if (multicastLock?.isHeld == true) {
            multicastLockGen = gen
            return MulticastPreparation.ACQUIRED
        }
        val wifiManager = wifi ?: return MulticastPreparation.FAILED
        val lock = wifiManager.createMulticastLock("filehop-lan-nsd")
            ?: return MulticastPreparation.FAILED
        lock.setReferenceCounted(false)
        return try {
            lock.acquire()
            multicastLock = lock
            multicastLockGen = gen
            MulticastPreparation.ACQUIRED
        } catch (_: RuntimeException) {
            MulticastPreparation.FAILED
        }
    }

    /** Idempotent. Never releases a lock owned by a newer generation. */
        private fun releaseMulticastLock(gen: Int) {
        val lock = multicastLock ?: return
        if (multicastLockGen > gen) return
        try {
            if (lock.isHeld) {
                lock.release()
            }
        } catch (_: RuntimeException) {
        }
        multicastLock = null
    }

    private fun emitCandidate(
        eventKind: String,
        candidateId: String,
        displayLabel: String,
        locatorHint: String,
    ) {
        emit(
            mapOf(
                "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
                "eventKind" to eventKind,
                "transportKind" to "lan",
                "candidate" to
                    mapOf(
                        "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
                        "candidateId" to candidateId,
                        "kind" to "lan",
                        "displayLabel" to displayLabel,
                        "locatorHint" to locatorHint,
                    ),
            ),
        )
    }

    private fun emitLost(candidateId: String) {
        emit(
            mapOf(
                "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
                "eventKind" to "candidateLost",
                "transportKind" to "lan",
                "candidate" to
                    mapOf(
                        "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
                        "candidateId" to candidateId,
                        "kind" to "lan",
                    ),
            ),
        )
    }

    /** Raw NSD numeric codes stay diagnostic detail, never a thrown error. */
    private fun emitError(code: String, message: String, gen: Int) {
        if (!live(gen) &&
            code != "discoveryStartFailed" &&
            code != "discoveryStopFailed" &&
            code != "multicastLockFailed"
        ) {
            return
        }
        emit(
            mapOf(
                "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
                "eventKind" to "adapterError",
                "transportKind" to "lan",
                "error" to
                    mapOf(
                        "bridgeVersion" to FileHopNativePlugin.BRIDGE_VERSION,
                        "errorClass" to "nativeFailure",
                        "message" to message,
                        "nativeCode" to code,
                        "kind" to "lan",
                    ),
            ),
        )
    }
}

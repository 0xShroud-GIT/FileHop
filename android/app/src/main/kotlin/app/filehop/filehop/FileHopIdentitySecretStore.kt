package app.filehop.filehop

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

fun interface FileHopReferenceCandidateSource {
    fun nextCandidate(): String?
}

class FileHopSecureReferenceCandidateSource : FileHopReferenceCandidateSource {
    override fun nextCandidate(): String? = FileHopIdentitySecretStore.newReference()
}

/** Deterministic sequence for tests. Never a production default. */
class FileHopSequenceReferenceCandidateSource(
    candidates: List<String>,
) : FileHopReferenceCandidateSource {
    private val remaining = ArrayList(candidates)

    override fun nextCandidate(): String? {
        if (remaining.isEmpty()) {
            return null
        }
        return remaining.removeAt(0)
    }
}

/**
 * Android at-rest identity secret store.
 *
 * Android Keystore holds a non-exportable AES-256-GCM wrapping key.
 * FileHop static private bytes are encrypted and written only under
 * [Context.getNoBackupFilesDir]. SQLite never receives the private key
 * or the wrapping key.
 *
 * Allocation never deletes or adopts a pre-existing alias or ciphertext
 * merely because a generated reference collides. Rollback may remove only
 * resources created by the current failed attempt.
 *
 * Official APIs:
 * - https://developer.android.com/privacy-and-security/keystore
 * - https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec
 * - https://developer.android.com/reference/android/content/Context#getNoBackupFilesDir()
 */
class FileHopIdentitySecretStore(
    context: Context,
    private val candidates: FileHopReferenceCandidateSource =
        FileHopSecureReferenceCandidateSource(),
) {
    private val appContext = context.applicationContext

    data class Failure(val code: String, val message: String)

    private enum class Occupancy {
        UNUSED,
        OCCUPIED,
        INSPECT_FAILED,
    }

    fun store(privateKey: ByteArray): Any {
        if (privateKey.size != PRIVATE_KEY_LEN) {
            return Failure("invalidArgument", "privateKeyBytes must be exactly 32 bytes")
        }
        try {
            for (attempt in 1..MAX_ALLOCATION_ATTEMPTS) {
                val candidate = candidates.nextCandidate()
                    ?: return Failure(
                        "invalidState",
                        "identity secret reference allocator produced no candidate",
                    )
                val hex = parseReference(candidate)
                    ?: return Failure(
                        "invalidArgument",
                        "identity secret reference is not a supported FileHop reference",
                    )
                when (occupancy(hex)) {
                    Occupancy.OCCUPIED, Occupancy.INSPECT_FAILED -> continue
                    Occupancy.UNUSED -> {
                        val outcome = createAtUnused(hex, candidate, privateKey)
                        if (outcome is CollisionSkip) {
                            continue
                        }
                        return outcome
                    }
                }
            }
            return Failure(
                "invalidState",
                "identity secret reference allocation exhausted",
            )
        } finally {
            zero(privateKey)
        }
    }

    private class CollisionSkip

    private fun createAtUnused(hex: String, reference: String, privateKey: ByteArray): Any {
        var createdAlias = false
        var createdFile = false
        val alias = ALIAS_PREFIX + hex
        val file = blobFile(hex)
        try {
            if (occupancy(hex) != Occupancy.UNUSED) {
                return CollisionSkip()
            }
            createWrappingKey(alias)
            createdAlias = true
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, keystoreSecret(alias))
            val iv = cipher.iv
            if (iv == null || iv.isEmpty()) {
                rollbackCreated(hex, createdAlias, createdFile)
                return Failure("nativeFailure", "wrapping cipher did not provide an IV")
            }
            val ciphertext = cipher.doFinal(privateKey)
            val blob = ByteArray(2 + iv.size + ciphertext.size)
            blob[0] = BLOB_VERSION
            blob[1] = iv.size.toByte()
            System.arraycopy(iv, 0, blob, 2, iv.size)
            System.arraycopy(ciphertext, 0, blob, 2 + iv.size, ciphertext.size)
            if (file.exists()) {
                rollbackCreated(hex, createdAlias, createdFile = false)
                return CollisionSkip()
            }
            if (!file.createNewFile()) {
                rollbackCreated(hex, createdAlias, createdFile = false)
                return CollisionSkip()
            }
            createdFile = true
            file.writeBytes(blob)
            return reference
        } catch (_: Exception) {
            rollbackCreated(hex, createdAlias, createdFile)
            return Failure("nativeFailure", "failed to protect identity secret")
        }
    }

    fun load(reference: String): Any {
        val parsed = parseReference(reference) ?: return Failure(
            "invalidArgument",
            "identity secret reference is not a supported FileHop reference",
        )
        return when (occupancy(parsed)) {
            Occupancy.INSPECT_FAILED ->
                Failure("unavailable", "failed to inspect identity secret")
            Occupancy.UNUSED ->
                Failure("notFound", "protected secret is missing")
            Occupancy.OCCUPIED -> loadOccupied(parsed)
        }
    }

    private fun loadOccupied(hex: String): Any {
        val file = blobFile(hex)
        val alias = ALIAS_PREFIX + hex
        val keyPresent: Boolean
        val filePresent: Boolean
        try {
            keyPresent = keystoreContains(alias)
            filePresent = file.isFile
        } catch (_: Exception) {
            return Failure("unavailable", "failed to inspect identity secret")
        }
        if (!filePresent) {
            return Failure("corrupt", "wrapped identity ciphertext is missing")
        }
        if (!keyPresent) {
            return Failure("corrupt", "wrapping key is missing")
        }
        return try {
            decrypt(file, alias)
        } catch (_: AEADBadTagException) {
            Failure("corrupt", "wrapped identity secret failed authentication")
        } catch (error: IdentityBlobException) {
            Failure(error.code, error.message ?: "wrapped identity secret is unreadable")
        } catch (_: Exception) {
            Failure("nativeFailure", "failed to load identity secret")
        }
    }

    fun delete(reference: String): Any {
        val parsed = parseReference(reference) ?: return Failure(
            "invalidArgument",
            "identity secret reference is not a supported FileHop reference",
        )
        if (occupancy(parsed) == Occupancy.INSPECT_FAILED) {
            return Failure("unavailable", "failed to inspect identity secret")
        }
        val file = blobFile(parsed)
        val alias = ALIAS_PREFIX + parsed
        try {
            if (file.exists()) {
                if (!file.delete() && file.exists()) {
                    return Failure("nativeFailure", "failed to delete wrapped identity ciphertext")
                }
            }
        } catch (_: Exception) {
            return Failure("nativeFailure", "failed to delete wrapped identity ciphertext")
        }
        try {
            val store = keyStore()
            if (store.containsAlias(alias)) {
                store.deleteEntry(alias)
                if (store.containsAlias(alias)) {
                    return Failure("nativeFailure", "failed to delete wrapping key")
                }
            }
        } catch (_: Exception) {
            return Failure("nativeFailure", "failed to delete wrapping key")
        }
        return when (occupancy(parsed)) {
            Occupancy.UNUSED -> true
            Occupancy.OCCUPIED ->
                Failure("nativeFailure", "identity secret still present after delete")
            Occupancy.INSPECT_FAILED ->
                Failure("unavailable", "failed to verify identity secret deletion")
        }
    }

    fun status(reference: String): Any {
        val parsed = parseReference(reference) ?: return Failure(
            "invalidArgument",
            "identity secret reference is not a supported FileHop reference",
        )
        val file = blobFile(parsed)
        val alias = ALIAS_PREFIX + parsed
        val keyPresent: Boolean
        val filePresent: Boolean
        try {
            keyPresent = keystoreContains(alias)
            filePresent = file.isFile
        } catch (_: Exception) {
            return Failure("unavailable", "failed to inspect identity secret")
        }
        if (!keyPresent && !filePresent) {
            return "absent"
        }
        if (!filePresent) {
            return "missingCiphertext"
        }
        if (!keyPresent) {
            return "missingWrappingKey"
        }
        return try {
            val plaintext = decrypt(file, alias)
            zero(plaintext)
            "present"
        } catch (_: IdentityBlobException) {
            "unsupported"
        } catch (_: AEADBadTagException) {
            "corrupt"
        } catch (_: Exception) {
            "corrupt"
        }
    }

    fun hasAny(): Any {
        try {
            val files = identityDir().listFiles { candidate ->
                candidate.isFile && isOwnedBlobName(candidate.name)
            }
            if (files == null && identityDir().exists()) {
                return Failure("unavailable", "failed to inspect identity secrets")
            }
            if (files != null && files.isNotEmpty()) {
                return true
            }
            val store = keyStore()
            val aliases = store.aliases()
            while (aliases.hasMoreElements()) {
                if (aliases.nextElement().startsWith(ALIAS_PREFIX)) {
                    return true
                }
            }
            return false
        } catch (_: Exception) {
            return Failure("unavailable", "failed to inspect identity secrets")
        }
    }

    fun deleteAll(): Any {
        var incomplete = false
        try {
            val files = identityDir().listFiles()
            if (files == null && identityDir().exists()) {
                return Failure("unavailable", "failed to list identity secret files")
            }
            if (files != null) {
                for (file in files) {
                    if (!file.isFile || !isOwnedBlobName(file.name)) {
                        continue
                    }
                    if (!file.delete() && file.exists()) {
                        incomplete = true
                    }
                }
            }
            val store = keyStore()
            val aliases = store.aliases()
            val toDelete = ArrayList<String>()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                if (alias.startsWith(ALIAS_PREFIX)) {
                    toDelete.add(alias)
                }
            }
            for (alias in toDelete) {
                try {
                    store.deleteEntry(alias)
                    if (store.containsAlias(alias)) {
                        incomplete = true
                    }
                } catch (_: Exception) {
                    incomplete = true
                }
            }
            val remainingFiles = identityDir().listFiles { candidate ->
                candidate.isFile && isOwnedBlobName(candidate.name)
            }
            if (remainingFiles == null && identityDir().exists()) {
                return Failure("unavailable", "failed to verify identity secret deletion")
            }
            if (remainingFiles != null && remainingFiles.isNotEmpty()) {
                incomplete = true
            }
            val remainingAliases = keyStore().aliases()
            while (remainingAliases.hasMoreElements()) {
                if (remainingAliases.nextElement().startsWith(ALIAS_PREFIX)) {
                    incomplete = true
                    break
                }
            }
        } catch (_: Exception) {
            return Failure("nativeFailure", "failed to delete identity secrets")
        }
        if (incomplete) {
            return Failure("nativeFailure", "identity secret deleteAll was incomplete")
        }
        return true
    }

    private fun occupancy(hex: String): Occupancy {
        val aliasExists: Boolean
        val fileExists: Boolean
        try {
            aliasExists = keystoreContains(ALIAS_PREFIX + hex)
        } catch (_: Exception) {
            return Occupancy.INSPECT_FAILED
        }
        try {
            fileExists = blobFile(hex).exists()
        } catch (_: Exception) {
            return Occupancy.INSPECT_FAILED
        }
        return if (aliasExists || fileExists) Occupancy.OCCUPIED else Occupancy.UNUSED
    }

    private fun rollbackCreated(hex: String, createdAlias: Boolean, createdFile: Boolean) {
        if (createdFile) {
            blobFile(hex).delete()
        }
        if (createdAlias) {
            try {
                keyStore().deleteEntry(ALIAS_PREFIX + hex)
            } catch (_: Exception) {
                // Best-effort rollback of resources this attempt created only.
            }
        }
    }

    private fun decrypt(file: File, alias: String): ByteArray {
        val blob = file.readBytes()
        if (blob.size < 3) {
            throw IdentityBlobException("corrupt", "wrapped identity blob is truncated")
        }
        val version = blob[0]
        if (version != BLOB_VERSION) {
            throw IdentityBlobException("unsupported", "wrapped identity blob version is unsupported")
        }
        val ivLen = blob[1].toInt() and 0xff
        if (ivLen < 12 || blob.size < 2 + ivLen + 16) {
            throw IdentityBlobException("corrupt", "wrapped identity blob is malformed")
        }
        val iv = blob.copyOfRange(2, 2 + ivLen)
        val ciphertext = blob.copyOfRange(2 + ivLen, blob.size)
        val secret = keystoreSecret(alias)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(ciphertext)
    }

    private fun createWrappingKey(alias: String) {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(KEY_SIZE_BITS)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKey()
    }

    private fun keystoreSecret(alias: String): SecretKey {
        return keyStore().getKey(alias, null) as? SecretKey
            ?: throw IdentityBlobException("corrupt", "wrapping key is missing")
    }

    private fun keystoreContains(alias: String): Boolean = keyStore().containsAlias(alias)

    private fun keyStore(): KeyStore {
        val store = KeyStore.getInstance(KEYSTORE_PROVIDER)
        store.load(null)
        return store
    }

    private fun identityDir(): File {
        val dir = File(appContext.noBackupFilesDir, DIR_NAME)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    private fun blobFile(hex: String): File = File(identityDir(), "$hex.blob")

    private fun parseReference(raw: String): String? {
        if (!REF_REGEX.matches(raw)) {
            return null
        }
        if (raw.contains('/') || raw.contains('\\') || raw.contains('\u0000') || raw.contains("..")) {
            return null
        }
        return raw.substring(REF_PREFIX.length)
    }

    private fun isOwnedBlobName(name: String): Boolean {
        if (!name.endsWith(".blob")) {
            return false
        }
        val hex = name.removeSuffix(".blob")
        return HEX_ONLY.matches(hex)
    }

    private fun zero(bytes: ByteArray) {
        java.util.Arrays.fill(bytes, 0)
    }

    private class IdentityBlobException(
        val code: String,
        message: String,
    ) : Exception(message)

    companion object {
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
        const val KEY_SIZE_BITS = 256
        const val PRIVATE_KEY_LEN = 32
        const val BLOB_VERSION: Byte = 1
        const val REF_PREFIX = "fhik1."
        const val ALIAS_PREFIX = "app.filehop.wrap."
        const val DIR_NAME = "filehop_identity"
        const val MAX_ALLOCATION_ATTEMPTS = 8
        val REF_REGEX = Regex("^fhik1\\.[0-9a-f]{32}$")
        private val HEX_ONLY = Regex("^[0-9a-f]{32}$")
        private const val HEX = "0123456789abcdef"

        fun newReference(): String? {
            val bytes = ByteArray(16)
            SecureRandom().nextBytes(bytes)
            val out = StringBuilder(REF_PREFIX.length + 32)
            out.append(REF_PREFIX)
            for (b in bytes) {
                out.append(HEX[(b.toInt() ushr 4) and 0x0f])
                out.append(HEX[b.toInt() and 0x0f])
            }
            return out.toString()
        }
    }
}

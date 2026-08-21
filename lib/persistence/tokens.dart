import 'errors.dart';

/// Stable persisted tokens. Never [Enum.index].
abstract final class PersistTokens {
  static const String trusted = 'TRUSTED';
  static const String blocked = 'BLOCKED';

  static const String qr = 'QR';
  static const String sas = 'SAS';
  static const String userBlock = 'USER_BLOCK';

  static const String outgoing = 'outgoing';
  static const String incoming = 'incoming';

  static const String sender = 'sender';
  static const String receiver = 'receiver';

  static const Set<String> transferStates = <String>{
    'CREATED',
    'OFFERED',
    'ACCEPTED',
    'TRANSFERRING',
    'PAUSED',
    'VERIFYING',
    'RECOVERY_PENDING',
    'COMPLETED',
    'REJECTED',
    'CANCELLED',
    'FAILED',
  };

  static const Set<String> itemStates = <String>{
    'PENDING',
    'READY',
    'TRANSFERRING',
    'PAUSED',
    'VERIFYING',
    'COMPLETED',
    'SKIPPED',
    'CANCELLED',
    'FAILED',
  };

  static const Set<String> itemTypes = <String>{
    'file',
    'directory',
    'photo',
    'video',
    'app',
    'text',
    'link',
  };

  static const Set<String> shareTerminals = <String>{
    'COMPLETED',
    'REJECTED',
    'CANCELLED',
    'FAILED',
  };

  static const Set<String> screenTerminals = <String>{
    'CLOSED',
    'REJECTED',
    'CANCELLED',
    'FAILED',
    'INTERRUPTED',
  };

  static const Set<String> forbiddenSecretNames = <String>{
    'noise_session_key',
    'noise_transport_state',
    'qr_invitation_secret',
    'transfer_token',
    'tls_private_key',
    'webshare_secret',
    'sas_confirmation',
    'decrypted_control_message',
    'private_key',
    'static_private_key',
    'wrapping_key',
    'keystore_secret',
    'keychain_secret',
  };

  static String requireToken(
    String raw,
    Set<String> allowed,
    String label, {
    PersistenceFailureKind kind = PersistenceFailureKind.decodeFailure,
  }) {
    if (!allowed.contains(raw)) {
      throw PersistenceException(
        kind: kind,
        message: 'unknown $label token "$raw"',
      );
    }
    return raw;
  }
}

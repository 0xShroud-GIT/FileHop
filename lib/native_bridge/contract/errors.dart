import 'enums.dart';

/// Controlled failure at the Dart/native boundary. Not a FileHop protocol error.
class NativeBridgeException implements Exception {
  const NativeBridgeException({
    required this.errorClass,
    required this.message,
    this.nativeCode,
    this.diagnostic,
  });

  final NativeErrorClass errorClass;
  final String message;
  final String? nativeCode;
  final String? diagnostic;

  @override
  String toString() => 'NativeBridgeException(${errorClass.wire}: $message)';
}

/// Codec/schema failure. Callers treat this as [NativeErrorClass.invalidArgument].
class NativeCodecException implements Exception {
  const NativeCodecException(this.message);
  final String message;

  @override
  String toString() => 'NativeCodecException($message)';
}

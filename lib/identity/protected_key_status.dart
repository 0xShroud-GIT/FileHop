/// Resolution of a protected-key reference. Distinct from identity metadata.
enum ProtectedKeyStatus {
  present,
  absent,
  missingCiphertext,
  missingWrappingKey,
  corrupt,
  unavailable,
  unsupported,
}

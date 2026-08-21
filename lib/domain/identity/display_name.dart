import '../state_machine/invalid_state_transition.dart';

/// Advisory, mutable metadata. Never security identity.
class DisplayName {
  DisplayName._(this.value);

  final String value;

  factory DisplayName.parse(String raw) {
    if (raw.runes.length > 128) {
      throw const DomainFormatException(
        'display name exceeds 128 Unicode scalar values',
      );
    }
    return DisplayName._(raw);
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

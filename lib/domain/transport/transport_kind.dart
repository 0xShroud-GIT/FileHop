/// Domain transport family. Locator metadata only — never peer identity.
/// Distinct from Mission 02 native DTOs.
enum TransportKind {
  wifiDirect('wifiDirect'),
  wifiAware('wifiAware'),
  lan('lan');

  const TransportKind(this.wire);
  final String wire;
}

enum ShareDirection { outgoing, incoming }

enum TransferItemKind { file, directory, photo, video, app, text, link }

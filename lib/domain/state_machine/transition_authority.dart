/// Causes from `06_STATE_MACHINES.md`. Every transition has exactly one.
enum TransitionAuthority {
  localCommand('LOCAL_COMMAND'),
  peerEvent('PEER_EVENT'),
  transportEvent('TRANSPORT_EVENT'),
  osEvent('OS_EVENT'),
  timeout('TIMEOUT'),
  recovery('RECOVERY');

  const TransitionAuthority(this.wire);
  final String wire;
}

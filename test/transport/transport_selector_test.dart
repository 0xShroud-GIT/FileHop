import 'package:filehop/domain/transport/transport_candidate.dart';
import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/selector_fixtures.dart';

void main() {
  const TransportSelector selector = TransportSelector();

  TransportSelection pick(TransportSelectionInput value) =>
      selector.select(value);

  test('1 Aware available only → Aware', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
        ],
      ),
    );
    expect(result, isA<TransportSelected>());
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiAware);
  });

  test('2 Direct available only on Android → Direct', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiDirect, 'd1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiDirect);
  });

  test('3 LAN available only → LAN', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.ios,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.lan);
  });

  test('4 Aware + Direct + LAN eligible → Aware', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        remote: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.lan, 'l1'),
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.wifiAware, 'a1'),
        ],
      ),
    );
    final TransportSelected selected = result as TransportSelected;
    expect(selected.chosen.kind, TransportKind.wifiAware);
    expect(
      selected.attemptOrder.map((TransportCandidateKey k) => k.kind),
      <TransportKind>[
        TransportKind.wifiAware,
        TransportKind.wifiDirect,
        TransportKind.lan,
      ],
    );
  });

  test('5 Aware unavailable + Direct + LAN → Direct', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedUnavailable,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiDirect);
  });

  test('6 Aware failed + Direct + LAN → Direct', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.failed,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiDirect);
  });

  test('7 Aware permission-required + Direct + LAN → Direct', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.permissionRequired,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiDirect);
  });

  test('8 Aware unavailable + Direct unavailable + LAN → LAN', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedUnavailable,
          TransportKind.wifiDirect: TransportAvailability.supportedUnavailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.lan);
  });

  test('9 all unavailable → noEligibleTransport', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.unsupported,
          TransportKind.wifiDirect: TransportAvailability.failed,
          TransportKind.lan: TransportAvailability.supportedUnavailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect(result, isA<TransportNone>());
    expect(
      (result as TransportNone).reason,
      TransportSelectionReason.noEligibleTransport,
    );
  });

  test('10 healthy existing LAN + new Aware → retain LAN', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
        current: healthyPath(TransportKind.lan, 'l1'),
      ),
    );
    expect(result, isA<TransportRetainCurrent>());
    expect((result as TransportRetainCurrent).path.kind, TransportKind.lan);
  });

  test('11 healthy existing Direct + new Aware → retain Direct', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.wifiDirect, 'd1'),
        ],
        current: healthyPath(TransportKind.wifiDirect, 'd1'),
      ),
    );
    expect(
      (result as TransportRetainCurrent).path.kind,
      TransportKind.wifiDirect,
    );
  });

  test('12 current path lost → recompute selection', () {
    final SelectedTransportPath lost = SelectedTransportPath(
      key: const TransportCandidateKey(
        kind: TransportKind.wifiAware,
        candidateId: 'a1',
      ),
      connection: const TransportConnectionHandle(
        handleId: 'h',
        kind: TransportKind.wifiAware,
      ),
      healthy: false,
    );
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedUnavailable,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
        current: lost,
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiDirect);
  });

  test('13 Android↔iOS Aware unverified + LAN → LAN', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        remote: TransportPlatform.ios,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.lan);
  });

  test('14 Android↔iOS Aware verified + LAN → Aware', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        remote: TransportPlatform.ios,
        qualification: const TransportQualificationPolicy(
          androidIosAwareQualified: true,
        ),
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.wifiAware);
  });

  test('15 iOS context + Direct candidate → Direct rejected', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.ios,
        remote: TransportPlatform.ios,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiDirect, 'd1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.lan);
  });

  test('16 same candidateId across kinds remain distinct', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'candidate-1'),
          availableCandidate(TransportKind.lan, 'candidate-1'),
        ],
      ),
    );
    final TransportSelected selected = result as TransportSelected;
    expect(
      selected.chosen,
      const TransportCandidateKey(
        kind: TransportKind.wifiAware,
        candidateId: 'candidate-1',
      ),
    );
    expect(
      selected.fallbacks.single,
      const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'candidate-1',
      ),
    );
  });

  test('17 same display name does not merge candidates', () {
    final TransportSelectionInput value = input(
      local: TransportPlatform.android,
      adapters: <TransportKind, TransportAvailability>{
        TransportKind.wifiAware: TransportAvailability.supportedAvailable,
        TransportKind.lan: TransportAvailability.supportedAvailable,
      },
      candidates: <SelectableCandidate>[
        const SelectableCandidate(
          key: TransportCandidateKey(
            kind: TransportKind.wifiAware,
            candidateId: 'a',
          ),
          state: TransportCandidateState.available,
          displayLabel: 'Pixel',
        ),
        const SelectableCandidate(
          key: TransportCandidateKey(kind: TransportKind.lan, candidateId: 'l'),
          state: TransportCandidateState.available,
          displayLabel: 'Pixel',
        ),
      ],
    );
    final TransportSelected selected = pick(value) as TransportSelected;
    expect(selected.attemptOrder, hasLength(2));
    expect(selected.chosen.candidateId, 'a');
  });

  test('18 unknown capability state is non-selectable', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.unknown,
          TransportKind.lan: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
          availableCandidate(TransportKind.lan, 'l1'),
        ],
      ),
    );
    expect((result as TransportSelected).chosen.kind, TransportKind.lan);
  });

  test('20 repeated identical input is deterministic', () {
    final TransportSelectionInput value = input(
      local: TransportPlatform.android,
      adapters: <TransportKind, TransportAvailability>{
        TransportKind.wifiAware: TransportAvailability.supportedAvailable,
        TransportKind.wifiDirect: TransportAvailability.supportedAvailable,
        TransportKind.lan: TransportAvailability.supportedAvailable,
      },
      candidates: <SelectableCandidate>[
        availableCandidate(TransportKind.wifiAware, 'z'),
        availableCandidate(TransportKind.wifiAware, 'a'),
        availableCandidate(TransportKind.lan, 'l'),
      ],
    );
    final TransportSelected first = pick(value) as TransportSelected;
    final TransportSelected second = pick(value) as TransportSelected;
    expect(first.chosen.candidateId, 'a');
    expect(second.chosen, first.chosen);
    expect(second.attemptOrder, first.attemptOrder);
  });

  test('permission-only adapters report permissionBlocked', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.permissionRequired,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
        ],
      ),
    );
    expect(
      (result as TransportNone).reason,
      TransportSelectionReason.permissionBlocked,
    );
  });

  test('unverified cross-platform Aware only is interopUnverified', () {
    final TransportSelection result = pick(
      input(
        local: TransportPlatform.ios,
        remote: TransportPlatform.android,
        adapters: <TransportKind, TransportAvailability>{
          TransportKind.wifiAware: TransportAvailability.supportedAvailable,
        },
        candidates: <SelectableCandidate>[
          availableCandidate(TransportKind.wifiAware, 'a1'),
        ],
      ),
    );
    expect(
      (result as TransportNone).reason,
      TransportSelectionReason.interopUnverified,
    );
  });

  test('selector input copies are immutable', () {
    final Map<TransportKind, TransportCapabilitySnapshot> caps =
        <TransportKind, TransportCapabilitySnapshot>{
          TransportKind.lan: cap(
            TransportKind.lan,
            TransportAvailability.supportedAvailable,
          ),
        };
    final List<SelectableCandidate> list = <SelectableCandidate>[
      availableCandidate(TransportKind.lan, 'l'),
    ];
    final TransportSelectionInput value = TransportSelectionInput(
      localPlatform: TransportPlatform.android,
      remotePlatform: null,
      qualification: const TransportQualificationPolicy(),
      capabilities: caps,
      candidates: list,
      currentPath: null,
    );
    expect(
      () => value.candidates.add(availableCandidate(TransportKind.lan, 'x')),
      throwsUnsupportedError,
    );
    caps.clear();
    list.clear();
    expect(value.capabilities, isNotEmpty);
    expect(value.candidates, isNotEmpty);
  });
}

import 'package:filehop/app/app_shell.dart';
import 'package:filehop/app/filehop_app.dart';
import 'package:filehop/features/settings/settings_destination.dart';
import 'package:filehop/shared/identity_placeholder.dart';
import 'package:filehop/shared/shell_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FileHop shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const FileHopApp());
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(AppShell.navigationBarKey), findsOneWidget);
  });

  testWidgets('Home is the default destination', (WidgetTester tester) async {
    await tester.pumpWidget(const FileHopApp());
    expect(find.byKey(const Key('destination-home')), findsOneWidget);
    expect(find.text('FileHop'), findsOneWidget);
    final NavigationBar bar = tester.widget(find.byType(NavigationBar));
    expect(bar.selectedIndex, ShellDestination.home.index);
  });

  testWidgets('exactly four bottom destinations', (WidgetTester tester) async {
    await tester.pumpWidget(const FileHopApp());
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(ShellDestination.values, hasLength(4));
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Wi-Fi Direct'), findsNothing);
    expect(find.text('Wi-Fi Aware'), findsNothing);
    expect(find.text('LAN'), findsNothing);
  });

  testWidgets('switching destinations updates the visible body', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FileHopApp());

    await tester.tap(find.byKey(const Key('nav-activity')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination-activity')), findsOneWidget);
    expect(find.textContaining('No transfer activity yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-devices')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination-devices')), findsOneWidget);
    expect(
      find.textContaining('No trusted or known devices yet.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination-settings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination-home')), findsOneWidget);
    expect(find.text('FileHop'), findsOneWidget);
  });

  testWidgets('identity placeholder is non-authoritative', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FileHopApp());
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(SettingsDestination.deviceNameKey), findsOneWidget);
    expect(find.text('Device name: This device'), findsOneWidget);
    expect(find.text('Security identity: Not initialized'), findsOneWidget);
    expect(find.text(IdentityPlaceholder.disclaimer), findsOneWidget);
    expect(find.textContaining('fingerprint'), findsNothing);
    expect(find.textContaining('TRUSTED'), findsNothing);
  });

  testWidgets('navigation destinations expose semantic labels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FileHopApp());

    expect(find.byTooltip('Home destination'), findsOneWidget);
    expect(find.byTooltip('Activity destination'), findsOneWidget);
    expect(find.byTooltip('Devices destination'), findsOneWidget);
    expect(find.byTooltip('Settings destination'), findsOneWidget);
  });

  testWidgets('text scale does not overflow the shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: FileHopApp(),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(IdentityPlaceholder.disclaimer), findsOneWidget);
  });
}

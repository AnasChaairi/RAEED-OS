import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/theme/raeed_theme.dart';
import 'package:raeed_os/widgets/pickers.dart';

/// Opens a picker from a button and returns what it gave back.
Future<T?> open<T>(WidgetTester tester, Future<T?> Function(BuildContext) show, Future<void> Function() act) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  T? result;
  await tester.pumpWidget(MaterialApp(
    theme: buildRaeedTheme(),
    locale: const Locale('ar', 'MA'),
    supportedLocales: const [Locale('ar', 'MA')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(onPressed: () async => result = await show(context), child: const Text('open')),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act();
  await tester.tap(find.byKey(const Key('picker-done')));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('time: pick the hour, then the minutes', (tester) async {
    final t = await open(tester, (c) => showTimeSheet(c, title: 'من'), () async {
      expect(tester.widget<FilledButton>(find.byKey(const Key('picker-done'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('time-hour-17')));
      await tester.tap(find.byKey(const Key('time-minute-30')));
      await tester.pump();
      expect(find.text('17:30'), findsOneWidget);
    });
    expect(t, 17 * 60 + 30);
  });

  testWidgets('time: an odd existing time is kept as a choice', (tester) async {
    final t = await open(tester, (c) => showTimeSheet(c, title: 'من', initial: 7 * 60 + 10), () async {
      expect(find.byKey(const Key('time-hour-7')), findsOneWidget);
      expect(find.byKey(const Key('time-minute-10')), findsOneWidget);
    });
    expect(t, 7 * 60 + 10);
  });

  testWidgets('date cards: the next two weeks, then a later day from the month', (tester) async {
    final today = DateTime(2026, 10, 13);
    Future<DateTime?> show(BuildContext c) =>
        showUpcomingDateSheet(c, title: 'التاريخ', firstDate: DateTime(2026), lastDate: DateTime(2027, 6, 30), today: today);

    final soon = await open(tester, show, () async {
      expect(find.text('اليوم'), findsOneWidget);
      expect(find.text('غداً'), findsOneWidget);
      expect(find.byKey(const Key('date-day-2026-10-26')), findsOneWidget);
      expect(find.byKey(const Key('date-day-2026-10-27')), findsNothing);
      await tester.tap(find.byKey(const Key('date-day-2026-10-19')));
      await tester.pump();
      expect(find.text('الاثنين 19 أكتوبر'), findsOneWidget);
    });
    expect(soon, DateTime(2026, 10, 19));

    final later = await open(tester, show, () async {
      await tester.tap(find.byKey(const Key('date-toggle-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('month-forward')));
      await tester.pumpAndSettle();
      expect(find.text('نونبر 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('date-day-2026-11-20')));
      await tester.pump();
    });
    expect(later, DateTime(2026, 11, 20));
  });

  testWidgets('date cards: days before the first allowed date cannot be picked', (tester) async {
    final today = DateTime(2026, 10, 13);
    final d = await open(
      tester,
      (c) => showUpcomingDateSheet(c, title: 'ينتهي في', firstDate: DateTime(2026, 10, 15), lastDate: DateTime(2027), today: today),
      () async {
        // The cards start at the first allowed day.
        expect(find.byKey(const Key('date-day-2026-10-13')), findsNothing);
        await tester.tap(find.byKey(const Key('date-day-2026-10-15')));
        await tester.pump();
      },
    );
    expect(d, DateTime(2026, 10, 15));
  });

  testWidgets('date wheels: start at the suggestion and follow the month wheel', (tester) async {
    final d = await open(
      tester,
      (c) => showDateWheelsSheet(c, title: 'تاريخ الميلاد', initial: DateTime(2018, 1, 31), firstDate: DateTime(2005), lastDate: DateTime(2026, 10, 13)),
      () async {
        expect(find.text('31 يناير 2018'), findsOneWidget);
        // One step down the month wheel: February, so the 31st becomes the 28th.
        await tester.drag(find.byKey(const Key('wheel-month')), const Offset(0, -46));
        await tester.pumpAndSettle();
        expect(find.text('28 فبراير 2018'), findsOneWidget);
      },
    );
    expect(d, DateTime(2018, 2, 28));
  });
}

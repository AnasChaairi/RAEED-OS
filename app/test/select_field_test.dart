import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/theme/raeed_theme.dart';
import 'package:raeed_os/widgets/select_field.dart';

const names = ['أحمد بنعلي', 'سارة الإدريسي', 'يوسف العلوي', 'مريم', 'إلياس', 'هدى', 'كريم', 'ليلى', 'عمر', 'فاطمة'];

Future<void> host(WidgetTester tester, Widget Function(StateSetter) build) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRaeedTheme(),
      locale: const Locale('ar', 'MA'),
      supportedLocales: const [Locale('ar', 'MA')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) => ListView(children: [build(setState)])),
      ),
    ),
  );
}

void main() {
  test('search folds the Arabic spellings people mix up', () {
    expect(foldArabic('أحمد'), foldArabic('احمد'));
    expect(foldArabic('فاطمة'), foldArabic('فاطمه'));
    expect(foldArabic('مُصْطَفَى'), foldArabic('مصطفي'));
  });

  testWidgets('a short list stays as buttons', (tester) async {
    final chosen = <int>{};
    await host(
      tester,
      (setState) => MultiSelectField<int>(
        title: 'المؤطرون',
        options: [for (var i = 0; i < 3; i++) SelectOption(i, names[i], key: Key('opt-$i'))],
        selected: chosen,
        onChanged: (v, on) => setState(() => on ? chosen.add(v) : chosen.remove(v)),
      ),
    );
    expect(find.byType(FilterChip), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('opt-1')));
    await tester.pump();
    expect(chosen, {1});
  });

  testWidgets('a long list opens a sheet with search, and the choice shows on the form', (tester) async {
    final chosen = <int>{};
    await host(
      tester,
      (setState) => MultiSelectField<int>(
        title: 'المؤطرون',
        options: [for (var i = 0; i < names.length; i++) SelectOption(i, names[i])],
        selected: chosen,
        onChanged: (v, on) => setState(() => on ? chosen.add(v) : chosen.remove(v)),
      ),
    );
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.text('اختر من القائمة'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('select-search')), 'احمد');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.text('أحمد بنعلي'));
    await tester.pump();
    expect(find.text('1 / 10'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('select-search')), 'زززز');
    await tester.pump();
    expect(find.text('لا توجد نتيجة مطابقة.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-done')));
    await tester.pumpAndSettle();
    expect(chosen, {0});
    expect(find.widgetWithText(InputChip, 'أحمد بنعلي'), findsOneWidget);

    // Removed straight from the form.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(chosen, isEmpty);
  });

  testWidgets('one value: pick from the sheet, or pick none', (tester) async {
    String? value;
    await host(
      tester,
      (setState) => SelectField<String>(
        label: 'الفئة',
        noneLabel: 'بدون فئة',
        options: [for (final n in names) SelectOption(n, n)],
        value: value,
        onChanged: (v) => setState(() => value = v),
      ),
    );
    await tester.tap(find.text('بدون فئة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('select-search')), 'فاطمه');
    await tester.pump();
    await tester.tap(find.text('فاطمة'));
    await tester.pumpAndSettle();
    expect(value, 'فاطمة');

    await tester.tap(find.text('فاطمة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-none')));
    await tester.pumpAndSettle();
    expect(value, isNull);
  });
}

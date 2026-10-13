import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/phone.dart';
import '../config.dart';
import '../theme/raeed_theme.dart';
import '../widgets/pickers.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'setup_store.dart';

/// Makes the advisor's [SetupStore] available to the setup screens.
class SetupScope extends InheritedNotifier<SetupStore> {
  const SetupScope({super.key, required SetupStore store, required super.child}) : super(notifier: store);

  static SetupStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SetupScope>()!.notifier!;

  static SetupStore read(BuildContext context) => context.getInheritedWidgetOfExactType<SetupScope>()!.notifier!;
}

String setupFailureMessage(SetupFailure f) => switch (f) {
      SetupFailure.offline => 'لا يوجد اتصال بالإنترنت. تحقّق من الاتصال وحاول مرة أخرى.',
      SetupFailure.duplicateName => 'يوجد اسم مطابق من قبل. اختر اسماً آخر.',
      SetupFailure.invalidPhone => 'رقم الهاتف غير صحيح. اكتبه هكذا: 06 12 34 56 78',
      SetupFailure.tooManyParents => 'لا يمكن تسجيل أكثر من وليّي أمر لطفل واحد.',
      SetupFailure.ownAdvisorRole => 'لا يمكنك إزالة دور المشرف عن حسابك.',
      SetupFailure.ownAccount => 'لا يمكنك حذف حسابك بنفسك. اطلب ذلك من مشرف آخر.',
      SetupFailure.notAllowed => 'ليست لديك صلاحية لهذا التغيير.',
      SetupFailure.unknown => 'حدث خطأ. حاول مرة أخرى بعد قليل.',
    };

/// Group logo colours 1 to 8, with the text colour that reads on each.
const groupLogoColors = <(LinearGradient, Color)>[
  (RaeedColors.sky, RaeedColors.ink),
  (RaeedColors.star, RaeedColors.ink),
  (LinearGradient(colors: [Color(0xFF1C7A55), Color(0xFF3FAE7F)]), Colors.white),
  (LinearGradient(colors: [Color(0xFF5B4BC4), Color(0xFF8F7FF0)]), Colors.white),
  (LinearGradient(colors: [RaeedColors.blue, Color(0xFF3D93F5)]), Colors.white),
  (LinearGradient(colors: [Color(0xFFC2341D), Color(0xFFE8705A)]), Colors.white),
  (LinearGradient(colors: [Color(0xFFB0306A), Color(0xFFE0619B)]), Colors.white),
  (LinearGradient(colors: [Color(0xFF0B2545), Color(0xFF34557F)]), Colors.white),
];

class GroupLogo extends StatelessWidget {
  const GroupLogo({super.key, required this.letter, required this.color, this.size = 44, this.image});

  GroupLogo.of(Group g, {Key? key, double size = 44})
      : this(key: key, letter: g.logoLetter, color: g.logoColor, size: size, image: groupLogoImage(g.logoPath));

  final String letter;
  final int color;
  final double size;

  /// The uploaded logo. While it loads, or when it can't be fetched (offline), the
  /// letter shows instead.
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final (gradient, ink) = groupLogoColors[(color - 1).clamp(0, groupLogoColors.length - 1)];
    final radius = BorderRadius.circular(size * 0.32);
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: gradient, borderRadius: radius),
      child: Text(
        letter,
        style: TextStyle(fontFamily: RaeedFonts.display, fontWeight: FontWeight.w700, fontSize: size * 0.45, height: 1.2, color: ink),
      ),
    );
    if (image == null) return tile;
    return ClipRRect(
      borderRadius: radius,
      child: Image(
        image: image!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, sync) => frame == null && !sync ? tile : child,
        errorBuilder: (context, error, stack) => tile,
      ),
    );
  }
}

/// The public address of an uploaded group logo.
ImageProvider? groupLogoImage(String? path) => path == null
    ? null
    : NetworkImage('${AppConfig.supabaseUrl}/storage/v1/object/public/$groupLogoBucket/$path');

/// A round initial for a person or child.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.size = 34});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: RaeedColors.surfaceAlt, shape: BoxShape.circle),
        child: Text(
          name.trim().isEmpty ? '؟' : name.trim().characters.first,
          style: TextStyle(fontWeight: FontWeight.w600, color: RaeedColors.blue, fontSize: size * 0.42),
        ),
      );
}

/// A tappable card row: leading, title, subtitle lines, chevron.
class SetupRow extends StatelessWidget {
  const SetupRow({super.key, required this.leading, required this.title, this.lines = const [], this.trailing, this.onTap});

  final Widget leading;
  final String title;
  final List<String> lines;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    for (final l in lines) Text(l, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                  ],
                ),
              ),
              ?trailing,
              if (onTap != null) const Icon(Icons.chevron_left, color: RaeedColors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: RaeedColors.grey)),
      );
}

/// A highlighted note, star-coloured, for things that would break a journey.
class WarningCard extends StatelessWidget {
  const WarningCard({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: RaeedColors.starSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF8A4B00))),
          for (final l in lines) Text(l, style: text.bodySmall?.copyWith(color: RaeedColors.ink)),
        ],
      ),
    );
  }
}

/// Shows the store's content once loaded, a spinner before, and the reason with a retry
/// button when loading failed.
class SetupLoadGate extends StatelessWidget {
  const SetupLoadGate({super.key, required this.builder});

  final Widget Function(BuildContext context, SetupSnapshot data) builder;

  @override
  Widget build(BuildContext context) {
    final store = SetupScope.of(context);
    if (!store.loaded) {
      if (store.loadFailure != null && !store.loading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(setupFailureMessage(store.loadFailure!), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: store.load, child: const Text('حاول مرة أخرى')),
              ],
            ),
          ),
        );
      }
      if (!store.loading) WidgetsBinding.instance.addPostFrameCallback((_) => store.ensureLoaded());
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(onRefresh: store.load, child: builder(context, store.data));
  }
}

/// After creating accounts: the temporary passwords to hand over, each with a copy button.
Future<void> showIssuedPasswords(BuildContext context, List<IssuedPassword> issued, {String? note}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    builder: (sheet) {
      final text = Theme.of(sheet).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('كلمات المرور المؤقتة', style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                note ?? 'سلّم لكل شخص رقمه وكلمة مروره. سيختار كلمة مرور خاصة به عند أول دخول.',
                style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
              ),
              const SizedBox(height: 12),
              for (final p in issued) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.fullName, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              Text(formatPhone(p.phone), textDirection: TextDirection.ltr, style: text.bodySmall),
                              const SizedBox(height: 4),
                              SelectableText(
                                p.temporaryPassword,
                                key: Key('password-${p.phone}'),
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2, color: RaeedColors.blue),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'نسخ',
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                              text: 'رائد · ${p.fullName}\nرقم الهاتف: ${formatPhone(p.phone)}\nكلمة المرور المؤقتة: ${p.temporaryPassword}',
                            ));
                            ScaffoldMessenger.of(sheet).showSnackBar(const SnackBar(content: Text('تم النسخ')));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(key: const Key('passwords-done'), onPressed: () => Navigator.pop(sheet), child: const Text('تم')),
            ],
          ),
        ),
      );
    },
  );
}

/// A date shown as 12/10/2026. Tapping opens day, month and year wheels, or with [upcoming]
/// the next two weeks as day cards.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.required = false,
    this.upcoming = false,
    this.suggested,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool required;

  /// For session dates, which are nearly always in the coming days.
  final bool upcoming;

  /// Where the wheels start when there is no value yet.
  final DateTime? suggested;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: (_) => required && value == null ? 'اختر التاريخ' : null,
      builder: (state) => InkWell(
        onTap: () async {
          final first = firstDate ?? DateTime(2000);
          final last = lastDate ?? DateTime(DateTime.now().year + 5, 12, 31);
          final picked = upcoming
              ? await showUpcomingDateSheet(context, title: label, initial: value, firstDate: first, lastDate: last)
              : await showDateWheelsSheet(context, title: label, initial: value ?? suggested, firstDate: first, lastDate: last);
          if (picked != null) {
            onChanged(picked);
            state.didChange(picked);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: state.errorText,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(value == null ? '' : formatDate(value!)),
        ),
      ),
    );
  }
}

String formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// An Arabic count with the right noun form: فئة واحدة، فئتان، 3 فئات، 11 فئة.
String countLabel(int n, {required String one, required String two, required String few, required String many}) {
  if (n == 0) return 'لا $many';
  if (n == 1) return one;
  if (n == 2) return two;
  final mod = n % 100;
  if (mod >= 3 && mod <= 10) return '$n $few';
  return '$n $many';
}

/// ذكر or أنثى, required.
class GenderField extends StatelessWidget {
  const GenderField({super.key, required this.value, required this.onChanged, this.fieldKey});

  final Gender? value;
  final ValueChanged<Gender> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => FormField<Gender>(
        key: fieldKey,
        initialValue: value,
        validator: (v) => v == null ? 'اختر الجنس' : null,
        builder: (state) => InputDecorator(
          decoration: InputDecoration(
            labelText: 'الجنس',
            errorText: state.errorText,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SegmentedButton<Gender>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                for (final g in Gender.values)
                  ButtonSegment(value: g, label: Text(g.label, key: Key('gender-${g.dbName}'))),
              ],
              selected: {?value},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                onChanged(s.first);
                state.didChange(s.first);
              },
            ),
          ),
        ),
      );
}

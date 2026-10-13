import 'package:flutter/material.dart';

import '../instructor/models.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'stats_models.dart';
import 'stats_store.dart';

const _good = Color(0xFF1C7A55);

/// The pilot's success measures against their targets, for the chosen period.
class PilotScreen extends StatefulWidget {
  const PilotScreen({super.key});

  @override
  State<PilotScreen> createState() => _PilotScreenState();
}

class _PilotScreenState extends State<PilotScreen> {
  @override
  void initState() {
    super.initState();
    final store = StatsScope.read(context);
    Future.microtask(store.loadPilot);
  }

  @override
  Widget build(BuildContext context) {
    final store = StatsScope.of(context);
    final m = store.pilot;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مؤشرات التجربة'),
            Text(store.period.label, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
      body: m == null
          ? Center(
              child: store.pilotFailure == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(setupFailureMessage(store.pilotFailure!), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: store.loadPilot, child: const Text('حاول مرة أخرى')),
                      ],
                    ),
            )
          : RefreshIndicator(
              onRefresh: store.loadPilot,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _Measure(
                    key: const Key('pilot-on-time'),
                    title: 'حضور مسجّل خلال 24 ساعة',
                    value: percent(m.onTimeRate),
                    target: 'الهدف: ${_ltr('90%')} أو أكثر',
                    met: m.onTimeRate == null ? null : m.onTimeRate! >= pilotOnTimeTarget,
                    detail: m.sessionsHeld == 0
                        ? 'لا حصص منتهية في هذه الفترة'
                        : '${m.recordedWithin24h} من ${countLabel(m.sessionsHeld, one: 'حصة واحدة', two: 'حصتين', few: 'حصص', many: 'حصة')}'
                              '${m.recordedLate > 0 ? ' · ${m.recordedLate} متأخرة' : ''}',
                  ),
                  _Measure(
                    key: const Key('pilot-sheet-time'),
                    title: 'مدة تسجيل الحضور (الوسيط)',
                    value: m.medianSheetSeconds == null ? '—' : _duration(m.medianSheetSeconds!),
                    target: 'الهدف: 3 دقائق أو أقل',
                    met: m.medianSheetSeconds == null ? null : m.medianSheetSeconds! <= pilotSheetSecondsTarget,
                    detail: m.sheetsTimed == 0
                        ? 'لم يُقس أي تسجيل بعد'
                        : 'محسوبة من ${countLabel(m.sheetsTimed, one: 'ورقة حضور واحدة', two: 'ورقتي حضور', few: 'أوراق حضور', many: 'ورقة حضور')}',
                  ),
                  _Measure(
                    key: const Key('pilot-follow-up'),
                    title: 'تنبيهات غياب تمت متابعتها خلال 7 أيام',
                    value: percent(m.followUpRate),
                    target: 'الهدف: ${_ltr('80%')} أو أكثر',
                    met: m.followUpRate == null ? null : m.followUpRate! >= pilotFollowUpTarget,
                    detail: m.alertsDue == 0
                        ? 'لا تنبيهات مستحقة بعد'
                        : '${m.alertsFollowedUp} من ${m.alertsDue} · محاولة اتصال أو إغلاق',
                  ),
                  _Measure(
                    key: const Key('pilot-families'),
                    title: 'أسر دخلت إلى التطبيق',
                    value: percent(m.signedInRate),
                    target: 'الهدف: ${_ltr('70%')} أو أكثر',
                    met: m.signedInRate == null ? null : m.signedInRate! >= pilotSignedInTarget,
                    detail: m.families == 0
                        ? 'لا أولياء أمور بعد'
                        : '${m.familiesSignedIn} من ${m.families} · ولي أمر واحد على الأقل غيّر كلمة المرور',
                  ),
                  const SectionLabel('المشرفون · فتح الإحصائيات كل أسبوع'),
                  Card(
                    child: Column(
                      children: [
                        for (final a in m.advisors)
                          ListTile(
                            leading: InitialAvatar(a.name, size: 32),
                            title: Text(a.name),
                            subtitle: Text(
                              a.lastOpened == null ? 'لم يفتحها بعد' : 'آخر مرة: ${longDay(a.lastOpened!)}',
                            ),
                            trailing: Text(
                              countLabel(
                                a.weeksOpened,
                                one: 'أسبوع واحد',
                                two: 'أسبوعان',
                                few: 'أسابيع',
                                many: 'أسبوعاً',
                              ),
                              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (m.groups.isNotEmpty) ...[
                    const SectionLabel('التسجيل في الوقت حسب الفئة'),
                    Card(
                      child: Column(
                        children: [
                          for (final g in [
                            ...m.groups,
                          ]..sort((a, b) => (a.onTime / a.held).compareTo(b.onTime / b.held)))
                            ListTile(
                              dense: true,
                              title: Text(
                                store.data?.groups.where((x) => x.id == g.groupId).firstOrNull?.name ?? 'فئة مؤرشفة',
                              ),
                              trailing: Text(
                                '${g.onTime} من ${g.held}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: g.onTime / g.held >= pilotOnTimeTarget ? _good : RaeedColors.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'تُحسب مدة التسجيل من فتح ورقة الحضور إلى أول حفظ. التسجيل بدون إنترنت لا يُقاس.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Keeps 90% reading as 90% inside Arabic text.
String _ltr(String s) => '\u2066$s\u2069';

/// 2:35
String _duration(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class _Measure extends StatelessWidget {
  const _Measure({
    super.key,
    required this.title,
    required this.value,
    required this.target,
    required this.met,
    required this.detail,
  });

  final String title;
  final String value;
  final String target;

  /// Null when there is nothing to measure yet.
  final bool? met;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = switch (met) {
      true => _good,
      false => RaeedColors.error,
      null => RaeedColors.grey,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(detail, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                  const SizedBox(height: 2),
                  Text(target, style: text.bodySmall?.copyWith(color: color)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: text.headlineSmall?.copyWith(
                fontFamily: RaeedFonts.display,
                fontWeight: FontWeight.w700,
                color: met == null ? RaeedColors.grey : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

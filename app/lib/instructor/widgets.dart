import 'package:flutter/material.dart';

import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'instructor_store.dart';
import 'models.dart';

class InstructorScope extends InheritedNotifier<InstructorStore> {
  const InstructorScope({super.key, required InstructorStore store, required super.child}) : super(notifier: store);

  static InstructorStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InstructorScope>()!.notifier!;

  static InstructorStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InstructorScope>()!.notifier!;
}

/// The colours of each attendance status, from the attendance wireframe.
(Color, Color) statusColors(AttendanceStatus s) => switch (s) {
  AttendanceStatus.present => (const Color(0xFF1C7A55), const Color(0xFFE3F4EC)),
  AttendanceStatus.late => (const Color(0xFF5B4BC4), const Color(0xFFEEEBFC)),
  AttendanceStatus.absent => (const Color(0xFFC2341D), const Color(0xFFFDE8E3)),
  AttendanceStatus.excused => (const Color(0xFF8A5A00), const Color(0xFFFFF1D6)),
};

/// The instructor's data once there is any, a spinner before, and the reason with a retry
/// button when the first load failed.
class InstructorLoadGate extends StatelessWidget {
  const InstructorLoadGate({super.key, required this.builder});

  final Widget Function(BuildContext context, InstructorSnapshot data) builder;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
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
                FilledButton(onPressed: store.refresh, child: const Text('حاول مرة أخرى')),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(onRefresh: store.refresh, child: builder(context, store.data));
  }
}

/// Shown while there is no connection: what still works.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.text = 'لا يوجد إنترنت. يمكنك تسجيل الحضور، وسيُرسل تلقائياً عند عودة الاتصال.',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('offline-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: RaeedColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(color: RaeedColors.starEnd, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// A session as a card: time, group, title, place, and what is attached.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.session, required this.data, this.onTap, this.showGroup = true});

  final Session session;
  final InstructorSnapshot data;
  final VoidCallback? onTap;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final text = Theme.of(context).textTheme;
    final group = data.group(s.groupId);
    final taken = data.attendanceFor(s.id).isNotEmpty;
    final extras = [
      if (s.materials.isNotEmpty)
        countLabel(s.materials.length, one: 'مادة مرفقة', two: 'مادتان مرفقتان', few: 'مواد مرفقة', many: 'مادة مرفقة'),
      s.seriesId == null ? 'مرة واحدة' : 'أسبوعي',
      if (taken && !s.cancelled) 'الحضور مسجّل',
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Column(
                  children: [
                    Text(
                      formatTime(s.start),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: s.cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text('${s.end - s.start} د', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [if (showGroup && group != null) group.name, s.title].join(' · '),
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (s.cancelled)
                      Text(
                        'ملغاة${s.cancelReason == null || s.cancelReason!.isEmpty ? '' : ' · ${s.cancelReason}'}',
                        style: text.bodySmall?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w600),
                      )
                    else ...[
                      Text(s.placeLabel, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                      if (s.away && s.pickupTime != null)
                        Text(
                          [
                            if (s.dropoffTime != null) 'التسليم ${formatTime(s.dropoffTime!)}',
                            'الاستلام ${formatTime(s.pickupTime!)}${s.pickupPlace == null ? '' : ' · ${s.pickupPlace}'}',
                          ].join(' · '),
                          style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                        ),
                      Text(extras.join(' · '), style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                    ],
                  ],
                ),
              ),
              if (s.status == SessionStatus.changed && !s.cancelled)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 6),
                  child: Icon(Icons.update, size: 18, color: RaeedColors.starEnd, semanticLabel: 'تغيّر الموعد'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "منذ يومين", "أمس", "اليوم".
String daysAgo(DateTime t, DateTime now) {
  final d = dayOnly(now).difference(dayOnly(t)).inDays;
  if (d <= 0) return 'اليوم';
  if (d == 1) return 'أمس';
  if (d == 2) return 'منذ يومين';
  return 'منذ ${countLabel(d, one: 'يوم', two: 'يومين', few: 'أيام', many: 'يوماً')}';
}

/// The day of a session, relative when close: اليوم, غداً, or السبت 13 فبراير.
String dayLabel(DateTime day, DateTime now) {
  final d = dayOnly(day).difference(dayOnly(now)).inDays;
  if (d == 0) return 'اليوم · ${longDay(day)}';
  if (d == 1) return 'غداً · ${longDay(day)}';
  return longDay(day);
}

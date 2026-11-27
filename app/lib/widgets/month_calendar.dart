import 'package:flutter/material.dart';

import '../instructor/activities_screen.dart' show activityColors;
import '../instructor/models.dart';
import '../instructor/widgets.dart' show dayLabel;
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';

/// How a schedule is shown: a list (one week, or what is coming) or a month calendar.
enum ScheduleMode { list, month }

/// The last mode picked, shared by every schedule screen while the app is open, so a
/// parent who prefers the calendar keeps it from one visit to the next.
final scheduleMode = ValueNotifier<ScheduleMode>(ScheduleMode.list);

const _changed = Color(0xFFB45F00);

/// The tint of a day under a [CalendarBreak], and the colour of its label.
(Color, Color) breakColors(BreakKind k) => switch (k) {
  BreakKind.holiday => (const Color(0xFFFFF1C2), const Color(0xFF8A5A00)),
  BreakKind.ramadan => (const Color(0xFFE0F2E6), const Color(0xFF1C7A55)),
  BreakKind.pause => (const Color(0xFFE6E9EE), RaeedColors.grey),
};

const _shortDays = ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

/// أسبوع | شهر, on top of a schedule.
class ScheduleModeToggle extends StatelessWidget {
  const ScheduleModeToggle({super.key, this.listLabel = 'أسبوع', this.listIcon = Icons.view_week_outlined});

  final String listLabel;
  final IconData listIcon;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ScheduleMode>(
    valueListenable: scheduleMode,
    builder: (context, mode, _) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: SegmentedButton<ScheduleMode>(
          key: const Key('schedule-mode'),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            selectedBackgroundColor: RaeedColors.blue,
            selectedForegroundColor: Colors.white,
          ),
          segments: [
            ButtonSegment(
              value: ScheduleMode.list,
              icon: Icon(listIcon, size: 18),
              label: Text(listLabel, key: const Key('mode-list')),
            ),
            const ButtonSegment(
              value: ScheduleMode.month,
              icon: Icon(Icons.calendar_month_outlined, size: 18),
              label: Text('شهر', key: Key('mode-month')),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => scheduleMode.value = s.first,
        ),
      ),
    ),
  );
}

/// Rebuilds [builder] when the schedule mode changes.
class ScheduleModeBuilder extends StatelessWidget {
  const ScheduleModeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ScheduleMode mode) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ScheduleMode>(
    valueListenable: scheduleMode,
    builder: (context, mode, _) => builder(context, mode),
  );
}

/// A month on a grid, Sunday first (on the right). Each day shows a dot per حصة
/// (blue, orange when it changed, red when it is cancelled or replaced by a نشاط نوعي),
/// and each نشاط نوعي is a coloured bar across the days it covers. Tapping a day lists
/// that day's items under the grid, built by [dayItems].
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.now,
    required this.sessions,
    required this.activities,
    required this.replacedBy,
    required this.dayItems,
    this.breaks = const [],
    this.emptyDay = 'لا حصص ولا أنشطة في هذا اليوم.',
  });

  final DateTime now;
  final List<Session> sessions;
  final List<SpecialActivity> activities;
  final SpecialActivity? Function(Session s) replacedBy;

  /// Holidays, Ramadan and the academy's stops that concern these فئات.
  final List<CalendarBreak> breaks;

  /// The cards for one day: its activities, then its sessions.
  final List<Widget> Function(BuildContext context, DateTime day) dayItems;
  final String emptyDay;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month = DateTime(widget.now.year, widget.now.month);
  DateTime? _selected;

  bool _inMonth(DateTime d) => d.year == _month.year && d.month == _month.month;

  void _go(int by) => setState(() {
    _month = DateTime(_month.year, _month.month + by);
    _selected = null;
  });

  DateTime _defaultDay(Map<DateTime, List<Session>> byDay) {
    final today = dayOnly(widget.now);
    if (_inMonth(today)) return today;
    final busy = [
      ...byDay.keys.where(_inMonth),
      for (final a in widget.activities)
        for (var d = a.startDate; !d.isAfter(a.endDate); d = DateTime(d.year, d.month, d.day + 1))
          if (_inMonth(d)) d,
    ]..sort();
    return busy.firstOrNull ?? _month;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = widget.now;
    final today = dayOnly(now);
    final byDay = <DateTime, List<Session>>{};
    for (final s in widget.sessions) {
      (byDay[dayOnly(s.date)] ??= []).add(s);
    }
    final selected = _selected ?? _defaultDay(byDay);

    // Whole weeks, Sunday to Saturday, around the month.
    final first = _month;
    final last = DateTime(_month.year, _month.month + 1, 0);
    final gridStart = first.subtract(Duration(days: dayOfWeek(first)));
    final gridEnd = last.add(Duration(days: 6 - dayOfWeek(last)));
    final weeks = <DateTime>[for (var w = gridStart; !w.isAfter(gridEnd); w = DateTime(w.year, w.month, w.day + 7)) w];

    final monthSessions = widget.sessions.where((s) => _inMonth(s.date)).toList();
    final monthActivities = widget.activities
        .where((a) => !a.endDate.isBefore(first) && !a.startDate.isAfter(last))
        .toList();
    final off = monthSessions.where((s) => s.cancelled || widget.replacedBy(s) != null).length;
    final summary = [
      countLabel(monthSessions.length, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة'),
      if (off > 0) '$off ملغاة',
      if (monthActivities.isNotEmpty)
        countLabel(
          monthActivities.length,
          one: 'نشاط نوعي',
          two: 'نشاطان نوعيان',
          few: 'أنشطة نوعية',
          many: 'نشاطاً نوعياً',
        ),
    ].join(' · ');

    final items = widget.dayItems(context, selected);
    final dayBreaks = widget.breaks.where((b) => b.covers(selected)).toList();
    final monthKinds = {
      for (final b in widget.breaks)
        if (!b.endDate.isBefore(gridStart) && !b.startDate.isAfter(gridEnd)) b.kind,
    };
    return Column(
      key: const Key('month-calendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('calendar-previous-month'),
              tooltip: 'الشهر السابق',
              onPressed: () => _go(-1),
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${monthNames[_month.month - 1]} ${_month.year}',
                    key: const Key('calendar-month-label'),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(summary, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                ],
              ),
            ),
            IconButton(
              key: const Key('calendar-next-month'),
              tooltip: 'الشهر التالي',
              onPressed: () => _go(1),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final d in _shortDays)
                      Expanded(
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: text.labelSmall?.copyWith(color: RaeedColors.grey, fontSize: 10.5),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final w in weeks)
                  _WeekRow(
                    start: w,
                    inMonth: _inMonth,
                    today: today,
                    selected: selected,
                    byDay: byDay,
                    breaks: widget.breaks,
                    activities: widget.activities,
                    replacedBy: widget.replacedBy,
                    onTap: (d) => setState(() {
                      if (!_inMonth(d)) _month = DateTime(d.year, d.month);
                      _selected = d;
                    }),
                  ),
                const SizedBox(height: 4),
                _Legend(breaks: monthKinds),
              ],
            ),
          ),
        ),
        SectionLabel(dayLabel(selected, now)),
        for (final b in dayBreaks) _BreakNote(b),
        if (items.isEmpty && dayBreaks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              widget.emptyDay,
              key: const Key('calendar-empty-day'),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
            ),
          )
        else
          ...items,
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.start,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.byDay,
    required this.breaks,
    required this.activities,
    required this.replacedBy,
    required this.onTap,
  });

  /// The day's number, then its حصص as dots right under it.
  static const _numberHeight = 40.0;
  static const _barHeight = 15.0;
  static const _lanes = 2;
  static const _height = _numberHeight + _lanes * (_barHeight + 2) + 4;

  final DateTime start;
  final bool Function(DateTime) inMonth;
  final DateTime today;
  final DateTime selected;
  final Map<DateTime, List<Session>> byDay;
  final List<CalendarBreak> breaks;
  final List<SpecialActivity> activities;
  final SpecialActivity? Function(Session) replacedBy;
  final ValueChanged<DateTime> onTap;

  /// The break that tints [day]: a stop or a holiday shows over Ramadan.
  BreakKind? _shownBreak(DateTime day) {
    BreakKind? shown;
    for (final b in breaks) {
      if (!b.covers(day)) continue;
      if (shown == null || shown == BreakKind.ramadan || b.kind == BreakKind.pause) shown = b.kind;
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final end = start.add(const Duration(days: 6));
    final days = [for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i)];

    // Activities in this week, each in the first lane free over its days.
    final inWeek = activities.where((a) => !a.endDate.isBefore(start) && !a.startDate.isAfter(end)).toList()
      ..sort((a, b) {
        final byStart = a.startDate.compareTo(b.startDate);
        return byStart != 0 ? byStart : b.dayCount.compareTo(a.dayCount);
      });
    final laneEnds = <int>[];
    final bars = <({SpecialActivity a, int from, int to, int lane})>[];
    final hidden = List<int>.filled(7, 0);
    for (final a in inWeek) {
      final from = a.startDate.isBefore(start) ? 0 : a.startDate.difference(start).inDays;
      final to = a.endDate.isAfter(end) ? 6 : a.endDate.difference(start).inDays;
      var lane = laneEnds.indexWhere((e) => e < from);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(to);
      } else {
        laneEnds[lane] = to;
      }
      if (lane < _lanes) {
        bars.add((a: a, from: from, to: to, lane: lane));
      } else {
        for (var i = from; i <= to; i++) {
          hidden[i]++;
        }
      }
    }

    return Container(
      height: _height,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: RaeedColors.line.withValues(alpha: 0.6))),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final cell = box.maxWidth / 7;
          return Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      width: cell,
                      child: _DayCell(
                        day: days[i],
                        faded: !inMonth(days[i]),
                        isToday: days[i] == today,
                        isSelected: days[i] == selected,
                        sessions: byDay[days[i]] ?? const [],
                        replacedBy: replacedBy,
                        off: _shownBreak(days[i]),
                        hidden: hidden[i],
                        onTap: () => onTap(days[i]),
                      ),
                    ),
                ],
              ),
              for (final b in bars)
                PositionedDirectional(
                  start: b.from * cell + 2,
                  width: (b.to - b.from + 1) * cell - 4,
                  top: _numberHeight + b.lane * (_barHeight + 2),
                  height: _barHeight,
                  child: IgnorePointer(
                    child: _Bar(
                      activity: b.a,
                      // Rounded only where it really starts or ends, so a camp reads as one block.
                      opensHere: !b.a.startDate.isBefore(days[b.from]),
                      closesHere: !b.a.endDate.isAfter(days[b.to]),
                      style: text.labelSmall,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.activity, required this.opensHere, required this.closesHere, this.style});

  final SpecialActivity activity;
  final bool opensHere;
  final bool closesHere;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final (fg, bg) = activityColors(a.kind);
    const r = Radius.circular(6);
    return Container(
      key: Key('calendar-bar-${a.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: a.cancelled ? RaeedColors.surfaceAlt : bg,
        border: Border.all(color: a.cancelled ? RaeedColors.line : fg, width: 1),
        borderRadius: BorderRadiusDirectional.horizontal(
          start: opensHere ? r : Radius.zero,
          end: closesHere ? r : Radius.zero,
        ),
      ),
      child: Text(
        '${a.kind.emoji} ${a.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: style?.copyWith(
          fontSize: 9.5,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: a.cancelled ? RaeedColors.grey : fg,
          decoration: a.cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.faded,
    required this.isToday,
    required this.isSelected,
    required this.sessions,
    required this.replacedBy,
    required this.off,
    required this.hidden,
    required this.onTap,
  });

  final DateTime day;
  final bool faded;
  final bool isToday;
  final bool isSelected;
  final List<Session> sessions;
  final SpecialActivity? Function(Session) replacedBy;

  /// The break this day falls in, which tints it.
  final BreakKind? off;
  final int hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Color dot(Session s) {
      if (s.cancelled || replacedBy(s) != null) return RaeedColors.error;
      if (s.status == SessionStatus.changed) return _changed;
      return RaeedColors.blue;
    }

    final shown = sessions.take(3).toList();
    return InkWell(
      key: Key('calendar-day-${dbDay(day)}'),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: off == null ? null : breakColors(off!).$1,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Opacity(
          opacity: faded ? 0.4 : 1,
          child: Column(
            children: [
              const SizedBox(height: 2),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? RaeedColors.blue : null,
                  border: isToday && !isSelected ? Border.all(color: RaeedColors.blue, width: 1.5) : null,
                ),
                child: Text(
                  '${day.day}',
                  style: text.bodySmall?.copyWith(
                    fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : RaeedColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final s in shown)
                      Container(
                        key: Key('calendar-dot-${s.id}'),
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: dot(s)),
                      ),
                    if (sessions.length + hidden > shown.length)
                      Text(
                        '+${sessions.length + hidden - shown.length}',
                        style: text.labelSmall?.copyWith(fontSize: 8, color: RaeedColors.grey, height: 1),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({this.breaks = const {}});

  /// The kinds of break on the grid, each given its tint.
  final Set<BreakKind> breaks;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: RaeedColors.grey);
    Widget item(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
    Widget dot(Color c) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    );
    final (fg, bg) = activityColors(ActivityKind.camp);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        item(dot(RaeedColors.blue), 'حصة'),
        item(dot(_changed), 'تغيّرت'),
        item(dot(RaeedColors.error), 'ملغاة'),
        item(
          Container(
            width: 16,
            height: 8,
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: fg),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          'نشاط نوعي',
        ),
        for (final k in BreakKind.values)
          if (breaks.contains(k))
            item(
              Container(
                width: 12,
                height: 10,
                decoration: BoxDecoration(color: breakColors(k).$1, borderRadius: BorderRadius.circular(3)),
              ),
              k.label,
            ),
      ],
    );
  }
}

/// «عطلة · العطلة البينية الثانية», above a day's cards.
class _BreakNote extends StatelessWidget {
  const _BreakNote(this.b);

  final CalendarBreak b;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = breakColors(b.kind);
    final text = Theme.of(context).textTheme;
    final span = b.startDate == b.endDate
        ? ''
        : ' · من ${b.startDate.day} ${monthNames[b.startDate.month - 1]} إلى ${b.endDate.day} ${monthNames[b.endDate.month - 1]}';
    return Container(
      key: Key('calendar-break-${b.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(
            switch (b.kind) {
              BreakKind.holiday => Icons.beach_access_outlined,
              BreakKind.ramadan => Icons.nightlight_outlined,
              BreakKind.pause => Icons.pause_circle_outline,
            },
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.title == b.kind.label ? '${b.title}$span' : '${b.kind.label} · ${b.title}$span',
              style: text.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

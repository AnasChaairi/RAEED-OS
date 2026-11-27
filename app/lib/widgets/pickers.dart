import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../instructor/models.dart' show dayOnly, longDay, monthNames, weekdayNames;
import '../theme/raeed_theme.dart';

/// Opens the time sheet: hour buttons, then the minutes. Returns minutes after midnight.
Future<int?> showTimeSheet(BuildContext context, {required String title, int? initial}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TimeSheet(title: title, initial: initial),
    );

/// Opens the next two weeks as day cards, with the whole month one tap away. For session dates.
Future<DateTime?> showUpcomingDateSheet(
  BuildContext context, {
  required String title,
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? today,
}) =>
    showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UpcomingDateSheet(
        title: title,
        initial: initial,
        firstDate: dayOnly(firstDate),
        lastDate: dayOnly(lastDate),
        today: dayOnly(today ?? DateTime.now()),
      ),
    );

/// Opens day, month and year wheels. For dates far from today, such as a birth date.
Future<DateTime?> showDateWheelsSheet(
  BuildContext context, {
  required String title,
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
}) =>
    showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DateWheelsSheet(
        title: title,
        initial: _clamp(dayOnly(initial ?? DateTime.now()), dayOnly(firstDate), dayOnly(lastDate)),
        firstDate: dayOnly(firstDate),
        lastDate: dayOnly(lastDate),
      ),
    );

DateTime _clamp(DateTime d, DateTime lo, DateTime hi) => d.isBefore(lo) ? lo : (d.isAfter(hi) ? hi : d);

const _numbers = TextStyle(fontFamily: RaeedFonts.display, fontWeight: FontWeight.w700, color: RaeedColors.ink);

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, this.trailing, required this.children, required this.onDone});

  final String title;
  final String? trailing;
  final List<Widget> children;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (trailing != null)
                  Text(trailing!, key: const Key('picker-summary'), style: const TextStyle(color: RaeedColors.grey)),
              ]),
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton(key: const Key('picker-done'), onPressed: onDone, child: const Text('تم')),
                ),
                const SizedBox(width: 10),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ]),
            ],
          ),
        ),
      );
}

/// A rounded button showing a number, filled when selected.
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap, this.width = 52});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? RaeedColors.blue : RaeedColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? RaeedColors.blue : RaeedColors.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: 44,
              child: Center(
                child: Text(label, style: _numbers.copyWith(fontSize: 19, color: selected ? Colors.white : RaeedColors.ink)),
              ),
            ),
          ),
        ),
      );
}

class _TimeSheet extends StatefulWidget {
  const _TimeSheet({required this.title, this.initial});

  final String title;
  final int? initial;

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  late int? _hour = widget.initial == null ? null : widget.initial! ~/ 60;
  late int _minute = widget.initial == null ? 0 : widget.initial! % 60;

  @override
  Widget build(BuildContext context) {
    final hours = {for (var h = 8; h <= 21; h++) h, ?_hour}.toList()..sort();
    final minutes = {0, 15, 30, 45, _minute}.toList()..sort();
    String two(int n) => n.toString().padLeft(2, '0');
    const label = TextStyle(color: RaeedColors.grey, fontWeight: FontWeight.w600);
    return _Sheet(
      title: widget.title,
      onDone: _hour == null ? null : () => Navigator.pop(context, _hour! * 60 + _minute),
      children: [
        Center(
          child: Text(
            _hour == null ? '--:${two(_minute)}' : '${two(_hour!)}:${two(_minute)}',
            key: const Key('time-preview'),
            textDirection: TextDirection.ltr,
            style: _numbers.copyWith(fontSize: 52, color: _hour == null ? RaeedColors.grey : RaeedColors.blue),
          ),
        ),
        const SizedBox(height: 6),
        const Text('الساعة', style: label),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final h in hours)
                _Choice(
                  key: Key('time-hour-$h'),
                  label: '$h',
                  selected: h == _hour,
                  onTap: () => setState(() => _hour = h),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('الدقائق', style: label),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              for (final (i, m) in minutes.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => _Choice(
                      key: Key('time-minute-$m'),
                      label: two(m),
                      width: c.maxWidth,
                      selected: m == _minute,
                      onTap: () => setState(() => _minute = m),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UpcomingDateSheet extends StatefulWidget {
  const _UpcomingDateSheet({
    required this.title,
    this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.today,
  });

  final String title;
  final DateTime? initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime today;

  @override
  State<_UpcomingDateSheet> createState() => _UpcomingDateSheetState();
}

class _UpcomingDateSheetState extends State<_UpcomingDateSheet> {
  late DateTime? _selected = widget.initial == null ? null : dayOnly(widget.initial!);
  /// The first card: today, or the first allowed day if that is later.
  late final DateTime _start = widget.today.isBefore(widget.firstDate) ? widget.firstDate : widget.today;
  late bool _month = _selected != null && !_inWindow(_selected!);
  late DateTime _shownMonth = DateTime((_selected ?? _start).year, (_selected ?? _start).month);

  bool _inWindow(DateTime d) => !d.isBefore(_start) && d.isBefore(_start.add(const Duration(days: 14)));

  bool _allowed(DateTime d) => !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: widget.title,
      trailing: _selected == null ? null : longDay(_selected!),
      onDone: _selected == null ? null : () => Navigator.pop(context, _selected),
      children: [
        if (_month) _monthView() else ..._cards(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('date-toggle-month'),
            onPressed: () => setState(() => _month = !_month),
            icon: Icon(_month ? Icons.view_week_outlined : Icons.calendar_month_outlined),
            label: Text(_month ? 'الأسبوعان القادمان' : 'تاريخ أبعد: الشهر كاملاً'),
          ),
        ),
      ],
    );
  }

  List<Widget> _cards() => [
        for (final week in const [0, 7])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _card(DateTime(_start.year, _start.month, _start.day + week + i)),
                  ),
                ),
            ]),
          ),
      ];

  Widget _card(DateTime d) {
    final selected = d == _selected;
    final allowed = _allowed(d);
    final name = d == widget.today
        ? 'اليوم'
        : d == widget.today.add(const Duration(days: 1))
            ? 'غداً'
            : weekdayNames[d.weekday % 7];
    final ink = selected ? Colors.white : (allowed ? RaeedColors.ink : RaeedColors.line);
    final soft = selected ? Colors.white : (allowed ? RaeedColors.grey : RaeedColors.line);
    return Semantics(
      button: true,
      selected: selected,
      label: longDay(d),
      child: InkWell(
        key: Key('date-day-${d.year}-${d.month}-${d.day}'),
        borderRadius: BorderRadius.circular(16),
        onTap: allowed ? () => setState(() => _selected = d) : null,
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? RaeedColors.sky : null,
            color: selected ? null : RaeedColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: selected ? null : Border.all(color: RaeedColors.line),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(fontSize: 11, color: soft)),
            Text('${d.day}', style: _numbers.copyWith(fontSize: 23, color: ink, height: 1.2)),
            Text(monthNames[d.month - 1], maxLines: 1, softWrap: false, style: TextStyle(fontSize: 10, color: soft)),
          ]),
        ),
      ),
    );
  }

  Widget _monthView() {
    final m = _shownMonth;
    final lead = (DateTime(m.year, m.month).weekday + 6) % 7; // weeks start on Monday
    final days = DateUtils.getDaysInMonth(m.year, m.month);
    final canBack = DateTime(m.year, m.month).isAfter(DateTime(widget.firstDate.year, widget.firstDate.month));
    final canForward = DateTime(m.year, m.month).isBefore(DateTime(widget.lastDate.year, widget.lastDate.month));
    const initials = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        IconButton(
          key: const Key('month-back'),
          tooltip: 'الشهر السابق',
          onPressed: canBack ? () => setState(() => _shownMonth = DateTime(m.year, m.month - 1)) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        Expanded(
          child: Center(child: Text('${monthNames[m.month - 1]} ${m.year}', style: _numbers.copyWith(fontSize: 21))),
        ),
        IconButton(
          key: const Key('month-forward'),
          tooltip: 'الشهر التالي',
          onPressed: canForward ? () => setState(() => _shownMonth = DateTime(m.year, m.month + 1)) : null,
          icon: const Icon(Icons.chevron_left),
        ),
      ]),
      Row(children: [
        for (final s in initials)
          Expanded(
            child: Center(child: Text(s, style: const TextStyle(color: RaeedColors.grey, fontWeight: FontWeight.w600))),
          ),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < lead; i++) const SizedBox(),
          for (var day = 1; day <= days; day++) _monthDay(DateTime(m.year, m.month, day)),
        ],
      ),
    ]);
  }

  Widget _monthDay(DateTime d) {
    final selected = d == _selected;
    final allowed = _allowed(d);
    return Center(
      child: InkWell(
        key: Key('date-day-${d.year}-${d.month}-${d.day}'),
        customBorder: const CircleBorder(),
        onTap: allowed ? () => setState(() => _selected = d) : null,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: selected ? RaeedColors.sky : null,
            shape: BoxShape.circle,
            border: d == widget.today && !selected ? Border.all(color: RaeedColors.blue, width: 1.5) : null,
          ),
          child: Center(
            child: Text(
              '${d.day}',
              style: _numbers.copyWith(
                fontSize: 17,
                color: selected ? Colors.white : (allowed ? RaeedColors.ink : RaeedColors.line),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateWheelsSheet extends StatefulWidget {
  const _DateWheelsSheet({required this.title, required this.initial, required this.firstDate, required this.lastDate});

  final String title;
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DateWheelsSheet> createState() => _DateWheelsSheetState();
}

class _DateWheelsSheetState extends State<_DateWheelsSheet> {
  late int _day = widget.initial.day;
  late int _month = widget.initial.month;
  late int _year = widget.initial.year;
  late final _dayWheel = FixedExtentScrollController(initialItem: _day - 1);
  late final _monthWheel = FixedExtentScrollController(initialItem: _month - 1);
  late final _yearWheel = FixedExtentScrollController(initialItem: _year - widget.firstDate.year);

  @override
  void dispose() {
    _dayWheel.dispose();
    _monthWheel.dispose();
    _yearWheel.dispose();
    super.dispose();
  }

  /// The chosen date, with the day shortened to fit the month and kept within the limits.
  DateTime get _value {
    final day = _day.clamp(1, DateUtils.getDaysInMonth(_year, _month));
    return _clamp(DateTime(_year, _month, day), widget.firstDate, widget.lastDate);
  }

  Widget _wheel({
    required Key key,
    required FixedExtentScrollController controller,
    required List<String> items,
    required ValueChanged<int> onChanged,
    required int flex,
  }) =>
      Expanded(
        flex: flex,
        child: SizedBox(
          height: 200,
          child: CupertinoPicker(
            key: key,
            scrollController: controller,
            itemExtent: 46,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                color: RaeedColors.blue.withValues(alpha: 0.08),
                border: Border.symmetric(horizontal: BorderSide(color: RaeedColors.blue.withValues(alpha: 0.35))),
              ),
            ),
            onSelectedItemChanged: (i) => setState(() => onChanged(i)),
            children: [for (final i in items) Center(child: Text(i, style: _numbers.copyWith(fontSize: 22)))],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return _Sheet(
      title: widget.title,
      trailing: '${value.day} ${monthNames[value.month - 1]} ${value.year}',
      onDone: () => Navigator.pop(context, value),
      children: [
        Row(children: [
          _wheel(
            key: const Key('wheel-day'),
            controller: _dayWheel,
            items: [for (var d = 1; d <= 31; d++) '$d'],
            onChanged: (i) => _day = i + 1,
            flex: 2,
          ),
          _wheel(
            key: const Key('wheel-month'),
            controller: _monthWheel,
            items: monthNames,
            onChanged: (i) => _month = i + 1,
            flex: 4,
          ),
          _wheel(
            key: const Key('wheel-year'),
            controller: _yearWheel,
            items: [for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) '$y'],
            onChanged: (i) => _year = widget.firstDate.year + i,
            flex: 3,
          ),
        ]),
      ],
    );
  }
}

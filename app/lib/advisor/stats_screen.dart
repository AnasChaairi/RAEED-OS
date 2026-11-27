import 'package:flutter/material.dart';

import '../instructor/models.dart';
import '../profile/child_profile_screen.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'pilot_screen.dart';
import 'stats_models.dart';
import 'stats_store.dart';

const _low = 0.8;
const _star = Color(0xFFF06C00);

/// The advisor's الإحصائيات tab: the academy's numbers, the attendance trend, what needs
/// attention, and attendance by فئة, weakest first.
class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StatsScope.of(context);
    final stats = store.stats;
    if (stats == null) {
      return Center(
        child: store.failure == null || store.loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(setupFailureMessage(store.failure!), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: store.load, child: const Text('حاول مرة أخرى')),
                ],
              ),
      );
    }
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: store.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final p in StatsPeriod.values)
                ChoiceChip(
                  key: Key('period-${p.name}'),
                  label: Text(p.label),
                  selected: p == store.period,
                  onSelected: (_) => store.choosePeriod(p),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Kpi(value: stats.groupCount, label: 'فئات'),
              const SizedBox(width: 8),
              _Kpi(value: stats.instructorCount, label: 'مؤطرون'),
              const SizedBox(width: 8),
              _Kpi(value: stats.childCount, label: 'أطفال'),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('نسبة الحضور', style: text.bodyMedium?.copyWith(color: RaeedColors.grey)),
                      ),
                      Text(
                        percent(stats.rate),
                        key: const Key('stats-rate'),
                        style: text.headlineMedium?.copyWith(
                          fontFamily: RaeedFonts.display,
                          fontWeight: FontWeight.w700,
                          color: RaeedColors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: CustomPaint(painter: _Sparkline(stats.weeks)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.period.label} · ${countLabel(stats.sessionsHeld, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة')} · الخط: آخر 5 أسابيع · الحضور والتأخر محسوبان',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MonthlyTrend(stats.months, change: stats.monthChange),
          const SectionLabel('متابعة الأطفال'),
          _AttentionRow(
            key: const Key('attention-threshold'),
            label: 'تجاوزوا 25% غياباً من الحصص',
            hint: '${stats.period.label} · 3 حصص مسجّلة على الأقل',
            value: stats.overThreshold.length,
            color: RaeedColors.error,
            soft: const Color(0xFFFDE8E3),
            onTap: () => _openChildren(
              context,
              title: 'تجاوزوا 25% غياباً',
              explain:
                  'الأطفال الذين غابوا (غائب أو معذور) عن أكثر من 25% من حصصهم المسجّلة · ${stats.period.label}. الحصص الملغاة أو التي عوّضها نشاط نوعي لا تُحسب.',
              rows: stats.overThreshold,
              line: (c) => 'غاب ${c.count} من ${c.of} حصص · ${percent(c.count / c.of)}',
            ),
          ),
          const SizedBox(height: 6),
          _AttentionRow(
            key: const Key('attention-repeated-absence'),
            label: 'غياب متكرر',
            hint: '3 مرات أو أكثر في آخر 30 يوماً',
            value: stats.repeatedAbsence.length,
            color: RaeedColors.error,
            soft: const Color(0xFFFDE8E3),
            onTap: () => _openChildren(
              context,
              title: 'غياب متكرر',
              explain: 'الأطفال الذين غابوا (غائب أو معذور) 3 مرات أو أكثر في آخر 30 يوماً.',
              rows: stats.repeatedAbsence,
              line: (c) => 'غاب ${c.count} مرات من ${c.of} حصص',
            ),
          ),
          const SizedBox(height: 6),
          _AttentionRow(
            key: const Key('attention-repeated-late'),
            label: 'تأخر متكرر',
            hint: '3 مرات أو أكثر في آخر 30 يوماً',
            value: stats.repeatedLate.length,
            color: const Color(0xFFB45F00),
            soft: const Color(0xFFFFF4DA),
            onTap: () => _openChildren(
              context,
              title: 'تأخر متكرر',
              explain: 'الأطفال الذين تأخروا 3 مرات أو أكثر في آخر 30 يوماً.',
              rows: stats.repeatedLate,
              line: (c) => 'تأخر ${c.count} مرات من ${c.of} حصص',
            ),
          ),
          const SectionLabel('يحتاج انتباهك'),
          _AttentionRow(
            key: const Key('attention-alerts'),
            label: 'تنبيهات غياب مفتوحة',
            value: stats.openAlerts,
            color: RaeedColors.error,
            soft: const Color(0xFFFDE8E3),
          ),
          const SizedBox(height: 6),
          _AttentionRow(
            key: const Key('attention-unrecorded'),
            label: 'حصص بدون تسجيل حضور',
            value: stats.sessionsWithoutAttendance,
            color: const Color(0xFFB45F00),
            soft: const Color(0xFFFFF4DA),
          ),
          const SizedBox(height: 6),
          _AttentionRow(
            key: const Key('attention-instructors'),
            label: 'مؤطرون لم يسجلوا معطيات حصصهم',
            hint: stats.period.label,
            value: stats.unrecorded.length,
            color: const Color(0xFFB45F00),
            soft: const Color(0xFFFFF4DA),
            onTap: () =>
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const UnrecordedInstructorsScreen())),
          ),
          const SectionLabel('الحصص حسب الفئة · المنجزة من المبرمجة'),
          _ProgrammedByGroup(stats),
          const SectionLabel('الحضور حسب الفئة · مرتبة من الأضعف'),
          if (stats.groups.isEmpty)
            Text('لا فئات بعد.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey))
          else
            Card(
              child: Column(
                children: [
                  for (final g in stats.groups)
                    InkWell(
                      key: Key('stats-group-${g.group.id}'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => GroupStatsScreen(groupId: g.group.id)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 96,
                              child: Text(g.group.name, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: g.rate ?? 0,
                                  minHeight: 8,
                                  backgroundColor: RaeedColors.surfaceAlt,
                                  color: (g.rate ?? 1) < _low ? _star : RaeedColors.blue,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              child: Text(
                                percent(g.rate),
                                textAlign: TextAlign.end,
                                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              key: const Key('open-pilot'),
              leading: const Icon(Icons.flag_outlined, color: RaeedColors.blue),
              title: const Text('مؤشرات التجربة'),
              subtitle: const Text('التسجيل في الوقت، مدة التسجيل، المتابعة، دخول الأسر'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PilotScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(
                '$value',
                style: text.headlineSmall?.copyWith(fontFamily: RaeedFonts.display, fontWeight: FontWeight.w700),
              ),
              Text(label, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.soft,
    this.hint,
    this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final Color soft;
  final String? hint;

  /// Opens the names behind [value]; only offered when there are some.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = value > 0;
    final tap = on ? onTap : null;
    return Material(
      color: on ? soft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: on ? BorderSide.none : const BorderSide(color: Color(0xFFD7E4F2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: text.bodyMedium),
                    if (hint != null) Text(hint!, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                  ],
                ),
              ),
              Text(
                '$value',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: on ? color : RaeedColors.grey),
              ),
              if (tap != null) const Icon(Icons.chevron_left, color: RaeedColors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

void _openChildren(
  BuildContext context, {
  required String title,
  required String explain,
  required List<ChildCount> rows,
  required String Function(ChildCount) line,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => ChildCountScreen(title: title, explain: explain, rows: rows, line: line),
  ),
);

/// The children behind one of the follow-up numbers; a name opens the child's file.
class ChildCountScreen extends StatelessWidget {
  const ChildCountScreen({
    super.key,
    required this.title,
    required this.explain,
    required this.rows,
    required this.line,
  });

  final String title;
  final String explain;
  final List<ChildCount> rows;
  final String Function(ChildCount) line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final groups = {for (final g in StatsScope.of(context).data?.groups ?? const []) g.id: g.name};
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(explain, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (final c in rows)
                  ListTile(
                    key: Key('count-kid-${c.child.id}'),
                    leading: InitialAvatar(c.child.fullName, size: 32),
                    title: Text(c.child.fullName),
                    subtitle: Text([?groups[c.child.groupId], line(c)].join(' · ')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => openChildProfile(context, c.child.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Instructors with حصص in the period that ended without attendance, and those حصص.
class UnrecordedInstructorsScreen extends StatelessWidget {
  const UnrecordedInstructorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StatsScope.of(context);
    final stats = store.stats;
    final text = Theme.of(context).textTheme;
    final groups = {for (final g in store.data?.groups ?? const []) g.id: g.name};
    final rows = stats?.unrecorded ?? const <InstructorGap>[];
    return Scaffold(
      appBar: AppBar(title: const Text('حصص بلا معطيات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'حصص انتهت دون تسجيل الحضور · ${store.period.label}. تُنسب الحصة إلى المؤطرين المكلّفين بها، ومن أبلغ بغيابه عنها لا يُحسب.',
            style: text.bodySmall?.copyWith(color: RaeedColors.grey),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) Text('سجّل الجميع حصصهم.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey)),
          for (final r in rows)
            Card(
              key: Key('gap-${r.personId}'),
              child: ExpansionTile(
                leading: InitialAvatar(r.name, size: 32),
                title: Text(r.name),
                subtitle: Text(countLabel(r.sessions.length, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة')),
                shape: const Border(),
                children: [
                  for (final s in r.sessions)
                    ListTile(
                      dense: true,
                      title: Text(longDay(s.date)),
                      subtitle: Text(
                        [
                          ?groups[s.groupId],
                          if (s.start != null) '${formatTime(s.start!)} – ${formatTime(s.end)}',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Programmed and completed حصص of each فئة in the period.
class _ProgrammedByGroup extends StatelessWidget {
  const _ProgrammedByGroup(this.stats);

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = [...stats.groups]..sort((a, b) => a.group.name.compareTo(b.group.name));
    if (rows.isEmpty) return Text('لا فئات بعد.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey));
    final done = rows.fold(0, (n, g) => n + g.recorded);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in rows)
              Padding(
                key: Key('programmed-${g.group.id}'),
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(width: 96, child: Text(g.group.name, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: g.programmed == 0 ? 0 : g.recorded / g.programmed,
                          minHeight: 8,
                          backgroundColor: RaeedColors.surfaceAlt,
                          color: RaeedColors.blue,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${g.recorded} / ${g.programmed}',
                        textAlign: TextAlign.end,
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'المجموع: $done منجزة من ${stats.programmed} مبرمجة · ${stats.period.label} كاملاً · المنجزة = انتهت وسُجّل حضورها · بدون الملغاة وما عوّضه نشاط نوعي',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// The attendance rate month by month since the season began. A bar shows its month's
/// rate when tapped; the latest is shown first.
class _MonthlyTrend extends StatefulWidget {
  const _MonthlyTrend(this.months, {required this.change});

  final List<MonthRate> months;
  final int? change;

  @override
  State<_MonthlyTrend> createState() => _MonthlyTrendState();
}

class _MonthlyTrendState extends State<_MonthlyTrend> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final months = widget.months;
    final lastRated = months.lastIndexWhere((m) => m.rate != null);
    final shown = _picked != null && _picked! < months.length ? _picked! : (lastRated < 0 ? null : lastRated);
    final change = widget.change;
    final (String trend, Color color, IconData icon) = switch (change) {
      null => ('شهران مسجّلان على الأقل لمعرفة الاتجاه', RaeedColors.grey, Icons.remove),
      0 => ('مستقرة مقارنة بالشهر السابق', RaeedColors.grey, Icons.trending_flat),
      > 0 => ('في تحسن: +$change نقطة مقارنة بالشهر السابق', const Color(0xFF1C7A55), Icons.trending_up),
      _ => ('في تراجع: $change نقطة مقارنة بالشهر السابق', RaeedColors.error, Icons.trending_down),
    };
    return Card(
      key: const Key('monthly-trend'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تطور الحضور شهرياً', style: text.bodyMedium?.copyWith(color: RaeedColors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trend,
                    key: const Key('monthly-change'),
                    style: text.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (shown != null)
              Text(
                '${monthNames[months[shown].month.month - 1]} ${months[shown].month.year}: ${percent(months[shown].rate)}'
                ' · ${countLabel(months[shown].sessions, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة')}',
                key: const Key('monthly-picked'),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: RaeedColors.ink),
              ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < months.length; i++)
                    Expanded(
                      child: GestureDetector(
                        key: Key('month-${months[i].month.year}-${months[i].month.month}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _picked = i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (months[i].rate ?? 0).clamp(0.0, 1.0).toDouble(),
                                  child: Container(
                                    width: 18,
                                    decoration: BoxDecoration(
                                      color: i == shown ? RaeedColors.blue : RaeedColors.blue.withValues(alpha: 0.35),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(height: 1, color: RaeedColors.line),
                            const SizedBox(height: 4),
                            Text(
                              months[i].rate == null ? '—' : monthNames[months[i].month.month - 1],
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: text.labelSmall?.copyWith(
                                color: i == shown ? RaeedColors.ink : RaeedColors.grey,
                                fontSize: months.length > 8 ? 9 : 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'منذ بداية الموسم · اضغط على شهر لرؤية نسبته · الحضور والتأخر محسوبان، والحصص الملغاة أو التي عوّضها نشاط نوعي لا تُحسب',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// The weekly rate as a line; weeks with nothing recorded are skipped.
class _Sparkline extends CustomPainter {
  _Sparkline(this.weeks);

  final List<double?> weeks;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 4;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = const Color(0xFFD7E4F2));
    final points = <Offset>[];
    for (var i = 0; i < weeks.length; i++) {
      final w = weeks[i];
      if (w == null) continue;
      // Oldest on the left, this week on the right, as in the design.
      final x = weeks.length == 1 ? size.width / 2 : size.width * i / (weeks.length - 1);
      points.add(Offset(x, base - (base - 4) * w));
    }
    if (points.isEmpty) return;
    final line = Paint()
      ..color = RaeedColors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(points.last.dx, base)
      ..lineTo(points.first.dx, base)
      ..close();
    canvas.drawPath(area, Paint()..color = RaeedColors.blue.withValues(alpha: 0.12));
    canvas.drawPath(path, line);
    canvas.drawCircle(points.last, 3, Paint()..color = RaeedColors.blue);
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.weeks != weeks;
}

/// One فئة's numbers for the chosen period, and its children's attendance.
class GroupStatsScreen extends StatelessWidget {
  const GroupStatsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final store = StatsScope.of(context);
    final stats = store.stats;
    final g = stats?.groups.where((x) => x.group.id == groupId).firstOrNull;
    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم تعد هذه الفئة موجودة.')),
      );
    }
    final data = store.data!;
    final now = store.now();
    final text = Theme.of(context).textTheme;
    final kids = data.children.where((c) => c.groupId == groupId).toList();
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          children: [
            GroupLogo.of(g.group, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.group.name),
                  Text(
                    [?g.group.ageLabel, store.period.label].join(' · '),
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  line('نسبة الحضور', percent(g.rate)),
                  line('الأطفال', '${g.children}'),
                  line('المؤطرون', g.instructors.isEmpty ? 'لا أحد بعد' : g.instructors.join('، ')),
                  line('حصص مسجّلة الحضور', '${g.recorded} / ${g.sessions}'),
                  line('حصص منجزة من المبرمجة', '${g.recorded} / ${g.programmed}'),
                  line('تنبيهات مفتوحة', '${g.openAlerts}'),
                ],
              ),
            ),
          ),
          const SectionLabel('الأطفال'),
          if (kids.isEmpty)
            Text('لا يوجد أطفال في هذه الفئة.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey))
          else
            Card(
              child: Column(
                children: [
                  for (final k in kids)
                    () {
                      final rate = data.childRate(k.id, store.period, now);
                      return ListTile(
                        key: Key('stats-kid-${k.id}'),
                        leading: InitialAvatar(k.fullName, size: 32),
                        title: Text(k.fullName),
                        trailing: Text(
                          percent(rate),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: rate == null
                                ? RaeedColors.grey
                                : (rate < _low ? RaeedColors.error : const Color(0xFF1C7A55)),
                          ),
                        ),
                        onTap: () => openChildProfile(context, k.id),
                      );
                    }(),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text('اضغط على اسم لفتح ملف الطفل.', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
        ],
      ),
    );
  }
}

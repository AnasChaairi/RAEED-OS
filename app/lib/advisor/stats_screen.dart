import 'package:flutter/material.dart';

import '../profile/child_profile_screen.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
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
  const _AttentionRow({super.key, required this.label, required this.value, required this.color, required this.soft});

  final String label;
  final int value;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: on ? soft : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: on ? null : Border.all(color: const Color(0xFFD7E4F2)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(
            '$value',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: on ? color : RaeedColors.grey),
          ),
        ],
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

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/phone.dart';
import '../instructor/models.dart';
import '../instructor/widgets.dart' show statusColors;
import '../setup/models.dart' show ChildRegistration;
import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'profile_repository.dart';

Future<void> openChildProfile(BuildContext context, String childId) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChildProfileScreen(childId: childId)));

/// ملف الطفل: attendance pattern, follow-ups, notes and group history in one place.
class ChildProfileScreen extends StatefulWidget {
  const ChildProfileScreen({super.key, required this.childId});

  final String childId;

  @override
  State<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen> {
  ChildProfile? _profile;
  SetupFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    try {
      final p = await ProfileScope.of(context).repo.load(widget.childId);
      if (mounted) setState(() => _profile = p);
    } on SetupError catch (e) {
      if (mounted) setState(() => _failure = e.failure);
    }
  }

  Future<void> _addNote() async {
    final body = await showDialog<String>(context: context, builder: (_) => const _NoteDialog());
    if (body == null || body.trim().isEmpty || !mounted) return;
    try {
      await ProfileScope.of(context).repo.addNote(widget.childId, body.trim());
      await _load();
    } on SetupError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ملف الطفل')),
        body: Center(
          child: _failure == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(setupFailureMessage(_failure!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('حاول مرة أخرى')),
                  ],
                ),
        ),
      );
    }
    final now = ProfileScope.of(context).clock();
    final text = Theme.of(context).textTheme;
    final stay = p.currentStay;
    final age = p.ageOn(now);
    final since = p.stays.isEmpty ? null : p.stays.first.from.year;
    final rate = p.termRate(now);
    final recent = p.marks.length > 14 ? p.marks.sublist(p.marks.length - 14) : p.marks;
    final events = _history(p);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          children: [
            InitialAvatar(p.fullName, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.fullName),
                  Text(
                    [
                      stay?.groupName ?? 'بدون فئة',
                      if (age != null) countLabel(age, one: 'سنة واحدة', two: 'سنتان', few: 'سنوات', many: 'سنة'),
                      if (since != null) 'منذ $since',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('profile-add-note'),
        onPressed: _addNote,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('ملاحظة'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            if (p.registration.hasHealthInfo) ...[_HealthCard(p.registration), const SizedBox(height: 8)],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.termStart == null ? 'الحضور · آخر 90 يوماً' : 'الحضور · هذا الفصل',
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          rate == null ? '—' : '${(rate * 100).round()}%',
                          key: const Key('profile-rate'),
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: RaeedColors.blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (recent.isEmpty)
                      Text('لم يُسجَّل حضور بعد.', style: text.bodySmall?.copyWith(color: RaeedColors.grey))
                    else
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final m in recent)
                            Tooltip(
                              message: '${longDay(m.date)} · ${m.status.label}',
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: statusColors(m.status).$1,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final s in AttendanceStatus.values)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: statusColors(s).$1,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(s.label, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SectionLabel('أولياء الأمور'),
            if (p.parents.isEmpty)
              Text('لا يوجد ولي أمر مسجّل.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey))
            else
              Card(
                child: Column(
                  children: [
                    for (final parent in p.parents)
                      ListTile(
                        title: Text(parent.fullName),
                        subtitle: Text(
                          formatPhone(parent.phone),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.end,
                        ),
                        trailing: IconButton(
                          tooltip: 'اتصال',
                          onPressed: () => launchUrl(Uri.parse('tel:${parent.phone}')),
                          icon: const Icon(Icons.call, color: RaeedColors.blue),
                        ),
                      ),
                  ],
                ),
              ),
            const SectionLabel('السجل'),
            if (events.isEmpty) Text('لا شيء بعد.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey)),
            for (final e in events)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsetsDirectional.only(start: 10),
                decoration: const BoxDecoration(
                  border: BorderDirectional(start: BorderSide(color: Color(0xFFD7E4F2), width: 2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (e.body != null) Text(e.body!, style: text.bodyMedium),
                    Text(e.meta, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                  ],
                ),
              ),
            if (_registrationRows(p.registration) case final rows when rows.isNotEmpty) ...[
              const SectionLabel('استمارة التسجيل'),
              Card(
                key: const Key('profile-registration'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: rows),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 14, color: RaeedColors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'الملاحظات مرئية لمؤطري الطفل والمشرفين فقط',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown at the top of the profile, so staff see it before a session or a camp.
class _HealthCard extends StatelessWidget {
  const _HealthCard(this.r);

  final ChildRegistration r;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const Key('profile-health'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RaeedColors.starSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RaeedColors.starStart),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_outlined, color: RaeedColors.starEnd),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.hasChronicCondition ? 'مرض مزمن · احتياطات' : 'احتياطات صحية',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: RaeedColors.ink),
                ),
                const SizedBox(height: 2),
                Text(r.medicalNotes ?? 'لم تُذكر تفاصيل. تواصل مع ولي الأمر.', style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the registration card: a label, its value, and a call button for phones.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.phone});

  final String label;
  final String value;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      dense: true,
      title: Text(label, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
      subtitle: phone == null
          ? Text(value, style: text.bodyMedium)
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value),
                  const TextSpan(text: ' · '),
                  TextSpan(text: '\u2066${formatPhone(phone!)}\u2069'),
                ],
              ),
              style: text.bodyMedium,
            ),
      trailing: phone == null
          ? null
          : IconButton(
              tooltip: 'اتصال',
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              icon: const Icon(Icons.call, color: RaeedColors.blue),
            ),
    );
  }
}

List<Widget> _registrationRows(ChildRegistration r) => [
  if (r.fullNameLatin != null) _InfoRow('الاسم بالفرنسية', r.fullNameLatin!),
  if (r.schoolLevel != null) _InfoRow('المستوى الدراسي', r.schoolLevel!),
  if (r.residence != null) _InfoRow('السكن', r.residence!),
  if (r.returningMember != null) _InfoRow('مسجل الموسم الماضي', r.returningMember! ? 'نعم' : 'لا، تسجيل جديد'),
  if (r.motherName != null || r.motherPhone != null) _InfoRow('الأم', r.motherName ?? '—', phone: r.motherPhone),
  if (r.fatherName != null || r.fatherPhone != null) _InfoRow('الأب', r.fatherName ?? '—', phone: r.fatherPhone),
  if (r.contactEmail != null) _InfoRow('البريد الإلكتروني', r.contactEmail!),
  if (r.registrationNotes != null) _InfoRow('ملاحظات الأسرة', r.registrationNotes!),
  if (r.registeredAt != null) _InfoRow('تاريخ التسجيل', _shortDay(r.registeredAt!)),
];

class _Event {
  const _Event(this.at, this.title, this.body, this.meta);

  final DateTime at;
  final String title;
  final String? body;
  final String meta;
}

String _shortDay(DateTime d) => '${d.day} ${monthNames[d.month - 1]} ${d.year}';

/// Follow-ups, notes and group moves, newest first.
List<_Event> _history(ChildProfile p) {
  String by(String? name) => name == null || name.isEmpty ? '' : ' · $name';
  final events = <_Event>[
    for (final a in p.alerts)
      if (a.open)
        _Event(
          a.createdAt,
          'تنبيه غياب · مفتوح',
          a.lastAttemptAt == null ? 'غياب حصتين متتاليتين' : 'لم يرد ولي الأمر بعد',
          _shortDay(a.createdAt),
        )
      else
        _Event(
          a.closedAt ?? a.createdAt,
          'تتبّع غياب · تم التواصل',
          a.reason,
          '${_shortDay(a.closedAt ?? a.createdAt)}${by(a.closedByName)}',
        ),
    for (final n in p.notes) _Event(n.createdAt, 'ملاحظة', n.body, '${_shortDay(n.createdAt)}${by(n.authorName)}'),
    for (var i = 0; i < p.stays.length; i++)
      _Event(
        p.stays[i].from,
        i == 0 ? 'الانضمام إلى ${p.stays[i].groupName}' : 'الانتقال إلى ${p.stays[i].groupName}',
        i == 0 ? null : 'من ${p.stays[i - 1].groupName}',
        _shortDay(p.stays[i].from),
      ),
  ];
  events.sort((a, b) => b.at.compareTo(a.at));
  return events;
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _body = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ملاحظة'),
    content: TextField(
      key: const Key('profile-note'),
      controller: _body,
      autofocus: true,
      maxLines: 4,
      maxLength: 2000,
      decoration: const InputDecoration(hintText: 'مرئية لمؤطري الطفل والمشرفين فقط'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      FilledButton(
        key: const Key('save-profile-note'),
        onPressed: () => Navigator.pop(context, _body.text),
        child: const Text('حفظ'),
      ),
    ],
  );
}

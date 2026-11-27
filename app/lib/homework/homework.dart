import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../instructor/models.dart' show dayOnly, dbDay;
import '../setup/setup_repository.dart';

/// One field of a homework template, such as السورة or من الصفحة.
class HomeworkField {
  const HomeworkField(this.key, this.label, {this.hint, this.required = false, this.number = false});

  /// Its key in homework.fields.
  final String key;
  final String label;
  final String? hint;
  final bool required;

  /// Page and verse numbers: a number keyboard.
  final bool number;
}

/// The ready homework models the مشرف الفئة picks from. Each has its own fields; [custom]
/// is the generic form for anything else.
enum HomeworkTemplate {
  review('review', 'مراجعة المحفوظ', Icons.auto_stories, [
    HomeworkField('surah', 'السورة', hint: 'مثال: الملك', required: true),
    HomeworkField('from', 'من', hint: 'الآية 1'),
    HomeworkField('to', 'إلى', hint: 'الآية 15'),
  ]),
  wird('wird', 'ورد قرآني', Icons.menu_book, [
    HomeworkField('amount', 'المقدار', hint: 'مثال: ثمن حزب كل يوم', required: true),
  ]),
  reading('reading', 'قراءة مقطع من كتاب', Icons.import_contacts, [
    HomeworkField('book', 'الكتاب', required: true),
    HomeworkField('from', 'من الصفحة', number: true),
    HomeworkField('to', 'إلى الصفحة', number: true),
  ]),
  summary('summary', 'تلخيص مقطع', Icons.short_text, [
    HomeworkField('book', 'من كتاب أو درس', hint: 'اختياري'),
    HomeworkField('from', 'من', required: true),
    HomeworkField('to', 'إلى', required: true),
  ]),
  presentation('presentation', 'إعداد عرض', Icons.co_present, [
    HomeworkField('topic', 'حول', hint: 'موضوع العرض', required: true),
  ]),
  research('research', 'إنجاز وتقديم بحث', Icons.travel_explore, [
    HomeworkField('topic', 'حول', hint: 'موضوع البحث', required: true),
  ]),
  custom('custom', 'واجب آخر', Icons.edit_note, [
    HomeworkField('title', 'الواجب', required: true),
    HomeworkField('amount', 'المقدار'),
  ]);

  const HomeworkTemplate(this.dbName, this.label, this.icon, this.fields);

  final String dbName;
  final String label;
  final IconData icon;
  final List<HomeworkField> fields;

  static HomeworkTemplate fromDb(String v) => values.firstWhere((t) => t.dbName == v, orElse: () => custom);
}

/// What was marked for one child: done is تم, not done is لم يتم.
class HomeworkMark {
  const HomeworkMark({required this.done, required this.markedAt});

  final bool done;
  final DateTime markedAt;
}

/// A homework the مشرف الفئة gave to a فئة or to some of its children.
class Homework {
  const Homework({
    required this.id,
    required this.groupId,
    required this.template,
    required this.fields,
    required this.dueDate,
    this.details,
    this.wholeGroup = true,
    this.childIds = const [],
    this.marks = const {},
  });

  final String id;
  final String groupId;
  final HomeworkTemplate template;
  final Map<String, String> fields;
  final String? details;
  final DateTime dueDate;

  /// For every child of the فئة; otherwise for [childIds].
  final bool wholeGroup;
  final List<String> childIds;

  /// By child id. A child without one is not marked yet.
  final Map<String, HomeworkMark> marks;

  String? field(String key) {
    final v = fields[key]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// One line, like the notification: «مراجعة المحفوظ: الملك من الآية 1 إلى الآية 15».
  String get summary {
    String part(String prefix, String key) => field(key) == null ? '' : '$prefix${field(key)}';
    return switch (template) {
      HomeworkTemplate.review => 'مراجعة المحفوظ: ${field('surah') ?? ''}${part(' من ', 'from')}${part(' إلى ', 'to')}',
      HomeworkTemplate.wird => 'ورد قرآني: ${field('amount') ?? ''}',
      HomeworkTemplate.reading =>
        'قراءة مقطع من ${field('book') ?? 'كتاب'}${part(' من الصفحة ', 'from')}${part(' إلى الصفحة ', 'to')}',
      HomeworkTemplate.summary => 'تلخيص مقطع${part(' من ', 'book')}${part(' من ', 'from')}${part(' إلى ', 'to')}',
      HomeworkTemplate.presentation => 'إعداد عرض حول ${field('topic') ?? ''}',
      HomeworkTemplate.research => 'إنجاز وتقديم بحث حول ${field('topic') ?? ''}',
      HomeworkTemplate.custom => '${field('title') ?? ''}${field('amount') == null ? '' : ' (${field('amount')})'}',
    };
  }

  /// Which of [groupChildren] (the فئة's children now) it is for.
  List<String> targets(Iterable<String> groupChildren) => wholeGroup
      ? groupChildren.toList()
      : [
          for (final c in groupChildren)
            if (childIds.contains(c)) c,
        ];

  bool isPast(DateTime now) => dueDate.isBefore(dayOnly(now));

  static Homework fromJson(Map<String, dynamic> j) => Homework(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    template: HomeworkTemplate.fromDb(j['template'] as String),
    fields: {for (final e in (j['fields'] as Map? ?? const {}).entries) e.key as String: '${e.value ?? ''}'},
    details: j['details'] as String?,
    dueDate: DateTime.parse(j['due_date'] as String),
    wholeGroup: j['whole_group'] as bool? ?? true,
    childIds: [for (final c in j['homework_children'] as List? ?? const []) (c as Map)['child_id'] as String],
    marks: {
      for (final s in j['homework_status'] as List? ?? const [])
        (s as Map)['child_id'] as String: HomeworkMark(
          done: s['done'] as bool,
          markedAt: DateTime.parse(s['marked_at'] as String).toLocal(),
        ),
    },
  );
}

/// What the form sends to create or change a homework.
class HomeworkDraft {
  const HomeworkDraft({
    required this.groupId,
    required this.template,
    required this.fields,
    required this.dueDate,
    this.details,
    this.childIds = const [],
  });

  final String groupId;
  final HomeworkTemplate template;
  final Map<String, String> fields;
  final String? details;
  final DateTime dueDate;

  /// Empty for the whole فئة.
  final List<String> childIds;

  Map<String, Object?> toJson() => {
    'group_id': groupId,
    'template': template.dbName,
    'fields': {
      for (final e in fields.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    },
    'details': details?.trim(),
    'due_date': dbDay(dueDate),
  };
}

/// الواجبات. Every call throws [SetupError].
abstract interface class HomeworkRepository {
  /// Newest due date first, with who it is for and the marks the caller may read.
  Future<List<Homework>> load(List<String> groupIds);
  Future<void> create(HomeworkDraft draft);
  Future<void> update(String id, HomeworkDraft draft);
  Future<void> delete(String id);

  /// [done]: true = تم, false = لم يتم, null clears the mark.
  Future<void> mark(String homeworkId, String childId, bool? done);
}

class SupabaseHomeworkRepository implements HomeworkRepository {
  SupabaseHomeworkRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<List<Homework>> load(List<String> groupIds) => guardSupabase(() async {
    if (groupIds.isEmpty) return const [];
    final rows = await _db
        .from('homework')
        .select('*, homework_children(child_id), homework_status(child_id, done, marked_at)')
        .inFilter('group_id', groupIds)
        .order('due_date', ascending: false)
        .limit(300);
    return [for (final r in rows) Homework.fromJson(r)];
  });

  @override
  Future<void> create(HomeworkDraft draft) => guardSupabase(
    () => _db.rpc<dynamic>('create_homework', params: {'p_fields': draft.toJson(), 'p_children': draft.childIds}),
  );

  @override
  Future<void> update(String id, HomeworkDraft draft) => guardSupabase(
    () => _db.rpc<dynamic>(
      'update_homework',
      params: {'p_id': id, 'p_fields': draft.toJson(), 'p_children': draft.childIds},
    ),
  );

  @override
  Future<void> delete(String id) => guardSupabase(() => _db.from('homework').delete().eq('id', id));

  @override
  Future<void> mark(String homeworkId, String childId, bool? done) => guardSupabase(
    () =>
        _db.rpc<dynamic>('set_homework_status', params: {'p_homework': homeworkId, 'p_child': childId, 'p_done': done}),
  );
}

/// Hands the homework repository to the screens. Null in tests that do not cover it.
class HomeworkScope extends InheritedWidget {
  const HomeworkScope({super.key, required this.repo, required super.child});

  final HomeworkRepository? repo;

  static HomeworkRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeworkScope>()?.repo;

  @override
  bool updateShouldNotify(HomeworkScope old) => old.repo != repo;
}

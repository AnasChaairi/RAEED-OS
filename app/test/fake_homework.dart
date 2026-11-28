import 'package:raeed_os/homework/homework.dart';
import 'package:raeed_os/setup/setup_repository.dart';

/// الواجبات kept in memory, with every write recorded in [calls].
class FakeHomeworkRepository implements HomeworkRepository {
  FakeHomeworkRepository({List<Homework>? items}) : items = items ?? [];

  final List<Homework> items;
  final calls = <String>[];
  bool offline = false;
  var _next = 0;

  void _check() {
    if (offline) throw const SetupError(SetupFailure.offline);
  }

  Homework _from(String id, HomeworkDraft d, Map<String, HomeworkMark> marks) => Homework(
    id: id,
    groupId: d.groupId,
    template: d.template,
    fields: {
      for (final e in d.fields.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    },
    details: (d.details ?? '').trim().isEmpty ? null : d.details!.trim(),
    dueDate: d.dueDate,
    wholeGroup: d.childIds.isEmpty,
    childIds: d.childIds,
    marks: marks,
  );

  @override
  Future<List<Homework>> load(List<String> groupIds) async {
    _check();
    return [
      for (final h in items)
        if (groupIds.contains(h.groupId)) h,
    ]..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  }

  /// Which فئة each child is in, for [loadForChild].
  final childGroups = <String, String>{};

  @override
  Future<List<Homework>> loadForChild(String childId) async {
    _check();
    final g = childGroups[childId];
    return [
      for (final h in await load([?g]))
        if (h.targets([childId]).isNotEmpty) h,
    ];
  }

  @override
  Future<void> create(HomeworkDraft draft) async {
    _check();
    calls.add('create ${draft.template.dbName} ${draft.childIds.isEmpty ? 'all' : draft.childIds.join(',')}');
    items.add(_from('h${_next++}', draft, const {}));
  }

  @override
  Future<void> update(String id, HomeworkDraft draft) async {
    _check();
    calls.add('update $id');
    final i = items.indexWhere((h) => h.id == id);
    items[i] = _from(id, draft, items[i].marks);
  }

  @override
  Future<void> delete(String id) async {
    _check();
    calls.add('delete $id');
    items.removeWhere((h) => h.id == id);
  }

  @override
  Future<void> mark(String homeworkId, String childId, bool? done) async {
    _check();
    calls.add('mark $homeworkId $childId $done');
    final i = items.indexWhere((h) => h.id == homeworkId);
    final h = items[i];
    final marks = {...h.marks}..remove(childId);
    if (done != null) marks[childId] = HomeworkMark(done: done, markedAt: DateTime(2027, 2, 10));
    items[i] = Homework(
      id: h.id,
      groupId: h.groupId,
      template: h.template,
      fields: h.fields,
      details: h.details,
      dueDate: h.dueDate,
      wholeGroup: h.wholeGroup,
      childIds: h.childIds,
      marks: marks,
      assignedBy: h.assignedBy,
    );
  }
}

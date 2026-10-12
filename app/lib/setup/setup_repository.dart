import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/phone.dart';
import '../roles/app_role.dart';
import 'models.dart';

enum SetupFailure {
  offline,

  /// Another group already has this name.
  duplicateName,
  invalidPhone,

  /// A child can have at most two parents.
  tooManyParents,

  /// An advisor tried to take away their own advisor role.
  ownAdvisorRole,

  /// The server said this account may not do that.
  notAllowed,
  unknown,
}

class SetupError implements Exception {
  const SetupError(this.failure);

  final SetupFailure failure;

  @override
  String toString() => 'SetupError($failure)';
}

/// The advisor's reads and writes for setup. Each call does one thing; [SetupStore]
/// strings them together, so the order of steps is tested without a server.
abstract interface class SetupRepository {
  Future<SetupSnapshot> load();

  /// Inserts or updates the group row and returns its id. Instructors are set separately.
  Future<String> saveGroup(GroupDraft draft);
  Future<void> setGroupInstructors(String groupId, List<String> personIds);
  Future<void> setInstructorGroups(String personId, List<String> groupIds);

  /// Creates an account through the manage-account server function. A phone number that
  /// already has an account gets the roles added instead.
  Future<NewAccount> createAccount({required String fullName, required String phone, required Set<AppRole> roles});
  Future<String> resetPassword(String personId);
  Future<void> setRoles(String personId, Set<AppRole> roles);
  Future<void> renamePerson(String personId, String fullName);

  /// Inserts or updates the child row and returns its id. [recordConsent] stamps the consent
  /// with now and the signed-in advisor; it is never cleared.
  Future<String> saveChild({String? id, required String fullName, DateTime? birthDate, required bool recordConsent});

  /// Ends the current group membership today and starts the new one. Null removes the
  /// child from any group.
  Future<void> moveChild(String childId, String? groupId);
  Future<void> setChildParents(String childId, List<String> parentIds);

  Future<String> saveSeason({String? id, required String name, required DateTime startsOn, required DateTime endsOn});
  Future<String> saveTerm({
    String? id,
    required String seasonId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
  });
}

class SupabaseSetupRepository implements SetupRepository {
  SupabaseSetupRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<SetupSnapshot> load() => _guard(() async {
        final results = await Future.wait([
          _db.from('groups').select('id, name, logo_letter, logo_color, age_min, age_max, archived, group_instructors(person_id)').order('name'),
          _db.from('people').select('id, full_name, phone, must_change_password, person_roles(role)').order('full_name'),
          _db.from('children').select('id, full_name, birth_date, consent_recorded_at, child_groups(group_id, to_date), child_parents(parent_id)').order('full_name'),
          _db.from('seasons').select('id, name, starts_on, ends_on, terms(id, name, starts_on, ends_on)').order('starts_on', ascending: false),
        ]);
        return SetupSnapshot(
          groups: [
            for (final g in results[0])
              Group(
                id: g['id'] as String,
                name: g['name'] as String,
                logoLetter: g['logo_letter'] as String,
                logoColor: g['logo_color'] as int,
                ageMin: g['age_min'] as int?,
                ageMax: g['age_max'] as int?,
                archived: g['archived'] as bool,
                instructorIds: [for (final i in g['group_instructors'] as List) i['person_id'] as String],
              ),
          ],
          people: [
            for (final p in results[1])
              Person(
                id: p['id'] as String,
                fullName: p['full_name'] as String,
                phone: p['phone'] as String,
                mustChangePassword: p['must_change_password'] as bool,
                roles: {
                  for (final r in p['person_roles'] as List)
                    ?AppRole.fromDb(r['role'] as String),
                },
              ),
          ],
          children: [
            for (final c in results[2])
              Child(
                id: c['id'] as String,
                fullName: c['full_name'] as String,
                birthDate: _date(c['birth_date']),
                consentRecordedAt: c['consent_recorded_at'] == null ? null : DateTime.parse(c['consent_recorded_at'] as String),
                groupId: [
                  for (final m in c['child_groups'] as List)
                    if (m['to_date'] == null) m['group_id'] as String,
                ].firstOrNull,
                parentIds: [for (final p in c['child_parents'] as List) p['parent_id'] as String],
              ),
          ],
          seasons: [
            for (final s in results[3])
              Season(
                id: s['id'] as String,
                name: s['name'] as String,
                startsOn: _date(s['starts_on'])!,
                endsOn: _date(s['ends_on'])!,
                terms: [
                  for (final t in s['terms'] as List)
                    Term(
                      id: t['id'] as String,
                      name: t['name'] as String,
                      startsOn: _date(t['starts_on'])!,
                      endsOn: _date(t['ends_on'])!,
                    ),
                ]..sort((a, b) => a.startsOn.compareTo(b.startsOn)),
              ),
          ],
        );
      });

  @override
  Future<String> saveGroup(GroupDraft d) => _guard(() async {
        final row = {
          'name': d.name,
          'logo_letter': d.logoLetter,
          'logo_color': d.logoColor,
          'age_min': d.ageMin,
          'age_max': d.ageMax,
          'archived': d.archived,
        };
        if (d.id == null) {
          final inserted = await _db.from('groups').insert(row).select('id').single();
          return inserted['id'] as String;
        }
        await _db.from('groups').update(row).eq('id', d.id!);
        return d.id!;
      });

  @override
  Future<void> setGroupInstructors(String groupId, List<String> personIds) => _guard(() async {
        var remove = _db.from('group_instructors').delete().eq('group_id', groupId);
        if (personIds.isNotEmpty) remove = remove.not('person_id', 'in', '(${personIds.join(',')})');
        await remove;
        if (personIds.isNotEmpty) {
          await _db
              .from('group_instructors')
              .upsert([for (final p in personIds) {'group_id': groupId, 'person_id': p}], ignoreDuplicates: true);
        }
      });

  @override
  Future<void> setInstructorGroups(String personId, List<String> groupIds) => _guard(() async {
        var remove = _db.from('group_instructors').delete().eq('person_id', personId);
        if (groupIds.isNotEmpty) remove = remove.not('group_id', 'in', '(${groupIds.join(',')})');
        await remove;
        if (groupIds.isNotEmpty) {
          await _db
              .from('group_instructors')
              .upsert([for (final g in groupIds) {'group_id': g, 'person_id': personId}], ignoreDuplicates: true);
        }
      });

  @override
  Future<NewAccount> createAccount({required String fullName, required String phone, required Set<AppRole> roles}) =>
      _guard(() async {
        final normalized = normalizePhone(phone);
        if (normalized == null) throw const SetupError(SetupFailure.invalidPhone);
        final result = await _call({
          'action': 'create',
          'full_name': fullName,
          'phone': normalized,
          'roles': [for (final r in roles) r.dbName],
        });
        return NewAccount(personId: result['person_id'] as String, temporaryPassword: result['temporary_password'] as String?);
      });

  @override
  Future<String> resetPassword(String personId) => _guard(() async {
        final result = await _call({'action': 'reset', 'person_id': personId});
        return result['temporary_password'] as String;
      });

  @override
  Future<void> setRoles(String personId, Set<AppRole> roles) => _guard(() async {
        await _call({'action': 'set_roles', 'person_id': personId, 'roles': [for (final r in roles) r.dbName]});
      });

  @override
  Future<void> renamePerson(String personId, String fullName) => _guard(() async {
        await _db.from('people').update({'full_name': fullName}).eq('id', personId);
      });

  @override
  Future<String> saveChild({String? id, required String fullName, DateTime? birthDate, required bool recordConsent}) =>
      _guard(() async {
        final row = <String, dynamic>{'full_name': fullName, 'birth_date': birthDate == null ? null : _day(birthDate)};
        if (recordConsent) {
          row['consent_recorded_at'] = DateTime.now().toUtc().toIso8601String();
          row['consent_recorded_by'] = _db.auth.currentUser!.id;
        }
        if (id == null) {
          final inserted = await _db.from('children').insert(row).select('id').single();
          return inserted['id'] as String;
        }
        await _db.from('children').update(row).eq('id', id);
        return id;
      });

  @override
  Future<void> moveChild(String childId, String? groupId) => _guard(() async {
        final today = _day(DateTime.now());
        // A membership that started today is simply replaced, not closed.
        await _db.from('child_groups').delete().eq('child_id', childId).isFilter('to_date', null).eq('from_date', today);
        await _db.from('child_groups').update({'to_date': today}).eq('child_id', childId).isFilter('to_date', null);
        if (groupId != null) {
          await _db.from('child_groups').insert({'child_id': childId, 'group_id': groupId, 'from_date': today});
        }
      });

  @override
  Future<void> setChildParents(String childId, List<String> parentIds) => _guard(() async {
        var remove = _db.from('child_parents').delete().eq('child_id', childId);
        if (parentIds.isNotEmpty) remove = remove.not('parent_id', 'in', '(${parentIds.join(',')})');
        await remove;
        if (parentIds.isNotEmpty) {
          await _db
              .from('child_parents')
              .upsert([for (final p in parentIds) {'child_id': childId, 'parent_id': p}], ignoreDuplicates: true);
        }
      });

  @override
  Future<String> saveSeason({String? id, required String name, required DateTime startsOn, required DateTime endsOn}) =>
      _guard(() async {
        final row = {'name': name, 'starts_on': _day(startsOn), 'ends_on': _day(endsOn)};
        if (id == null) return (await _db.from('seasons').insert(row).select('id').single())['id'] as String;
        await _db.from('seasons').update(row).eq('id', id);
        return id;
      });

  @override
  Future<String> saveTerm({
    String? id,
    required String seasonId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
  }) =>
      _guard(() async {
        final row = {'season_id': seasonId, 'name': name, 'starts_on': _day(startsOn), 'ends_on': _day(endsOn)};
        if (id == null) return (await _db.from('terms').insert(row).select('id').single())['id'] as String;
        await _db.from('terms').update(row).eq('id', id);
        return id;
      });

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final response = await _db.functions.invoke('manage-account', body: body);
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw SetupError(switch (code) {
        'invalid_phone' => SetupFailure.invalidPhone,
        'cannot_remove_own_advisor_role' => SetupFailure.ownAdvisorRole,
        'advisors_only' || 'not_signed_in' => SetupFailure.notAllowed,
        _ => SetupFailure.unknown,
      });
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) => guardSupabase(call);

  static DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Runs a Supabase call and turns its failures into [SetupError].
Future<T> guardSupabase<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on SetupError {
    rethrow;
  } on PostgrestException catch (e) {
    if (e.code == '23505') throw const SetupError(SetupFailure.duplicateName);
    if (e.message.contains('at most two parents')) throw const SetupError(SetupFailure.tooManyParents);
    if (e.code == '42501') throw const SetupError(SetupFailure.notAllowed);
    throw const SetupError(SetupFailure.unknown);
  } catch (e) {
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('ClientException') || text.contains('TimeoutException')) {
      throw const SetupError(SetupFailure.offline);
    }
    throw const SetupError(SetupFailure.unknown);
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/setup/setup_repository.dart';
import 'package:raeed_os/setup/setup_store.dart';

import 'fake_setup.dart';

void main() {
  late FakeSetupRepository repo;
  late SetupStore store;

  setUp(() async {
    repo = FakeSetupRepository()..addPerson('yassine', 'ياسين', '0611111111', {AppRole.instructor});
    store = SetupStore(repo);
    await store.load();
  });

  test('a new child creates parent accounts and returns their passwords', () async {
    await store.saveGroup(const GroupDraft(name: 'فئة النجوم', logoLetter: 'ن', logoColor: 1, instructorIds: ['yassine']));
    final group = store.data.groups.single;
    expect(group.instructorIds, ['yassine']);

    final issued = await store.saveChild(ChildDraft(
      fullName: 'آدم بنعلي',
      groupId: group.id,
      consent: true,
      parents: const [
        ParentDraft.create(fullName: 'كريم بنعلي', phone: '06 12 34 56 78'),
        ParentDraft.create(fullName: 'سعاد العلوي', phone: '0698765432'),
      ],
    ));

    expect(issued.map((p) => p.fullName), ['كريم بنعلي', 'سعاد العلوي']);
    expect(issued.first.phone, '+212612345678');
    final child = store.data.children.single;
    expect(child.groupId, group.id);
    expect(child.parentIds, hasLength(2));
    expect(child.consentRecordedAt, isNotNull);
    expect(store.data.person(child.parentIds.first)!.roles, {AppRole.parent});
  });

  test('a parent who is already staff is linked, keeps their password and gains the parent role', () async {
    final issued = await store.saveChild(const ChildDraft(
      fullName: 'سلمى',
      parents: [ParentDraft.create(fullName: 'ياسين', phone: '+212611111111')],
    ));
    expect(issued, isEmpty);
    expect(store.data.children.single.parentIds, ['yassine']);
    expect(store.data.person('yassine')!.roles, {AppRole.instructor, AppRole.parent});
  });

  test('editing a child only touches what changed, and consent is recorded once', () async {
    await store.saveChild(const ChildDraft(fullName: 'سلمى', consent: true, parents: [ParentDraft.existing('yassine')]));
    final child = store.data.children.single;
    repo.calls.clear();

    await store.saveChild(ChildDraft(id: child.id, fullName: 'سلمى العلوي', consent: true, parents: const [ParentDraft.existing('yassine')]));

    expect(repo.calls, ['saveChild سلمى العلوي consent=false']);
  });

  test('moving a child to another group ends the old membership', () async {
    await store.saveGroup(const GroupDraft(name: 'أ', logoLetter: 'أ', logoColor: 1));
    await store.saveGroup(const GroupDraft(name: 'ب', logoLetter: 'ب', logoColor: 2));
    final [a, b] = store.data.groups;
    await store.saveChild(ChildDraft(fullName: 'سلمى', groupId: a.id, parents: const [ParentDraft.existing('yassine')]));
    final child = store.data.children.single;
    await store.saveChild(ChildDraft(id: child.id, fullName: 'سلمى', groupId: b.id, parents: const [ParentDraft.existing('yassine')]));
    expect(repo.calls.where((c) => c.startsWith('moveChild')), ['moveChild ${child.id} ${a.id}', 'moveChild ${child.id} ${b.id}']);
    expect(store.data.children.single.groupId, b.id);
  });

  test('a new instructor is placed in the chosen groups', () async {
    await store.saveGroup(const GroupDraft(name: 'أ', logoLetter: 'أ', logoColor: 1, instructorIds: ['yassine']));
    final group = store.data.groups.single;
    final issued = await store.createStaff(fullName: 'سارة', phone: '0622222222', roles: {AppRole.instructor}, groupIds: [group.id]);
    expect(issued!.temporaryPassword, isNotEmpty);
    final sara = store.data.people.firstWhere((p) => p.fullName == 'سارة');
    expect(store.data.groups.single.instructorIds, unorderedEquals(['yassine', sara.id]));
  });

  test('updating staff keeps the parent role and clears groups when no longer an instructor', () async {
    repo.addPerson('hamza', 'حمزة', '0633333333', {AppRole.instructor, AppRole.parent});
    await store.load();
    await store.saveGroup(const GroupDraft(name: 'أ', logoLetter: 'أ', logoColor: 1, instructorIds: ['hamza']));
    await store.updateStaff(person: store.data.person('hamza')!, fullName: 'حمزة', roles: {AppRole.advisor}, groupIds: const []);
    expect(store.data.person('hamza')!.roles, {AppRole.advisor, AppRole.parent});
    expect(store.data.groups.single.instructorIds, isEmpty);
  });

  test('a new group logo replaces the old one, and saving without a change keeps it', () async {
    final first = Uint8List.fromList([1, 2, 3]);
    await store.saveGroup(GroupDraft(name: 'أ', logoLetter: 'أ', logoColor: 1, newLogo: first));
    final group = store.data.groups.single;
    final firstPath = group.logoPath!;
    await store.saveGroup(GroupDraft(id: group.id, name: 'أ', logoLetter: 'أ', logoColor: 2));
    expect(store.data.groups.single.logoPath, firstPath);

    await store.saveGroup(GroupDraft(id: group.id, name: 'أ', logoLetter: 'أ', logoColor: 2, newLogo: Uint8List(4)));
    expect(store.data.groups.single.logoPath, isNot(firstPath));
    expect(repo.logos.keys, [store.data.groups.single.logoPath]);
    expect(repo.calls.where((c) => c.startsWith('setGroupLogo')).last, endsWith('replaces=$firstPath'));
  });

  test('staff gender is saved on creation and only sent again when it changes', () async {
    await store.createStaff(fullName: 'سارة', phone: '0622222222', roles: {AppRole.instructor}, groupIds: const [], gender: Gender.female);
    final sara = store.data.people.singleWhere((p) => p.fullName == 'سارة');
    expect(sara.gender, Gender.female);
    repo.calls.clear();
    await store.updateStaff(person: sara, fullName: 'سارة', roles: {AppRole.instructor}, groupIds: const [], gender: Gender.female);
    expect(repo.calls.where((c) => c.startsWith('setGender')), isEmpty);
  });

  test('a load failure is kept for the screen to explain', () async {
    repo.offline = true;
    final fresh = SetupStore(repo);
    await fresh.load();
    expect(fresh.loaded, isFalse);
    expect(fresh.loadFailure, SetupFailure.offline);
  });
}

import 'package:flutter/material.dart';

import '../roles/app_role.dart';
import '../theme/raeed_theme.dart';
import 'children_screen.dart';
import 'groups_screen.dart';
import 'models.dart';
import 'seasons_screen.dart';
import 'setup_repository.dart';
import 'staff_screen.dart';
import 'widgets.dart';

/// Screen 10, the advisor's الإعدادات tab: the four lists the advisor manages, and a
/// warning for anything that would break a journey.
class SetupHub extends StatelessWidget {
  const SetupHub({super.key});

  @override
  Widget build(BuildContext context) {
    return SetupLoadGate(
      builder: (context, data) {
        final instructors = data.staff.where((p) => p.roles.contains(AppRole.instructor)).length;
        final advisors = data.staff.where((p) => p.roles.contains(AppRole.advisor)).length;
        final parents = data.people.where((p) => p.roles.contains(AppRole.parent)).length;
        final current = data.seasons.firstOrNull;
        final now = DateTime.now();
        final term = current?.terms.where((t) => !now.isBefore(t.startsOn) && !now.isAfter(t.endsOn)).firstOrNull;
        final warnings = [
          if (data.childrenWithoutParent.isNotEmpty)
            '${_kids(data.childrenWithoutParent.length)} بدون ولي أمر مسجّل، فلن تصل إشعاراتهم.',
          if (data.childrenWithoutGroup.isNotEmpty) '${_kids(data.childrenWithoutGroup.length)} بدون فئة.',
          if (data.groupsWithoutInstructor.isNotEmpty)
            'فئات بدون مؤطر: ${data.groupsWithoutInstructor.map((g) => g.name).join('، ')}.',
          if (data.children.any((c) => c.consentRecordedAt == null))
            '${_kids(data.children.where((c) => c.consentRecordedAt == null).length)} بدون موافقة مسجّلة.',
          if (data.seasons.isEmpty) 'لم يُسجَّل الموسم وفصوله بعد.',
        ];
        void open(Widget screen) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SetupRow(
              key: const Key('setup-groups'),
              leading: const _Badge(letter: 'ف', color: 1),
              title: 'الفئات',
              lines: [countLabel(data.activeGroups.length, one: 'فئة واحدة', two: 'فئتان', few: 'فئات', many: 'فئة')],
              onTap: () => open(const GroupsScreen()),
            ),
            const SizedBox(height: 8),
            SetupRow(
              key: const Key('setup-staff'),
              leading: const _Badge(letter: 'م', color: 4),
              title: 'المؤطرون والمشرفون',
              lines: [
                '${countLabel(instructors, one: 'مؤطر واحد', two: 'مؤطران', few: 'مؤطرين', many: 'مؤطراً')} · '
                    '${countLabel(advisors, one: 'مشرف واحد', two: 'مشرفان', few: 'مشرفين', many: 'مشرفاً')}',
              ],
              onTap: () => open(const StaffScreen()),
            ),
            const SizedBox(height: 8),
            SetupRow(
              key: const Key('setup-children'),
              leading: const _Badge(letter: 'ط', color: 2),
              title: 'الأطفال وأولياء الأمور',
              lines: [
                '${countLabel(data.children.length, one: 'طفل واحد', two: 'طفلان', few: 'أطفال', many: 'طفلاً')} · '
                    '${countLabel(parents, one: 'ولي أمر واحد', two: 'وليّا أمر', few: 'أولياء أمور', many: 'ولي أمر')}',
              ],
              onTap: () => open(const ChildrenScreen()),
            ),
            const SizedBox(height: 8),
            SetupRow(
              key: const Key('setup-seasons'),
              leading: const _Badge(letter: 'س', color: 3),
              title: 'الموسم والفصول',
              lines: [
                if (current == null) 'لم يُسجَّل بعد' else current.name,
                if (term != null) '${term.name}: من ${formatDate(term.startsOn)} إلى ${formatDate(term.endsOn)}',
              ],
              onTap: () => open(const SeasonsScreen()),
            ),
            if (data.deletionRequests.isNotEmpty) ...[
              const SectionLabel('طلبات حذف الحساب'),
              for (final r in data.deletionRequests)
                if (data.person(r.personId) case final p?)
                  Card(
                    child: ListTile(
                      key: Key('deletion-${p.id}'),
                      title: Text(p.fullName),
                      subtitle: Text(
                        '${[for (final role in p.roles) role.label].join('، ')} · طلب في ${formatDate(r.requestedAt)}',
                      ),
                      trailing: TextButton(
                        key: Key('delete-account-${p.id}'),
                        style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
                        onPressed: () => _confirmDelete(context, p),
                        child: const Text('حذف'),
                      ),
                    ),
                  ),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              WarningCard(title: 'قبل البدء', lines: warnings),
            ] else if (data.children.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('كل شيء جاهز.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RaeedColors.grey)),
            ],
          ],
        );
      },
    );
  }
}

Future<void> _confirmDelete(BuildContext context, Person person) async {
  final store = SetupScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('حذف حساب ${person.fullName}؟'),
      content: const Text(
        'يُحذف الحساب ورقم الهاتف ولا يمكن التراجع. إن كان اسمه على سجلات الحضور أو الملاحظات، '
        'تبقى السجلات باسم "حساب محذوف".',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(
          key: const Key('confirm-delete-account'),
          style: FilledButton.styleFrom(backgroundColor: RaeedColors.error),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await store.deleteAccount(person);
    messenger.showSnackBar(SnackBar(content: Text('حُذف حساب ${person.fullName} ✓')));
  } on SetupError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
  }
}

String _kids(int n) => countLabel(n, one: 'طفل واحد', two: 'طفلان', few: 'أطفال', many: 'طفلاً');

class _Badge extends StatelessWidget {
  const _Badge({required this.letter, required this.color});

  final String letter;
  final int color;

  @override
  Widget build(BuildContext context) => GroupLogo(letter: letter, color: color);
}

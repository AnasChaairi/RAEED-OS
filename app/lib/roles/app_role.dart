import 'package:flutter/material.dart';

/// A role from person_roles. One account can hold several.
enum AppRole {
  advisor('advisor', 'مشرف عام', 'الإحصائيات والحصص والفئات والإعدادات'),
  instructor('instructor', 'مؤطر', 'مواعدي والحضور وفئاتي'),

  /// مشرف الفئة: plans the sessions of the فئة they are in charge of and follows its
  /// instructors. Not an app_role value: someone holds it by being in group_supervisors.
  supervisor('category_supervisor', 'مشرف الفئة', 'أنشطة فئتي ومؤطروها والتواصل مع أولياء الأمور'),
  parent('parent', 'ولي أمر', 'جدول أطفالي وحسابي');

  const AppRole(this.dbName, this.label, this.summary);

  /// The value in the app_role enum in the database.
  final String dbName;
  final String label;

  /// One line under the role on the role chooser.
  final String summary;

  IconData get icon => switch (this) {
        AppRole.advisor => Icons.verified_user,
        AppRole.instructor => Icons.school,
        AppRole.supervisor => Icons.supervisor_account,
        AppRole.parent => Icons.family_restroom,
      };

  static AppRole? fromDb(String value) {
    for (final r in values) {
      if (r.dbName == value) return r;
    }
    return null;
  }

  /// The bottom tabs this role sees, from the main screens design.
  List<RoleTab> get tabs => switch (this) {
        AppRole.advisor => const [
            RoleTab('الإحصائيات', Icons.insights_outlined, Icons.insights),
            RoleTab('الحصص', Icons.calendar_month_outlined, Icons.calendar_month),
            RoleTab('الفئات', Icons.groups_outlined, Icons.groups),
            RoleTab('الأطفال', Icons.child_care_outlined, Icons.child_care),
            RoleTab('الإعدادات', Icons.settings_outlined, Icons.settings),
          ],
        AppRole.instructor => const [
            RoleTab('مواعدي', Icons.event_available_outlined, Icons.event_available),
            RoleTab('الحصص', Icons.calendar_month_outlined, Icons.calendar_month),
            RoleTab('فئاتي', Icons.groups_outlined, Icons.groups),
            RoleTab('التنبيهات', Icons.notifications_outlined, Icons.notifications),
          ],
        AppRole.supervisor => const [
            RoleTab('الأنشطة', Icons.calendar_month_outlined, Icons.calendar_month),
            RoleTab('فئتي', Icons.groups_outlined, Icons.groups),
            RoleTab('أولياء الأمور', Icons.forum_outlined, Icons.forum),
            RoleTab('الملاحظات', Icons.rate_review_outlined, Icons.rate_review),
            RoleTab('التنبيهات', Icons.notifications_outlined, Icons.notifications),
          ],
        AppRole.parent => const [
            RoleTab('جدول أطفالي', Icons.event_note_outlined, Icons.event_note),
            RoleTab('الملاحظات', Icons.forum_outlined, Icons.forum),
            RoleTab('حسابي', Icons.person_outline, Icons.person),
          ],
      };
}

class RoleTab {
  const RoleTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

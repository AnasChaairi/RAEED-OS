/// Phone numbers as RAEED OS stores them.
///
/// Sign-in has no SMS: each account uses an internal e-mail address made from the phone
/// number. This must match normalizePhone and phoneToEmail in
/// supabase/functions/manage-account/index.ts, which creates the accounts.
library;

/// Accepts 06…, 07…, +2126…, 2126… with spaces or dashes, in Western or Arabic-Indic
/// digits. Returns 2126XXXXXXXX (no plus sign), or null if it is not a Moroccan mobile
/// or fixed-line number.
String? normalizePhone(String raw) {
  final digits = _westernDigits(raw).replaceAll(RegExp(r'[\s\-().]'), '').replaceFirst(RegExp(r'^\+'), '');
  final local = digits.startsWith('212') ? digits.substring(3) : digits.replaceFirst(RegExp(r'^0'), '');
  return RegExp(r'^[5-7]\d{8}$').hasMatch(local) ? '212$local' : null;
}

String phoneToEmail(String normalizedPhone) => '$normalizedPhone@phone.raeed.app';

/// +212 6 12 34 56 78, for showing a stored number back to people.
String formatPhone(String phone) {
  final n = normalizePhone(phone);
  if (n == null) return phone;
  final l = n.substring(3);
  return '+212 ${l[0]} ${l.substring(1, 3)} ${l.substring(3, 5)} ${l.substring(5, 7)} ${l.substring(7)}';
}

// Arabic keyboards on Android often type ٠١٢٣٤٥٦٧٨٩ (or Persian ۰…۹).
String _westernDigits(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + r - 0x06F0);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

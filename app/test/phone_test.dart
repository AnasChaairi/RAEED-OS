import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/auth/phone.dart';

void main() {
  group('normalizePhone matches the manage-account server function', () {
    const cases = {
      '+212691015402': '212691015402',
      '212691015402': '212691015402',
      '0691015402': '212691015402',
      '691015402': '212691015402',
      '06 91 01 54 02': '212691015402',
      '06-91-01-54-02': '212691015402',
      '+212 (6) 91 01 54 02': '212691015402',
      '0712345678': '212712345678',
      '0522123456': '212522123456',
      '٠٦٩١٠١٥٤٠٢': '212691015402',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(normalizePhone(input), expected));
    });

    for (final bad in ['', '123', '0891015402', '06910154', '069101540212', '+33612345678', 'abc']) {
      test('rejects "$bad"', () => expect(normalizePhone(bad), isNull));
    }
  });

  test('phoneToEmail', () {
    expect(phoneToEmail('212691015402'), '212691015402@phone.raeed.app');
  });

  test('formatPhone', () {
    expect(formatPhone('+212691015402'), '+212 6 91 01 54 02');
  });
}

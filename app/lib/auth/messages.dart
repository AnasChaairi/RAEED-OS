import 'auth_repository.dart';

/// What to tell people when sign-in or a password change fails.
String failureMessage(AuthFailure failure) => switch (failure) {
      AuthFailure.invalidPhone => 'رقم الهاتف غير صحيح. اكتبه هكذا: 06 12 34 56 78',
      AuthFailure.wrongCredentials => 'رقم الهاتف أو كلمة المرور غير صحيحة. إذا نسيت كلمة المرور، تواصل مع المشرف.',
      AuthFailure.noProfile => 'هذا الرقم غير مسجّل في الأكاديمية. تواصل مع المشرف.',
      AuthFailure.offline => 'لا يوجد اتصال بالإنترنت. تحقّق من الاتصال وحاول مرة أخرى.',
      AuthFailure.weakPassword => 'كلمة المرور ضعيفة. اختر كلمة مرور أطول وأصعب تخميناً.',
      AuthFailure.samePassword => 'اختر كلمة مرور مختلفة عن كلمة المرور المؤقتة.',
      AuthFailure.unknown => 'حدث خطأ. حاول مرة أخرى بعد قليل.',
    };

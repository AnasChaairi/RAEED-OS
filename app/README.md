# RAEED OS app

Flutter app for Android and iPhone. Arabic only, right to left, on the Supabase project in Frankfurt.

## Run it

```sh
cd app
flutter pub get
flutter run            # on a connected phone or emulator
flutter test           # sign-in, password change and role tabs, against an in-memory fake
flutter analyze
```

The Supabase address and publishable key are in `lib/config.dart`. To point at another project:
`flutter run --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_PUBLISHABLE_KEY=…`

## How sign-in works

People type their phone number (06…, 07…, +212…) and password. The app turns the number into the
internal address `2126XXXXXXXX@phone.raeed.app`, the same way the `manage-account` server function
does when an advisor creates the account (`lib/auth/phone.dart`). On the first sign-in,
`people.must_change_password` sends them to choose their own password; the app then calls
`mark_password_changed`. Someone with several roles picks one, the app remembers it, and the
avatar at the top switches roles or signs out.

## Layout

| Path | What it holds |
|---|---|
| `lib/app.dart` | App root (Arabic locale, RTL) and the gate that picks the screen for each sign-in stage |
| `lib/auth/` | Supabase sign-in, the session state, sign-in and password screens |
| `lib/roles/` | Roles, their tabs, and the role chooser |
| `lib/home/` | The tab shell and the account sheet with the role switcher |
| `lib/setup/` | The advisor's setup: groups, staff, children and parents, seasons |
| `lib/instructor/` | The instructor's tabs: today, sessions, groups, alerts, offline attendance |
| `lib/parent/` | The parent's schedule, session detail and account |
| `lib/advisor/` | The advisor's statistics |
| `lib/profile/` | The child profile, for advisors and instructors |
| `lib/notifications/` | Push notifications through Firebase |
| `lib/theme/` | RAEED colours and fonts |
| `assets/fonts/` | Baloo Bhaijaan 2 (titles) and IBM Plex Sans Arabic (text), SIL Open Font License |

## Push notifications

Session changes queue one row per parent in `notification_outbox`. The `send-notifications` server
function sends each as a push notification through Firebase Cloud Messaging to every phone the
parent signed in on, and records how many phones it reached.

Until the academy's Firebase project exists, the app runs without notifications and rows wait in the
queue. To turn them on:

1. In the Firebase console, create a project and add an Android app with the package name
   `app.raeed.raeed_os`.
2. Build with the values from that app's `google-services.json`:
   `flutter build apk --dart-define=FIREBASE_API_KEY=… --dart-define=FIREBASE_APP_ID=… --dart-define=FIREBASE_SENDER_ID=… --dart-define=FIREBASE_PROJECT_ID=…`
3. In Firebase, Project settings, Service accounts, generate a private key. In Supabase, Edge
   Functions, Secrets, save its whole JSON as `FCM_SERVICE_ACCOUNT`.

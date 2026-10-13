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
| `lib/advisor/` | The advisor's statistics and the pilot measures |
| `lib/profile/` | The child profile, for advisors and instructors |
| `lib/notifications/` | Push notifications through Firebase |
| `lib/theme/` | RAEED colours and fonts |
| `tool/make_icons.py` | Rebuilds the launcher icons from the logo |
| `assets/fonts/` | Baloo Bhaijaan 2 (titles) and IBM Plex Sans Arabic (text), SIL Open Font License |

## Push notifications

Session changes queue one row per parent in `notification_outbox`. The `send-notifications` server
function sends each as a push notification through Firebase Cloud Messaging to every phone the
parent signed in on, and records how many phones it reached.

The app uses the Firebase project `raeed-os`; its Android settings from `google-services.json` are in
`lib/config.dart` and can be overridden with `--dart-define=FIREBASE_API_KEY=…` and the like. The
server needs that project's service account key: in Firebase, Project settings, Service accounts,
generate a private key, and in Supabase, Edge Functions, Secrets, save its whole JSON as
`FCM_SERVICE_ACCOUNT`. Until then rows wait in the queue.

## Pilot measures

The advisor's statistics open a مؤشرات التجربة page with the product definition's success measures
for the chosen period, from the `pilot_metrics` database function:

- sessions with attendance saved within 24 hours of their end (target 90%);
- the median time from opening the attendance sheet to its first save (target 3 minutes), logged by
  the app in `usage_events`; sheets saved offline are not timed;
- absence alerts with a call attempt or a closing within 7 days (target 80%);
- children with a parent who has signed in and set a password (target 70%);
- how many weeks each advisor opened the statistics, also from `usage_events`.

## Account deletion

Anyone can ask for their account to be deleted from the account sheet (or the parent's حسابي tab).
The request appears in the advisor's الإعدادات, where the advisor deletes the account through
`manage-account`. Someone whose name is on attendance, notes or follow-ups is anonymised instead:
the records stay under "حساب محذوف", and the phone number, roles, devices and sign-in are removed.

## Group logos, gender, brothers and sisters

- **Group logo:** on the group form, «رفع صورة الشعار» picks a photo (scaled to 512 px) and
  uploads it to the public storage bucket `group-logos`; `groups.logo_path` names it. Only
  advisors can upload or remove one. The letter and colour still show while the image loads,
  offline, or when there is no image.
- **Gender:** children and staff (`children.gender`, `people.gender`, `male` or `female`).
  The forms require it; records made before it existed stay empty until next saved.
- **Brothers and sisters:** on the child form, «اختيار ولي أمر مسجّل» lists parents who
  already have an account, searchable by name, phone or a child's name, and links the new
  child to them without a new account. Typing a registered number still links too.

## Store builds

Release builds are signed with the upload key when `android/key.properties` exists (it is ignored
by git, like the key itself):

```
storeFile=/absolute/path/to/raeed-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Without it they are signed with the debug key, which installs fine from an APK but is refused by
the Play Store. For the store, build an app bundle with `flutter build appbundle --release` and
raise the build number in `pubspec.yaml` (`version: 1.0.0+N`) for each upload.


# icare mobile (Android)

Flutter app for the icare carpooling platform (English and Amharic). It talks to the JSON API at `/api/v1`.

```sh
cd mobile
flutter pub get
flutter analyze && flutter test
flutter run --dart-define=API_BASE=https://your-server        # device or emulator
flutter build apk --release --dart-define=API_BASE=https://your-server
```

`API_BASE` defaults to the production server in `lib/core/config.dart`.

Release builds are signed with the debug key until you add your own keystore in `android/app/build.gradle.kts`.
Admin tools stay on the web.

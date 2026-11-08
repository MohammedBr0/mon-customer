/// Where the icare server lives. Override at build time:
/// `flutter build apk --dart-define=API_BASE=https://your-domain`
const String apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://icare-vif2.onrender.com');

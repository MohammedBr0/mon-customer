/// Ethiopian mobile numbers: 09… (Ethio Telecom) and 07… (Safaricom), nine digits after the country code.
/// Returns "+2519XXXXXXXX", or null when what was typed is not a mobile number.
String? normalizeEthiopianPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (RegExp(r'^0[79]\d{8}$').hasMatch(digits)) digits = '+251${digits.substring(1)}';
  if (RegExp(r'^[79]\d{8}$').hasMatch(digits)) digits = '+251$digits';
  if (RegExp(r'^251[79]\d{8}$').hasMatch(digits)) digits = '+$digits';
  return RegExp(r'^\+251[79]\d{8}$').hasMatch(digits) ? digits : null;
}

/// True when a sign-in box holds something we can send: an email address or an Ethiopian mobile number.
bool isValidLogin(String raw) {
  final text = raw.trim();
  if (text.contains('@')) return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
  return normalizeEthiopianPhone(text) != null;
}

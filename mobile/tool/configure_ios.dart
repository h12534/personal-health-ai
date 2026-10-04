import 'dart:io';

void main() {
  final bundleId = Platform.environment['IOS_BUNDLE_ID']?.trim();
  final displayName = Platform.environment['APP_DISPLAY_NAME']?.trim();
  final distribution = Platform.environment['APP_DISTRIBUTION'] ?? 'standard';
  final free = Platform.environment['PERSONAL_SIDELOAD_FREE'] ?? 'false';
  if (!{'standard', 'personal_sideload'}.contains(distribution) ||
      !{'true', 'false'}.contains(free) ||
      (free == 'true' && distribution != 'personal_sideload')) {
    stderr
        .writeln('Invalid distribution / PERSONAL_SIDELOAD_FREE combination.');
    exitCode = 64;
    return;
  }
  if (bundleId == null || bundleId.isEmpty) {
    stderr.writeln('IOS_BUNDLE_ID is required.');
    exitCode = 64;
    return;
  }
  if (!RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(bundleId)) {
    stderr.writeln('IOS_BUNDLE_ID must be a reverse-DNS identifier.');
    exitCode = 64;
    return;
  }
  if (displayName == null ||
      displayName.isEmpty ||
      RegExp(r'[\r\n$;/]').hasMatch(displayName)) {
    stderr.writeln('APP_DISPLAY_NAME is required and must be one line.');
    exitCode = 64;
    return;
  }

  final output = File('ios/Flutter/AppConfig.local.xcconfig');
  output.writeAsStringSync(
    '// Generated locally; do not commit.\n'
    'IOS_BUNDLE_ID = $bundleId\n'
    'APP_DISPLAY_NAME = $displayName\n'
    'APP_DISTRIBUTION = $distribution\n'
    'PERSONAL_SIDELOAD_FREE = $free\n'
    'IOS_CODE_SIGN_ENTITLEMENTS = Runner/'
    '${free == 'true' ? 'PersonalSideloadFree' : 'Runner'}.entitlements\n',
  );
  stdout.writeln('Wrote ${output.path}');
}

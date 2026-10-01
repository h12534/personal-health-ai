import 'dart:io';

void main() {
  _configureIos();
  _configureAndroid();
}

void _configureIos() {
  final file = File('ios/Runner/Info.plist');
  if (!file.existsSync()) return;
  var content = file.readAsStringSync();
  const entries = {
    'NSCameraUsageDescription': '用于拍摄餐食照片并生成可编辑的营养记录草稿。',
    'NSPhotoLibraryUsageDescription': '用于选择餐食照片并生成可编辑的营养记录草稿。',
    'NSPhotoLibraryAddUsageDescription': '仅在你主动选择保存餐食图片时写入照片图库。',
    'NSHealthShareUsageDescription':
        '在你分别开启同步后，读取步数、睡眠、静息心率和训练摘要，用于展示活动、恢复与训练建议。',
    'NSHealthUpdateUsageDescription':
        '当前版本不会向 Apple 健康写入数据；此说明用于 HealthKit 能力配置，未来写入仍会另行征得你的同意。',
    'NSFaceIDUsageDescription': '用于在你开启隐私锁后保护体检、身体照片和健康数据。',
  };
  for (final entry in entries.entries) {
    if (content.contains('<key>${entry.key}</key>')) continue;
    final rootClosingTag = content.lastIndexOf('</dict>');
    if (rootClosingTag < 0) {
      throw const FormatException('Invalid ios/Runner/Info.plist');
    }
    content = content.replaceRange(
      rootClosingTag,
      rootClosingTag,
      '\t<key>${entry.key}</key>\n'
      '\t<string>${entry.value}</string>\n',
    );
  }
  file.writeAsStringSync(content);

  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (project.existsSync()) {
    project.writeAsStringSync(
      project.readAsStringSync().replaceAll(
          'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
          'IPHONEOS_DEPLOYMENT_TARGET = 16.0;'),
    );
  }
}

void _configureAndroid() {
  final kotlin = File('android/app/build.gradle.kts');
  if (kotlin.existsSync()) {
    final content = kotlin.readAsStringSync().replaceFirst(
          'minSdk = flutter.minSdkVersion',
          'minSdk = 26',
        );
    kotlin.writeAsStringSync(content);
  }
  final groovy = File('android/app/build.gradle');
  if (groovy.existsSync()) {
    final content = groovy.readAsStringSync().replaceFirst(
          'minSdkVersion flutter.minSdkVersion',
          'minSdkVersion 26',
        );
    groovy.writeAsStringSync(content);
  }

  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var content = manifest.readAsStringSync();
    const permissions = [
      '<uses-permission android:name="android.permission.USE_BIOMETRIC" />',
      '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
    ];
    for (final permission in permissions) {
      if (!content.contains(permission)) {
        content = content.replaceFirst('>', '>\n    $permission');
      }
    }
    if (!content.contains('ScheduledNotificationReceiver')) {
      const receivers = '''
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
            android:exported="false" />
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"
            android:exported="false" />
''';
      content = content.replaceFirst(
          '</application>', '$receivers    </application>');
    }
    manifest.writeAsStringSync(content);
  }

  final kotlinRoot = Directory('android/app/src/main/kotlin');
  if (kotlinRoot.existsSync()) {
    for (final entity in kotlinRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('MainActivity.kt')) continue;
      final content = entity
          .readAsStringSync()
          .replaceAll(
            'import io.flutter.embedding.android.FlutterActivity',
            'import io.flutter.embedding.android.FlutterFragmentActivity',
          )
          .replaceAll('FlutterActivity()', 'FlutterFragmentActivity()');
      entity.writeAsStringSync(content);
    }
  }

  for (final path in [
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
  ]) {
    final styles = File(path);
    if (!styles.existsSync()) continue;
    final content = styles
        .readAsStringSync()
        .replaceAll(
          'parent="@android:style/Theme.Light.NoTitleBar"',
          'parent="Theme.AppCompat.DayNight.NoActionBar"',
        )
        .replaceAll(
          'parent="@android:style/Theme.Black.NoTitleBar"',
          'parent="Theme.AppCompat.DayNight.NoActionBar"',
        );
    styles.writeAsStringSync(content);
  }
}

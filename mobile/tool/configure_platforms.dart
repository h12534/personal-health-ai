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
          'minSdk = 24',
        );
    kotlin.writeAsStringSync(content);
  }
  final groovy = File('android/app/build.gradle');
  if (groovy.existsSync()) {
    final content = groovy.readAsStringSync().replaceFirst(
          'minSdkVersion flutter.minSdkVersion',
          'minSdkVersion 24',
        );
    groovy.writeAsStringSync(content);
  }
}

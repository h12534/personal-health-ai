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
}

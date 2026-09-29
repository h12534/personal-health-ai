import 'dart:io';

void main() {
  _configureIos();
  _configureAndroid();
}

void _configureIos() {
  final file = File('ios/Runner/Info.plist');
  if (!file.existsSync()) return;
  var content = file.readAsStringSync();
  if (!content.contains('NSCameraUsageDescription')) {
    content = content.replaceFirst('</dict>', '''
\t<key>NSCameraUsageDescription</key>
\t<string>用于拍摄餐食照片并生成可编辑的营养记录草稿。</string>
\t<key>NSPhotoLibraryUsageDescription</key>
\t<string>用于选择餐食照片并生成可编辑的营养记录草稿。</string>
</dict>''');
    file.writeAsStringSync(content);
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

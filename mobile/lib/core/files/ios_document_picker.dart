import 'dart:io';

import 'package:flutter/services.dart';

class PickedPrivateDocument {
  const PickedPrivateDocument({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class IosDocumentPicker {
  const IosDocumentPicker();

  static const _channel = MethodChannel('personal_health_os/document_picker');

  Future<PickedPrivateDocument?> pickPdf() async {
    if (!Platform.isIOS) {
      throw UnsupportedError('PDF 文件选择当前仅在 iPhone/iPad 上启用。');
    }
    final value = await _channel.invokeMapMethod<String, dynamic>('pickPdf');
    if (value == null) return null;
    final bytes = value['bytes'];
    final name = value['name'];
    if (bytes is! Uint8List || name is! String) {
      throw const FormatException('系统文件选择器返回了无效数据。');
    }
    return PickedPrivateDocument(name: name, bytes: bytes);
  }
}

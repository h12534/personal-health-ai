import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';

final mealPhotoServiceProvider = Provider<MealPhotoService>((ref) {
  return MealPhotoService(ref.watch(localDatabaseProvider), ImagePicker());
});

class MealPhotoService {
  MealPhotoService(this._database, this._picker);

  final LocalDatabase _database;
  final ImagePicker _picker;

  Future<VisionTaskRecord?> pickAndPersist({
    required ImageSource source,
    required String mealType,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    return _persist(picked, mealType);
  }

  Future<VisionTaskRecord?> recoverLostImage({required String mealType}) async {
    final response = await _picker.retrieveLostData();
    final files = response.files;
    if (response.isEmpty || files == null || files.isEmpty) return null;
    return _persist(files.first, mealType);
  }

  Future<VisionTaskRecord> _persist(XFile source, String mealType) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(root.path, 'meal-analysis-pending'));
    await directory.create(recursive: true);
    final localId = const Uuid().v4();
    final target = path.join(directory.path, '$localId.jpg');
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      target,
      minWidth: 2048,
      minHeight: 2048,
      quality: 86,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (compressed == null) {
      throw StateError('图片压缩失败，请换一张照片重试。');
    }
    final bytes = await compressed.length();
    if (bytes > 10 * 1024 * 1024) {
      await File(compressed.path).delete();
      throw StateError('压缩后的图片仍超过 10 MB，请裁剪后重试。');
    }
    final now = DateTime.now();
    final task = VisionTaskRecord(
      localId: localId,
      imagePath: compressed.path,
      mealType: mealType,
      locationContext: 'school_canteen',
      status: 'waiting_network',
      uploadProgress: 0,
      createdAt: now,
      updatedAt: now,
    );
    await _database.saveVisionTask(task);
    return task;
  }
}

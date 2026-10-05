// Read-only local review helper. Does not approve a baseline or write any file.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../test/support/reviewed_pixel_comparator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('read reviewed local PNG pixel digests without committing images',
      () async {
    const directory = String.fromEnvironment('UI_REVIEW_DIRECTORY');
    if (directory.isEmpty) {
      throw StateError('Explicit review directory required');
    }
    final files = await Directory(directory)
        .list()
        .where((file) => file is File && file.path.endsWith('.png'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (!RegExp(r'^[a-z0-9-]+\.png$').hasMatch(name)) {
        throw StateError('Unexpected review filename');
      }
      final digest =
          await ReviewedPixelComparator.pixelDigest(await file.readAsBytes());
      stdout.writeln('GOLDEN_REVIEW_DIGEST ${jsonEncode({
            'key': 'goldens/personal-free/$name',
            ...digest
          })}');
    }
  });
}

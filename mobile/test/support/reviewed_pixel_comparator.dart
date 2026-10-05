import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exact decoded RGBA + dimensions, not a perceptual or percentage threshold.
/// PNGs remain ephemeral artifacts; only individually reviewed digests are Git
/// baselines. Missing entries fail, and --update-goldens cannot approve them.
class ReviewedPixelComparator extends GoldenFileComparator {
  ReviewedPixelComparator({
    required this.legacy,
    required this.digests,
    required this.useDigestsForAll,
    required this.free,
    this.captureReview = false,
    this.evidenceRoot = 'test/failures/ui-review',
  });

  final GoldenFileComparator legacy;
  final Map<String, dynamic> digests;
  final bool useDigestsForAll, free, captureReview;
  final String evidenceRoot;

  static Future<Map<String, dynamic>> loadDigests(String host) async {
    final file = File('test/goldens/digests/$host.json');
    if (!await file.exists()) {
      return {}; // No approval: every missing key fails.
    }
    final document =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (document['schema'] != 1 || document['pixel_format'] != 'rawRgba8') {
      throw const FormatException('Unsupported reviewed pixel manifest');
    }
    return document['images'] as Map<String, dynamic>;
  }

  static Future<Map<String, Object>> pixelDigest(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      final frame = await codec.getNextFrame();
      try {
        final raw =
            await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) throw StateError('RGBA decoding failed');
        return {
          'width': frame.image.width,
          'height': frame.image.height,
          'rgba_sha256': sha256
              .convert(
                  raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes))
              .toString(),
        };
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final key = golden.toString();
    if (!RegExp(r'^goldens/(personal-free/)?[a-z0-9-]+\.png$').hasMatch(key)) {
      throw const FormatException('Unsafe golden key');
    }
    final isFreeImage = key.startsWith('goldens/personal-free/');
    final selectedReview = captureReview && (!free || isFreeImage);
    final usesDigest = useDigestsForAll || isFreeImage;
    final actual = await pixelDigest(imageBytes);
    final expected = digests[key] as Map<String, dynamic>?;
    final matches = usesDigest
        ? expected != null &&
            expected['width'] == actual['width'] &&
            expected['height'] == actual['height'] &&
            expected['rgba_sha256'] == actual['rgba_sha256']
        : await legacy.compare(imageBytes, golden);
    if (selectedReview || (!captureReview && !matches)) {
      final name = golden.pathSegments.last;
      final folder = Directory('$evidenceRoot/${free ? 'free' : 'standard'}');
      await folder.create(recursive: true);
      await File('${folder.path}/$name').writeAsBytes(imageBytes, flush: true);
    }
    if (selectedReview || (usesDigest && !matches)) {
      // Non-sensitive candidate metadata, not automatic acceptance or a file.
      // OCR text and image bytes are never printed or attached as logs.
      stdout.writeln(
          'GOLDEN_REVIEW_DIGEST ${jsonEncode({'key': key, ...actual})}');
    }
    return matches;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    throw UnsupportedError(
        'Review each artifact before updating its text digest; automatic Golden approval is disabled');
  }
}

/// Rendered fixture code cannot fetch a real API, remote photo or real account.
class SyntheticGoldenNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network is forbidden in synthetic UI goldens');
}

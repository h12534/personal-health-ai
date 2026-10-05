import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'support/reviewed_pixel_comparator.dart';

class _Legacy extends GoldenFileComparator {
  int comparisons = 0;
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    comparisons++;
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async =>
      throw StateError('No automatic approval');
}

Future<Uint8List> _png(int color,
    {int width = 2, int height = 2, bool changeOnePixel = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = ui.Color(color));
  if (changeOnePixel) {
    canvas.drawRect(ui.Rect.fromLTWH(width - 1.0, height - 1.0, 1, 1),
        ui.Paint()..color = ui.Color(color + 1));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory evidence;
  setUp(() async =>
      evidence = await Directory.systemTemp.createTemp('ui-digest-unit-'));
  tearDown(() async => evidence.delete(recursive: true));
  final key = Uri.parse('goldens/synthetic.png');
  test('exact RGBA succeeds and a one-channel one-value change fails',
      () async {
    final png = await _png(0xff112233);
    final comparator = ReviewedPixelComparator(
        legacy: _Legacy(),
        digests: {
          key.toString(): await ReviewedPixelComparator.pixelDigest(png)
        },
        useDigestsForAll: true,
        free: false,
        evidenceRoot: evidence.path);
    expect(await comparator.compare(png, key), isTrue);
    expect(
        await comparator.compare(
            await _png(0xff112233, changeOnePixel: true), key),
        isFalse);
    expect(
        await File('${evidence.path}/standard/synthetic.png').exists(), isTrue);
  });
  test('dimensions cannot pass even with an identical pixel hash', () async {
    final png = await _png(0xff112233);
    final digest = await ReviewedPixelComparator.pixelDigest(png);
    final comparator = ReviewedPixelComparator(
        legacy: _Legacy(),
        digests: {
          key.toString(): {...digest, 'width': 1, 'height': 4}
        },
        useDigestsForAll: true,
        free: false,
        evidenceRoot: evidence.path);
    expect(await comparator.compare(png, key), isFalse);
  });
  test('missing approval fails closed instead of adopting actual', () async {
    final comparator = ReviewedPixelComparator(
        legacy: _Legacy(),
        digests: {},
        useDigestsForAll: true,
        free: false,
        evidenceRoot: evidence.path);
    expect(await comparator.compare(await _png(0xff112233), key), isFalse);
    expect(comparator.digests, isEmpty);
  });
  test('automatic update and path traversal are rejected', () async {
    final comparator = ReviewedPixelComparator(
        legacy: _Legacy(),
        digests: {},
        useDigestsForAll: true,
        free: false,
        evidenceRoot: evidence.path);
    final png = await _png(0xff112233);
    await expectLater(comparator.update(key, png), throwsUnsupportedError);
    await expectLater(
        comparator.compare(png, Uri.parse('goldens/../../secret.png')),
        throwsFormatException);
  });
  test('existing non-macOS standard references retain the exact legacy check',
      () async {
    final legacy = _Legacy();
    final comparator = ReviewedPixelComparator(
        legacy: legacy,
        digests: {},
        useDigestsForAll: false,
        free: false,
        evidenceRoot: evidence.path);
    expect(await comparator.compare(await _png(0xff112233), key), isTrue);
    expect(legacy.comparisons, 1);
  });
  test('synthetic rendering refuses HTTP clients', () {
    expect(() => SyntheticGoldenNetwork().createHttpClient(null),
        throwsStateError);
  });
}

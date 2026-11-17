// Makes every logo image from the Health Pro brand files (tool/brand/):
// the in-app logos (assets/images/), the launch screens and the app icons.
//
//   cd packages/health_pro_core && flutter test tool/brand_images.dart
//
// The logo is logo-dark-new.png (already transparent, blue lettering); it
// makes a white-lettered version of it for dark backgrounds. The mark (the
// cross with the runner) and the app icons come from logo-white-small.png,
// lifted off its white tile. (logo-white-new.png, the logo on white, is
// the reference; nothing is made from it.) If the logo's shape changes,
// update HealthProLogo.aspectRatio and markAspectRatio, web/index.html and
// LaunchScreen.storyboard to the sizes it prints. With PREVIEW=<folder>
// set, it writes samples there and touches nothing else. The in-app logos
// and the web splash are WebP, made with cwebp (brew install webp).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const logoSource = 'tool/brand/logo-dark-new.png';
const iconSource = 'tool/brand/logo-white-small.png';
const navy = Color(0xFF0A1A3E);

Future<Pixels> load(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  return Pixels(image.width, image.height, Uint8List.fromList(rgba));
}

/// RGBA pixels, straight alpha.
class Pixels {
  final int width, height;
  final Uint8List rgba;

  Pixels(this.width, this.height, this.rgba);

  Pixels.blank(this.width, this.height) : rgba = Uint8List(width * height * 4);

  int at(int x, int y) => (y * width + x) * 4;

  Pixels crop(Rect r) {
    final out = Pixels.blank(r.width.round(), r.height.round());
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final sx = x + r.left.round(), sy = y + r.top.round();
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue;
        out.rgba.setRange(out.at(x, y), out.at(x, y) + 4, rgba, at(sx, sy));
      }
    }
    return out;
  }

  /// The smallest box holding everything at least [minAlpha] opaque, in
  /// columns [from] to [to].
  Rect bounds({int from = 0, int? to, int minAlpha = 24}) {
    var left = width, top = height, right = -1, bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = from; x < (to ?? width); x++) {
        if (rgba[at(x, y) + 3] < minAlpha) continue;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
    return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
  }

  Future<ui.Image> toImage() async {
    final codec = await ui.instantiateImageCodec(encodePng(this));
    return (await codec.getNextFrame()).image;
  }
}

/// The logo off its white. Everything light joined to the edges (the white,
/// the soft glow under the cross) and a thin band round every shape takes
/// the least opacity that, over white, gives the colour it has, and the
/// colour without the white in it ("colour to alpha"); so edges and the
/// glow keep no pale fringe on dark. The rest stays as it is, solid, white
/// the outside can't reach (the runner) included.
Pixels liftOffWhite(Pixels src) {
  final w = src.width, h = src.height, px = src.rgba;
  double needed(int i) => (255 - math.min(px[i], math.min(px[i + 1], px[i + 2]))) / 255;

  final light = Uint8List(w * h);
  final queue = <int>[];
  void visit(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final p = y * w + x;
    if (light[p] == 1 || needed(p * 4) >= 0.5) return;
    light[p] = 1;
    queue.add(p);
  }

  for (var x = 0; x < w; x++) {
    visit(x, 0);
    visit(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    visit(0, y);
    visit(w - 1, y);
  }
  while (queue.isNotEmpty) {
    final p = queue.removeLast();
    final x = p % w, y = p ~/ w;
    visit(x + 1, y);
    visit(x - 1, y);
    visit(x, y + 1);
    visit(x, y - 1);
  }
  final edge = _grow(light, w, h, 2);

  final out = Pixels.blank(w, h);
  for (var p = 0; p < w * h; p++) {
    final i = p * 4;
    if (edge[p] == 0) {
      out.rgba.setRange(i, i + 3, px, i);
      out.rgba[i + 3] = 255;
      continue;
    }
    // The paper isn't quite white: the faintest few percent go entirely.
    final a = ((needed(i) - 0.04) / 0.96).clamp(0.0, 1.0);
    if (a == 0) continue;
    for (var c = 0; c < 3; c++) {
      out.rgba[i + c] = ((px[i + c] - (1 - a) * 255) / a).round().clamp(0, 255);
    }
    out.rgba[i + 3] = (a * 255).round();
  }
  return out;
}

/// [p] over a soft dark shadow of itself, so white lettering stays clear
/// over a photo as well as on the navy.
Pixels withShadow(Pixels p, {int radius = 7, double strength = 0.55}) {
  final w = p.width, h = p.height;
  var alpha = Float64List(w * h);
  for (var q = 0; q < w * h; q++) {
    alpha[q] = p.rgba[q * 4 + 3] / 255;
  }
  // Three box blurs, each way: close to a Gaussian.
  for (var pass = 0; pass < 3; pass++) {
    for (final rows in [true, false]) {
      final next = Float64List(w * h);
      final lines = rows ? h : w, length = rows ? w : h;
      int index(int line, int i) => rows ? line * w + i : i * w + line;
      for (var line = 0; line < lines; line++) {
        final sums = Float64List(length + 1);
        for (var i = 0; i < length; i++) {
          sums[i + 1] = sums[i] + alpha[index(line, i)];
        }
        for (var i = 0; i < length; i++) {
          final a = math.max(0, i - radius), b = math.min(length, i + radius + 1);
          next[index(line, i)] = (sums[b] - sums[a]) / (radius * 2 + 1);
        }
      }
      alpha = next;
    }
  }
  const shade = [4, 10, 26];
  final out = Pixels.blank(w, h);
  for (var q = 0; q < w * h; q++) {
    final i = q * 4;
    final top = p.rgba[i + 3] / 255;
    final under = (alpha[q] * strength).clamp(0.0, 1.0) * (1 - top);
    final a = top + under;
    if (a == 0) continue;
    for (var c = 0; c < 3; c++) {
      out.rgba[i + c] = ((p.rgba[i + c] * top + shade[c] * under) / a).round().clamp(0, 255);
    }
    out.rgba[i + 3] = (a * 255).round();
  }
  return out;
}

/// For dark backgrounds: the lettering (all but [mark]) white, except the
/// green 'PRO' and heartbeat; the tagline (below [taglineY]) a touch softer.
Pixels whiteLettering(Pixels logo, Uint8List mark, int taglineY) {
  final out = Pixels(logo.width, logo.height, Uint8List.fromList(logo.rgba));
  for (var y = 0; y < logo.height; y++) {
    for (var x = 0; x < logo.width; x++) {
      final i = logo.at(x, y);
      if (out.rgba[i + 3] == 0 || mark[y * logo.width + x] == 1) continue;
      final hsv = HSVColor.fromColor(Color.fromARGB(255, out.rgba[i], out.rgba[i + 1], out.rgba[i + 2]));
      final green = hsv.hue >= 65 && hsv.hue <= 165 && hsv.saturation > 0.25;
      if (green) continue;
      out.rgba.fillRange(i, i + 3, 255);
      if (y >= taglineY) out.rgba[i + 3] = (out.rgba[i + 3] * 0.88).round();
    }
  }
  return out;
}

/// Draws [image] into a [width] x [height] picture by [place]; [background]
/// fills it first.
Future<ui.Image> render(int width, int height, void Function(Canvas c, Size size) place, {Color? background}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (background != null) canvas.drawColor(background, BlendMode.src);
  place(canvas, Size(width.toDouble(), height.toDouble()));
  return recorder.endRecording().toImage(width, height);
}

void drawInto(Canvas canvas, ui.Image image, Rect to) => canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      to,
      Paint()..filterQuality = FilterQuality.high,
    );

Future<void> save(String path, ui.Image image, {bool opaque = false}) async {
  final file = File(path)..parent.createSync(recursive: true);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  // App Store icons may not have an alpha channel: plain RGB for those.
  file.writeAsBytesSync(encodePng(Pixels(image.width, image.height, data), alpha: !opaque));
}

/// [image] as WebP: quality 90 with its transparency exact, a quarter of
/// the PNG's size with no visible change. Through cwebp (brew install webp).
Future<void> saveWebp(String path, ui.Image image) async {
  final png = '$path.png';
  await save(png, image);
  final result = await Process.run(
      'cwebp', ['-quiet', '-q', '90', '-alpha_q', '100', '-m', '6', '-sharp_yuv', png, '-o', path]);
  File(png).deleteSync();
  if (result.exitCode != 0) throw Exception('cwebp could not make $path: ${result.stderr}');
}

Uint8List encodePng(Pixels p, {bool alpha = true}) {
  final raw = BytesBuilder();
  for (var y = 0; y < p.height; y++) {
    raw.addByte(0);
    for (var x = 0; x < p.width; x++) {
      final i = p.at(x, y);
      raw.add(p.rgba.sublist(i, i + (alpha ? 4 : 3)));
    }
  }
  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc(body)));
  }

  chunk('IHDR', [..._u32(p.width), ..._u32(p.height), 8, alpha ? 6 : 2, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder(level: 9).convert(raw.toBytes()));
  chunk('IEND', []);
  return out.toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// The pixels of every shape (joined, at least faintly opaque) whose box
/// [keep] takes. The mark and the name share columns (the slanted 'H', the
/// tagline's rule), and the icon's tile frames its mark, so a straight cut
/// won't do.
Uint8List shapesWhere(Pixels p, bool Function(Rect box) keep) {
  final w = p.width, h = p.height;
  final shape = Int32List(w * h)..fillRange(0, w * h, -1);
  final mask = Uint8List(w * h);
  bool solid(int q) => p.rgba[q * 4 + 3] >= 8;
  var next = 0;
  for (var start = 0; start < w * h; start++) {
    if (shape[start] != -1 || !solid(start)) continue;
    final members = <int>[start];
    shape[start] = next;
    var left = w, right = 0, top = h, bottom = 0;
    for (var k = 0; k < members.length; k++) {
      final q = members[k], x = q % w, y = q ~/ w;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final n = ny * w + nx;
          if (shape[n] != -1 || !solid(n)) continue;
          shape[n] = next;
          members.add(n);
        }
      }
    }
    if (keep(Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0))) {
      for (final q in members) {
        mask[q] = 1;
      }
    }
    next++;
  }
  return mask;
}

/// [mask] grown by [r] every way (a square), in two passes.
Uint8List _grow(Uint8List mask, int w, int h, int r) {
  Uint8List pass(Uint8List m, bool rows) {
    final out = Uint8List(w * h);
    final lines = rows ? h : w, length = rows ? w : h;
    int index(int line, int i) => rows ? line * w + i : i * w + line;
    for (var line = 0; line < lines; line++) {
      final sums = List<int>.filled(length + 1, 0);
      for (var i = 0; i < length; i++) {
        sums[i + 1] = sums[i] + m[index(line, i)];
      }
      for (var i = 0; i < length; i++) {
        final a = math.max(0, i - r), b = math.min(length, i + r + 1);
        if (sums[b] - sums[a] > 0) out[index(line, i)] = 1;
      }
    }
    return out;
  }

  return pass(pass(mask, true), false);
}

/// [p] with only the pixels in [mask].
Pixels only(Pixels p, Uint8List mask) {
  final out = Pixels(p.width, p.height, Uint8List.fromList(p.rgba));
  for (var q = 0; q < mask.length; q++) {
    if (mask[q] == 0) out.rgba.fillRange(q * 4, q * 4 + 4, 0);
  }
  return out;
}

void main() {
  testWidgets('brand images', (tester) async {
    await tester.runAsync(() async {
      // The logo, transparent already. White lettering for dark: all but
      // the mark (the shapes left of the 'H', which starts about 28% in);
      // the tagline starts about 68% down.
      final source = await load(logoSource);
      final logoMark = shapesWhere(source, (box) => box.center.dx < source.width * 0.28);
      final all = source.bounds();
      final logoBox = all.inflate(all.height * 0.04);
      final logo = source.crop(logoBox);
      final logoOnDark = withShadow(whiteLettering(source, logoMark, (source.height * 0.68).round()).crop(logoBox));

      // The mark, off the icon's white tile: the shapes well inside it (the
      // tile's edge and its shadow run round the outside).
      final icon = liftOffWhite(await load(iconSource));
      final inset = math.min(icon.width, icon.height) * 0.1;
      final iconArea = Rect.fromLTRB(inset, inset, icon.width - inset, icon.height - inset);
      final markOnly = only(icon, shapesWhere(icon, (box) => iconArea.contains(box.topLeft) && iconArea.contains(box.bottomRight)));
      final markBox = markOnly.bounds();
      final side = math.max(markBox.width, markBox.height) * 1.06;
      final markPixels = markOnly.crop(Rect.fromCenter(center: markBox.center, width: side, height: side));
      final markOnDark = withShadow(markPixels);

      // ignore: avoid_print
      print('logo ${logo.width}x${logo.height} (aspect ${(logo.width / logo.height).toStringAsFixed(4)}), '
          'mark ${markPixels.width}x${markPixels.height}');

      final logoImage = await logo.toImage();
      final logoOnDarkImage = await logoOnDark.toImage();
      final markImage = await markPixels.toImage();
      final markOnDarkImage = await markOnDark.toImage();

      Future<ui.Image> logoAt(double width, ui.Image image, {Color? background}) {
        final h = (width * image.height / image.width).round();
        return render(width.round(), h, (c, s) => drawInto(c, image, Offset.zero & s), background: background);
      }

      /// The mark (or [image]) in a [size] square, [scale] of its side, on
      /// [background].
      Future<ui.Image> markAt(int size, {double scale = 1, Color? background, ui.Image? image}) =>
          render(size, size, (c, s) {
            final d = s.width * scale;
            drawInto(c, image ?? markImage, Rect.fromCenter(center: s.center(Offset.zero), width: d, height: d));
          }, background: background);

      final preview = Platform.environment['PREVIEW'];
      if (preview != null) {
        final photoCodec = await ui.instantiateImageCodec(File('assets/auth/background.jpg').readAsBytesSync());
        final photo = (await photoCodec.getNextFrame()).image;
        Future<ui.Image> onPhoto(double logoWidth) => render(1350, 560, (c, s) {
              final crop = Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.width * 560 / 1350);
              c.drawImageRect(photo, crop, Offset.zero & s, Paint()..filterQuality = FilterQuality.high);
              c.drawRect(Offset.zero & s, Paint()..color = navy.withValues(alpha: 0.35));
              final h = logoWidth * logoOnDarkImage.height / logoOnDarkImage.width;
              drawInto(c, logoOnDarkImage, Rect.fromLTWH(190, 95, logoWidth, h));
            });
        await save('$preview/on_photo.png', await onPhoto(790));
        await save('$preview/logo_light.png', await logoAt(900, logoImage, background: Colors.white));
        await save('$preview/logo_dark.png', await logoAt(900, logoOnDarkImage, background: navy));
        await save('$preview/mark_dark.png', await markAt(256, background: navy));
        await save('$preview/app_icon.png', await markAt(512, scale: 0.84, background: Colors.white), opaque: true);
        // Close up: the cross's edge, 3x.
        await save('$preview/edge_zoom.png', await render(600, 600, (c, s) {
          c.drawColor(const Color(0xFF6B4A2A), BlendMode.src);
          final m = markOnDarkImage;
          c.drawImageRect(m, Rect.fromLTWH(0, m.height * 0.25, m.width * 0.5, m.height * 0.5), Offset.zero & s, Paint());
        }));
        return;
      }

      const images = 'assets/images';
      const app = '../../apps/health_pro_app';
      const res = '$app/android/app/src/main/res';
      const ios = '$app/ios/Runner/Assets.xcassets';

      // In the app (HealthProLogo): the logo 1600 wide (150 tall at 3x), the
      // mark 512 square (it shows 54 tall at most).
      await saveWebp('$images/logo.webp', await logoAt(1600, logoImage));
      await saveWebp('$images/logo_on_dark.webp', await logoAt(1600, logoOnDarkImage));
      await saveWebp('$images/mark.webp', await markAt(512));
      await saveWebp('$images/mark_on_dark.webp', await markAt(512, image: markOnDarkImage));

      // Launch screens, on navy: the white-lettered logo, 240 wide.
      await saveWebp('$app/web/splash/logo.webp', await logoAt(720, logoOnDarkImage));
      for (final (dpi, scale) in [('mdpi', 1.0), ('hdpi', 1.5), ('xhdpi', 2.0), ('xxhdpi', 3.0), ('xxxhdpi', 4.0)]) {
        await save('$res/drawable-$dpi/splash_logo.png', await logoAt(240 * scale, logoOnDarkImage));
        // Android 12+: the mark in its 288dp icon, inside the 192dp circle.
        await save('$res/drawable-$dpi/splash_icon.png', await markAt((288 * scale).round(), scale: 0.5));
        await save('$res/mipmap-$dpi/ic_launcher.png',
            await markAt((48 * scale).round(), scale: 0.86, background: Colors.white), opaque: true);
      }
      for (final (suffix, scale) in [('', 1), ('@2x', 2), ('@3x', 3)]) {
        await save('$ios/LaunchImage.imageset/LaunchImage$suffix.png', await logoAt(240.0 * scale, logoOnDarkImage));
      }

      // App icons: the mark on white. iOS rounds them itself and wants no
      // transparency.
      for (final (name, size) in [
        ('20x20@1x', 20), ('20x20@2x', 40), ('20x20@3x', 60), ('29x29@1x', 29), ('29x29@2x', 58),
        ('29x29@3x', 87), ('40x40@1x', 40), ('40x40@2x', 80), ('40x40@3x', 120), ('60x60@2x', 120),
        ('60x60@3x', 180), ('76x76@1x', 76), ('76x76@2x', 152), ('83.5x83.5@2x', 167), ('1024x1024@1x', 1024),
      ]) {
        await save('$ios/AppIcon.appiconset/Icon-App-$name.png', await markAt(size, scale: 0.84, background: Colors.white),
            opaque: true);
      }
      // The web: home-screen icons (maskable keeps the mark inside the middle
      // 80%), and the favicon, the mark alone.
      for (final size in [192, 512]) {
        await save('$app/web/icons/Icon-$size.png', await markAt(size, scale: 0.84, background: Colors.white), opaque: true);
        await save('$app/web/icons/Icon-maskable-$size.png', await markAt(size, scale: 0.68, background: Colors.white),
            opaque: true);
      }
      await save('$app/web/favicon.png', await markAt(32));
    });
  });
}

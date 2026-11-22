import 'package:flutter/material.dart';

/// A 3D icon: soft, colourful, lit from above (Microsoft's Fluent Emoji 3D,
/// MIT, assets/icons3d/LICENSE.txt). The side menu and the search show these
/// beside its pages; elsewhere the flat [IconData] stays.
class Art3D {
  /// Its file in assets/icons3d/, without '.png'.
  final String name;

  const Art3D._(this.name);

  // The day's work.
  static const chartIncreasing = Art3D._('chart_increasing');
  static const barChart = Art3D._('bar_chart');
  static const bellhopBell = Art3D._('bellhop_bell');
  static const checkMark = Art3D._('check_mark_button');
  static const person = Art3D._('person');
  static const idCard = Art3D._('identification_card');
  static const memo = Art3D._('memo');
  static const phoneScan = Art3D._('mobile_phone_with_arrow');

  // What's waiting.
  static const inbox = Art3D._('inbox_tray');
  static const handshake = Art3D._('handshake');
  static const creditCard = Art3D._('credit_card');
  static const speechBalloon = Art3D._('speech_balloon');

  // Training.
  static const runner = Art3D._('person_running');
  static const calendar = Art3D._('spiral_calendar');
  static const biceps = Art3D._('flexed_biceps');
  static const liftingWeights = Art3D._('person_lifting_weights');

  // Money.
  static const moneyBag = Art3D._('money_bag');
  static const tickets = Art3D._('admission_tickets');
  static const priceTag = Art3D._('label');
  static const coin = Art3D._('coin');
  static const receipt = Art3D._('receipt');

  // Stock.
  static const package = Art3D._('package');
  static const clipboard = Art3D._('clipboard');
  static const truck = Art3D._('delivery_truck');

  // The team and settings.
  static const gear = Art3D._('gear');
  static const officeWorker = Art3D._('office_worker');
  static const key = Art3D._('key');
  static const tools = Art3D._('hammer_and_wrench');
  static const knobs = Art3D._('control_knobs');
  static const notepad = Art3D._('spiral_notepad');

  // The platform's own.
  static const house = Art3D._('house');
  static const puzzle = Art3D._('puzzle_piece');
  static const officeBuilding = Art3D._('office_building');
  static const classicalBuilding = Art3D._('classical_building');
  static const magnifier = Art3D._('magnifying_glass_tilted_left');
  static const cardFileBox = Art3D._('card_file_box');
  static const plug = Art3D._('electric_plug');
  static const ladybird = Art3D._('lady_beetle');
  static const rocket = Art3D._('rocket');
  static const bell = Art3D._('bell');

  /// Every one, for checking they're all there.
  static const all = [
    chartIncreasing, barChart, bellhopBell, checkMark, person, idCard, memo, phoneScan, inbox, handshake, creditCard,
    speechBalloon, runner, calendar, biceps, liftingWeights, moneyBag, tickets, priceTag, coin, receipt, package,
    clipboard, truck, gear, officeWorker, key, tools, knobs, notepad, house, puzzle, officeBuilding, classicalBuilding,
    magnifier, cardFileBox, plug, ladybird, rocket, bell,
  ];

  String get asset => 'assets/icons3d/$name.png';
}

/// An [Art3D] at [size], or [fallback] (a flat icon) if it can't be shown.
class Art3DIcon extends StatelessWidget {
  final Art3D art;
  final double size;
  final IconData? fallback;
  final Color? fallbackColor;

  const Art3DIcon(this.art, {super.key, this.size = 24, this.fallback, this.fallbackColor});

  /// How much colour the icons keep (1 = the emoji as drawn).
  static const saturation = 0.55;

  /// Turns saturation down to [s], keeping each pixel's brightness (Rec. 709 luma).
  static ColorFilter _saturation(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final k = 1 - s;
    return ColorFilter.matrix(<double>[
      r * k + s, g * k, b * k, 0, 0,
      r * k, g * k + s, b * k, 0, 0,
      r * k, g * k, b * k + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(colorFilter: _saturation(saturation), child: _image());
  }

  Widget _image() {
    return Image.asset(
      art.asset,
      package: 'health_pro_core',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, _, __) =>
          SizedBox.square(dimension: size, child: fallback == null ? null : Icon(fallback, size: size * 0.85, color: fallbackColor)),
    );
  }
}

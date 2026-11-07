import 'r_icon.dart';

/// Icon geometry copied from `design/export/artboards/` (Pairing, States,
/// Power). Circles and lines are written as equivalent path data.
abstract final class RIcons {
  static const back = RIconData(['m15 18-6-6 6-6']);

  static const flashlight = RIconData([
    'M18 6c0 2-2 2-2 4v10a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2V10c0-2-2-2-2-4V2h12z',
    'M6 6h12',
  ]);

  static const camera = RIconData([
    'M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z',
    'M15 13a3 3 0 1 1-6 0a3 3 0 1 1 6 0',
  ]);

  static const cameraOff = RIconData([
    'M2 2l20 20M7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16M9.5 4h5L17 7h3a2 2 0 0 1 2 2v7.3',
  ]);

  static const wifi = RIconData([
    'M12 20h.01M8.5 16.4a5 5 0 0 1 7 0M5 12.9a10 10 0 0 1 14 0M2 8.8a15 15 0 0 1 20 0',
  ]);

  static const wifiOff = RIconData([
    'M12 20h.01',
    'M8.5 16.4a5 5 0 0 1 7 0',
    'M5 12.9a10 10 0 0 1 5.2-2.8',
    'M19 12.9a10 10 0 0 0-2.9-2',
    'M2 8.8a15 15 0 0 1 4.2-2.6',
    'M22 8.8a15 15 0 0 0-11.3-3.8',
    'm2 2 20 20',
  ]);

  static const key = RIconData([
    'M15.5 7.5 19 4M21 2l-2 2 3 3-3.5 3.5-3-3M10.6 12.4a5 5 0 1 1-7.07 7.07 5 5 0 0 1 7.07-7.07Z',
  ]);

  static const plug = RIconData([
    'M12 22v-5M9 8V2M15 8V2M18 8v5a6 6 0 0 1-12 0V8Z',
  ]);

  static const check = RIconData(['M20 6 9 17l-5-5']);

  static const alertTriangle = RIconData([
    'M12 8v5M12 16.5h.01M10.3 3.9 2.4 18a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z',
  ]);

  static const alertCircle = RIconData([
    'M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0',
    'M12 8v4M12 16h.01',
  ]);

  static const eye = RIconData([
    'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z',
    'M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0',
  ]);

  static const settingsSliders = RIconData([
    'M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4',
  ]);

  static const power = RIconData(['M12 2v10', 'M18.4 6.6a9 9 0 1 1-12.77.04']);
}

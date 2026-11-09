import 'package:permission_handler/permission_handler.dart';

/// Camera permission status for the pairing flow (Q01, Q02, Q05).
enum CameraPermission { granted, denied, permanentlyDenied, restricted }

/// Camera permission. An interface so tests use a fake; the real implementation is below.
abstract interface class CameraPermissionService {
  /// Reads the status without showing the OS dialog.
  Future<CameraPermission> status();

  /// Shows the OS dialog. On Android, a permanently denied permission
  /// immediately returns [CameraPermission.permanentlyDenied] without a dialog.
  Future<CameraPermission> request();

  /// Opens the app settings on the phone. Returns false if it fails to open.
  Future<bool> openSettings();
}

/// Real implementation via `permission_handler`. The only place that package
/// is used for camera permission.
final class PermissionHandlerCameraService implements CameraPermissionService {
  const PermissionHandlerCameraService();

  @override
  Future<CameraPermission> status() async =>
      _fromStatus(await Permission.camera.status);

  @override
  Future<CameraPermission> request() async =>
      _fromStatus(await Permission.camera.request());

  @override
  Future<bool> openSettings() => openAppSettings();

  static CameraPermission _fromStatus(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted => CameraPermission.granted,
      PermissionStatus.permanentlyDenied => CameraPermission.permanentlyDenied,
      PermissionStatus.restricted => CameraPermission.restricted,
      PermissionStatus.denied ||
      PermissionStatus.limited ||
      PermissionStatus.provisional => CameraPermission.denied,
    };
  }
}

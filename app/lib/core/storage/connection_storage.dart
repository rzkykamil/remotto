import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pairing_data.dart';

/// Penyimpanan data sambungan. Implementasi nyata memakai secure storage;
/// test memakai implementasi in-memory.
abstract interface class ConnectionStorage {
  /// Mengembalikan null bila data tidak lengkap atau tidak bisa dibaca.
  Future<PairingData?> read();

  Future<void> write(PairingData data);

  Future<void> clear();
}

/// Menyimpan empat key sambungan di secure storage (data-design.md §6).
final class SecureConnectionStorage implements ConnectionStorage {
  const SecureConnectionStorage(this._storage);

  static const keyHost = 'remotto.host';
  static const keyPort = 'remotto.port';
  static const keyToken = 'remotto.token';
  static const keyLaptopName = 'remotto.laptopName';

  final FlutterSecureStorage _storage;

  /// Keempat key dibaca sebagai satu kesatuan. Salah satu hilang, port tidak
  /// valid, atau storage melempar exception: hasilnya null (dianggap kosong).
  @override
  Future<PairingData?> read() async {
    try {
      final host = await _storage.read(key: keyHost);
      final portRaw = await _storage.read(key: keyPort);
      final token = await _storage.read(key: keyToken);
      final laptopName = await _storage.read(key: keyLaptopName);

      if (host == null || host.isEmpty) return null;
      if (token == null || token.isEmpty) return null;
      if (laptopName == null) return null;
      if (portRaw == null) return null;

      final port = int.tryParse(portRaw);
      if (port == null || port < 1 || port > 65535) return null;

      return PairingData(
        host: host,
        port: port,
        token: token,
        laptopName: laptopName,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(PairingData data) async {
    await _storage.write(key: keyHost, value: data.host);
    await _storage.write(key: keyPort, value: data.port.toString());
    await _storage.write(key: keyToken, value: data.token);
    await _storage.write(key: keyLaptopName, value: data.laptopName);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: keyHost);
    await _storage.delete(key: keyPort);
    await _storage.delete(key: keyToken);
    await _storage.delete(key: keyLaptopName);
  }
}

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

/// Menyimpan key sambungan di secure storage (data-design.md §2). Empat key
/// wajib sebagai satu kesatuan; `remotto.agentId` opsional.
final class SecureConnectionStorage implements ConnectionStorage {
  const SecureConnectionStorage(this._storage);

  static const keyHost = 'remotto.host';
  static const keyPort = 'remotto.port';
  static const keyToken = 'remotto.token';
  static const keyLaptopName = 'remotto.laptopName';
  static const keyAgentId = 'remotto.agentId';

  final FlutterSecureStorage _storage;

  /// Empat key wajib dibaca sebagai satu kesatuan. Salah satu hilang, port tidak
  /// valid, atau storage melempar exception: hasilnya null (dianggap kosong).
  /// `agentId` yang hilang tidak membuat hasil null (pairing lama, sebelum M7).
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
        agentId: await _readAgentId(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Gagal baca `agentId` dianggap tidak ada, sama seperti key hilang.
  Future<String?> _readAgentId() async {
    try {
      return await _storage.read(key: keyAgentId);
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
    final agentId = data.agentId;
    if (agentId != null) {
      await _storage.write(key: keyAgentId, value: agentId);
    } else {
      await _storage.delete(key: keyAgentId);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: keyHost);
    await _storage.delete(key: keyPort);
    await _storage.delete(key: keyToken);
    await _storage.delete(key: keyLaptopName);
    await _storage.delete(key: keyAgentId);
  }
}

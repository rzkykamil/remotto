import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/remote/data/http_volume_repository.dart';
import 'package:remotto/features/remote/data/volume_repository.dart';
import 'package:remotto/features/remote/state/volume_controller.dart';

/// Source of the volume commands (`/volume` endpoints on the paired laptop).
/// Tests override it with a fake.
final volumeRepositoryProvider = Provider<VolumeRepository>(
  (ref) => HttpVolumeRepository(
    ref.watch(agentHttpClientProvider),
    () => ref.read(pairingProvider),
  ),
);

/// State and commands of the volume panel.
final volumeControllerProvider =
    NotifierProvider<VolumeController, VolumeState>(VolumeController.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/features/remote/data/volume_repository.dart';
import 'package:remotto/features/remote/state/volume_controller.dart';

/// Source of the volume commands. No default yet: the Integrasi phase installs
/// the HTTP repository, and tests override it with a fake.
final volumeRepositoryProvider = Provider<VolumeRepository>(
  (ref) => throw UnimplementedError('override volumeRepositoryProvider'),
);

/// State and commands of the volume panel.
final volumeControllerProvider =
    NotifierProvider<VolumeController, VolumeState>(VolumeController.new);

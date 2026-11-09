import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:remotto/features/remote/state/volume_providers.dart';

import 'fake_volume_repository.dart';

/// Override for [volumeRepositoryProvider]. Every test that renders
/// RemoteScreen needs it, because the provider has no default until the
/// Integrasi phase. Pass [repo] to keep a reference for assertions.
Override volumeOverride([FakeVolumeRepository? repo]) =>
    volumeRepositoryProvider.overrideWithValue(repo ?? FakeVolumeRepository());

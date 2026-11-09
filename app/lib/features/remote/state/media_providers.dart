import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/remote/data/http_media_repository.dart';
import 'package:remotto/features/remote/data/media_repository.dart';
import 'package:remotto/features/remote/state/media_controller.dart';

/// Source of the media commands (`POST /media/{action}` to the paired laptop).
final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => HttpMediaRepository(
    ref.watch(agentHttpClientProvider),
    () => ref.read(pairingProvider),
  ),
);

/// State and commands of the media dock.
final mediaControllerProvider = NotifierProvider<MediaController, MediaState>(
  MediaController.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/features/remote/data/media_repository.dart';
import 'package:remotto/features/remote/data/mock_media_repository.dart';
import 'package:remotto/features/remote/state/media_controller.dart';

const _mockMediaDelay = Duration(milliseconds: 150);

/// Source of the media commands. Mock always succeeds for now.
/// The Integrasi phase replaces it with the HTTP implementation.
final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MockMediaRepository(const [MockMediaEcho()], delay: _mockMediaDelay),
);

/// State and commands of the media dock.
final mediaControllerProvider = NotifierProvider<MediaController, MediaState>(
  MediaController.new,
);

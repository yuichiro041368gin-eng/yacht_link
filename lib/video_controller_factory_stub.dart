import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(String path) {
  return VideoPlayerController.networkUrl(Uri.parse(path));
}

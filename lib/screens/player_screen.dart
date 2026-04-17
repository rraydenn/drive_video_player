import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoPlayerScreen extends StatefulWidget {
  final List<drive.File> videoList;
  final int currentIndex;
  final String accessToken;

  const VideoPlayerScreen({
    super.key,
    required this.videoList,
    required this.currentIndex,
    required this.accessToken,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _hasError = false;

  Timer? _autoplayTimer;
  int _countdown = 5;
  bool _showAutoplayOverlay = false;
  bool _autoplayCanceled = false;

  bool get _canSkip => widget.videoList.length > 1;
  int get _nextIndex => (widget.currentIndex + 1) % widget.videoList.length;
  int get _prevIndex => (widget.currentIndex - 1 + widget.videoList.length) % widget.videoList.length;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _player = Player();
      _videoController = VideoController(_player);

      final prefs = await SharedPreferences.getInstance();
      double savedVolume = prefs.getDouble('video_volume') ?? 100.0;
      await _player.setVolume(savedVolume);

      _player.stream.volume.listen((double v) {
        prefs.setDouble('video_volume', v);
      });

      final currentVideo = widget.videoList[widget.currentIndex];
      final videoUrl = 'https://www.googleapis.com/drive/v3/files/${currentVideo.id}?alt=media';

      await _player.open(
        Media(
          videoUrl,
          httpHeaders: {'Authorization': 'Bearer ${widget.accessToken}'},
        ),
        play: true,
      );

      _player.stream.completed.listen((completed) {
        if (completed && !_showAutoplayOverlay && !_autoplayCanceled && _canSkip) {
          _startAutoplayCountdown();
        }
      });

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("MediaKit Error: $e");
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _startAutoplayCountdown() {
    setState(() {
      _showAutoplayOverlay = true;
      _countdown = 5;
    });

    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _playTargetVideo(_nextIndex);
      }
    });
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    setState(() {
      _showAutoplayOverlay = false;
      _autoplayCanceled = true;
    });
  }

  void _playTargetVideo(int targetIndex) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) => VideoPlayerScreen(
          videoList: widget.videoList,
          currentIndex: targetIndex,
          accessToken: widget.accessToken,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _cleanName(String? name) {
    if (name == null) return 'Unknown Video';
    return name.replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final currentVideo = widget.videoList[widget.currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(_cleanName(currentVideo.name)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: _canSkip ? () => _playTargetVideo(_prevIndex) : null,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: _canSkip ? () => _playTargetVideo(_nextIndex) : null,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _hasError
            ? const Text('Error loading video', style: TextStyle(color: Colors.white))
            : Stack(
          alignment: Alignment.center,
          children: [
            Video(controller: _videoController),
            if (_showAutoplayOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next video in $_countdown...', style: const TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 10),
                      Text(_cleanName(widget.videoList[_nextIndex].name),
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(onPressed: _cancelAutoplay, style: OutlinedButton.styleFrom(foregroundColor: Colors.white), child: const Text('Cancel')),
                          const SizedBox(width: 20),
                          ElevatedButton(onPressed: () { _autoplayTimer?.cancel(); _playTargetVideo(_nextIndex); }, child: const Text('Play Now')),
                        ],
                      )
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}
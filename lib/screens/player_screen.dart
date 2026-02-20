import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _hasError = false;

  Timer? _autoplayTimer;
  int _countdown = 5;
  bool _showAutoplayOverlay = false;
  bool _autoplayCanceled = false;

  // --- V2 UPDATE: WRAP AROUND LOGIC ---
  // Only enable skip buttons if there is more than 1 video in the entire list
  bool get _canSkip => widget.videoList.length > 1;

  // Calculates the index safely, looping back to the start (or end) when needed
  int get _nextIndex => (widget.currentIndex + 1) % widget.videoList.length;
  int get _prevIndex => (widget.currentIndex - 1 + widget.videoList.length) % widget.videoList.length;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  String _cleanName(String? name) {
    if (name == null) return 'Unknown Video';
    return name.replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  Future<void> _initializePlayer() async {
    try {
      final currentVideo = widget.videoList[widget.currentIndex];

      final videoUrl = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/${currentVideo.id}?alt=media');

      _videoPlayerController = VideoPlayerController.networkUrl(
        videoUrl,
        httpHeaders: {'Authorization': 'Bearer ${widget.accessToken}'},
      );

      await _videoPlayerController.initialize();
      _videoPlayerController.addListener(_videoListener);

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController.value.aspectRatio,
        allowFullScreen: true,
      );

      setState(() {});
    } catch (e) {
      debugPrint("Video Player Error: $e");
      setState(() => _hasError = true);
    }
  }

  void _videoListener() {
    if (!_videoPlayerController.value.isInitialized) return;

    final position = _videoPlayerController.value.position;
    final duration = _videoPlayerController.value.duration;

    if (position < duration && _autoplayCanceled) {
      _autoplayCanceled = false;
    }

    if (duration != Duration.zero && position >= duration) {
      if (!_showAutoplayOverlay && !_autoplayCanceled) {
        // Trigger autoplay as long as the list has more than 1 video
        if (_canSkip) {
          _startAutoplayCountdown();
        }
      }
    }
  }

  void _startAutoplayCountdown() {
    if (_chewieController?.isFullScreen ?? false) {
      _chewieController?.exitFullScreen();
    }

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

  // --- V2 UPDATE: INSTANT TRANSITIONS ---
  void _playTargetVideo(int targetIndex) {
    Navigator.pushReplacement(
      context,
      // PageRouteBuilder replaces MaterialPageRoute so we can kill the animation completely
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
    _videoPlayerController.removeListener(_videoListener);
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
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
            tooltip: 'Previous Video',
            // Button is greyed out only if there's just 1 video total
            onPressed: _canSkip ? () => _playTargetVideo(_prevIndex) : null,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Next Video',
            onPressed: _canSkip ? () => _playTargetVideo(_nextIndex) : null,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _hasError
            ? const Text('Error loading video', style: TextStyle(color: Colors.white))
            : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
            ? Stack(
          alignment: Alignment.center,
          children: [
            Chewie(controller: _chewieController!),

            if (_showAutoplayOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                          'Next video in $_countdown...',
                          style: const TextStyle(color: Colors.white, fontSize: 18)
                      ),
                      const SizedBox(height: 10),
                      // Now correctly looks ahead to the wrapped _nextIndex!
                      Text(
                        _cleanName(widget.videoList[_nextIndex].name),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: _cancelAutoplay,
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton(
                            onPressed: () {
                              _autoplayTimer?.cancel();
                              _playTargetVideo(_nextIndex);
                            },
                            child: const Text('Play Now'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              )
          ],
        )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
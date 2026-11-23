import 'dart:async';

import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Modal dialog that initializes and plays a product demo video on demand.
class VideoDetailDialog extends StatefulWidget {
  const VideoDetailDialog({
    super.key,
    required this.product,
    required this.media,
    this.videoBuilder,
    this.controllerFactory,
  });

  final Product product;
  final ProductMedia media;

  /// Optional test hook to render a custom video surface without platform codecs.
  final Widget Function(BuildContext context, ProductMedia media)? videoBuilder;

  /// Optional factory hook for injecting a [VideoPlayerController] in tests.
  final VideoPlayerController Function(Uri uri)? controllerFactory;

  @override
  State<VideoDetailDialog> createState() => _VideoDetailDialogState();
}

class _VideoDetailDialogState extends State<VideoDetailDialog> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoBuilder == null) {
      final uri = Uri.tryParse(widget.media.mediaUrl);
      if (uri == null || !uri.hasScheme) {
        _hasError = true;
        return;
      }
      final createController =
          widget.controllerFactory ?? VideoPlayerController.networkUrl;
      final controller = createController(uri);
      _controller = controller;
      _initializeController(controller);
    }
  }

  Future<void> _initializeController(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      if (!mounted) return;
      await controller.play();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _buildVideoSurface(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.product.sku} • ĐVT: ${widget.product.unit}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        CurrencyFormatter.formatVnd(widget.product.price),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFEE4D2D),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    if (widget.videoBuilder != null) {
      return widget.videoBuilder!(context, widget.media);
    }
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 40),
            SizedBox(height: 8),
            Text(
              'Không thể phát video sản phẩm',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }
    final controller = _controller;
    if (!_isInitialized || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return GestureDetector(
          key: const Key('video-player-surface'),
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayback,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio:
                      value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                  child: VideoPlayer(controller),
                ),
              ),
              if (!value.isPlaying)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

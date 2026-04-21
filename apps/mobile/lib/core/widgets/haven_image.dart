import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:shimmer/shimmer.dart';

/// Branded network image with cache, skeleton placeholder, and error state.
///
/// Use this everywhere instead of `Image.network` / `NetworkImage` so we:
///   * cache bytes on disk across app launches (`cached_network_image`),
///   * show a shimmering skeleton in brand colors while bytes load,
///   * fall back to a branded placeholder on error instead of the broken-image
///     glyph that ships with Material,
///   * get consistent rounded corners when the caller supplies a radius.
///
/// If [url] is null or empty, the placeholder renders immediately — no
/// network call is queued.
class HavenImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double? borderRadius;
  final Widget? errorFallback;
  final Widget? emptyFallback;

  const HavenImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorFallback,
    this.emptyFallback,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (url == null || url!.isEmpty) {
      child = emptyFallback ?? _defaultPlaceholder();
    } else {
      child = CachedNetworkImage(
        imageUrl: url!,
        width: width,
        height: height,
        fit: fit,
        fadeInDuration: HavenMotion.medium,
        fadeOutDuration: HavenMotion.fast,
        placeholder: (_, __) => _ShimmerTile(width: width, height: height),
        errorWidget: (_, __, ___) =>
            errorFallback ?? _defaultErrorFallback(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius!),
        child: child,
      );
    }
    return child;
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: HavenColors.surface,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: HavenColors.textTertiary,
        size: 28,
      ),
    );
  }

  Widget _defaultErrorFallback() {
    return Container(
      width: width,
      height: height,
      color: HavenColors.surface,
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: HavenColors.textTertiary,
        size: 28,
      ),
    );
  }
}

/// Convenience constructor for circular avatars (matches `CircleAvatar` sizing
/// but uses the cached pipeline). Use for user photos / partner logos so they
/// don't re-download on every scroll.
class HavenAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Widget fallback;
  final Color? backgroundColor;

  const HavenAvatar({
    super.key,
    required this.url,
    required this.fallback,
    this.radius = 20,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final bg = backgroundColor ?? HavenColors.primary;
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: fallback,
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: HavenMotion.medium,
        placeholder: (_, __) => _ShimmerTile(width: size, height: size),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          child: fallback,
        ),
      ),
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  final double? width;
  final double? height;
  const _ShimmerTile({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: HavenColors.surface,
      highlightColor: HavenColors.elevated,
      period: const Duration(milliseconds: 1400),
      child: Container(
        width: width,
        height: height,
        color: HavenColors.surface,
      ),
    );
  }
}

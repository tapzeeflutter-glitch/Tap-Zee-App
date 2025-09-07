import 'package:flutter/material.dart';

/// A reusable logo widget for the app
/// Supports different sizes and colors for various use cases
class AppLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  final BoxFit fit;
  final String? logoPath;

  const AppLogo({
    Key? key,
    this.width,
    this.height,
    this.color,
    this.fit = BoxFit.contain,
    this.logoPath,
  }) : super(key: key);

  /// Small logo for AppBar
  const AppLogo.small({Key? key, this.color, this.logoPath})
    : width = 32,
      height = 32,
      fit = BoxFit.contain,
      super(key: key);

  /// Medium logo for cards/sections
  const AppLogo.medium({Key? key, this.color, this.logoPath})
    : width = 64,
      height = 64,
      fit = BoxFit.contain,
      super(key: key);

  /// Large logo for splash/welcome screens
  const AppLogo.large({Key? key, this.color, this.logoPath})
    : width = 120,
      height = 120,
      fit = BoxFit.contain,
      super(key: key);

  /// Extra large logo for main branding
  const AppLogo.extraLarge({Key? key, this.color, this.logoPath})
    : width = 200,
      height = 200,
      fit = BoxFit.contain,
      super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use the actual logo file
    final String assetPath = logoPath ?? 'assets/images/Logo.png';

    return Container(
      width: width,
      height: height,
      child: _buildLogo(assetPath),
    );
  }

  Widget _buildLogo(String assetPath) {
    try {
      return Image.asset(
        assetPath,
        width: width,
        height: height,
        color: color,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackLogo();
        },
      );
    } catch (e) {
      return _buildFallbackLogo();
    }
  }

  /// Fallback logo when image is not found
  Widget _buildFallbackLogo() {
    return Container(
      width: width ?? 120,
      height: height ?? 120,
      decoration: BoxDecoration(
        color: color ?? Colors.lightBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.apps, size: (width ?? 120) * 0.6, color: Colors.white),
    );
  }
}

/// Logo with text combination
class AppLogoWithText extends StatelessWidget {
  final double? logoSize;
  final String appName;
  final TextStyle? textStyle;
  final MainAxisAlignment alignment;
  final double spacing;
  final Axis direction;

  const AppLogoWithText({
    Key? key,
    this.logoSize,
    required this.appName,
    this.textStyle,
    this.alignment = MainAxisAlignment.center,
    this.spacing = 12,
    this.direction = Axis.horizontal,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logo = AppLogo(width: logoSize ?? 40, height: logoSize ?? 40);

    final text = Text(
      appName,
      style: textStyle ?? Theme.of(context).textTheme.headlineMedium,
    );

    if (direction == Axis.horizontal) {
      return Row(
        mainAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          logo,
          SizedBox(width: spacing),
          text,
        ],
      );
    } else {
      return Column(
        mainAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          logo,
          SizedBox(height: spacing),
          text,
        ],
      );
    }
  }
}

/// Animated logo for splash screens
class AnimatedAppLogo extends StatefulWidget {
  final double? size;
  final Duration duration;
  final Curve curve;

  const AnimatedAppLogo({
    Key? key,
    this.size,
    this.duration = const Duration(milliseconds: 1500),
    this.curve = Curves.elasticOut,
  }) : super(key: key);

  @override
  _AnimatedAppLogoState createState() => _AnimatedAppLogoState();
}

class _AnimatedAppLogoState extends State<AnimatedAppLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value,
            child: AppLogo(
              width: widget.size ?? 120,
              height: widget.size ?? 120,
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

enum InstrumentHandleRole { move, remove, rotate, resize, pencil }

/// Small circular drag/tap handle reused by every Math Pad instrument,
/// matching the red-remove / purple-rotate / green-resize convention from
/// the reference design. Positioned by the caller (each handle is a plain,
/// un-rotated circle at a computed world position — only its position moves
/// as the owning instrument rotates, not the handle itself).
class InstrumentHandle extends StatelessWidget {
  final InstrumentHandleRole role;
  final String tooltip;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  /// Only used by [InstrumentHandleRole.pencil]: true once tapped ("ready
  /// to draw"), rendered blue instead of the default idle gray.
  final bool armed;

  const InstrumentHandle({
    super.key,
    required this.role,
    required this.tooltip,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.armed = false,
  });

  static const double size = 26;

  Color get _color {
    switch (role) {
      case InstrumentHandleRole.remove:
        return const Color(0xFFEF4444);
      case InstrumentHandleRole.rotate:
        return const Color(0xFF9333EA);
      case InstrumentHandleRole.resize:
        return const Color(0xFF22C55E);
      case InstrumentHandleRole.move:
        return const Color(0xFF6366F1);
      case InstrumentHandleRole.pencil:
        return armed ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF);
    }
  }

  IconData get _icon {
    switch (role) {
      case InstrumentHandleRole.remove:
        return Icons.close_rounded;
      case InstrumentHandleRole.rotate:
        return Icons.refresh_rounded;
      case InstrumentHandleRole.resize:
        return Icons.open_in_full_rounded;
      case InstrumentHandleRole.move:
        return Icons.open_with_rounded;
      case InstrumentHandleRole.pencil:
        return Icons.edit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The pencil handle sits directly over the drawing itself (unlike
    // move/rotate/resize/remove, which float beside the instrument body),
    // so the flat opaque white disc the other roles use was needlessly
    // blocking whatever's underneath it. No fill and no blur/backdrop
    // effect at all -- just a plain see-through ring (the same coloured
    // border every other handle already uses) with the icon on top.
    final bool isPencil = role == InstrumentHandleRole.pencil;

    final Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPencil ? null : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(_icon, size: 14, color: _color),
    );

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: circle,
      ),
    );
  }
}

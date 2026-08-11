import 'package:flutter/material.dart';
import '../services/geocoding_service.dart';

/// Displays a reverse-geocoded, human-readable location ("Bosila,
/// Mohammadpur") for a pair of coordinates, instead of raw lat/lng or a
/// hand-typed address string. Resolves once per distinct coordinate pair —
/// [GeocodingService] caches the result, and this widget only re-resolves
/// when [latitude]/[longitude] actually change (e.g. a live position
/// update), never on every rebuild.
class LiveLocationText extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final IconData? icon;
  final double iconSize;
  final Color? iconColor;

  const LiveLocationText({
    super.key,
    required this.latitude,
    required this.longitude,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.icon,
    this.iconSize = 14,
    this.iconColor,
  });

  @override
  State<LiveLocationText> createState() => _LiveLocationTextState();
}

class _LiveLocationTextState extends State<LiveLocationText> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant LiveLocationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude || oldWidget.longitude != widget.longitude) {
      _resolved = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat == null || lng == null) return;
    final resolved = await GeocodingService.reverseGeocode(lat, lng);
    if (mounted) setState(() => _resolved = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final label = _resolved ?? (widget.latitude == null ? 'Location unavailable' : 'Locating…');
    final text = Text(label, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow);
    if (widget.icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(widget.icon, size: widget.iconSize, color: widget.iconColor),
        const SizedBox(width: 4),
        Expanded(child: text),
      ],
    );
  }
}

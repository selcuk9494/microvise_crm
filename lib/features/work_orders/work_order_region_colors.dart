import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/format/search_normalize.dart';

class WorkOrderRegionColor {
  const WorkOrderRegionColor({
    required this.regionKey,
    required this.label,
    required this.bgColor,
    required this.borderColor,
  });

  final String regionKey;
  final String label;
  final Color bgColor;
  final Color borderColor;
}

class WorkOrderRegionThemeResolver {
  const WorkOrderRegionThemeResolver(this._colors);

  final Map<String, WorkOrderRegionColor> _colors;

  static const _default = <String, WorkOrderRegionColor>{
    'girne': WorkOrderRegionColor(
      regionKey: 'girne',
      label: 'Girne',
      bgColor: Color(0xFFEEF2FF),
      borderColor: Color(0xFF364FC7),
    ),
    'guzelyurt': WorkOrderRegionColor(
      regionKey: 'guzelyurt',
      label: 'Güzelyurt',
      bgColor: Color(0xFFEBFBEE),
      borderColor: Color(0xFF2B8A3E),
    ),
    'iskele': WorkOrderRegionColor(
      regionKey: 'iskele',
      label: 'İskele',
      bgColor: Color(0xFFFFF9DB),
      borderColor: Color(0xFFF59F00),
    ),
    'magusa': WorkOrderRegionColor(
      regionKey: 'magusa',
      label: 'Gazimağusa',
      bgColor: Color(0xFFFFF4E6),
      borderColor: Color(0xFFF76707),
    ),
    'lefke': WorkOrderRegionColor(
      regionKey: 'lefke',
      label: 'Lefke',
      bgColor: Color(0xFFF1F3F5),
      borderColor: Color(0xFF495057),
    ),
    'lefkosa': WorkOrderRegionColor(
      regionKey: 'lefkosa',
      label: 'Lefkoşa',
      bgColor: Color(0xFFFFF8F0),
      borderColor: Color(0xFF7C4A2D),
    ),
  };

  static WorkOrderRegionThemeResolver defaults() =>
      const WorkOrderRegionThemeResolver(_default);

  static String normalizeRegionKey(String? city) {
    final v = (city ?? '').trim();
    if (v.isEmpty) return '';
    final key = normalizeSearchText(v).replaceAll(' ', '');
    if (key == 'gazimagusa') return 'magusa';
    return key;
  }

  static int _hashString32(String input) {
    var hash = 0x811C9DC5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  Color accent(String? city, {required int fallbackIndex}) {
    final key = normalizeRegionKey(city);
    if (key.isEmpty) return _rowAccentColor(fallbackIndex);
    final fixed = _colors[key];
    if (fixed != null) return fixed.borderColor;
    final h = _hashString32(key) % 360;
    return HSLColor.fromAHSL(1, h.toDouble(), 0.62, 0.42).toColor();
  }

  Color? background(String? city) {
    final key = normalizeRegionKey(city);
    if (key.isEmpty) return null;
    final fixed = _colors[key];
    if (fixed != null) return fixed.bgColor;
    final h = _hashString32(key) % 360;
    return HSLColor.fromAHSL(1, h.toDouble(), 0.60, 0.94).toColor();
  }

  List<WorkOrderRegionColor> get items =>
      _colors.values.toList(growable: false);
}

Color _rowAccentColor(int index) {
  const palette = [
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFFEF4444),
    Color(0xFF0EA5E9),
  ];
  return palette[index % palette.length];
}

Color _parseHexColor(String hex) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length == 6) {
    return Color(int.parse('FF$cleaned', radix: 16));
  }
  if (cleaned.length == 8) {
    return Color(int.parse(cleaned, radix: 16));
  }
  return const Color(0xFF94A3B8);
}

final workOrderRegionThemeProvider =
    FutureProvider<WorkOrderRegionThemeResolver>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return WorkOrderRegionThemeResolver.defaults();
  try {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: const {'resource': 'definition_region_colors'},
    );
    final maps = ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);

    final base = <String, WorkOrderRegionColor>{
      for (final e in WorkOrderRegionThemeResolver.defaults().items) e.regionKey: e,
    };

    for (final m in maps) {
      final key = (m['region_key'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final label = (m['label'] ?? key).toString();
      final bg = _parseHexColor((m['bg_color'] ?? '').toString());
      final border = _parseHexColor((m['border_color'] ?? '').toString());
      base[key] = WorkOrderRegionColor(
        regionKey: key,
        label: label,
        bgColor: bg,
        borderColor: border,
      );
    }

    return WorkOrderRegionThemeResolver(base);
  } catch (_) {
    return WorkOrderRegionThemeResolver.defaults();
  }
});


class AppUtils {
  /// Convert bytes to human-readable format
  static String humanSize(dynamic value) {
    if (value == null) return '';
    int? bytes;
    if (value is int) {
      bytes = value;
    } else if (value is double) {
      bytes = value.toInt();
    } else if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) bytes = parsed;
    }
    if (bytes == null) return value.toString();

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double b = bytes.toDouble();
    int i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b < 10 ? 2 : (b < 100 ? 1 : 0))} ${units[i]}';
  }

  /// Try to find a numeric size field in a model map
  static dynamic findSizeField(Map<String, dynamic> m) {
    for (final k in m.keys) {
      final lk = k.toLowerCase();
      if (lk.contains('size') ||
          lk.contains('bytes') ||
          lk.contains('file_size')) {
        return m[k];
      }
    }
    // try nested maps
    for (final v in m.values) {
      if (v is Map) {
        for (final k2 in v.keys) {
          final lk2 = k2.toString().toLowerCase();
          if (lk2.contains('size') ||
              lk2.contains('bytes') ||
              lk2.contains('file_size')) {
            return v[k2];
          }
        }
      }
    }
    return null;
  }

  /// Build base URL from endpoint
  static String baseUrlFromEndpoint(String endpoint) {
    try {
      final uri = Uri.parse(endpoint);
      final host = uri.host;
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
      final portPart = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://$host$portPart';
    } catch (_) {
      return endpoint; // fallback
    }
  }

  /// Normalize endpoint URL
  static String normalizeEndpoint(String value) {
    var v = value.trim();
    if (v.contains('/api/')) {
      v = v.split('/api/')[0];
    }
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    return v;
  }
}

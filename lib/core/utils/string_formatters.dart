/// String helpers for PasswordSaver naming rules.
class StringFormatters {
  StringFormatters._();

  /// Converts any service label so every word starts with a capital letter.
  ///
  /// Examples:
  /// - `sarkari result` → `Sarkari Result`
  /// - `HDFC net-banking` → `Hdfc Net Banking`
  /// - `sarkari_result` → `Sarkari Result`
  static String toTitleCase(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return '';

    // Split on spaces, underscores, hyphens, and other non-alphanumeric chars
    final parts = cleaned
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '';

    return parts.map((part) {
      if (part.isEmpty) return part;
      final lower = part.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.length > 1 ? lower.substring(1) : ''}';
    }).join(' ');
  }
}

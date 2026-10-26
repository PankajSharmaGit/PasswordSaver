import 'dart:convert';

import '../../domain/entities/entities.dart';
import '../../domain/entities/platform_category.dart';

/// Plaintext vault card that another PasswordSaver install can import.
class SharedCredential {
  const SharedCredential({
    required this.title,
    required this.accountUserId,
    required this.password,
    this.description = '',
    this.website,
    this.platform = PlatformCategory.other,
    this.customPlatformName,
    this.accountGroup,
  });

  final String title;
  final String accountUserId;
  final String password;
  final String description;
  final String? website;
  final PlatformCategory platform;
  final String? customPlatformName;
  final String? accountGroup;
}

/// `PSVAULT1:` + base64 JSON. Safe to paste from WhatsApp / files.
class CredentialShareCodec {
  CredentialShareCodec._();

  static const String prefix = 'PSVAULT1:';

  static String encode(SharedCredential item) {
    final payload = jsonEncode({
      'v': 1,
      'title': item.title,
      'accountUserId': item.accountUserId,
      'password': item.password,
      'description': item.description,
      'website': item.website,
      'platform': item.platform.name,
      'customPlatformName': item.customPlatformName,
      'accountGroup': item.accountGroup,
    });
    return '$prefix${base64Encode(utf8.encode(payload))}';
  }

  static String readable(SharedCredential item) {
    final service = item.platform == PlatformCategory.other &&
            (item.customPlatformName ?? '').trim().isNotEmpty
        ? item.customPlatformName!.trim()
        : PlatformInfo.of(item.platform).label;
    final lines = <String>[
      'PasswordSaver',
      'Title: ${item.title}',
      'Service: $service',
      if ((item.accountGroup ?? '').trim().isNotEmpty)
        'Group: ${item.accountGroup!.trim()}',
      'User ID: ${item.accountUserId}',
      'Password: ${item.password}',
      if ((item.website ?? '').trim().isNotEmpty) 'Website: ${item.website!.trim()}',
      if (item.description.trim().isNotEmpty) 'Notes: ${item.description.trim()}',
    ];
    return lines.join('\n');
  }

  static SharedCredential? decode(String raw) {
    final text = raw.trim();
    final start = text.indexOf(prefix);
    if (start < 0) return null;
    var token = text.substring(start + prefix.length).trim();
    final end = token.indexOf(RegExp(r'\s'));
    if (end > 0) token = token.substring(0, end);
    try {
      final map = jsonDecode(utf8.decode(base64Decode(token)));
      if (map is! Map) return null;
      final title = '${map['title'] ?? ''}'.trim();
      final userId = '${map['accountUserId'] ?? ''}'.trim();
      final password = '${map['password'] ?? ''}';
      if (title.isEmpty || userId.isEmpty || password.isEmpty) return null;
      return SharedCredential(
        title: title,
        accountUserId: userId,
        password: password,
        description: '${map['description'] ?? ''}',
        website: map['website']?.toString(),
        platform: PlatformInfo.fromName('${map['platform'] ?? 'other'}'),
        customPlatformName: map['customPlatformName']?.toString(),
        accountGroup: map['accountGroup']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

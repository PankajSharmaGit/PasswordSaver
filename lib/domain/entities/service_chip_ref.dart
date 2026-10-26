import 'platform_category.dart';

/// A service that can appear on the dashboard chip row, with user-set priority.
class ServiceChipRef {
  const ServiceChipRef.builtin(this.platform) : customName = null;

  const ServiceChipRef.custom(this.customName) : platform = null;

  final PlatformCategory? platform;
  final String? customName;

  bool get isCustom => customName != null && customName!.trim().isNotEmpty;

  String get label {
    if (isCustom) return customName!.trim();
    return PlatformInfo.of(platform!).label;
  }

  String get iconName {
    if (isCustom) return 'lock';
    return PlatformInfo.of(platform!).iconName;
  }

  /// Stable key for storage / reorder widgets.
  String get storageKey =>
      isCustom ? 'c:${customName!.trim()}' : 'b:${platform!.name}';

  bool matchesFilter({
    PlatformCategory? filter,
    String? customFilter,
  }) {
    if (isCustom) {
      return customFilter != null &&
          customFilter.toLowerCase() == customName!.toLowerCase();
    }
    return customFilter == null && filter == platform;
  }

  Map<String, dynamic> toJson() => {
        'type': isCustom ? 'custom' : 'builtin',
        'id': isCustom ? customName!.trim() : platform!.name,
      };

  static ServiceChipRef? fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    if (type == 'custom') {
      return ServiceChipRef.custom(id);
    }
    final cat = PlatformCategory.values.where((e) => e.name == id);
    if (cat.isEmpty || cat.first == PlatformCategory.other) return null;
    return ServiceChipRef.builtin(cat.first);
  }

  /// Default chip order before the user customizes priority.
  static List<ServiceChipRef> defaultPriority() {
    const defaults = <PlatformCategory>[
      PlatformCategory.email,
      PlatformCategory.outlook,
      PlatformCategory.google,
      PlatformCategory.whatsapp,
      PlatformCategory.banking,
      PlatformCategory.facebook,
      PlatformCategory.instagram,
      PlatformCategory.microsoft,
      PlatformCategory.linkedin,
      PlatformCategory.twitter,
      PlatformCategory.appStore,
      PlatformCategory.playStore,
      PlatformCategory.government,
      PlatformCategory.system,
      PlatformCategory.mobile,
      PlatformCategory.netflix,
      PlatformCategory.amazon,
      PlatformCategory.github,
    ];
    return defaults.map(ServiceChipRef.builtin).toList();
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceChipRef && other.storageKey == storageKey;

  @override
  int get hashCode => storageKey.hashCode;
}

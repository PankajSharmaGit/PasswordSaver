/// Platform categories for the password vault dashboard (requirement 6, 12).
enum PlatformCategory {
  email,
  outlook,
  google,
  microsoft,
  whatsapp,
  facebook,
  instagram,
  twitter,
  linkedin,
  appStore,
  playStore,
  banking,
  government,
  system,
  mobile,
  netflix,
  amazon,
  github,
  other,
}

/// Metadata for UI icons and labels.
class PlatformInfo {
  const PlatformInfo({
    required this.category,
    required this.label,
    required this.iconName,
  });

  final PlatformCategory category;
  final String label;
  final String iconName;

  static const List<PlatformInfo> all = [
    PlatformInfo(category: PlatformCategory.email, label: 'Email', iconName: 'email'),
    PlatformInfo(category: PlatformCategory.outlook, label: 'Outlook', iconName: 'outlook'),
    PlatformInfo(category: PlatformCategory.google, label: 'Google', iconName: 'google'),
    PlatformInfo(category: PlatformCategory.microsoft, label: 'Microsoft', iconName: 'microsoft'),
    PlatformInfo(category: PlatformCategory.whatsapp, label: 'WhatsApp', iconName: 'chat'),
    PlatformInfo(category: PlatformCategory.facebook, label: 'Facebook', iconName: 'facebook'),
    PlatformInfo(category: PlatformCategory.instagram, label: 'Instagram', iconName: 'camera'),
    PlatformInfo(category: PlatformCategory.twitter, label: 'X / Twitter', iconName: 'tag'),
    PlatformInfo(category: PlatformCategory.linkedin, label: 'LinkedIn', iconName: 'work'),
    PlatformInfo(category: PlatformCategory.appStore, label: 'App Store', iconName: 'apple'),
    PlatformInfo(category: PlatformCategory.playStore, label: 'Play Store', iconName: 'store'),
    PlatformInfo(category: PlatformCategory.banking, label: 'Banking', iconName: 'account_balance'),
    PlatformInfo(category: PlatformCategory.government, label: 'Government', iconName: 'account_balance_gov'),
    PlatformInfo(category: PlatformCategory.system, label: 'System / PC', iconName: 'computer'),
    PlatformInfo(category: PlatformCategory.mobile, label: 'Mobile Device', iconName: 'phone'),
    PlatformInfo(category: PlatformCategory.netflix, label: 'Netflix', iconName: 'tv'),
    PlatformInfo(category: PlatformCategory.amazon, label: 'Amazon', iconName: 'shopping'),
    PlatformInfo(category: PlatformCategory.github, label: 'GitHub', iconName: 'code'),
    PlatformInfo(category: PlatformCategory.other, label: 'Custom / Manual', iconName: 'lock'),
  ];

  static PlatformInfo of(PlatformCategory category) {
    return all.firstWhere(
      (p) => p.category == category,
      orElse: () => all.last,
    );
  }

  static PlatformCategory fromName(String name) {
    return PlatformCategory.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PlatformCategory.other,
    );
  }
}

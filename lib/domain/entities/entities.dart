import 'platform_category.dart';
import '../../core/constants/app_constants.dart';

/// User profile entity (domain layer).
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.userId,
    this.primaryMobile,
    this.secondaryMobile,
    this.photoUrl,
    this.deviceDetails = const {},
    this.emailVerified = false,
    this.primaryMobileVerified = false,
    this.recoveryEmailVerified = false,
    this.createdAt,
    this.trialStartedAt,
    this.subscriptionExpiresAt,
    this.lastExpiresAt,
    this.isTrialActive = true,
    this.subscriptionPlanMonths,
    this.isLifetimeFree = false,
    this.filePlanMonths,
    this.filePlanMaxFiles,
    this.filePlanExpiresAt,
    this.isBlocked = false,
    this.countryCode,
    this.countryName,
    this.buyerGstin,
  });

  final String uid;
  final String email;
  final String displayName;
  final String userId;

  /// Recovery mobile number (legacy field name: primaryMobile).
  final String? primaryMobile;

  /// Recovery email id (legacy field name: secondaryMobile).
  final String? secondaryMobile;
  final String? photoUrl;
  final Map<String, String> deviceDetails;

  /// Login email verified via Firebase Auth.
  final bool emailVerified;

  /// Recovery mobile verified via OTP.
  final bool primaryMobileVerified;

  /// Recovery email verified via OTP.
  final bool recoveryEmailVerified;
  final DateTime? createdAt;

  /// When free trial began (stored on Firebase). Falls back to [createdAt].
  final DateTime? trialStartedAt;

  /// Current trial / paid plan end time.
  final DateTime? subscriptionExpiresAt;

  /// Last known expiry written to Firebase (mirrors [subscriptionExpiresAt]).
  final DateTime? lastExpiresAt;

  final bool isTrialActive;

  /// Paid plan length in months (3/6/12/24). Null while on free trial.
  final int? subscriptionPlanMonths;

  /// Admin-granted lifetime free access (never expires).
  final bool isLifetimeFree;

  /// Separate file-upgrade plan duration (months).
  final int? filePlanMonths;

  /// Max files granted by the active file-upgrade plan.
  final int? filePlanMaxFiles;

  /// When the file-upgrade plan expires.
  final DateTime? filePlanExpiresAt;

  /// Admin-blocked accounts cannot use the vault.
  final bool isBlocked;

  /// ISO country code selected after first login (e.g. IN, US).
  final String? countryCode;

  /// Display name for [countryCode].
  final String? countryName;

  /// Optional GSTIN entered at subscription checkout (India).
  final String? buyerGstin;

  /// True when country was saved on the server.
  bool get hasSelectedCountry =>
      (countryCode ?? '').trim().length >= 2;

  /// Alias — recovery mobile number.
  String? get recoveryMobile => primaryMobile;

  /// Alias — recovery email id (stored in [secondaryMobile]).
  String? get recoveryEmail => secondaryMobile;

  bool get isRecoveryMobileVerified =>
      (primaryMobile ?? '').trim().isNotEmpty && primaryMobileVerified;

  bool get isRecoveryEmailVerified =>
      (secondaryMobile ?? '').trim().isNotEmpty && recoveryEmailVerified;

  /// True when a paid file-upgrade plan is still active.
  ///
  /// File plan keeps its own expiry. Base upgrade does not cut remaining
  /// file-plan time; after it ends, only the new base free quota applies.
  bool get hasActiveFilePlan {
    final end = filePlanExpiresAt;
    if (end == null || filePlanMaxFiles == null) return false;
    if (!DateTime.now().isBefore(end)) return false;
    // Still need an active base plan to use the vault / open files.
    return hasActiveAccess;
  }

  /// Effective trial start for UI.
  DateTime? get effectiveTrialStartedAt => trialStartedAt ?? createdAt;

  /// Effective expiry for UI / access checks. Null when lifetime free.
  DateTime? get effectiveExpiresAt {
    if (isLifetimeFree) return null;
    final end = lastExpiresAt ?? subscriptionExpiresAt;
    if (end != null) return end;
    final start = effectiveTrialStartedAt;
    if (start == null) return null;
    return AppConstants.trialEndsAt(start);
  }

  /// True if trial, paid, or lifetime free access is still valid.
  bool get hasActiveAccess {
    if (isBlocked) return false;
    if (isLifetimeFree) return true;
    final end = effectiveExpiresAt;
    if (end == null) return true;
    return DateTime.now().isBefore(end);
  }

  /// True when user has an active paid plan (not trial / not lifetime free).
  bool get hasPaidPlan =>
      !isLifetimeFree &&
      !isTrialActive &&
      subscriptionPlanMonths != null &&
      hasActiveAccess;

  /// Last paid plan duration (still set after expiry until user renews).
  int? get lastPaidPlanMonths =>
      !isLifetimeFree && !isTrialActive ? subscriptionPlanMonths : null;

  /// Paid plan existed but subscription period ended.
  bool get isExpiredPaidPlan =>
      lastPaidPlanMonths != null && !hasActiveAccess;

  String get planStatusLabel {
    if (isLifetimeFree) return 'Lifetime free';
    if (hasPaidPlan) {
      return '$subscriptionPlanMonths-month plan';
    }
    if (isTrialActive && hasActiveAccess) {
      return 'Free trial (${AppConstants.freeTrialDays} days)';
    }
    if (isTrialActive) return 'Free trial expired';
    if (isExpiredPaidPlan) {
      return '$lastPaidPlanMonths-month plan expired';
    }
    return 'Plan expired';
  }

  AppUser copyWith({
    String? displayName,
    String? primaryMobile,
    String? secondaryMobile,
    String? photoUrl,
    Map<String, String>? deviceDetails,
    bool? emailVerified,
    bool? primaryMobileVerified,
    bool? recoveryEmailVerified,
    DateTime? trialStartedAt,
    DateTime? subscriptionExpiresAt,
    DateTime? lastExpiresAt,
    bool? isTrialActive,
    int? subscriptionPlanMonths,
    bool clearPlanMonths = false,
    bool? isLifetimeFree,
    int? filePlanMonths,
    int? filePlanMaxFiles,
    DateTime? filePlanExpiresAt,
    bool? isBlocked,
    String? countryCode,
    String? countryName,
    String? buyerGstin,
    bool clearSubscriptionExpiry = false,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      userId: userId,
      primaryMobile: primaryMobile ?? this.primaryMobile,
      secondaryMobile: secondaryMobile ?? this.secondaryMobile,
      photoUrl: photoUrl ?? this.photoUrl,
      deviceDetails: deviceDetails ?? this.deviceDetails,
      emailVerified: emailVerified ?? this.emailVerified,
      primaryMobileVerified:
          primaryMobileVerified ?? this.primaryMobileVerified,
      recoveryEmailVerified:
          recoveryEmailVerified ?? this.recoveryEmailVerified,
      createdAt: createdAt,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      subscriptionExpiresAt: clearSubscriptionExpiry
          ? null
          : (subscriptionExpiresAt ?? this.subscriptionExpiresAt),
      lastExpiresAt: clearSubscriptionExpiry
          ? null
          : (lastExpiresAt ?? this.lastExpiresAt),
      isTrialActive: isTrialActive ?? this.isTrialActive,
      subscriptionPlanMonths: clearPlanMonths
          ? null
          : (subscriptionPlanMonths ?? this.subscriptionPlanMonths),
      isLifetimeFree: isLifetimeFree ?? this.isLifetimeFree,
      filePlanMonths: filePlanMonths ?? this.filePlanMonths,
      filePlanMaxFiles: filePlanMaxFiles ?? this.filePlanMaxFiles,
      filePlanExpiresAt: filePlanExpiresAt ?? this.filePlanExpiresAt,
      isBlocked: isBlocked ?? this.isBlocked,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      buyerGstin: buyerGstin ?? this.buyerGstin,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'userId': userId,
      'primaryMobile': primaryMobile,
      'secondaryMobile': secondaryMobile,
      'photoUrl': photoUrl,
      'deviceDetails': deviceDetails,
      'emailVerified': emailVerified,
      'primaryMobileVerified': primaryMobileVerified,
      'recoveryEmailVerified': recoveryEmailVerified,
      'createdAt': createdAt?.toIso8601String(),
      'trialStartedAt': trialStartedAt?.toIso8601String(),
      'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
      'lastExpiresAt':
          (lastExpiresAt ?? subscriptionExpiresAt)?.toIso8601String(),
      'isTrialActive': isTrialActive,
      'subscriptionPlanMonths': subscriptionPlanMonths,
      'isLifetimeFree': isLifetimeFree,
      'filePlanMonths': filePlanMonths,
      'filePlanMaxFiles': filePlanMaxFiles,
      'filePlanExpiresAt': filePlanExpiresAt?.toIso8601String(),
      'isBlocked': isBlocked,
      // countryCode / countryName are written only via Cloud Function.
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final device = map['deviceDetails'];
    final created = map['createdAt'] != null
        ? DateTime.tryParse(map['createdAt'].toString())
        : null;
    final trialStart = map['trialStartedAt'] != null
        ? DateTime.tryParse(map['trialStartedAt'].toString())
        : null;
    final expires = map['subscriptionExpiresAt'] != null
        ? DateTime.tryParse(map['subscriptionExpiresAt'].toString())
        : null;
    final lastExpires = map['lastExpiresAt'] != null
        ? DateTime.tryParse(map['lastExpiresAt'].toString())
        : null;
    final filePlanExpires = map['filePlanExpiresAt'] != null
        ? DateTime.tryParse(map['filePlanExpiresAt'].toString())
        : null;
    return AppUser(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      primaryMobile: map['primaryMobile'] as String?,
      secondaryMobile: map['secondaryMobile'] as String? ??
          map['recoveryEmail'] as String?,
      photoUrl: map['photoUrl'] as String?,
      deviceDetails: device is Map
          ? device.map((k, v) => MapEntry(k.toString(), v.toString()))
          : {},
      emailVerified: map['emailVerified'] as bool? ?? false,
      primaryMobileVerified: map['primaryMobileVerified'] as bool? ?? false,
      recoveryEmailVerified: map['recoveryEmailVerified'] as bool? ??
          map['secondaryMobileVerified'] as bool? ??
          false,
      createdAt: created,
      trialStartedAt: trialStart ?? created,
      subscriptionExpiresAt: expires,
      lastExpiresAt: lastExpires ?? expires,
      isTrialActive: map['isTrialActive'] as bool? ?? true,
      subscriptionPlanMonths: map['subscriptionPlanMonths'] is int
          ? map['subscriptionPlanMonths'] as int
          : int.tryParse('${map['subscriptionPlanMonths'] ?? ''}'),
      isLifetimeFree: map['isLifetimeFree'] as bool? ?? false,
      filePlanMonths: map['filePlanMonths'] is int
          ? map['filePlanMonths'] as int
          : int.tryParse('${map['filePlanMonths'] ?? ''}'),
      filePlanMaxFiles: map['filePlanMaxFiles'] is int
          ? map['filePlanMaxFiles'] as int
          : int.tryParse('${map['filePlanMaxFiles'] ?? ''}'),
      filePlanExpiresAt: filePlanExpires,
      isBlocked: map['isBlocked'] as bool? ?? false,
      countryCode: map['countryCode']?.toString(),
      countryName: map['countryName']?.toString(),
      buyerGstin: map['buyerGstin']?.toString(),
    );
  }
}

/// One file attached to a credential (cloud or on-device).
class CredentialAttachment {
  const CredentialAttachment({
    required this.id,
    this.url,
    this.path,
    this.name,
    this.mime,
    this.sizeBytes,
    this.createdAt,
  });

  final String id;
  final String? url;
  final String? path;
  final String? name;
  final String? mime;
  final int? sizeBytes;
  final DateTime? createdAt;

  bool get hasFile =>
      (url != null && url!.trim().isNotEmpty) ||
      (path != null && path!.trim().isNotEmpty);

  bool get isLocal =>
      path != null && path!.startsWith('local::');

  String? get localFilePath {
    if (!isLocal) return null;
    return path!.substring('local::'.length);
  }

  CredentialAttachment copyWith({
    String? id,
    String? url,
    String? path,
    String? name,
    String? mime,
    int? sizeBytes,
    DateTime? createdAt,
  }) {
    return CredentialAttachment(
      id: id ?? this.id,
      url: url ?? this.url,
      path: path ?? this.path,
      name: name ?? this.name,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'url': url,
        'path': path,
        'name': name,
        'mime': mime,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory CredentialAttachment.fromMap(Map<String, dynamic> map) {
    return CredentialAttachment(
      id: map['id'] as String? ??
          (map['path'] as String? ?? map['url'] as String? ?? 'att'),
      url: map['url'] as String? ?? map['attachmentUrl'] as String?,
      path: map['path'] as String? ?? map['attachmentPath'] as String?,
      name: map['name'] as String? ?? map['attachmentName'] as String?,
      mime: map['mime'] as String? ?? map['attachmentMime'] as String?,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ??
          (map['attachmentSizeBytes'] as num?)?.toInt(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
    );
  }
}

/// Encrypted credential entry — one platform can have many (requirement 12).
class CredentialEntry {
  const CredentialEntry({
    required this.id,
    required this.userId,
    required this.platform,
    required this.title,
    required this.accountUserId,
    required this.encryptedPassword,
    this.description = '',
    this.website,
    this.customPlatformName,
    this.accountGroup,
    this.accountGroupId,
    this.sortOrder = 0,
    this.isDemoSample = false,
    this.attachments = const [],
    this.attachmentUrl,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentMime,
    this.attachmentSizeBytes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final PlatformCategory platform;
  final String title;
  final String accountUserId;
  final String encryptedPassword;
  final String description;
  final String? website;

  /// Manual / custom platform label when [platform] is [PlatformCategory.other].
  final String? customPlatformName;

  /// Sub-group within a service (e.g. Email → "Abc Company" → passwords).
  final String? accountGroup;

  /// Firestore / Hive id of the parent group document under `users/{uid}/groups`.
  final String? accountGroupId;

  /// Display order within the same platform group (lower = higher).
  final int sortOrder;

  /// True for guest preview samples — removed on first real password add.
  final bool isDemoSample;

  /// All attached files (preferred). Legacy scalar fields mirror the first item.
  final List<CredentialAttachment> attachments;

  /// Legacy single-file fields (kept for older docs / sync).
  final String? attachmentUrl;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentMime;
  final int? attachmentSizeBytes;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Normalized list: [attachments] or a single legacy scalar attachment.
  List<CredentialAttachment> get effectiveAttachments {
    if (attachments.isNotEmpty) {
      return attachments.where((a) => a.hasFile).toList();
    }
    final legacy = CredentialAttachment(
      id: 'legacy',
      url: attachmentUrl,
      path: attachmentPath,
      name: attachmentName,
      mime: attachmentMime,
      sizeBytes: attachmentSizeBytes,
      createdAt: createdAt,
    );
    return legacy.hasFile ? [legacy] : const [];
  }

  bool get hasAttachment => effectiveAttachments.isNotEmpty;

  int get attachmentCount => effectiveAttachments.length;

  /// True when any attachment is still only on-device.
  bool get isLocalAttachment =>
      effectiveAttachments.any((a) => a.isLocal);

  String? get localAttachmentFilePath {
    for (final a in effectiveAttachments) {
      if (a.isLocal) return a.localFilePath;
    }
    return null;
  }

  /// Label shown in UI (Outlook, Google, or custom name).
  String get platformLabel {
    if (platform == PlatformCategory.other &&
        customPlatformName != null &&
        customPlatformName!.trim().isNotEmpty) {
      return customPlatformName!.trim();
    }
    return PlatformInfo.of(platform).label;
  }

  /// Group key for dashboard service sections (Email / Outlook / Custom…).
  String get serviceKey {
    if (platform == PlatformCategory.other &&
        customPlatformName != null &&
        customPlatformName!.trim().isNotEmpty) {
      return 'other:${customPlatformName!.trim().toLowerCase()}';
    }
    return platform.name;
  }

  /// Display label for the company / account group.
  String get accountGroupLabel {
    final g = accountGroup?.trim();
    if (g == null || g.isEmpty) return 'General';
    return g;
  }

  /// Key for nesting under a service (company group).
  String get accountGroupKey {
    final g = accountGroup?.trim().toLowerCase();
    if (g == null || g.isEmpty) return 'general';
    return g;
  }

  /// Legacy alias — same as [serviceKey].
  String get groupKey => serviceKey;

  CredentialEntry copyWith({
    String? id,
    String? title,
    String? accountUserId,
    String? encryptedPassword,
    String? description,
    String? website,
    PlatformCategory? platform,
    String? customPlatformName,
    String? accountGroup,
    String? accountGroupId,
    int? sortOrder,
    bool? isDemoSample,
    List<CredentialAttachment>? attachments,
    String? attachmentUrl,
    String? attachmentPath,
    String? attachmentName,
    String? attachmentMime,
    int? attachmentSizeBytes,
    bool clearAttachment = false,
    DateTime? updatedAt,
  }) {
    final nextAttachments = clearAttachment
        ? const <CredentialAttachment>[]
        : (attachments ?? this.attachments);
    final first =
        nextAttachments.isNotEmpty ? nextAttachments.first : null;
    return CredentialEntry(
      id: id ?? this.id,
      userId: userId,
      platform: platform ?? this.platform,
      title: title ?? this.title,
      accountUserId: accountUserId ?? this.accountUserId,
      encryptedPassword: encryptedPassword ?? this.encryptedPassword,
      description: description ?? this.description,
      website: website ?? this.website,
      customPlatformName: customPlatformName ?? this.customPlatformName,
      accountGroup: accountGroup ?? this.accountGroup,
      accountGroupId: accountGroupId ?? this.accountGroupId,
      sortOrder: sortOrder ?? this.sortOrder,
      isDemoSample: isDemoSample ?? this.isDemoSample,
      attachments: nextAttachments,
      attachmentUrl: clearAttachment
          ? null
          : (first?.url ?? attachmentUrl ?? this.attachmentUrl),
      attachmentPath: clearAttachment
          ? null
          : (first?.path ?? attachmentPath ?? this.attachmentPath),
      attachmentName: clearAttachment
          ? null
          : (first?.name ?? attachmentName ?? this.attachmentName),
      attachmentMime: clearAttachment
          ? null
          : (first?.mime ?? attachmentMime ?? this.attachmentMime),
      attachmentSizeBytes: clearAttachment
          ? null
          : (first?.sizeBytes ??
              attachmentSizeBytes ??
              this.attachmentSizeBytes),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Builds an entry with [files] as the attachment list and mirrored scalars.
  CredentialEntry withAttachments(List<CredentialAttachment> files) {
    final list = files.where((a) => a.hasFile).toList();
    if (list.isEmpty) return copyWith(clearAttachment: true);
    return copyWith(attachments: list);
  }

  Map<String, dynamic> toMap() {
    final files = effectiveAttachments;
    final first = files.isNotEmpty ? files.first : null;
    return {
      'id': id,
      'userId': userId,
      'platform': platform.name,
      'title': title,
      'accountUserId': accountUserId,
      'encryptedPassword': encryptedPassword,
      'description': description,
      'website': website,
      'customPlatformName': customPlatformName,
      'accountGroup': accountGroup,
      'accountGroupId': accountGroupId,
      'sortOrder': sortOrder,
      'isDemoSample': isDemoSample,
      'attachments': files.map((a) => a.toMap()).toList(),
      // Legacy mirrors for older app versions / pending ops.
      'attachmentUrl': first?.url,
      'attachmentPath': first?.path,
      'attachmentName': first?.name,
      'attachmentMime': first?.mime,
      'attachmentSizeBytes': first?.sizeBytes,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory CredentialEntry.fromMap(Map<String, dynamic> map) {
    final description = map['description'] as String? ?? '';
    // Legacy demo samples used "Sample —" description before isDemoSample flag
    final legacyDemo = description.startsWith('Sample —');
    final rawList = map['attachments'];
    var files = <CredentialAttachment>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final att = CredentialAttachment.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (att.hasFile) files.add(att);
        }
      }
    }
    if (files.isEmpty) {
      final legacy = CredentialAttachment(
        id: 'legacy',
        url: map['attachmentUrl'] as String?,
        path: map['attachmentPath'] as String?,
        name: map['attachmentName'] as String?,
        mime: map['attachmentMime'] as String?,
        sizeBytes: (map['attachmentSizeBytes'] as num?)?.toInt(),
        createdAt: map['createdAt'] != null
            ? DateTime.tryParse(map['createdAt'].toString())
            : null,
      );
      if (legacy.hasFile) files = [legacy];
    }
    final first = files.isNotEmpty ? files.first : null;
    return CredentialEntry(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      platform: PlatformInfo.fromName(map['platform'] as String? ?? 'other'),
      title: map['title'] as String? ?? '',
      accountUserId: map['accountUserId'] as String? ?? '',
      encryptedPassword: map['encryptedPassword'] as String? ?? '',
      description: description,
      website: map['website'] as String?,
      customPlatformName: map['customPlatformName'] as String?,
      accountGroup: map['accountGroup'] as String?,
      accountGroupId: map['accountGroupId'] as String?,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      isDemoSample: map['isDemoSample'] as bool? ?? legacyDemo,
      attachments: files,
      attachmentUrl: first?.url ?? map['attachmentUrl'] as String?,
      attachmentPath: first?.path ?? map['attachmentPath'] as String?,
      attachmentName: first?.name ?? map['attachmentName'] as String?,
      attachmentMime: first?.mime ?? map['attachmentMime'] as String?,
      attachmentSizeBytes: first?.sizeBytes ??
          (map['attachmentSizeBytes'] as num?)?.toInt(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
    );
  }
}

/// Parent group under a service (Email → Abc Company → password children).
class AccountGroup {
  const AccountGroup({
    required this.id,
    required this.userId,
    required this.name,
    required this.serviceKey,
    required this.platform,
    this.customPlatformName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String serviceKey;
  final PlatformCategory platform;
  final String? customPlatformName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get nameKey => name.trim().toLowerCase().isEmpty
      ? 'general'
      : name.trim().toLowerCase();

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'name': name,
        'nameKey': nameKey,
        'serviceKey': serviceKey,
        'platform': platform.name,
        'customPlatformName': customPlatformName,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory AccountGroup.fromMap(Map<String, dynamic> map) => AccountGroup(
        id: map['id'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        name: map['name'] as String? ?? 'General',
        serviceKey: map['serviceKey'] as String? ?? 'other',
        platform: PlatformInfo.fromName(map['platform'] as String? ?? 'other'),
        customPlatformName: map['customPlatformName'] as String?,
        createdAt: map['createdAt'] != null
            ? DateTime.tryParse(map['createdAt'].toString())
            : null,
        updatedAt: map['updatedAt'] != null
            ? DateTime.tryParse(map['updatedAt'].toString())
            : null,
      );

  /// Stable Firestore doc id for a service + group name pair.
  static String docIdFor({
    required String serviceKey,
    required String groupName,
  }) {
    final nameKey = groupName.trim().isEmpty
        ? 'general'
        : groupName.trim().toLowerCase();
    final raw = '${serviceKey}__$nameKey';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }
}

/// Subscription plan selection (base access + included files).
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.months,
    required this.priceInr,
    this.priceUsd,
    this.maxAttachmentFiles = 0,
  });

  final int months;
  final int priceInr;
  final double? priceUsd;
  final int maxAttachmentFiles;

  String get label => '$months months';
  String get priceLabel => '₹$priceInr';
  String get filesLabel => maxAttachmentFiles <= 0
      ? 'No file uploads'
      : '$maxAttachmentFiles files free';

  double usdPrice(SubscriptionCatalog catalog) {
    if (priceUsd != null && priceUsd! > 0) return priceUsd!;
    return catalog.usdFromInr(priceInr);
  }
}

/// Paid file-quota upgrade (separate from base subscription).
class FileUpgradePlan {
  const FileUpgradePlan({
    required this.months,
    required this.priceInr,
    this.priceUsd,
    required this.maxAttachmentFiles,
  });

  final int months;
  final int priceInr;
  final double? priceUsd;
  final int maxAttachmentFiles;

  String get label => '$months months · +$maxAttachmentFiles files';
  String get priceLabel => '₹$priceInr';
  String get filesLabel => '+$maxAttachmentFiles files';

  double usdPrice(SubscriptionCatalog catalog) {
    if (priceUsd != null && priceUsd! > 0) return priceUsd!;
    return catalog.usdFromInr(priceInr);
  }
}

/// Admin-managed GST for India subscription checkout.
class SubscriptionGstConfig {
  const SubscriptionGstConfig({
    this.gstPercent = 18,
    this.platformGstin = '',
    this.platformStateCode = '',
    this.platformLegalName = 'PasswordSaver',
    this.platformAddress = '',
  });

  final double gstPercent;
  final String platformGstin;
  final String platformStateCode;
  final String platformLegalName;
  final String platformAddress;

  factory SubscriptionGstConfig.fromMap(Map<String, dynamic>? map) {
    const fallback = SubscriptionGstConfig();
    if (map == null) return fallback;
    final pct = (map['gstPercent'] as num?)?.toDouble();
    var stateCode = '${map['platformStateCode'] ?? ''}'.trim();
    final gstin = '${map['platformGstin'] ?? ''}'.trim().toUpperCase();
    if (stateCode.length < 2 && gstin.length >= 2) {
      stateCode = gstin.substring(0, 2);
    }
    final legalName = '${map['platformLegalName'] ?? ''}'.trim();
    return SubscriptionGstConfig(
      gstPercent: pct != null && pct >= 0 ? pct.clamp(0, 40) : fallback.gstPercent,
      platformGstin: gstin,
      platformStateCode: stateCode.length >= 2 ? stateCode.substring(0, 2) : '',
      platformLegalName:
          legalName.isNotEmpty ? legalName : fallback.platformLegalName,
      platformAddress: '${map['platformAddress'] ?? ''}'.trim(),
    );
  }

  /// Catalog INR price + GST (matches server Razorpay charge for India).
  int inrGrandTotal(int taxableInr) {
    if (gstPercent <= 0) return taxableInr;
    final gst = (taxableInr * gstPercent / 100).round();
    return taxableInr + gst;
  }

  double gstOn(int taxableInr) =>
      gstPercent <= 0 ? 0 : (taxableInr * gstPercent / 100);
}

/// Admin-controllable subscription catalog (pricing + file limits).
class SubscriptionCatalog {
  const SubscriptionCatalog({
    required this.plans,
    required this.fileUpgradePlans,
    required this.trialMaxAttachmentFiles,
    this.maxAttachmentBytes = 1024 * 1024,
    this.inrToUsdRate = 0.012,
    this.internationalMultiplier = 1.5,
    this.lifetimeFreeMaxAttachmentFiles = 25,
    this.gst = const SubscriptionGstConfig(),
  });

  final List<SubscriptionPlan> plans;
  final List<FileUpgradePlan> fileUpgradePlans;
  final int trialMaxAttachmentFiles;
  final int maxAttachmentBytes;
  final double inrToUsdRate;
  final double internationalMultiplier;
  final int lifetimeFreeMaxAttachmentFiles;
  final SubscriptionGstConfig gst;

  /// International USD = INR × rate × multiplier (default +50%).
  double usdFromInr(int priceInr) {
    final raw = priceInr * inrToUsdRate * internationalMultiplier;
    return (raw * 100).round() / 100;
  }

  static SubscriptionCatalog defaults() {
    const inrToUsdRate = 0.012;
    const internationalMultiplier = 1.5;
    double usd(int inr) =>
        ((inr * inrToUsdRate * internationalMultiplier) * 100).round() / 100;

    final plans = AppConstants.subscriptionPlans.entries
        .map(
          (e) => SubscriptionPlan(
            months: e.key,
            priceInr: e.value,
            priceUsd: usd(e.value),
            maxAttachmentFiles:
                AppConstants.defaultPlanFileLimits[e.key] ?? 12,
          ),
        )
        .toList()
      ..sort((a, b) => a.months.compareTo(b.months));
    final filePlans = AppConstants.defaultFileUpgradePrices.entries
        .map(
          (e) => FileUpgradePlan(
            months: e.key,
            priceInr: e.value,
            priceUsd: usd(e.value),
            maxAttachmentFiles:
                AppConstants.defaultFileUpgradeFileCounts[e.key] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => a.months.compareTo(b.months));
    return SubscriptionCatalog(
      plans: plans,
      fileUpgradePlans: filePlans,
      trialMaxAttachmentFiles: AppConstants.defaultTrialFileLimit,
      maxAttachmentBytes: AppConstants.maxAttachmentBytes,
      inrToUsdRate: 0.012,
      internationalMultiplier: 1.5,
      lifetimeFreeMaxAttachmentFiles:
          AppConstants.defaultLifetimeFreeFileLimit,
    );
  }

  factory SubscriptionCatalog.fromMap(Map<String, dynamic> map) {
    final fallback = SubscriptionCatalog.defaults();
    final inrToUsdRate =
        (map['inrToUsdRate'] as num?)?.toDouble() ?? fallback.inrToUsdRate;
    final internationalMultiplier =
        (map['internationalMultiplier'] as num?)?.toDouble() ??
            fallback.internationalMultiplier;
    double defaultUsd(int priceInr) =>
        ((priceInr * inrToUsdRate * internationalMultiplier) * 100).round() /
        100;
    final rawPlans = map['plans'];
    final plans = <SubscriptionPlan>[];
    if (rawPlans is Map) {
      for (final entry in rawPlans.entries) {
        final months = int.tryParse(entry.key.toString()) ?? 0;
        if (months <= 0) continue;
        final value = entry.value;
        if (value is Map) {
          final m = Map<String, dynamic>.from(value);
          plans.add(
            SubscriptionPlan(
              months: months,
              priceInr: (m['priceInr'] as num?)?.toInt() ??
                  AppConstants.subscriptionPlans[months] ??
                  0,
              priceUsd: (m['priceUsd'] as num?)?.toDouble() ??
                  defaultUsd(
                    (m['priceInr'] as num?)?.toInt() ??
                        AppConstants.subscriptionPlans[months] ??
                        0,
                  ),
              maxAttachmentFiles: (m['maxAttachmentFiles'] as num?)?.toInt() ??
                  AppConstants.defaultPlanFileLimits[months] ??
                  0,
            ),
          );
        } else if (value is num) {
          plans.add(
            SubscriptionPlan(
              months: months,
              priceInr: value.toInt(),
              priceUsd: defaultUsd(value.toInt()),
              maxAttachmentFiles:
                  AppConstants.defaultPlanFileLimits[months] ?? 0,
            ),
          );
        }
      }
    }
    if (plans.isEmpty) {
      plans.addAll(fallback.plans);
    }
    plans.sort((a, b) => a.months.compareTo(b.months));

    final rawFilePlans = map['fileUpgradePlans'];
    final filePlans = <FileUpgradePlan>[];
    if (rawFilePlans is Map) {
      for (final entry in rawFilePlans.entries) {
        final months = int.tryParse(entry.key.toString()) ?? 0;
        if (months <= 0) continue;
        final value = entry.value;
        if (value is! Map) continue;
        final m = Map<String, dynamic>.from(value);
        filePlans.add(
          FileUpgradePlan(
            months: months,
            priceInr: (m['priceInr'] as num?)?.toInt() ??
                AppConstants.defaultFileUpgradePrices[months] ??
                0,
            priceUsd: (m['priceUsd'] as num?)?.toDouble() ??
                defaultUsd(
                  (m['priceInr'] as num?)?.toInt() ??
                      AppConstants.defaultFileUpgradePrices[months] ??
                      0,
                ),
            maxAttachmentFiles: (m['maxAttachmentFiles'] as num?)?.toInt() ??
                AppConstants.defaultFileUpgradeFileCounts[months] ??
                0,
          ),
        );
      }
    }
    if (filePlans.isEmpty) {
      filePlans.addAll(fallback.fileUpgradePlans);
    }
    filePlans.sort((a, b) => a.months.compareTo(b.months));

    final trial = map['trial'];
    var trialFiles = fallback.trialMaxAttachmentFiles;
    if (trial is Map) {
      trialFiles = (trial['maxAttachmentFiles'] as num?)?.toInt() ?? trialFiles;
    } else if (map['trialMaxAttachmentFiles'] != null) {
      trialFiles =
          (map['trialMaxAttachmentFiles'] as num?)?.toInt() ?? trialFiles;
    }

    return SubscriptionCatalog(
      plans: plans,
      fileUpgradePlans: filePlans,
      trialMaxAttachmentFiles: trialFiles,
      maxAttachmentBytes: (map['maxAttachmentBytes'] as num?)?.toInt() ??
          AppConstants.maxAttachmentBytes,
      inrToUsdRate: inrToUsdRate,
      internationalMultiplier: internationalMultiplier,
      lifetimeFreeMaxAttachmentFiles:
          (map['lifetimeFreeMaxAttachmentFiles'] as num?)?.toInt() ??
              fallback.lifetimeFreeMaxAttachmentFiles,
      gst: SubscriptionGstConfig.fromMap(
        map['gst'] is Map
            ? Map<String, dynamic>.from(map['gst'] as Map)
            : null,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'inrToUsdRate': inrToUsdRate,
        'internationalMultiplier': internationalMultiplier,
        'plans': {
          for (final p in plans)
            '${p.months}': {
              'priceInr': p.priceInr,
              'priceUsd': p.usdPrice(this),
              'maxAttachmentFiles': p.maxAttachmentFiles,
            },
        },
        'fileUpgradePlans': {
          for (final p in fileUpgradePlans)
            '${p.months}': {
              'priceInr': p.priceInr,
              'priceUsd': p.usdPrice(this),
              'maxAttachmentFiles': p.maxAttachmentFiles,
            },
        },
        'trial': {
          'days': AppConstants.freeTrialDays,
          'maxAttachmentFiles': trialMaxAttachmentFiles,
        },
        'maxAttachmentBytes': maxAttachmentBytes,
        'lifetimeFreeMaxAttachmentFiles': lifetimeFreeMaxAttachmentFiles,
        'schemaVersion': 3,
      };

  SubscriptionPlan? planForMonths(int? months) {
    if (months == null) return null;
    for (final p in plans) {
      if (p.months == months) return p;
    }
    return null;
  }

  FileUpgradePlan? fileUpgradeForMonths(int? months) {
    if (months == null) return null;
    for (final p in fileUpgradePlans) {
      if (p.months == months) return p;
    }
    return null;
  }

  int priceForMonths(int months) =>
      planForMonths(months)?.priceInr ??
      AppConstants.subscriptionPlans[months] ??
      0;

  int fileLimitForMonths(int? months, {required bool isTrialActive}) {
    if (isTrialActive || months == null) return trialMaxAttachmentFiles;
    return planForMonths(months)?.maxAttachmentFiles ??
        AppConstants.defaultPlanFileLimits[months] ??
        trialMaxAttachmentFiles;
  }

  Map<int, int> get pricesMap => {
        for (final p in plans) p.months: p.priceInr,
      };
}

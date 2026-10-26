import 'package:uuid/uuid.dart';

import '../../domain/entities/entities.dart';
import 'hive_boxes.dart';

/// Offline-first credential persistence using Hive.
///
 /// Keys are stored as `{userId}::{credentialId}`.
class HiveCredentialStore {
  HiveCredentialStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// Returns all credentials for [userId] sorted by sortOrder, then updatedAt.
  List<CredentialEntry> getAll(String userId) {
    final box = HiveBoxes.credentialsBox;
    final list = <CredentialEntry>[];
    for (final key in box.keys) {
      final keyStr = key.toString();
      if (!keyStr.startsWith('$userId::')) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(raw as Map);
      list.add(CredentialEntry.fromMap(map));
    }
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final aTime = a.updatedAt ?? a.createdAt ?? DateTime(1970);
      final bTime = b.updatedAt ?? b.createdAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return list;
  }

  /// Upserts a credential into Hive. Generates id when empty.
  CredentialEntry put(CredentialEntry entry) {
    final now = DateTime.now();
    final withId = entry.copyWith(
      id: entry.id.isEmpty ? _uuid.v4() : entry.id,
      updatedAt: now,
    );
    final groupId = withId.accountGroupId ??
        AccountGroup.docIdFor(
          serviceKey: withId.serviceKey,
          groupName: withId.accountGroupLabel,
        );
    // Preserve createdAt on insert
    final stored = CredentialEntry(
      id: withId.id,
      userId: withId.userId,
      platform: withId.platform,
      title: withId.title,
      accountUserId: withId.accountUserId,
      encryptedPassword: withId.encryptedPassword,
      description: withId.description,
      website: withId.website,
      customPlatformName: withId.customPlatformName,
      accountGroup: withId.accountGroup,
      accountGroupId: groupId,
      sortOrder: withId.sortOrder,
      isDemoSample: withId.isDemoSample,
      attachments: withId.effectiveAttachments,
      attachmentUrl: withId.attachmentUrl,
      attachmentPath: withId.attachmentPath,
      attachmentName: withId.attachmentName,
      attachmentMime: withId.attachmentMime,
      attachmentSizeBytes: withId.attachmentSizeBytes,
      createdAt: entry.createdAt ?? now,
      updatedAt: now,
    );
    final key = _key(stored.userId, stored.id);
    HiveBoxes.credentialsBox.put(key, stored.toMap());
    return stored;
  }

  /// All account groups for [userId].
  List<AccountGroup> getGroups(String userId) {
    final box = HiveBoxes.groupsBox;
    final list = <AccountGroup>[];
    for (final key in box.keys) {
      final keyStr = key.toString();
      if (!keyStr.startsWith('$userId::')) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      list.add(AccountGroup.fromMap(Map<String, dynamic>.from(raw as Map)));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Upserts a parent group document locally.
  AccountGroup putGroup(AccountGroup group) {
    final now = DateTime.now();
    final stored = AccountGroup(
      id: group.id.isEmpty
          ? AccountGroup.docIdFor(
              serviceKey: group.serviceKey,
              groupName: group.name,
            )
          : group.id,
      userId: group.userId,
      name: group.name.trim().isEmpty ? 'General' : group.name.trim(),
      serviceKey: group.serviceKey,
      platform: group.platform,
      customPlatformName: group.customPlatformName,
      createdAt: group.createdAt ?? now,
      updatedAt: now,
    );
    HiveBoxes.groupsBox.put(_groupKey(stored.userId, stored.id), stored.toMap());
    return stored;
  }

  void deleteGroup(String userId, String groupId) {
    HiveBoxes.groupsBox.delete(_groupKey(userId, groupId));
  }

  /// Replaces all local groups for [userId].
  void replaceAllGroups(String userId, List<AccountGroup> groups) {
    final box = HiveBoxes.groupsBox;
    final toDelete = box.keys
        .where((k) => k.toString().startsWith('$userId::'))
        .toList();
    for (final k in toDelete) {
      box.delete(k);
    }
    for (final g in groups) {
      putGroup(g);
    }
  }

  /// Deletes a credential from Hive.
  void delete(String userId, String credentialId) {
    HiveBoxes.credentialsBox.delete(_key(userId, credentialId));
  }

  /// Replaces all local credentials for [userId] with [entries].
  void replaceAll(String userId, List<CredentialEntry> entries) {
    final box = HiveBoxes.credentialsBox;
    final toDelete = box.keys
        .where((k) => k.toString().startsWith('$userId::'))
        .toList();
    for (final k in toDelete) {
      box.delete(k);
    }
    for (final e in entries) {
      put(e);
    }
  }

  /// Queues an offline mutation to push later when online.
  void enqueuePendingOp({
    required String op,
    required String userId,
    required String credentialId,
    Map<String, dynamic>? payload,
  }) {
    final id = _uuid.v4();
    HiveBoxes.pendingOpsBox.put(id, {
      'id': id,
      'op': op, // add | update | delete
      'userId': userId,
      'credentialId': credentialId,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Returns pending sync operations for [userId].
  List<Map<String, dynamic>> pendingOps(String userId) {
    final list = <Map<String, dynamic>>[];
    for (final key in HiveBoxes.pendingOpsBox.keys) {
      final raw = HiveBoxes.pendingOpsBox.get(key);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['userId'] == userId) list.add(map);
    }
    list.sort((a, b) =>
        (a['createdAt'] as String).compareTo(b['createdAt'] as String));
    return list;
  }

  /// Removes a pending op after successful Firebase sync.
  void removePendingOp(String opId) {
    HiveBoxes.pendingOpsBox.delete(opId);
  }

  /// Number of offline mutations waiting to sync for [userId].
  int pendingCount(String userId) => pendingOps(userId).length;

  /// Last successful sync time for [userId], if any.
  DateTime? lastSyncAt(String userId) {
    final raw = HiveBoxes.syncMetaBox.get('last_sync_$userId');
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _key(String userId, String credentialId) => '$userId::$credentialId';

  String _groupKey(String userId, String groupId) => '$userId::$groupId';
}

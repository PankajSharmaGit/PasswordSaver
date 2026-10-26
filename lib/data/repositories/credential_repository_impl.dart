import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/storage/attachment_storage_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../local/hive_boxes.dart';
import '../local/hive_credential_store.dart';
import 'auth_repository_impl.dart';

/// Offline-first credentials: Hive is source of truth; Firebase syncs when online.
class CredentialRepositoryImpl implements CredentialRepository {
  CredentialRepositoryImpl({
    required HiveCredentialStore hiveStore,
    FirebaseFirestore? firestore,
    AttachmentStorageService? attachments,
  })  : _hive = hiveStore,
        _firestore = firestore,
        _attachments = attachments ?? AttachmentStorageService();

  final HiveCredentialStore _hive;
  final FirebaseFirestore? _firestore;
  final AttachmentStorageService _attachments;
  final _controller = StreamController<List<CredentialEntry>>.broadcast();

  CollectionReference<Map<String, dynamic>>? _col(String userId) {
    if (_firestore == null) return null;
    return _firestore
        .collection(AppConstants.colUsers)
        .doc(userId)
        .collection(AppConstants.colCredentials);
  }

  CollectionReference<Map<String, dynamic>>? _groupsCol(String userId) {
    if (_firestore == null) return null;
    return _firestore
        .collection(AppConstants.colUsers)
        .doc(userId)
        .collection(AppConstants.colGroups);
  }

  /// Ensures parent group exists locally + on Firebase for a credential.
  Future<AccountGroup> upsertGroupForCredential(CredentialEntry entry) async {
    final name = entry.accountGroupLabel;
    final groupId = entry.accountGroupId ??
        AccountGroup.docIdFor(
          serviceKey: entry.serviceKey,
          groupName: name,
        );
    AccountGroup? existing;
    for (final g in _hive.getGroups(entry.userId)) {
      if (g.id == groupId) {
        existing = g;
        break;
      }
    }
    final group = AccountGroup(
      id: groupId,
      userId: entry.userId,
      name: name,
      serviceKey: entry.serviceKey,
      platform: entry.platform,
      customPlatformName: entry.customPlatformName,
      createdAt: existing?.createdAt,
    );
    return _persistGroup(group);
  }

  Future<AccountGroup> _persistGroup(AccountGroup group) async {
    final saved = _hive.putGroup(group);

    final online = FirebaseAvailability.isAvailable &&
        await ConnectivityHelper.isOnline();
    if (online) {
      try {
        await _groupsCol(saved.userId)
            ?.doc(saved.id)
            .set(saved.toMap(), SetOptions(merge: true));
      } catch (_) {
        _hive.enqueuePendingOp(
          op: 'upsert_group',
          userId: saved.userId,
          credentialId: saved.id,
          payload: saved.toMap(),
        );
      }
    } else {
      _hive.enqueuePendingOp(
        op: 'upsert_group',
        userId: saved.userId,
        credentialId: saved.id,
        payload: saved.toMap(),
      );
    }
    return saved;
  }

  @override
  Stream<List<CredentialEntry>> watchCredentials(String userId) async* {
    yield _hive.getAll(userId);
    yield* _controller.stream.map((_) => _hive.getAll(userId));
  }

  void _emit(String userId) {
    _controller.add(_hive.getAll(userId));
  }

  @override
  Future<List<CredentialEntry>> getCredentials(String userId) async {
    // Always serve Hive first (works offline)
    final local = _hive.getAll(userId);

    // Best-effort pull + merge when online + Firebase ready
    if (FirebaseAvailability.isAvailable &&
        await ConnectivityHelper.isOnline()) {
      try {
        await syncFromFirebase(userId);
        return _hive.getAll(userId);
      } catch (_) {
        return local;
      }
    }
    return local;
  }

  @override
  Future<CredentialEntry> addCredential(CredentialEntry entry) async {
    final linked = entry.copyWith(
      accountGroupId: AccountGroup.docIdFor(
        serviceKey: entry.serviceKey,
        groupName: entry.accountGroupLabel,
      ),
    );
    final saved = _hive.put(linked);
    await upsertGroupForCredential(saved);
    _emit(saved.userId);

    final online = FirebaseAvailability.isAvailable &&
        await ConnectivityHelper.isOnline();
    if (online) {
      try {
        await _col(saved.userId)?.doc(saved.id).set(saved.toMap());
      } catch (_) {
        _hive.enqueuePendingOp(
          op: 'add',
          userId: saved.userId,
          credentialId: saved.id,
          payload: saved.toMap(),
        );
      }
    } else {
      _hive.enqueuePendingOp(
        op: 'add',
        userId: saved.userId,
        credentialId: saved.id,
        payload: saved.toMap(),
      );
    }
    return saved;
  }

  @override
  Future<CredentialEntry> updateCredential(CredentialEntry entry) async {
    final linked = entry.copyWith(
      accountGroupId: AccountGroup.docIdFor(
        serviceKey: entry.serviceKey,
        groupName: entry.accountGroupLabel,
      ),
    );
    final updated = _hive.put(linked);
    await upsertGroupForCredential(updated);
    _emit(updated.userId);

    final online = FirebaseAvailability.isAvailable &&
        await ConnectivityHelper.isOnline();
    if (online) {
      try {
        await _col(updated.userId)
            ?.doc(updated.id)
            .set(updated.toMap(), SetOptions(merge: true));
      } catch (_) {
        _hive.enqueuePendingOp(
          op: 'update',
          userId: updated.userId,
          credentialId: updated.id,
          payload: updated.toMap(),
        );
      }
    } else {
      _hive.enqueuePendingOp(
        op: 'update',
        userId: updated.userId,
        credentialId: updated.id,
        payload: updated.toMap(),
      );
    }
    return updated;
  }

  @override
  Future<void> deleteCredential(
    String userId,
    String credentialId, {
    String? attachmentPath,
    List<String>? attachmentPaths,
  }) async {
    _hive.delete(userId, credentialId);
    _emit(userId);

    final paths = <String>{
      if (attachmentPath != null && attachmentPath.isNotEmpty) attachmentPath,
      ...?attachmentPaths?.where((p) => p.isNotEmpty),
    };
    for (final path in paths) {
      await _deleteAttachmentOrQueue(
        userId: userId,
        credentialId: credentialId,
        attachmentPath: path,
      );
    }

    final payload = <String, dynamic>{
      if (paths.isNotEmpty) 'attachmentPath': paths.first,
      if (paths.length > 1) 'attachmentPaths': paths.toList(),
    };

    final online = FirebaseAvailability.isAvailable &&
        await ConnectivityHelper.isOnline();
    if (online) {
      try {
        await _col(userId)?.doc(credentialId).delete();
      } catch (_) {
        _hive.enqueuePendingOp(
          op: 'delete',
          userId: userId,
          credentialId: credentialId,
          payload: payload.isEmpty ? null : payload,
        );
      }
    } else {
      _hive.enqueuePendingOp(
        op: 'delete',
        userId: userId,
        credentialId: credentialId,
        payload: payload.isEmpty ? null : payload,
      );
    }
  }

  /// Removes a Storage / local attachment now, or queues `delete_storage`.
  Future<void> deleteAttachmentReliably({
    required String userId,
    required String credentialId,
    required String? attachmentPath,
  }) {
    return _deleteAttachmentOrQueue(
      userId: userId,
      credentialId: credentialId,
      attachmentPath: attachmentPath,
    );
  }

  Future<void> _deleteAttachmentOrQueue({
    required String userId,
    required String credentialId,
    required String? attachmentPath,
  }) async {
    if (attachmentPath == null || attachmentPath.isEmpty) return;

    final ok = await _attachments.deleteIfExists(attachmentPath);
    if (ok) return;

    // Offline / Storage error — retry on next sync.
    if (!AttachmentStorageService.isLocalPath(attachmentPath)) {
      _hive.enqueuePendingOp(
        op: 'delete_storage',
        userId: userId,
        credentialId: credentialId,
        payload: {'attachmentPath': attachmentPath},
      );
    }
  }

  /// Pulls remote credentials + groups into Hive (merge by updatedAt).
  Future<void> syncFromFirebase(String userId) async {
    if (!FirebaseAvailability.isAvailable || _firestore == null) return;
    if (!await ConnectivityHelper.isOnline()) return;

    // Push pending local ops first
    await pushPendingOps(userId);

    final snap = await _col(userId)!.get();
    final remote = snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return CredentialEntry.fromMap(data);
    }).toList();

    final local = _hive.getAll(userId);
    final merged = <String, CredentialEntry>{};

    for (final e in local) {
      merged[e.id] = e;
    }
    for (final e in remote) {
      final existing = merged[e.id];
      if (existing == null) {
        merged[e.id] = e;
      } else {
        final eTime = e.updatedAt ?? e.createdAt ?? DateTime(1970);
        final lTime =
            existing.updatedAt ?? existing.createdAt ?? DateTime(1970);
        if (eTime.isAfter(lTime)) {
          merged[e.id] = e;
        }
      }
    }

    // Backfill accountGroupId + ensure parent group docs for all credentials.
    final withGroups = <CredentialEntry>[];
    final groupsToPersist = <String, AccountGroup>{};
    for (final e in merged.values) {
      final groupId = e.accountGroupId ??
          AccountGroup.docIdFor(
            serviceKey: e.serviceKey,
            groupName: e.accountGroupLabel,
          );
      final linked = e.accountGroupId == groupId
          ? e
          : e.copyWith(accountGroupId: groupId);
      withGroups.add(linked);
      groupsToPersist[groupId] = AccountGroup(
        id: groupId,
        userId: linked.userId,
        name: linked.accountGroupLabel,
        serviceKey: linked.serviceKey,
        platform: linked.platform,
        customPlatformName: linked.customPlatformName,
      );
    }

    _hive.replaceAll(userId, withGroups);

    // Merge remote groups collection
    try {
      final groupSnap = await _groupsCol(userId)!.get();
      final remoteGroups = groupSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return AccountGroup.fromMap(data);
      }).toList();
      for (final g in remoteGroups) {
        final existing = groupsToPersist[g.id];
        if (existing == null) {
          groupsToPersist[g.id] = g;
        } else {
          final eTime = g.updatedAt ?? g.createdAt ?? DateTime(1970);
          final lTime =
              existing.updatedAt ?? existing.createdAt ?? DateTime(1970);
          if (eTime.isAfter(lTime)) groupsToPersist[g.id] = g;
        }
      }
    } catch (_) {
      // Groups collection optional until rules deploy.
    }

    for (final g in groupsToPersist.values) {
      await _persistGroup(g);
    }

    HiveBoxes.syncMetaBox.put(
      'last_sync_$userId',
      DateTime.now().toIso8601String(),
    );
    _emit(userId);
  }

  /// Pushes queued offline mutations to Firestore (+ Storage deletes).
  Future<void> pushPendingOps(String userId) async {
    if (!FirebaseAvailability.isAvailable || _firestore == null) return;
    if (!await ConnectivityHelper.isOnline()) return;

    final ops = _hive.pendingOps(userId);
    for (final op in ops) {
      final opId = op['id'] as String;
      final type = op['op'] as String;
      final credId = op['credentialId'] as String;
      final payload = Map<String, dynamic>.from(op['payload'] as Map? ?? {});
      try {
        switch (type) {
          case 'add':
          case 'update':
            await _col(userId)
                ?.doc(credId)
                .set(payload, SetOptions(merge: true));
            // Also upsert parent group from credential payload when present.
            final groupId = payload['accountGroupId'] as String?;
            if (groupId != null && groupId.isNotEmpty) {
              final entry = CredentialEntry.fromMap({
                ...payload,
                'id': credId,
                'userId': userId,
              });
              final group = AccountGroup(
                id: groupId,
                userId: userId,
                name: entry.accountGroupLabel,
                serviceKey: entry.serviceKey,
                platform: entry.platform,
                customPlatformName: entry.customPlatformName,
              );
              await _groupsCol(userId)
                  ?.doc(groupId)
                  .set(group.toMap(), SetOptions(merge: true));
              _hive.putGroup(group);
            }
            _hive.removePendingOp(opId);
            break;
          case 'upsert_group':
            await _groupsCol(userId)
                ?.doc(credId)
                .set(payload, SetOptions(merge: true));
            _hive.removePendingOp(opId);
            break;
          case 'delete':
            await _col(userId)?.doc(credId).delete();
            final paths = <String>{
              if ((payload['attachmentPath'] as String?)?.isNotEmpty == true)
                payload['attachmentPath'] as String,
            };
            final extra = payload['attachmentPaths'];
            if (extra is List) {
              for (final item in extra) {
                final p = item?.toString() ?? '';
                if (p.isNotEmpty) paths.add(p);
              }
            }
            for (final path in paths) {
              final ok = await _attachments.deleteIfExists(path);
              if (!ok && !AttachmentStorageService.isLocalPath(path)) {
                _hive.enqueuePendingOp(
                  op: 'delete_storage',
                  userId: userId,
                  credentialId: credId,
                  payload: {'attachmentPath': path},
                );
              }
            }
            _hive.removePendingOp(opId);
            break;
          case 'delete_storage':
            final path = payload['attachmentPath'] as String?;
            if (path == null || path.isEmpty) {
              _hive.removePendingOp(opId);
              break;
            }
            final ok = await _attachments.deleteIfExists(path);
            if (!ok) {
              // Keep pending for next sync attempt.
              break;
            }
            _hive.removePendingOp(opId);
            break;
          default:
            _hive.removePendingOp(opId);
            break;
        }
      } catch (_) {
        // Keep pending for next sync attempt
        break;
      }
    }
  }

  /// Number of queued offline ops for [userId].
  int pendingCount(String userId) => _hive.pendingCount(userId);

  /// Last cloud sync timestamp for [userId].
  DateTime? lastSyncAt(String userId) => _hive.lastSyncAt(userId);

  void dispose() {
    _controller.close();
  }
}

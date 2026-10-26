import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive box names and offline bootstrap helpers.
class HiveBoxes {
  HiveBoxes._();

  static const String credentials = 'credentials_box';
  static const String groups = 'groups_box';
  static const String syncMeta = 'sync_meta_box';
  static const String pendingOps = 'pending_ops_box';

  /// Initializes Hive for Flutter (call once from main).
  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(credentials),
      Hive.openBox(groups),
      Hive.openBox(syncMeta),
      Hive.openBox(pendingOps),
    ]);
  }

  static Box get credentialsBox => Hive.box(credentials);
  static Box get groupsBox => Hive.box(groups);
  static Box get syncMetaBox => Hive.box(syncMeta);
  static Box get pendingOpsBox => Hive.box(pendingOps);
}

/// Checks whether the device currently has network access.
class ConnectivityHelper {
  ConnectivityHelper._();

  /// Returns true if any connection type other than none is present.
  static Future<bool> isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return false;
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/app_constants.dart';
import '../../domain/entities/entities.dart';

/// Loads / caches admin-controlled subscription catalog.
class SubscriptionCatalogService {
  SubscriptionCatalogService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions _functions;

  SubscriptionCatalog _cache = SubscriptionCatalog.defaults();
  SubscriptionCatalog get current => _cache;

  Future<SubscriptionCatalog> load({bool forceRefresh = true}) async {
    try {
      final result =
          await _functions.httpsCallable('getSubscriptionCatalog').call();
      final data = Map<String, dynamic>.from(result.data as Map);
      _cache = SubscriptionCatalog.fromMap(data);
      return _cache;
    } catch (_) {
      try {
        final fs = _firestore ?? FirebaseFirestore.instance;
        final snap = await fs
            .collection(AppConstants.colAppConfig)
            .doc(AppConstants.docSubscriptionConfig)
            .get();
        if (snap.exists && snap.data() != null) {
          _cache = SubscriptionCatalog.fromMap(snap.data()!);
          return _cache;
        }
      } catch (_) {}
      if (forceRefresh) {
        _cache = SubscriptionCatalog.defaults();
      }
      return _cache;
    }
  }
}

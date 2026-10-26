import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/entities.dart';

/// Admin + payment helpers via Cloud Functions (asia-south1).
class AdminCloudFunctions {
  AdminCloudFunctions({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<AdminDashboardData> getDashboard() async {
    try {
      final result =
          await _functions.httpsCallable('getAdminDashboard').call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final stats = Map<String, dynamic>.from(data['stats'] as Map? ?? {});
      final users = (data['users'] as List? ?? [])
          .map((e) => AdminUserRow.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final txns = (data['transactions'] as List? ?? [])
          .map(
            (e) => AdminTransaction.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      SubscriptionCatalog catalog = SubscriptionCatalog.defaults();
      if (data['catalog'] is Map) {
        catalog = SubscriptionCatalog.fromMap(
          Map<String, dynamic>.from(data['catalog'] as Map),
        );
      } else if (data['plans'] is Map) {
        catalog = SubscriptionCatalog.fromMap({
          'plans': data['plans'],
        });
      }
      return AdminDashboardData(
        stats: AdminStats.fromMap(stats),
        users: users,
        transactions: txns,
        catalog: catalog,
      );
    } on FirebaseFunctionsException catch (e) {
      throw AdminCloudException(e.message ?? e.code);
    }
  }

  Future<SubscriptionCatalog> updateSubscriptionConfig(
    SubscriptionCatalog catalog,
  ) async {
    try {
      final result = await _functions
          .httpsCallable('adminUpdateSubscriptionConfig')
          .call(catalog.toMap());
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['catalog'] is Map) {
        return SubscriptionCatalog.fromMap(
          Map<String, dynamic>.from(data['catalog'] as Map),
        );
      }
      return catalog;
    } on FirebaseFunctionsException catch (e) {
      throw AdminCloudException(e.message ?? e.code);
    }
  }

  Future<AdminUserRow> updateUserPlan({
    required String targetUserId,
    int? months,
    bool lifetimeFree = false,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('adminUpdateUserPlan').call({
        'targetUserId': targetUserId,
        if (months != null) 'months': months,
        'lifetimeFree': lifetimeFree,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return AdminUserRow.fromMap(
        Map<String, dynamic>.from(data['user'] as Map),
      );
    } on FirebaseFunctionsException catch (e) {
      throw AdminCloudException(e.message ?? e.code);
    }
  }

  Future<void> setUserBlocked({
    required String targetUserId,
    required bool blocked,
  }) async {
    try {
      await _functions.httpsCallable('adminSetUserBlocked').call({
        'targetUserId': targetUserId,
        'blocked': blocked,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AdminCloudException(e.message ?? e.code);
    }
  }

  Future<void> markPaymentFailed({
    required String orderId,
    String reason = 'cancelled',
  }) async {
    try {
      await _functions.httpsCallable('markPaymentFailed').call({
        'orderId': orderId,
        'reason': reason,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AdminCloudException(e.message ?? e.code);
    }
  }
}

class AdminCloudException implements Exception {
  AdminCloudException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminDashboardData {
  const AdminDashboardData({
    required this.stats,
    required this.users,
    required this.transactions,
    required this.catalog,
  });

  final AdminStats stats;
  final List<AdminUserRow> users;
  final List<AdminTransaction> transactions;
  final SubscriptionCatalog catalog;
}

class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.trialActive,
    required this.paidActive,
    required this.blocked,
    required this.expired,
    required this.successTransactions,
    required this.failedTransactions,
    required this.pendingTransactions,
  });

  factory AdminStats.fromMap(Map<String, dynamic> m) => AdminStats(
        totalUsers: (m['totalUsers'] as num?)?.toInt() ?? 0,
        trialActive: (m['trialActive'] as num?)?.toInt() ?? 0,
        paidActive: (m['paidActive'] as num?)?.toInt() ?? 0,
        blocked: (m['blocked'] as num?)?.toInt() ?? 0,
        expired: (m['expired'] as num?)?.toInt() ?? 0,
        successTransactions: (m['successTransactions'] as num?)?.toInt() ?? 0,
        failedTransactions: (m['failedTransactions'] as num?)?.toInt() ?? 0,
        pendingTransactions: (m['pendingTransactions'] as num?)?.toInt() ?? 0,
      );

  final int totalUsers;
  final int trialActive;
  final int paidActive;
  final int blocked;
  final int expired;
  final int successTransactions;
  final int failedTransactions;
  final int pendingTransactions;
}

class AdminUserRow {
  const AdminUserRow({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.userId,
    required this.planLabel,
    required this.isBlocked,
    required this.isTrialActive,
    required this.hasActiveAccess,
    this.isLifetimeFree = false,
    this.primaryMobile,
    this.subscriptionPlanMonths,
    this.subscriptionExpiresAt,
    this.trialStartedAt,
    this.createdAt,
  });

  factory AdminUserRow.fromMap(Map<String, dynamic> m) => AdminUserRow(
        uid: m['uid']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
        displayName: m['displayName']?.toString() ?? '',
        userId: m['userId']?.toString() ?? '',
        planLabel: m['planLabel']?.toString() ?? '—',
        isBlocked: m['isBlocked'] == true,
        isTrialActive: m['isTrialActive'] != false,
        hasActiveAccess: m['hasActiveAccess'] == true,
        isLifetimeFree: m['isLifetimeFree'] == true,
        primaryMobile: m['primaryMobile']?.toString(),
        subscriptionPlanMonths:
            (m['subscriptionPlanMonths'] as num?)?.toInt(),
        subscriptionExpiresAt: m['subscriptionExpiresAt']?.toString(),
        trialStartedAt: m['trialStartedAt']?.toString(),
        createdAt: m['createdAt']?.toString(),
      );

  final String uid;
  final String email;
  final String displayName;
  final String userId;
  final String planLabel;
  final bool isBlocked;
  final bool isTrialActive;
  final bool hasActiveAccess;
  final bool isLifetimeFree;
  final String? primaryMobile;
  final int? subscriptionPlanMonths;
  final String? subscriptionExpiresAt;
  final String? trialStartedAt;
  final String? createdAt;
}

class AdminTransaction {
  const AdminTransaction({
    required this.orderId,
    required this.userId,
    required this.status,
    this.months,
    this.priceInr,
    this.paymentId,
    this.failReason,
    this.createdAt,
    this.paidAt,
  });

  factory AdminTransaction.fromMap(Map<String, dynamic> m) => AdminTransaction(
        orderId: m['orderId']?.toString() ?? '',
        userId: m['userId']?.toString() ?? '',
        status: m['status']?.toString() ?? 'created',
        months: (m['months'] as num?)?.toInt(),
        priceInr: (m['priceInr'] as num?)?.toInt(),
        paymentId: m['paymentId']?.toString(),
        failReason: m['failReason']?.toString(),
        createdAt: m['createdAt']?.toString(),
        paidAt: m['paidAt']?.toString(),
      );

  final String orderId;
  final String userId;
  final String status;
  final int? months;
  final int? priceInr;
  final String? paymentId;
  final String? failReason;
  final String? createdAt;
  final String? paidAt;

  bool get isSuccess => status == 'paid';
  bool get isFailed => status == 'failed';
}

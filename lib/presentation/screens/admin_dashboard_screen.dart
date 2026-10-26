import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/admin/admin_cloud_functions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';

/// Admin console — only [AppConstants.adminEmail] may open this screen.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _admin = AdminCloudFunctions();
  final _dateFmt = DateFormat('dd MMM yyyy, HH:mm');
  int _tab = 0;
  bool _loading = true;
  String? _error;
  AdminDashboardData? _data;
  String _userFilter = 'all'; // all | trial | paid | blocked | expired
  String _txnFilter = 'all'; // all | paid | failed | pending

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAdminAndLoad());
  }

  Future<void> _ensureAdminAndLoad() async {
    final state = context.read<VaultAppState>();
    if (!AppConstants.isAdminEmail(state.user?.email)) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _admin.getDashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return _dateFmt.format(d.toLocal());
  }

  List<AdminUserRow> get _filteredUsers {
    final users = _data?.users ?? const <AdminUserRow>[];
    switch (_userFilter) {
      case 'trial':
        return users
            .where((u) => !u.isBlocked && u.isTrialActive && u.hasActiveAccess)
            .toList();
      case 'paid':
        return users
            .where(
              (u) =>
                  !u.isBlocked &&
                  !u.isTrialActive &&
                  u.subscriptionPlanMonths != null &&
                  u.hasActiveAccess,
            )
            .toList();
      case 'blocked':
        return users.where((u) => u.isBlocked).toList();
      case 'expired':
        return users.where((u) => !u.isBlocked && !u.hasActiveAccess).toList();
      default:
        return users;
    }
  }

  List<AdminTransaction> get _filteredTxns {
    final txns = _data?.transactions ?? const <AdminTransaction>[];
    switch (_txnFilter) {
      case 'paid':
        return txns.where((t) => t.isSuccess).toList();
      case 'failed':
        return txns.where((t) => t.isFailed).toList();
      case 'pending':
        return txns.where((t) => !t.isSuccess && !t.isFailed).toList();
      default:
        return txns;
    }
  }

  Future<void> _signOut() async {
    await context.read<VaultAppState>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _updatePlan(AdminUserRow user) async {
    // 0 = lifetime free; otherwise plan months.
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.sand,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update plan · ${user.email}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.all_inclusive, color: AppColors.teal),
                  title: const Text('Lifetime free'),
                  subtitle: const Text(
                    'Never expires · free vault access',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, 0),
                ),
                const Divider(height: 20),
                ...(_data?.catalog.plans ?? SubscriptionCatalog.defaults().plans)
                    .map((plan) {
                  return ListTile(
                    title: Text('${plan.months} months'),
                    subtitle: Text(
                      '₹${plan.priceInr} · ${plan.maxAttachmentFiles} files free',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, plan.months),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;

    try {
      if (choice == 0) {
        await _admin.updateUserPlan(
          targetUserId: user.uid,
          lifetimeFree: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lifetime free plan granted')),
        );
      } else {
        await _admin.updateUserPlan(
          targetUserId: user.uid,
          months: choice,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan updated to $choice months')),
        );
      }
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _toggleBlock(AdminUserRow user) async {
    final next = !user.isBlocked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(next ? 'Block user?' : 'Unblock user?'),
        content: Text(
          next
              ? '${user.email} will not be able to sign in.'
              : '${user.email} will be allowed to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(next ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _admin.setUserBlocked(targetUserId: user.uid, blocked: next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? 'User blocked' : 'User unblocked')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _showUserDetail(AdminUserRow user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sand,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName.isEmpty ? 'User' : user.displayName,
                  style: Theme.of(ctx).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(user.email),
              Text('@${user.userId}'),
              if (user.primaryMobile != null) Text(user.primaryMobile!),
              const SizedBox(height: 12),
              Text('Plan: ${user.planLabel}'),
              Text('Trial started: ${_fmtDate(user.trialStartedAt)}'),
              Text('Expires: ${_fmtDate(user.subscriptionExpiresAt)}'),
              Text('Created: ${_fmtDate(user.createdAt)}'),
              const SizedBox(height: 16),
              if (!AppConstants.isAdminEmail(user.email)) ...[
                VaultButton(
                  label: 'Update plan',
                  icon: Icons.workspace_premium_outlined,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _updatePlan(user);
                  },
                ),
                const SizedBox(height: 8),
                VaultButton(
                  label: user.isBlocked ? 'Unblock user' : 'Block user',
                  isOutlined: true,
                  icon: user.isBlocked
                      ? Icons.lock_open_outlined
                      : Icons.block_outlined,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _toggleBlock(user);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _data?.stats;

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin',
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          Text(
                            AppConstants.adminEmail,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          VaultButton(label: 'Retry', onPressed: _refresh),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _OverviewTab(stats: stats!),
                      _UsersTab(
                        filter: _userFilter,
                        onFilter: (v) => setState(() => _userFilter = v),
                        users: _filteredUsers,
                        onTap: _showUserDetail,
                        fmtDate: _fmtDate,
                      ),
                      _TxnsTab(
                        filter: _txnFilter,
                        onFilter: (v) => setState(() => _txnFilter = v),
                        txns: _filteredTxns,
                        fmtDate: _fmtDate,
                      ),
                      _PlansTab(
                        catalog: _data!.catalog,
                        onSaved: (catalog) async {
                          final messenger = ScaffoldMessenger.of(context);
                          final appState = context.read<VaultAppState>();
                          try {
                            final updated =
                                await _admin.updateSubscriptionConfig(catalog);
                            if (!mounted) return;
                            setState(() {
                              _data = AdminDashboardData(
                                stats: _data!.stats,
                                users: _data!.users,
                                transactions: _data!.transactions,
                                catalog: updated,
                              );
                            });
                            appState.subscriptionCatalog = updated;
                            await appState.refreshSubscriptionCatalog();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Plan prices & file limits updated',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.gradientBottom,
        indicatorColor: AppColors.foam,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Payments',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Plans',
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.stats});
  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _StatGrid(
          items: [
            _Stat('Total users', '${stats.totalUsers}', Icons.people),
            _Stat('Free trial', '${stats.trialActive}', Icons.hourglass_top),
            _Stat('Paid plans', '${stats.paidActive}', Icons.verified),
            _Stat('Expired', '${stats.expired}', Icons.event_busy),
            _Stat('Blocked', '${stats.blocked}', Icons.block),
            _Stat(
              'Success payments',
              '${stats.successTransactions}',
              Icons.check_circle_outline,
            ),
            _Stat(
              'Failed payments',
              '${stats.failedTransactions}',
              Icons.error_outline,
            ),
            _Stat(
              'Pending orders',
              '${stats.pendingTransactions}',
              Icons.pending_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});
  final List<_Stat> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((s) {
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 50) / 2,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(s.icon, color: AppColors.teal, size: 22),
                const SizedBox(height: 8),
                Text(s.value, style: Theme.of(context).textTheme.headlineMedium),
                Text(s.label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({
    required this.filter,
    required this.onFilter,
    required this.users,
    required this.onTap,
    required this.fmtDate,
  });

  final String filter;
  final ValueChanged<String> onFilter;
  final List<AdminUserRow> users;
  final ValueChanged<AdminUserRow> onTap;
  final String Function(String?) fmtDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in const [
                ('all', 'All'),
                ('trial', 'Trial'),
                ('paid', 'Paid'),
                ('expired', 'Expired'),
                ('blocked', 'Blocked'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.$2),
                    selected: filter == e.$1,
                    onSelected: (_) => onFilter(e.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: users.isEmpty
              ? const Center(child: Text('No users in this filter'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = users[i];
                    return Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        onTap: () => onTap(u),
                        title: Text(
                          u.displayName.isEmpty ? u.email : u.displayName,
                        ),
                        subtitle: Text(
                          '${u.email}\n${u.planLabel} · exp ${fmtDate(u.subscriptionExpiresAt)}',
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          u.isBlocked ? Icons.block : Icons.chevron_right,
                          color: u.isBlocked ? AppColors.coral : AppColors.slate,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TxnsTab extends StatelessWidget {
  const _TxnsTab({
    required this.filter,
    required this.onFilter,
    required this.txns,
    required this.fmtDate,
  });

  final String filter;
  final ValueChanged<String> onFilter;
  final List<AdminTransaction> txns;
  final String Function(String?) fmtDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in const [
                ('all', 'All'),
                ('paid', 'Success'),
                ('failed', 'Failed'),
                ('pending', 'Pending'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.$2),
                    selected: filter == e.$1,
                    onSelected: (_) => onFilter(e.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: txns.isEmpty
              ? const Center(child: Text('No transactions'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: txns.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = txns[i];
                    final color = t.isSuccess
                        ? AppColors.teal
                        : t.isFailed
                            ? AppColors.coral
                            : AppColors.amber;
                    return Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        leading: Icon(
                          t.isSuccess
                              ? Icons.check_circle
                              : t.isFailed
                                  ? Icons.cancel
                                  : Icons.hourglass_empty,
                          color: color,
                        ),
                        title: Text(
                          '${t.status.toUpperCase()} · '
                          '${t.months ?? '-'}m · ₹${t.priceInr ?? '-'}',
                        ),
                        subtitle: Text(
                          'User: ${t.userId}\n'
                          'Order: ${t.orderId}\n'
                          '${fmtDate(t.createdAt)}'
                          '${t.failReason != null ? '\n${t.failReason}' : ''}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Admin editor for plan prices + max attachment file counts.
class _PlansTab extends StatefulWidget {
  const _PlansTab({
    required this.catalog,
    required this.onSaved,
  });

  final SubscriptionCatalog catalog;
  final Future<void> Function(SubscriptionCatalog catalog) onSaved;

  @override
  State<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<_PlansTab> {
  late final TextEditingController _trialFilesCtrl;
  late final Map<int, TextEditingController> _priceCtrls;
  late final Map<int, TextEditingController> _fileCtrls;
  late final Map<int, TextEditingController> _upgradePriceCtrls;
  late final Map<int, TextEditingController> _upgradeFileCtrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _trialFilesCtrl = TextEditingController(
      text: '${widget.catalog.trialMaxAttachmentFiles}',
    );
    _priceCtrls = {
      for (final p in widget.catalog.plans)
        p.months: TextEditingController(text: '${p.priceInr}'),
    };
    _fileCtrls = {
      for (final p in widget.catalog.plans)
        p.months: TextEditingController(text: '${p.maxAttachmentFiles}'),
    };
    _upgradePriceCtrls = {
      for (final p in widget.catalog.fileUpgradePlans)
        p.months: TextEditingController(text: '${p.priceInr}'),
    };
    _upgradeFileCtrls = {
      for (final p in widget.catalog.fileUpgradePlans)
        p.months: TextEditingController(text: '${p.maxAttachmentFiles}'),
    };
  }

  @override
  void didUpdateWidget(covariant _PlansTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      _trialFilesCtrl.text = '${widget.catalog.trialMaxAttachmentFiles}';
      for (final p in widget.catalog.plans) {
        _priceCtrls[p.months]?.text = '${p.priceInr}';
        _fileCtrls[p.months]?.text = '${p.maxAttachmentFiles}';
      }
      for (final p in widget.catalog.fileUpgradePlans) {
        _upgradePriceCtrls[p.months]?.text = '${p.priceInr}';
        _upgradeFileCtrls[p.months]?.text = '${p.maxAttachmentFiles}';
      }
    }
  }

  @override
  void dispose() {
    _trialFilesCtrl.dispose();
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    for (final c in _fileCtrls.values) {
      c.dispose();
    }
    for (final c in _upgradePriceCtrls.values) {
      c.dispose();
    }
    for (final c in _upgradeFileCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final trialFiles = int.tryParse(_trialFilesCtrl.text.trim());
    if (trialFiles == null || trialFiles < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid trial file limit')),
      );
      return;
    }
    final plans = <SubscriptionPlan>[];
    for (final p in widget.catalog.plans) {
      final price = int.tryParse(_priceCtrls[p.months]?.text.trim() ?? '');
      final files = int.tryParse(_fileCtrls[p.months]?.text.trim() ?? '');
      if (price == null || price < 1 || files == null || files < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid base plan for ${p.months} months'),
          ),
        );
        return;
      }
      plans.add(
        SubscriptionPlan(
          months: p.months,
          priceInr: price,
          maxAttachmentFiles: files,
        ),
      );
    }
    final filePlans = <FileUpgradePlan>[];
    for (final p in widget.catalog.fileUpgradePlans) {
      final price =
          int.tryParse(_upgradePriceCtrls[p.months]?.text.trim() ?? '');
      final files =
          int.tryParse(_upgradeFileCtrls[p.months]?.text.trim() ?? '');
      if (price == null || price < 1 || files == null || files < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid file upgrade for ${p.months} months'),
          ),
        );
        return;
      }
      filePlans.add(
        FileUpgradePlan(
          months: p.months,
          priceInr: price,
          maxAttachmentFiles: files,
        ),
      );
    }
    setState(() => _saving = true);
    try {
      await widget.onSaved(
        SubscriptionCatalog(
          plans: plans,
          fileUpgradePlans: filePlans,
          trialMaxAttachmentFiles: trialFiles,
          maxAttachmentBytes: widget.catalog.maxAttachmentBytes,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Base subscription plans',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Price (₹) + files included with each subscription.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _trialFilesCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Free trial — max files',
            prefixIcon: Icon(Icons.hourglass_top),
          ),
        ),
        const SizedBox(height: 16),
        ...widget.catalog.plans.map((plan) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.months} months · base',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrls[plan.months],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price ₹',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _fileCtrls[plan.months],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Included files',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
        Text(
          'Upgrade file plans',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Separate add-on: more files for a price (per duration).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        ...widget.catalog.fileUpgradePlans.map((plan) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.months} months · file upgrade',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _upgradePriceCtrls[plan.months],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price ₹',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _upgradeFileCtrls[plan.months],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max files',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        VaultButton(
          label: 'Save all plan prices & file limits',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/share/credential_share_codec.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/platform_category.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pin_gate.dart';
import '../widgets/service_picker_sheet.dart';
import 'add_credential_screen.dart';
import 'pin_lock_screen.dart';
import 'subscription_screen.dart';

String _attachmentSizeLabel(CredentialAttachment file) {
  final bytes = file.sizeBytes;
  if (bytes == null) return 'File';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// Dashboard — all daily platforms, multi-account per platform (req 6, 12, 13).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _query = '';
  PlatformCategory? _filter;
  /// When filtering a manual service (e.g. Sarkari Result).
  String? _customServiceFilter;
  late final VaultBannerCoordinator _bannerCoordinator;

  @override
  void initState() {
    super.initState();
    _bannerCoordinator = VaultBannerCoordinator();
  }

  @override
  void dispose() {
    _bannerCoordinator.dispose();
    super.dispose();
  }

  String get _filterLabel {
    if (_customServiceFilter != null) return _customServiceFilter!;
    if (_filter == null) return 'All';
    return PlatformInfo.of(_filter!).label;
  }

  /// Prompts to renew the file plan matching the active base plan.
  Future<bool?> _promptFilePlanRenewal(
    BuildContext context,
    VaultAppState state, {
    int? months,
    int? priceInr,
    int? extraFiles,
  }) async {
    final planMonths = months ?? state.user?.subscriptionPlanMonths;
    final filePlan =
        state.subscriptionCatalog.fileUpgradeForMonths(planMonths);
    final renewMonths = filePlan?.months ?? planMonths ?? 3;
    final renewPrice = priceInr ?? filePlan?.priceInr ?? 0;
    final renewExtra = extraFiles ?? filePlan?.maxAttachmentFiles ?? 0;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renew file plan'),
        content: Text(
          'This file is above your free quota '
          '(${state.baseAttachmentFileLimit} free on your current base plan). '
          'Take the $renewMonths-month file plan'
          '${renewExtra > 0 ? ' (+$renewExtra files)' : ''}'
          '${renewPrice > 0 ? ' · ₹$renewPrice' : ''} to open it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Renew now'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return false;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const SubscriptionScreen(renewFilePlan: true),
      ),
    );
    if (!context.mounted) return false;
    await state.refreshUserProfile();
    return state.user?.hasActiveFilePlan == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();
    final q = _query.trim().toLowerCase();

    // Manual services that match the search box (even with zero passwords yet)
    final matchedManualServices = q.isEmpty
        ? const <String>[]
        : state.customServices
            .where((s) => s.toLowerCase().contains(q))
            .toList();

    final items = state.credentials.where((c) {
      final matchQuery = q.isEmpty ||
          c.title.toLowerCase().contains(q) ||
          c.accountUserId.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.platformLabel.toLowerCase().contains(q) ||
          (c.accountGroup?.toLowerCase().contains(q) ?? false) ||
          PlatformInfo.of(c.platform).label.toLowerCase().contains(q) ||
          c.platform.name.toLowerCase().contains(q) ||
          (c.customPlatformName?.toLowerCase().contains(q) ?? false) ||
          (c.website?.toLowerCase().contains(q) ?? false) ||
          // Match dashboard search against saved manual service names
          matchedManualServices.any(
            (s) =>
                c.platform == PlatformCategory.other &&
                (c.customPlatformName?.toLowerCase() == s.toLowerCase()),
          );

      bool matchPlatform = true;
      if (_customServiceFilter != null) {
        matchPlatform = c.platform == PlatformCategory.other &&
            (c.customPlatformName?.toLowerCase() ==
                _customServiceFilter!.toLowerCase());
      } else if (_filter != null) {
        matchPlatform = c.platform == _filter;
      }
      return matchQuery && matchPlatform;
    }).toList();

    // Nest: Service (Email) → Company group (Abc Company) → passwords
    final nested = <String, Map<String, List<CredentialEntry>>>{};
    for (final c in items) {
      final serviceMap =
          nested.putIfAbsent(c.serviceKey, () => <String, List<CredentialEntry>>{});
      serviceMap.putIfAbsent(c.accountGroupKey, () => []).add(c);
    }
    for (final groups in nested.values) {
      for (final list in groups.values) {
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
    }

    // Manual services matched by search that have no passwords yet
    final orphanManualMatches = matchedManualServices.where((name) {
      final key = 'other:${name.toLowerCase()}';
      return !nested.containsKey(key) &&
          (_customServiceFilter == null ||
              _customServiceFilter!.toLowerCase() == name.toLowerCase());
    }).toList();

    return VaultBackground(
      child: SafeArea(
        // Scaffold bottomNavigationBar already owns bottom inset
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VaultBannerAd(
              placement: 'dashboard_header',
              coordinator: _bannerCoordinator,
              slot: VaultBannerSlot.header,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vault',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          _filter == null && _customServiceFilter == null
                              ? '${state.credentials.length} encrypted secrets'
                              : 'Filter: $_filterLabel · long-press to reorder',
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FloatingActionButton.small(
                    heroTag: 'add_cred',
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.white,
                    onPressed: () => _openAdd(context, state),
                    child: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'Import from PasswordSaver share',
                    onPressed: () => _importSharedCredential(context, state),
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                  IconButton(
                    tooltip: state.unsyncedCount > 0
                        ? 'Sync · ${state.unsyncedCount} unsynced'
                        : 'Sync offline → cloud',
                    onPressed: state.isSyncing
                        ? null
                        : () async {
                            final ok = await state.syncNow();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? (state.unsyncedCount == 0
                                          ? 'Cloud sync complete'
                                          : 'Synced · ${state.unsyncedCount} still pending')
                                      : state.errorMessage ?? 'Sync failed',
                                ),
                              ),
                            );
                          },
                    icon: Badge(
                      isLabelVisible: state.unsyncedCount > 0,
                      label: Text('${state.unsyncedCount}'),
                      child: state.isSyncing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search service, title, email…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            // View more always pinned first (always on screen);
            // All fixed next; remaining chips scroll by priority.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    _Chip(
                      label: 'View more',
                      selected: false,
                      emphasized: true,
                      onTap: () => _openServicePicker(context),
                    ),
                    _Chip(
                      label: 'All',
                      selected:
                          _filter == null && _customServiceFilter == null,
                      onTap: () => setState(() {
                        _filter = null;
                        _customServiceFilter = null;
                      }),
                    ),
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: state.chipPriority.length,
                        itemBuilder: (context, index) {
                          final ref = state.chipPriority[index];
                          return _Chip(
                            label: ref.label,
                            selected: ref.matchesFilter(
                              filter: _filter,
                              customFilter: _customServiceFilter,
                            ),
                            onTap: () {
                              if (ref.isCustom) {
                                setState(() {
                                  _filter = PlatformCategory.other;
                                  _customServiceFilter = ref.customName;
                                });
                                return;
                              }
                              setState(() {
                                _filter = ref.platform;
                                _customServiceFilter = null;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _buildVaultList(
                context: context,
                state: state,
                nested: nested,
                orphanManualMatches: orphanManualMatches,
              ),
            ),
            if (state.showHomeFooterAds)
              VaultBannerAd(
                placement: 'dashboard_footer',
                coordinator: _bannerCoordinator,
                slot: VaultBannerSlot.footer,
              ),
          ],
        ),
      ),
    );
  }

  /// Credentials nested as Service → Company group → passwords.
  Widget _buildVaultList({
    required BuildContext context,
    required VaultAppState state,
    required Map<String, Map<String, List<CredentialEntry>>> nested,
    required List<String> orphanManualMatches,
  }) {
    final hasGroups = nested.isNotEmpty;
    final hasOrphans = orphanManualMatches.isNotEmpty;

    if (!hasGroups && !hasOrphans) {
      return _EmptyVault(
        serviceLabel: _customServiceFilter,
        onAdd: () => _openAdd(
          context,
          state,
          customServiceName: _customServiceFilter,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        ...orphanManualMatches.map(
          (name) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.lock_outline, color: AppColors.teal),
              title: Text(name),
              subtitle: const Text('Manual service · no passwords yet'),
              trailing: Icon(Icons.add_circle_outline, color: AppColors.teal),
              onTap: () {
                setState(() {
                  _filter = PlatformCategory.other;
                  _customServiceFilter = name;
                });
                _openAdd(context, state, customServiceName: name);
              },
            ),
          ),
        ),
        ...nested.entries.map((serviceEntry) {
          final groups = serviceEntry.value;
          final sample = groups.values.first.first;
          final totalPasswords =
              groups.values.fold<int>(0, (sum, list) => sum + list.length);
          return _ServiceSection(
            title: sample.platformLabel,
            iconName: PlatformInfo.of(sample.platform).iconName,
            totalCount: totalPasswords,
            groups: groups,
            onTapPassword: (e) => _showDetail(context, e),
            onAddToGroup: (groupLabel) => _openAdd(
              context,
              state,
              customServiceName: sample.platform == PlatformCategory.other
                  ? sample.customPlatformName
                  : null,
              platform: sample.platform == PlatformCategory.other
                  ? null
                  : sample.platform,
              accountGroup: groupLabel == 'General' ? null : groupLabel,
            ),
            onAddNewGroup: () => _openAdd(
              context,
              state,
              customServiceName: sample.platform == PlatformCategory.other
                  ? sample.customPlatformName
                  : null,
              platform: sample.platform == PlatformCategory.other
                  ? null
                  : sample.platform,
            ),
            onReorder: (ordered) async {
              await context.read<VaultAppState>().reorderCredentials(ordered);
            },
          );
        }),
      ],
    );
  }

  Future<void> _openServicePicker(BuildContext context) async {
    final result = await showServicePickerSheet(context);
    if (result == null || !mounted) return;
    setState(() {
      if (result.isAll) {
        _filter = null;
        _customServiceFilter = null;
      } else if (result.customName != null &&
          result.customName!.trim().isNotEmpty) {
        _filter = PlatformCategory.other;
        _customServiceFilter = result.customName!.trim();
      } else {
        _filter = result.platform;
        _customServiceFilter = null;
      }
    });
  }

  /// Share title, user id, password, notes, website, service, and group.
  Future<void> _shareEntry(
    BuildContext context,
    VaultAppState state,
    CredentialEntry entry,
  ) async {
    final pin = await requirePinToContinue(
      context,
      title: 'Enter app PIN',
      subtitle: 'PIN is required to share this password',
    );
    if (pin == null || !context.mounted) return;
    try {
      final plain = await state.decryptPasswordAsync(entry);
      if (!context.mounted) return;
      final shared = SharedCredential(
        title: entry.title,
        accountUserId: entry.accountUserId,
        password: plain,
        description: entry.description,
        website: entry.website,
        platform: entry.platform,
        customPlatformName: entry.customPlatformName,
        accountGroup: entry.accountGroup,
      );
      final mode = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Readable text'),
                subtitle: const Text('Title, user ID, and password in plain words'),
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_outlined),
                title: const Text('Import code'),
                subtitle: const Text('Another PasswordSaver can save this'),
                onTap: () => Navigator.pop(ctx, 'code'),
              ),
            ],
          ),
        ),
      );
      if (mode == null || !context.mounted) return;
      final text = mode == 'text'
          ? CredentialShareCodec.readable(shared)
          : CredentialShareCodec.encode(shared);
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: 'PasswordSaver · ${entry.title}',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _importSharedCredential(
    BuildContext context,
    VaultAppState state,
  ) async {
    final ready = await ensureAppPinExists(context);
    if (!context.mounted || !ready) return;

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('Paste share text'),
              onTap: () => Navigator.pop(ctx, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('Choose share file'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    String? raw;
    if (source == 'paste') {
      final ctrl = TextEditingController();
      raw = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import PasswordSaver share'),
          content: TextField(
            controller: ctrl,
            minLines: 3,
            maxLines: 6,
            enableInteractiveSelection: true,
            decoration: const InputDecoration(
              hintText: 'Paste the PSVAULT1:… text',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx, ctrl.text);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      // Dialog pop finishes its overlay on the next frames. Opening the PIN
      // dialog in the same frame reparents those overlay keys and crashes.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      ctrl.dispose();
    } else {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      if (file.bytes != null) {
        raw = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        raw = await File(file.path!).readAsString();
      }
    }
    if (!context.mounted || raw == null || raw.trim().isEmpty) return;

    final shared = CredentialShareCodec.decode(raw);
    if (shared == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This is not a PasswordSaver share'),
        ),
      );
      return;
    }

    final pin = await requirePinToContinue(
      context,
      title: 'Enter app PIN',
      subtitle: 'Save “${shared.title}” into your vault',
    );
    if (pin == null || !context.mounted) return;

    final ok = await state.addCredential(
      platform: shared.platform,
      title: shared.title,
      accountUserId: shared.accountUserId,
      plainPassword: shared.password,
      description: shared.description,
      website: shared.website,
      customPlatformName: shared.customPlatformName,
      accountGroup: shared.accountGroup,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Saved ${shared.title}'
              : state.errorMessage ?? 'Could not save',
        ),
      ),
    );
  }

  /// Opens Add Password. Prefills service and optional company group.
  Future<void> _openAdd(
    BuildContext context,
    VaultAppState state, {
    String? customServiceName,
    PlatformCategory? platform,
    String? accountGroup,
  }) async {
    final ready = await ensureAppPinExists(context);
    if (!context.mounted || !ready) return;

    final custom =
        (customServiceName ?? _customServiceFilter)?.trim();
    final hasCustom = custom != null && custom.isNotEmpty;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddCredentialScreen(
          initialPlatform: hasCustom
              ? PlatformCategory.other
              : (platform ?? _filter),
          initialCustomPlatformName: hasCustom ? custom : null,
          initialAccountGroup: accountGroup,
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, CredentialEntry entry) async {
    final state = context.read<VaultAppState>();
    var revealed = false;
    String? plain;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sand,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.mist,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(entry.title,
                      style: Theme.of(ctx).textTheme.headlineMedium),
                  Text(
                    '${entry.platformLabel} · ${entry.accountGroupLabel}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  if (!state.hasPin) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'App PIN not created yet. Create a PIN to view passwords.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    VaultButton(
                      label: 'Create app PIN',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PinLockScreen(
                              forceCreate: true,
                              returnAfterCreate: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(entry.accountUserId),
                    subtitle: const Text('User ID'),
                    trailing: IconButton(
                      tooltip: 'Copy user ID',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () async {
                        final id = entry.accountUserId.trim();
                        if (id.isEmpty) return;
                        await Clipboard.setData(ClipboardData(text: id));
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('User ID copied'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: Text(revealed ? (plain ?? '…') : '••••••••••••'),
                    subtitle: Text(
                      revealed
                          ? 'Visible — you can copy'
                          : 'Password (PIN required to view)',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (revealed && plain != null)
                          IconButton(
                            tooltip: 'Copy password',
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: plain!),
                              );
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Password copied'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        IconButton(
                          tooltip: revealed ? 'Hide' : 'Show',
                          icon: Icon(
                            revealed
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () async {
                            if (revealed) {
                              setModal(() {
                                revealed = false;
                                plain = null;
                              });
                              return;
                            }

                            // Use screen context (not sheet) so PIN dialog /
                            // errors remain visible above the bottom sheet.
                            final gateContext =
                                context.mounted ? context : ctx;

                            // PIN only when "PIN to view password" is enabled
                            if (state.reverifyOnView) {
                              final pin = await requirePinToContinue(
                                gateContext,
                                title: 'Enter app PIN',
                                subtitle:
                                    'PIN is required every time you view a password',
                              );
                              if (pin == null) return;
                              if (!ctx.mounted) return;
                            }

                            try {
                              final decrypted =
                                  await state.decryptPasswordAsync(entry);
                              if (!ctx.mounted) return;
                              setModal(() {
                                plain = decrypted;
                                revealed = true;
                              });
                            } catch (e) {
                              final message = '$e'
                                  .replaceFirst('Exception: ', '');
                              if (context.mounted) {
                                await showDialog<void>(
                                  context: context,
                                  builder: (dialogCtx) => AlertDialog(
                                    title: const Text('Cannot show password'),
                                    content: Text(message),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogCtx),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  if (entry.description.isNotEmpty)
                    Text(entry.description,
                        style: Theme.of(ctx).textTheme.bodyMedium),
                  if (entry.hasAttachment) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.attachmentCount == 1
                          ? 'Attachment'
                          : 'Attachments (${entry.attachmentCount})',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    for (final att in entry.effectiveAttachments)
                      FutureBuilder<bool>(
                        future: state.isAttachmentCached(entry, att),
                        builder: (context, snap) {
                          final cached = snap.data == true;
                          final needsFileRenew =
                              !state.canOpenAttachment(entry, att) &&
                                  state.isUpgradeAttachment(entry, att);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              needsFileRenew
                                  ? Icons.lock_outline_rounded
                                  : cached
                                      ? Icons.folder_rounded
                                      : att.isLocal
                                          ? Icons.phone_android_rounded
                                          : Icons.cloud_download_outlined,
                            ),
                            title: Text(att.name ?? 'Attachment'),
                            subtitle: Text(
                              needsFileRenew
                                  ? '${_attachmentSizeLabel(att)} · renew file plan to open'
                                  : cached
                                      ? '${_attachmentSizeLabel(att)} · saved in app · PIN to open'
                                      : att.isLocal
                                          ? '${_attachmentSizeLabel(att)} · on device · PIN to open'
                                          : '${_attachmentSizeLabel(att)} · will download once · PIN to open',
                            ),
                            trailing: Icon(
                              needsFileRenew
                                  ? Icons.workspace_premium_outlined
                                  : cached
                                      ? Icons.folder_open_rounded
                                      : Icons.download_rounded,
                            ),
                            onTap: () async {
                              if (needsFileRenew) {
                                final renewed =
                                    await _promptFilePlanRenewal(ctx, state);
                                if (renewed == true && ctx.mounted) {
                                  if (!state.canOpenAttachment(entry, att)) {
                                    return;
                                  }
                                } else {
                                  return;
                                }
                              }

                              final pin = await requirePinToContinue(
                                ctx,
                                title: 'Enter app PIN',
                                subtitle: 'Required to open this document',
                              );
                              if (pin == null || !ctx.mounted) return;

                              final alreadyCached =
                                  await state.isAttachmentCached(entry, att);

                              if (!alreadyCached && ctx.mounted) {
                                showDialog<void>(
                                  context: ctx,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: Card(
                                      child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              try {
                                final file = await state.downloadAttachment(
                                  entry,
                                  att,
                                );
                                if (!alreadyCached && ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                                await SharePlus.instance.share(
                                  ShareParams(
                                    files: [
                                      XFile(
                                        file.path,
                                        name: att.name ?? p.basename(file.path),
                                        mimeType: att.mime,
                                      ),
                                    ],
                                    text: att.name ?? 'Attachment',
                                  ),
                                );
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        alreadyCached
                                            ? 'Opened from app storage'
                                            : 'Downloaded & saved in app for offline use',
                                      ),
                                    ),
                                  );
                                }
                              } on FilePlanRenewalRequiredException catch (e) {
                                if (!alreadyCached && ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                                if (ctx.mounted) {
                                  await _promptFilePlanRenewal(
                                    ctx,
                                    state,
                                    months: e.months,
                                    priceInr: e.priceInr,
                                    extraFiles: e.extraFiles,
                                  );
                                }
                              } catch (e) {
                                if (!alreadyCached && ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e
                                            .toString()
                                            .replaceFirst('Exception: ', ''),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _shareEntry(context, state, entry),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share to PasswordSaver'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final pin = await requirePinToContinue(
                              ctx,
                              title: 'Enter app PIN',
                              subtitle: 'Required to update this password',
                            );
                            if (pin == null || !ctx.mounted) return;
                            Navigator.pop(ctx);
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AddCredentialScreen(
                                  existing: entry,
                                  verifyPin: pin,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Update'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final pin = await requirePinToContinue(
                              ctx,
                              title: 'Enter app PIN',
                              subtitle: 'Required to delete this password',
                            );
                            if (pin == null || !ctx.mounted) return;
                            final ok =
                                await state.deleteCredential(entry.id, pin);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Deleted'
                                      : state.errorMessage ?? 'Failed',
                                ),
                              ),
                            );
                          },
                          icon: Icon(Icons.delete_outline,
                              color: AppColors.coral),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.teal,
        labelStyle: TextStyle(
          color: selected
              ? Colors.white
              : emphasized
                  ? AppColors.teal
                  : AppColors.slate,
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: emphasized
            ? AppColors.foam
            : Colors.white,
        side: emphasized
            ? BorderSide(color: AppColors.teal, width: 1.2)
            : null,
      ),
    );
  }
}

class _ServiceSection extends StatelessWidget {
  const _ServiceSection({
    required this.title,
    required this.iconName,
    required this.totalCount,
    required this.groups,
    required this.onTapPassword,
    required this.onAddToGroup,
    required this.onAddNewGroup,
    required this.onReorder,
  });

  final String title;
  final String iconName;
  final int totalCount;
  final Map<String, List<CredentialEntry>> groups;
  final ValueChanged<CredentialEntry> onTapPassword;
  final ValueChanged<String> onAddToGroup;
  final VoidCallback onAddNewGroup;
  final Future<void> Function(List<CredentialEntry> ordered) onReorder;

  @override
  Widget build(BuildContext context) {
    final sortedGroupKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'general') return 1;
        if (b == 'general') return -1;
        final aLabel = groups[a]!.first.accountGroupLabel.toLowerCase();
        final bLabel = groups[b]!.first.accountGroupLabel.toLowerCase();
        return aLabel.compareTo(bLabel);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.foam,
                child: Icon(platformIcon(iconName), color: AppColors.teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '$totalCount',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              IconButton(
                tooltip: 'Add group / password',
                onPressed: onAddNewGroup,
                icon: Icon(Icons.add_circle_outline, color: AppColors.teal),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Groups inside $title · tap + to add another group',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 10),
          ...sortedGroupKeys.map((key) {
            final entries = groups[key]!;
            final groupLabel = entries.first.accountGroupLabel;
            return _AccountGroupCard(
              groupLabel: groupLabel,
              entries: entries,
              onTapPassword: onTapPassword,
              onAddPassword: () => onAddToGroup(groupLabel),
              onReorder: onReorder,
            );
          }),
        ],
      ),
    );
  }
}

class _AccountGroupCard extends StatelessWidget {
  const _AccountGroupCard({
    required this.groupLabel,
    required this.entries,
    required this.onTapPassword,
    required this.onAddPassword,
    required this.onReorder,
  });

  final String groupLabel;
  final List<CredentialEntry> entries;
  final ValueChanged<CredentialEntry> onTapPassword;
  final VoidCallback onAddPassword;
  final Future<void> Function(List<CredentialEntry> ordered) onReorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.foam.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mist.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 20, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  groupLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '${entries.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              IconButton(
                tooltip: 'Add password in $groupLabel',
                onPressed: onAddPassword,
                icon: Icon(Icons.add, color: AppColors.teal),
              ),
            ],
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: entries.length,
            onReorder: (oldIndex, newIndex) async {
              final list = List<CredentialEntry>.from(entries);
              if (newIndex > oldIndex) newIndex -= 1;
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              await onReorder(list);
            },
            itemBuilder: (context, index) {
              final e = entries[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(e.id),
                index: index,
                child: InkWell(
                  onTap: () => onTapPassword(e),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.mist.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.drag_handle, color: AppColors.slate, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                e.accountUserId,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (e.hasAttachment) ...[
                          Icon(Icons.attach_file_rounded,
                              size: 16, color: AppColors.teal),
                          if (e.attachmentCount > 1)
                            Text(
                              '${e.attachmentCount}',
                              style: TextStyle(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          const SizedBox(width: 4),
                        ],
                        Icon(Icons.chevron_right, color: AppColors.slate),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.onAdd, this.serviceLabel});

  final VoidCallback onAdd;
  final String? serviceLabel;

  @override
  Widget build(BuildContext context) {
    final hasService = serviceLabel != null && serviceLabel!.trim().isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_moon_outlined,
                    size: 56,
                    color: AppColors.teal.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasService
                        ? 'No passwords for $serviceLabel'
                        : 'Your vault is empty',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasService
                        ? 'Add the first encrypted password for this manual service.'
                        : 'Store email, banking, social, store, and government passwords — all encrypted.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  VaultButton(
                    label: hasService
                        ? 'Add password for $serviceLabel'
                        : 'Add first password',
                    onPressed: onAdd,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

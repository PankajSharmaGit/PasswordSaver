import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/string_formatters.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/platform_category.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pin_gate.dart';
import 'subscription_screen.dart';

/// Add or update credential (requirement 12, 13).
///
/// Selecting a service (e.g. Email) places the password in that service group.
/// Optional files (max 1 MB each) are compressed then uploaded to cloud storage.
class AddCredentialScreen extends StatefulWidget {
  const AddCredentialScreen({
    super.key,
    this.existing,
    this.verifyPin,
    this.initialPlatform,
    this.initialCustomPlatformName,
    this.initialAccountGroup,
  });

  final CredentialEntry? existing;
  final String? verifyPin;

  /// Pre-selected from dashboard filter (e.g. Outlook). User can still change.
  final PlatformCategory? initialPlatform;

  /// Pre-filled custom service name (e.g. Sarkari Result).
  final String? initialCustomPlatformName;

  /// Pre-filled company / account group (e.g. Abc Company).
  final String? initialAccountGroup;

  @override
  State<AddCredentialScreen> createState() => _AddCredentialScreenState();
}

class _AddCredentialScreenState extends State<AddCredentialScreen> {
  final _formKey = GlobalKey<FormState>();
  late PlatformCategory _platform;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _userIdCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _websiteCtrl;
  late final TextEditingController _customPlatformCtrl;
  late final TextEditingController _accountGroupCtrl;
  bool _obscure = true;
  final List<File> _pickedFiles = [];
  final List<String> _pickedLabels = [];
  final Set<String> _removedExistingIds = {};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final initialCustom =
        (widget.initialCustomPlatformName ?? '').trim();

    // Manual service from dashboard chip → always bind Other + name
    if (e == null && initialCustom.isNotEmpty) {
      _platform = PlatformCategory.other;
    } else {
      _platform =
          e?.platform ?? widget.initialPlatform ?? PlatformCategory.email;
    }

    final customName = e?.customPlatformName ??
        (initialCustom.isNotEmpty
            ? StringFormatters.toTitleCase(initialCustom)
            : '');

    final groupName = e?.accountGroup ??
        ((widget.initialAccountGroup ?? '').trim().isNotEmpty
            ? StringFormatters.toTitleCase(widget.initialAccountGroup!)
            : '');

    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _userIdCtrl = TextEditingController(text: e?.accountUserId ?? '');
    _passwordCtrl = TextEditingController();
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _websiteCtrl = TextEditingController(text: e?.website ?? '');
    _customPlatformCtrl = TextEditingController(text: customName);
    _accountGroupCtrl = TextEditingController(text: groupName);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    _descCtrl.dispose();
    _websiteCtrl.dispose();
    _customPlatformCtrl.dispose();
    _accountGroupCtrl.dispose();
    super.dispose();
  }

  Future<void> _openSubscriptionForFiles() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'File limit reached (${context.read<VaultAppState>().attachmentUsageLabel}). '
          'Upgrade your plan for more files.',
        ),
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
  }

  int get _keptExistingCount {
    final existing = widget.existing;
    if (existing == null) return 0;
    return existing.effectiveAttachments
        .where((a) => !_removedExistingIds.contains(a.id))
        .length;
  }

  int get _totalFilesAfterPick =>
      _keptExistingCount + _pickedFiles.length;

  Future<void> _pickFiles() async {
    final state = context.read<VaultAppState>();
    final remainingSlots =
        state.attachmentFileLimit - state.attachmentFileCount;
    if (remainingSlots <= 0) {
      await _openSubscriptionForFiles();
      return;
    }
    final remainingPerCredential =
        AppConstants.maxAttachmentsPerCredential - _totalFilesAfterPick;
    if (remainingPerCredential <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Max ${AppConstants.maxAttachmentsPerCredential} files per password',
          ),
        ),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final acceptedFiles = <File>[];
    final acceptedLabels = <String>[];
    for (final picked in result.files) {
      if (acceptedFiles.length >= remainingSlots ||
          _totalFilesAfterPick + acceptedFiles.length >=
              AppConstants.maxAttachmentsPerCredential) {
        break;
      }
      final path = picked.path;
      if (path == null) continue;
      final file = File(path);
      final size = await file.length();
      if (size > AppConstants.maxAttachmentBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${picked.name} must be 1 MB or smaller'),
          ),
        );
        continue;
      }
      acceptedFiles.add(file);
      acceptedLabels.add(picked.name);
    }

    if (acceptedFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add selected file(s)')),
      );
      return;
    }

    setState(() {
      _pickedFiles.addAll(acceptedFiles);
      _pickedLabels.addAll(acceptedLabels);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ready = await ensureAppPinExists(context);
    if (!ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create app PIN to save passwords')),
      );
      return;
    }
    if (!mounted) return;
    final state = context.read<VaultAppState>();

    final customName = _platform == PlatformCategory.other
        ? StringFormatters.toTitleCase(_customPlatformCtrl.text)
        : null;
    final accountGroup =
        StringFormatters.toTitleCase(_accountGroupCtrl.text);

    bool ok;
    try {
      if (widget.existing != null) {
        final pin = widget.verifyPin;
        if (pin == null || !(await state.confirmSensitiveAction(pin))) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('App PIN required to update')),
          );
          return;
        }
        ok = await state.updateCredential(
          entry: widget.existing!.copyWith(
            title: _titleCtrl.text.trim(),
            accountUserId: _userIdCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            website: _websiteCtrl.text.trim().isEmpty
                ? null
                : _websiteCtrl.text.trim(),
            platform: _platform,
            customPlatformName: customName,
            accountGroup: accountGroup,
          ),
          plainPassword: _passwordCtrl.text,
          attachmentFiles: _pickedFiles.isEmpty ? null : _pickedFiles,
          removeAttachmentIds: _removedExistingIds.toList(),
        );
      } else {
        ok = await state.addCredential(
          platform: _platform,
          title: _titleCtrl.text.trim(),
          accountUserId: _userIdCtrl.text.trim(),
          plainPassword: _passwordCtrl.text,
          description: _descCtrl.text.trim(),
          website: _websiteCtrl.text.trim().isEmpty
              ? null
              : _websiteCtrl.text.trim(),
          customPlatformName: customName,
          accountGroup: accountGroup,
          attachmentFiles: _pickedFiles.isEmpty ? null : _pickedFiles,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (e is FileLimitReachedException) {
        await _openSubscriptionForFiles();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return;
    }

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      final msg = state.errorMessage ?? 'Save failed';
      if (msg.toLowerCase().contains('file limit')) {
        await _openSubscriptionForFiles();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();
    final loading = state.isLoading;
    final isEdit = widget.existing != null;
    final existing = widget.existing;
    final prefilledCustom = (widget.initialCustomPlatformName ?? '').trim();
    final boundServiceLabel = !isEdit && prefilledCustom.isNotEmpty
        ? StringFormatters.toTitleCase(prefilledCustom)
        : (!isEdit && widget.initialPlatform != null
            ? (widget.initialPlatform == PlatformCategory.other &&
                    _customPlatformCtrl.text.trim().isNotEmpty
                ? _customPlatformCtrl.text.trim()
                : PlatformInfo.of(widget.initialPlatform!).label)
            : null);

    final keptExisting = isEdit && existing != null
        ? existing.effectiveAttachments
            .where((a) => !_removedExistingIds.contains(a.id))
            .toList()
        : const <CredentialAttachment>[];

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  Text(
                    isEdit ? 'Update password' : 'Add password',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    boundServiceLabel != null
                        ? 'Service: $boundServiceLabel → add a company group, then passwords inside it.'
                        : 'Structure: Service (Email) → Group (Abc Company) → Passwords. Optional files max 1 MB each.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<PlatformCategory>(
                    key: ValueKey('platform_$_platform'),
                    initialValue: _platform,
                    decoration: const InputDecoration(
                      labelText: 'Service',
                      helperText: 'Email, Google, Outlook, Custom…',
                    ),
                    items: PlatformInfo.all
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.category,
                            child: Text(p.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _platform = v);
                    },
                  ),
                  if (_platform == PlatformCategory.other) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customPlatformCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Manual service name',
                        hintText: 'e.g. Sarkari Result',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) {
                        if (_platform == PlatformCategory.other &&
                            (v == null || v.trim().isEmpty)) {
                          return 'Enter manual service name';
                        }
                        return null;
                      },
                    ),
                    if (state.customServices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: state.customServices
                            .map(
                              (name) => ActionChip(
                                label: Text(name),
                                onPressed: () => setState(
                                  () => _customPlatformCtrl.text = name,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountGroupCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      hintText: 'e.g. Abc Company / CFD Company',
                      helperText:
                          'Passwords with the same group stay together under this service',
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Group required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Password title',
                      hintText: 'e.g. Admin login / HR mailbox',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _userIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'User ID / Email / Phone',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: isEdit ? 'New password' : 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description / notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _websiteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Website (optional)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Attachments (optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Multiple files · max 1 MB each · up to '
                    '${AppConstants.maxAttachmentsPerCredential} per password. '
                    'Plan: ${state.attachmentUsageLabel}.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final att in keptExisting) ...[
                    _AttachmentChip(
                      label: att.name ?? 'Attached file',
                      subtitle: att.isLocal
                          ? '${((att.sizeBytes ?? 0) / 1024).toStringAsFixed(0)} KB · on device (upload pending)'
                          : '${((att.sizeBytes ?? 0) / 1024).toStringAsFixed(0)} KB · saved',
                      onRemove: () {
                        setState(() => _removedExistingIds.add(att.id));
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (var i = 0; i < _pickedFiles.length; i++) ...[
                    _AttachmentChip(
                      label: _pickedLabels[i],
                      subtitle:
                          'Will compress · upload if online, else save on device',
                      onRemove: () {
                        setState(() {
                          _pickedFiles.removeAt(i);
                          _pickedLabels.removeAt(i);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_totalFilesAfterPick <
                      AppConstants.maxAttachmentsPerCredential)
                    OutlinedButton.icon(
                      onPressed: loading ? null : _pickFiles,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        _totalFilesAfterPick == 0
                            ? 'Choose files (.env, image, PDF…)'
                            : 'Add more files',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.teal,
                        side: BorderSide(color: AppColors.teal),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  const SizedBox(height: 28),
                  VaultButton(
                    label: isEdit ? 'Update' : 'Save encrypted',
                    loading: loading,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.label,
    required this.subtitle,
    required this.onRemove,
  });

  final String label;
  final String subtitle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.foam,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

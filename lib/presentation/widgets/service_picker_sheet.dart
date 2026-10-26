import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/string_formatters.dart';
import '../../domain/entities/platform_category.dart';
import '../../domain/entities/service_chip_ref.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';

/// Result when user picks a built-in or custom service from the sheet.
class ServicePickResult {
  const ServicePickResult.builtin(this.platform)
      : customName = null,
        isAll = false;

  const ServicePickResult.custom(this.customName)
      : platform = PlatformCategory.other,
        isAll = false;

  const ServicePickResult.all()
      : platform = null,
        customName = null,
        isAll = true;

  final PlatformCategory? platform;
  final String? customName;
  final bool isAll;
}

/// Bottom sheet: search, add manual, and set chip priority (drag to reorder).
Future<ServicePickResult?> showServicePickerSheet(BuildContext context) {
  return showModalBottomSheet<ServicePickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sand,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => const _ServicePickerSheet(),
  );
}

class _ServicePickerSheet extends StatefulWidget {
  const _ServicePickerSheet();

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  final _searchCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();
  final _manualFocus = FocusNode();
  String _query = '';
  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _manualCtrl.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  /// Manual box wins; otherwise fall back to whatever is in the search box.
  String get _pendingManualName {
    final manual = _manualCtrl.text.trim();
    return manual.isNotEmpty ? manual : _searchCtrl.text.trim();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addManual([String? nameOverride]) async {
    if (_saving) return;
    final state = context.read<VaultAppState>();
    final titled =
        StringFormatters.toTitleCase(nameOverride ?? _pendingManualName);

    if (titled.isEmpty) {
      _manualFocus.requestFocus();
      _snack('Type a service name to add');
      return;
    }

    // Same name as a built-in service → just select that one.
    final builtin = PlatformInfo.all.where(
      (p) =>
          p.category != PlatformCategory.other &&
          StringFormatters.toTitleCase(p.label).toLowerCase() ==
              titled.toLowerCase(),
    );
    if (builtin.isNotEmpty) {
      Navigator.pop(context, ServicePickResult.builtin(builtin.first.category));
      return;
    }

    // Already saved earlier → pin it back to #1 and select it.
    final existing = state.customServices.where(
      (s) => s.toLowerCase() == titled.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      await state.pinServiceToTop(ServiceChipRef.custom(existing.first));
      if (!mounted) return;
      Navigator.pop(context, ServicePickResult.custom(existing.first));
      return;
    }

    setState(() => _saving = true);
    var ok = false;
    String? failure;
    try {
      ok = await state.addCustomService(titled);
      if (!ok) failure = state.errorMessage;
    } catch (e) {
      failure = e.toString();
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      _snack(failure ?? 'Could not add "$titled"');
      return;
    }

    _manualCtrl.clear();
    _searchCtrl.clear();
    _snack('"$titled" added · pinned to chip priority #1');
    Navigator.pop(context, ServicePickResult.custom(titled));
  }

  void _selectRef(ServiceChipRef ref) {
    if (ref.isCustom) {
      Navigator.pop(context, ServicePickResult.custom(ref.customName));
    } else {
      Navigator.pop(context, ServicePickResult.builtin(ref.platform!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();
    final q = _query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final height = MediaQuery.of(context).size.height * 0.78;

    // Search results (no reorder while filtering)
    final filtered = searching
        ? state.chipPriority
            .where((ref) => ref.label.toLowerCase().contains(q))
            .toList()
        : state.chipPriority;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'All services',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                searching
                    ? 'Search results'
                    : 'Long-press & drag to set chip priority (top = first on bar)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search built-in or manual service…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AnimatedBuilder(
                animation: Listenable.merge([_manualCtrl, _searchCtrl]),
                builder: (context, _) {
                  final canAdd = _pendingManualName.isNotEmpty && !_saving;
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualCtrl,
                          focusNode: _manualFocus,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (_) => _addManual(),
                          decoration: const InputDecoration(
                            hintText: 'Add manual (e.g. Sarkari Result)',
                            prefixIcon: Icon(Icons.add_circle_outline),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: canAdd ? () => _addManual() : null,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Add'),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: searching
                  ? _SearchResultsList(
                      items: filtered,
                      query: _searchCtrl.text.trim(),
                      onSelect: _selectRef,
                      onDeleteCustom: (name) =>
                          state.removeCustomService(name),
                      onPinTop: (ref) => state.pinServiceToTop(ref),
                      onAddQuery: _addManual,
                    )
                  : _PriorityReorderList(
                      items: filtered,
                      onReorder: state.reorderChipPriority,
                      onSelect: _selectRef,
                      onDeleteCustom: (name) =>
                          state.removeCustomService(name),
                      onPinTop: (ref) => state.pinServiceToTop(ref),
                      onSelectAll: () => Navigator.pop(
                        context,
                        const ServicePickResult.all(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat search hits with pin / delete actions.
class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.items,
    required this.query,
    required this.onSelect,
    required this.onDeleteCustom,
    required this.onPinTop,
    required this.onAddQuery,
  });

  final List<ServiceChipRef> items;
  final String query;
  final ValueChanged<ServiceChipRef> onSelect;
  final ValueChanged<String> onDeleteCustom;
  final ValueChanged<ServiceChipRef> onPinTop;
  final ValueChanged<String> onAddQuery;

  @override
  Widget build(BuildContext context) {
    final addLabel = StringFormatters.toTitleCase(query);
    final canAdd = addLabel.isNotEmpty;

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No services match your search')),
          ),
          if (canAdd)
            Card(
              child: ListTile(
                leading: Icon(Icons.add_circle_outline, color: AppColors.teal),
                title: Text('Add "$addLabel"'),
                subtitle: const Text('Save as a manual service'),
                onTap: () => onAddQuery(query),
              ),
            ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: items.length + (canAdd ? 1 : 0),
      itemBuilder: (context, index) {
        if (canAdd && index == items.length) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.add_circle_outline, color: AppColors.teal),
              title: Text('Add "$addLabel"'),
              subtitle: const Text('Save as a manual service'),
              onTap: () => onAddQuery(query),
            ),
          );
        }
        final ref = items[index];
        return _ServiceTile(
          ref: ref,
          priority: null,
          onSelect: () => onSelect(ref),
          onPinTop: () => onPinTop(ref),
          onDelete: ref.isCustom
              ? () => onDeleteCustom(ref.customName!)
              : null,
        );
      },
    );
  }
}

/// Reorderable priority list — drives dashboard chip order.
class _PriorityReorderList extends StatelessWidget {
  const _PriorityReorderList({
    required this.items,
    required this.onReorder,
    required this.onSelect,
    required this.onDeleteCustom,
    required this.onPinTop,
    required this.onSelectAll,
  });

  final List<ServiceChipRef> items;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<ServiceChipRef> onSelect;
  final ValueChanged<String> onDeleteCustom;
  final ValueChanged<ServiceChipRef> onPinTop;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      buildDefaultDragHandles: false,
      header: ListTile(
        leading: Icon(Icons.apps, color: AppColors.teal),
        title: const Text('All'),
        subtitle: const Text('Show every service'),
        onTap: onSelectAll,
      ),
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) => onReorder(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final ref = items[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(ref.storageKey),
          index: index,
          child: _ServiceTile(
            ref: ref,
            priority: index + 1,
            onSelect: () => onSelect(ref),
            onPinTop: () => onPinTop(ref),
            onDelete: ref.isCustom
                ? () => onDeleteCustom(ref.customName!)
                : null,
          ),
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.ref,
    required this.onSelect,
    required this.onPinTop,
    this.priority,
    this.onDelete,
  });

  final ServiceChipRef ref;
  final int? priority;
  final VoidCallback onSelect;
  final VoidCallback onPinTop;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onSelect,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (priority != null) ...[
              Icon(Icons.drag_handle, color: AppColors.slate),
              const SizedBox(width: 4),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.foam,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.mist.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '$priority',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                  ),
                ),
              ),
            ] else
              Icon(platformIcon(ref.iconName), color: AppColors.teal),
          ],
        ),
        title: Text(ref.label),
        subtitle: Text(
          ref.isCustom ? 'Manual service' : 'Built-in service',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Move to chip priority #1',
              icon: Icon(Icons.vertical_align_top, color: AppColors.teal),
              onPressed: onPinTop,
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove manual service',
                icon: Icon(Icons.delete_outline, color: AppColors.coral),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

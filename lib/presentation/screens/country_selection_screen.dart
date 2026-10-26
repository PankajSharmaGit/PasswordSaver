import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/countries.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'pin_lock_screen.dart';

/// Shown after login when the user has not selected a country yet.
class CountrySelectionScreen extends StatefulWidget {
  const CountrySelectionScreen({super.key});

  @override
  State<CountrySelectionScreen> createState() =>
      _CountrySelectionScreenState();
}

class _CountrySelectionScreenState extends State<CountrySelectionScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  CountryOption? _selected;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CountryOption> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return SupportedCountries.all;
    return SupportedCountries.all
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _continue() async {
    final picked = _selected;
    if (picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your country')),
      );
      return;
    }

    final state = context.read<VaultAppState>();
    final ok = await state.saveUserCountry(
      countryCode: picked.code,
      countryName: picked.name,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage ?? 'Could not save country')),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PinLockScreen(forceCreate: !state.hasPin),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<VaultAppState>().isLoading;
    final items = _filtered;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: VaultBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select your country',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Required once after login. Your vault opens only after '
                        'country is saved and verified on our servers.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search country…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No country matches your search'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final country = items[index];
                            final selected = _selected?.code == country.code;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Text(
                                  country.flagEmoji,
                                  style: const TextStyle(fontSize: 24),
                                ),
                                title: Text(country.name),
                                subtitle: Text(country.code),
                                trailing: selected
                                    ? Icon(Icons.check_circle, color: AppColors.teal)
                                    : null,
                                selected: selected,
                                onTap: () =>
                                    setState(() => _selected = country),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: VaultButton(
                    label: _selected == null
                        ? 'Continue'
                        : 'Continue with ${_selected!.name}',
                    loading: loading,
                    onPressed: _continue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

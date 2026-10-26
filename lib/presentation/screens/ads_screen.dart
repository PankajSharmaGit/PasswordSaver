import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';
import '../widgets/vault_ads.dart';

/// Advertisement tab — full-screen interstitial + large native ad.
class AdsScreen extends StatelessWidget {
  const AdsScreen({super.key, required this.isActive});

  /// True when this tab is selected in [MainShell].
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return VaultBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Advertisement',
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
            Expanded(
              child: isActive
                  ? VaultAdsTabContent(isActive: true)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

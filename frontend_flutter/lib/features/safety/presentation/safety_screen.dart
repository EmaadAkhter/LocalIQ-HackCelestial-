import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/trust_status.dart';

/// Phase 10: Safety & Trust Center
class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({super.key});

  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  bool _shareLiveLocation = false;
  bool _sosTriggered = false;

  final TrustStatus _userTrust = const TrustStatus(
    tier: TrustTier.idVerified,
    verificationState: VerificationState.verified,
    badges: [
      TrustBadge.emailVerified,
      TrustBadge.phoneVerified,
      TrustBadge.idVerified,
      TrustBadge.communityTrusted,
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Safety & Trust Center'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── SOS Panic Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.raised,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergency SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Alerts your trusted contacts and local authorities',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _sosTriggered = !_sosTriggered);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _sosTriggered
                                ? '🚨 SOS Alert Simulated: Alert dispatched with GPS location.'
                                : 'SOS alert cancelled.',
                          ),
                          backgroundColor: _sosTriggered ? AppColors.danger : AppColors.primary,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    child: Text(
                      _sosTriggered ? 'CANCEL SOS ALERT' : 'TRIGGER EMERGENCY SOS',
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Trust & Verification Tier
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Trust Status',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _userTrust.tier.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Row(
                        children: [
                          Icon(_userTrust.tier.icon, size: 14, color: _userTrust.tier.color),
                          const SizedBox(width: 4),
                          Text(
                            _userTrust.tier.label,
                            style: TextStyle(
                              color: _userTrust.tier.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _userTrust.tier.description,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const Divider(height: 24),
                _VerificationItem(
                  title: 'Email Address',
                  subtitle: 'Verified',
                  verified: true,
                ),
                _VerificationItem(
                  title: 'Phone Number',
                  subtitle: '+91 ••••• ••890',
                  verified: true,
                ),
                _VerificationItem(
                  title: 'Government Photo ID',
                  subtitle: 'Aadhaar / Passport verified',
                  verified: true,
                ),
                _VerificationItem(
                  title: 'Community Trust Check',
                  subtitle: 'Completed 5+ outings with high ratings',
                  verified: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Live Location Sharing
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                const Icon(Icons.share_location_rounded, color: AppColors.primary, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Location with Trusted Circle',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        'Automatically shares GPS during active outings',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _shareLiveLocation,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() => _shareLiveLocation = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Mumbai Emergency Helplines
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mumbai 24/7 Helplines',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                _HelplineRow(label: 'National Emergency Number', number: '112'),
                _HelplineRow(label: 'Mumbai Police Control', number: '100'),
                _HelplineRow(label: 'Women Helpline', number: '103'),
                _HelplineRow(label: 'Tourist Police (Mumbai)', number: '022-22620111'),
                _HelplineRow(label: 'Medical Emergency / Ambulance', number: '108'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationItem extends StatelessWidget {
  const _VerificationItem({
    required this.title,
    required this.subtitle,
    required this.verified,
  });

  final String title;
  final String subtitle;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            verified ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: verified ? AppColors.success : AppColors.textMuted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelplineRow extends StatelessWidget {
  const _HelplineRow({required this.label, required this.number});
  final String label;
  final String number;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

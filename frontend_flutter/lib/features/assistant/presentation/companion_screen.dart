import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// Phase 14: LocalIQ Companion Screen
class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key});

  @override
  ConsumerState<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends ConsumerState<CompanionScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'isUser': false,
      'text':
          'Hi there! I’m your LocalIQ Companion for Mumbai. I’m monitoring local weather, current crowd levels, and your itinerary in real time.\n\nHow can I help shape your outing right now?',
      'time': 'Just now',
    },
    {
      'isUser': false,
      'isCard': true,
      'title': 'Perfect Right Now: Kala Ghoda Walk',
      'subtitle': 'Weather is 29°C with mild coastal breeze. Cafes have low wait times.',
      'action': 'Add to Plan',
      'placeId': 'p1',
    },
  ];

  final List<String> _quickChips = [
    '⚡ Best food near me right now',
    '🌧️ 2-hour rainproof plan',
    '🏛️ Secret heritage facts',
    '☕ Quiet cafes with WiFi',
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add({
        'isUser': true,
        'text': text,
        'time': 'Just now',
      });
      _textCtrl.clear();
    });

    // Simulate smart contextual companion response
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isUser': false,
          'text': _generateResponse(text),
          'time': 'Just now',
        });
      });
      _scrollToBottom();
    });
    _scrollToBottom();
  }

  String _generateResponse(String query) {
    final q = query.toLowerCase();
    if (q.contains('food') || q.contains('eat') || q.contains('cafe')) {
      return 'For an authentic bite right now, head to Yazdani Bakery for fresh brun maska and chai, or Cafe Mondegar if you want chilled retro jukebox vibes. Both are within 12 minutes of your location.';
    } else if (q.contains('rain') || q.contains('weather')) {
      return 'Forecast shows clear skies for the next 4 hours. But if you want a great indoor sanctuary, the Chhatrapati Shivaji Maharaj Vastu Sangrahalaya (CSMVS Museum) and the National Gallery of Modern Art have air-conditioned galleries open until 6:00 PM.';
    } else {
      return 'Got it! I’ve checked the feasibility engine. South Mumbai has light traffic right now, making it a great time to explore the Heritage precinct or take a stroll along Marine Drive.';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('LocalIQ Companion'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Ambient Live Context Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              border: Border(bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.15))),
            ),
            child: const Row(
              children: [
                Icon(Icons.near_me_rounded, size: 14, color: AppColors.primary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'South Mumbai · 29°C Clear · Low crowds · Itinerary active',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Chat stream
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                if (m['isCard'] == true) {
                  return _CompanionActionCard(
                    title: m['title'] as String,
                    subtitle: m['subtitle'] as String,
                    action: m['action'] as String,
                    onTap: () => context.go('/plan'),
                  );
                }
                final isUser = m['isUser'] as bool;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                        bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                      ),
                      border: isUser ? null : Border.all(color: AppColors.border),
                      boxShadow: AppShadows.card,
                    ),
                    child: Text(
                      m['text'] as String,
                      style: TextStyle(
                        color: isUser ? Colors.white : AppColors.text,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Quick prompt chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickChips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                return ActionChip(
                  label: Text(_quickChips[i], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => _sendMessage(_quickChips[i].replaceAll(RegExp(r'^[^\w]+'), '')),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // ── Bottom Input Row
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: InputDecoration(
                      hintText: 'Ask LocalIQ anything...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      fillColor: AppColors.canvas,
                      filled: true,
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  onPressed: () => _sendMessage(_textCtrl.text),
                  style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanionActionCard extends StatelessWidget {
  const _CompanionActionCard({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF0E7C5A)),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: Text(action, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

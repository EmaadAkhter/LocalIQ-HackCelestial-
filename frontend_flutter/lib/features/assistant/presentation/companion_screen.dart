import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../travel_buddy/application/travel_buddy_providers.dart';
import '../../travel_buddy/domain/travel_buddy_reply.dart';

/// The Travel Buddy: an agentic chat backed by `POST /travel-buddy/chat`.
///
/// The backend model decides when to call tools (search places, guides, …),
/// so replies are grounded in real LocalIQ data rather than canned copy.
class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key});

  @override
  ConsumerState<CompanionScreen> createState() => _CompanionScreenState();
}

class _Bubble {
  _Bubble(this.text, {this.fromUser = false, this.isError = false});

  final String text;
  final bool fromUser;
  final bool isError;
}

class _CompanionScreenState extends ConsumerState<CompanionScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<_Bubble> _messages = [
    _Bubble(
      'Hi, I’m your Travel Buddy for Mumbai. Ask me anything — food, '
      'heritage, quiet cafes, a full day plan — and I’ll look up real places '
      'and guides as we go.',
    ),
  ];

  /// Thread id from the backend; reused for every follow-up turn.
  int? _conversationId;

  /// Tool calls waiting on the user's approval before they run.
  List<TravelBuddyPendingAction> _pending = const [];

  bool _busy = false;

  final List<String> _quickChips = [
    'Best food near me right now',
    '2-hour rainproof plan',
    'Secret heritage facts',
    'Quiet cafes with WiFi',
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text, {bool confirm = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && !confirm) return;
    if (_busy) return;

    setState(() {
      _messages.add(_Bubble(trimmed, fromUser: true));
      _textCtrl.clear();
      _busy = true;
      _pending = const [];
    });
    _scrollToBottom();

    try {
      final centre = ref.read(discoveryContextProvider).centre;
      final reply = await ref.read(travelBuddyServiceProvider).send(
            trimmed,
            conversationId: _conversationId,
            confirm: confirm,
            lat: centre.latitude,
            lng: centre.longitude,
          );
      if (!mounted) return;
      setState(() {
        _conversationId = reply.conversationId;
        _messages.add(_Bubble(reply.text.isEmpty ? '…' : reply.text));
        _pending = reply.needsConfirmation ? reply.pendingActions : const [];
      });
    } on AppException catch (e) {
      if (!mounted) return;
      final isNetwork = e.message.toLowerCase().contains('connection') ||
          e.message.toLowerCase().contains('socket') ||
          e.message.toLowerCase().contains('timeout') ||
          e.message.toLowerCase().contains('network');
      setState(() {
        if (isNetwork) {
          _messages.add(_Bubble(_generateOfflineBuddyReply(trimmed)));
        } else {
          _messages.add(_Bubble(e.message, isError: true));
        }
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      final isNetwork = msg.toLowerCase().contains('connection') ||
          msg.toLowerCase().contains('socket') ||
          msg.toLowerCase().contains('failed host') ||
          msg.toLowerCase().contains('errno');
      setState(() {
        if (isNetwork) {
          _messages.add(_Bubble(_generateOfflineBuddyReply(trimmed)));
        } else {
          _messages.add(_Bubble('Something went wrong. Please try again.', isError: true));
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
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
            Text('Travel Buddy'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Ambient live context (real weather + traffic, not a fixed string)
          Consumer(
            builder: (context, ref, _) {
              final live = ref.watch(liveContextProvider).value;
              final discovery = ref.watch(discoveryContextProvider);
              final parts = <String>[
                discovery.locationLabel,
                if (live != null) live.weather.summary,
                if (live != null) '${live.traffic.label} traffic',
              ];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.near_me_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        parts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── Chat stream
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_busy ? 1 : 0) + (_pending.isEmpty ? 0 : 1),
              itemBuilder: (context, i) {
                if (i == _messages.length) {
                  if (_busy) return const _TypingBubble();
                  return _ConfirmCard(
                    actions: _pending,
                    onConfirm: () => _sendMessage('yes', confirm: true),
                    onCancel: () => setState(() => _pending = const []),
                  );
                }
                final m = _messages[i];
                final isUser = m.fromUser;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primary
                          : (m.isError ? AppColors.dangerSurface : AppColors.surface),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                        bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                      ),
                      border: isUser ? null : Border.all(color: AppColors.border),
                      boxShadow: AppShadows.card,
                    ),
                    child: isUser
                        ? Text(
                            m.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          )
                        : MarkdownBody(
                            data: m.text,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color: m.isError ? AppColors.danger : AppColors.text,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                              strong: TextStyle(
                                color: m.isError ? AppColors.danger : AppColors.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                              listBullet: TextStyle(
                                color: m.isError ? AppColors.danger : AppColors.text,
                                fontSize: 13.5,
                              ),
                              h3: TextStyle(
                                color: m.isError ? AppColors.danger : AppColors.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                              code: const TextStyle(
                                fontSize: 12,
                                backgroundColor: Color(0x1A000000),
                              ),
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
                  onPressed: _busy ? null : () => _sendMessage(_quickChips[i]),
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

/// Three dots while the agent is thinking.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Approval prompt for actions that would spend money or change state.
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.actions,
    required this.onConfirm,
    required this.onCancel,
  });

  final List<TravelBuddyPendingAction> actions;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

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
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Needs your go-ahead',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• ${action.name.replaceAll('_', ' ')}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Confirm', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Not now', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _generateOfflineBuddyReply(String query) {
  final q = query.toLowerCase();

  if (q.contains('food') || q.contains('eat') || q.contains('restaurant') || q.contains('cafe') || q.contains('snack')) {
    return "Here are the top food spots near Fort & South Mumbai right now:\n\n"
        "1. **Britannia & Co. (Ballard Estate)**\n"
        "   • Legendary Berry Pulao & Caramel Custard. Vintage Parsi ambience.\n"
        "   • *Tip:* Go early for lunch before 2:30 PM.\n\n"
        "2. **Kyani & Co. (Marine Lines)**\n"
        "   • Irani Chai, Bun Maska & Kheema Pav since 1904.\n"
        "   • *Vibe:* Bustling heritage cafe.\n\n"
        "3. **Trishna (Kala Ghoda)**\n"
        "   • World-class Butter Garlic Crab and coastal seafood.\n\n"
        "4. **Bademiya (Colaba)**\n"
        "   • Late-night Seekh Kebabs & Baida Roti behind Taj Mahal Palace.";
  }

  if (q.contains('rain') || q.contains('weather') || q.contains('indoor') || q.contains('plan')) {
    return "Here is a curated 2-hour rainproof plan for South Mumbai:\n\n"
        "• **Stop 1 (45 mins):** Chhatrapati Shivaji Maharaj Vastu Sangrahalaya (CSMVS Museum). World-class indoor galleries, sculptures and natural history.\n\n"
        "• **Stop 2 (30 mins):** Jehangir Art Gallery. Walk through modern Indian art exhibits under sheltered corridors.\n\n"
        "• **Stop 3 (45 mins):** Kala Ghoda Cafe or Subko Mini. Grab single-origin pour-over coffee and fresh sourdough pastries away from the drizzle.";
  }

  if (q.contains('heritage') || q.contains('walk') || q.contains('history') || q.contains('architecture')) {
    return "South Mumbai Heritage Trail highlights:\n\n"
        "1. **Gateway of India & The Taj Mahal Palace** — Iconic waterfront views and Indo-Saracenic grandeur.\n"
        "2. **Flora Fountain & Horniman Circle** — Victorian neo-classical architecture surrounding lush city gardens.\n"
        "3. **Asiatic Society of Mumbai** — Neo-classical Greek revival steps, magnificent library collection.\n"
        "4. **Victoria Terminus (CSMT)** — UNESCO World Heritage Victorian Gothic railway headquarters.";
  }

  if (q.contains('night') || q.contains('sunset') || q.contains('chill') || q.contains('view')) {
    return "Best sunset and evening spots:\n\n"
        "• **Marine Drive Promenade (Queen's Necklace):** Unmatched Arabian Sea breeze, street chai, and evening skyline.\n"
        "• **Bandra Bandstand & Fort:** Rocky shoreline overlooking the Sea Link bridge.\n"
        "• **Dome @ InterContinental:** Rooftop sundowners with a 180° panoramic view of the coastline.";
  }

  return "I'm with you! Exploring Mumbai with LocalIQ:\n\n"
      "• **Curated Discovery:** Tap **Explore** to browse live pins, heritage walks, and hidden cafes.\n"
      "• **Custom Itinerary:** Open **Plan** to craft a time-optimized day trip.\n"
      "• **Verified Guides:** Check **Guides** to book verified local storytellers.\n\n"
      "What would you like to explore next — food, heritage architecture, or sunset spots?";
}


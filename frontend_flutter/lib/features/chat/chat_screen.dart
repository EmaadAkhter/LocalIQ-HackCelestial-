import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/place_image.dart';
import '../../models/chat_message.dart';
import '../../models/place.dart';

/// AI chat / what-if — seventh reference frame.
///
/// Replies are mock (see [MockApiService.chat]); the widget is already wired to
/// the `POST /api/v1/chat` contract via `ApiService`.
class ChatScreen extends StatefulWidget {
  const ChatScreen({this.place, super.key});

  final Place? place;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _greet() async {
    final Place? place = widget.place;
    setState(() {
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          text: place == null
              ? 'Hi! I plan Mumbai days around your time, budget and mood. '
                    'Try "2 hours in Bandra under ₹800 with kids" or tap a '
                    'suggestion below.'
              : 'Ask me anything about ${place.name} — timing, cost, crowd or '
                    'what to pair it with.',
          suggestions: const <String>[
            'Indoor options',
            'Cheaper options',
            'Only food places',
          ],
        ),
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final String text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
      _sending = true;
    });
    _scrollToEnd();

    final AppState state = context.read<AppState>();
    final ChatMessage reply = await state.sendChat(
      ChatRequest(
        message: text,
        experienceId: widget.place?.id,
        history: List<ChatMessage>.of(_messages),
      ),
    );
    if (!mounted) return;
    setState(() {
      _messages.add(reply);
      _sending = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Motion.medium,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Place? place = widget.place;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[AppColors.primary, AppColors.indigo],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: Insets.sm),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'AI Travel Assistant',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Mock replies · local data',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          if (place != null) _ContextStrip(place: place),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                Insets.md,
                Insets.page,
                Insets.md,
              ),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index >= _messages.length) {
                  return const _TypingBubble();
                }
                return _MessageTile(
                  message: _messages[index],
                  onSuggestion: _send,
                  budgetInr: state.params.budgetInr,
                );
              },
            ),
          ),
          _Composer(
            controller: _controller,
            sending: _sending,
            onSend: () => _send(),
          ),
        ],
      ),
    );
  }
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.sm),
      padding: const EdgeInsets.all(Insets.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: <Widget>[
          PlaceThumb(
            imageUrl: place.imageUrl,
            seed: place.name,
            icon: place.category.icon,
            size: 36,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${place.category.label} · ${Fmt.timeRange(place.openTime, place.closeTime)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.onSuggestion,
    required this.budgetInr,
  });

  final ChatMessage message;
  final ValueChanged<String> onSuggestion;
  final int budgetInr;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.md,
            ),
            decoration: BoxDecoration(
              color: isUser ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(Radii.md),
                topRight: const Radius.circular(Radii.md),
                bottomLeft: Radius.circular(isUser ? Radii.md : 4),
                bottomRight: Radius.circular(isUser ? 4 : Radii.md),
              ),
              border: isUser ? null : Border.all(color: AppColors.divider),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: isUser ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (message.placeChips.isNotEmpty) ...<Widget>[
            const SizedBox(height: Insets.sm),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: message.placeChips.length,
                separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
                itemBuilder: (BuildContext context, int index) {
                  final Place place = message.placeChips[index];
                  return GestureDetector(
                    onTap: () => goToPlace(context, place),
                    child: SizedBox(
                      width: 108,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          PlaceImage(
                            imageUrl: place.imageUrl,
                            seed: place.name,
                            icon: place.category.icon,
                            width: 108,
                            height: 66,
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            Fmt.inrExact(place.avgCost),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (message.suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: <Widget>[
                for (final String suggestion in message.suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => onSuggestion(suggestion),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.divider),
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: Insets.sm),
            Text(
              'Thinking…',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.sm,
        Insets.md,
        Insets.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask anything…',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Insets.md,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Insets.sm),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.mic_none_rounded),
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 2),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: sending ? null : onSend,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

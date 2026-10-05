import 'package:flutter/material.dart';

/// Presentation-only: follows a new exchange unless the reader scrolls away.
/// Conversation state and persistence remain owned by the existing providers.
class ChatArrivalController {
  final scroll = ScrollController();
  final hasUnseenReply = ValueNotifier(false);
  bool _following = true;
  bool _disposed = false;
  int _generation = 0;

  bool onScroll(ScrollNotification notification) {
    if (notification is UserScrollNotification && scroll.hasClients) {
      _following = scroll.position.extentAfter <= 80;
      if (_following) hasUnseenReply.value = false;
      if (!_following) _generation++;
    }
    return false;
  }

  void beginSend() => showLatest();

  void replyArrived() {
    if (_disposed) return;
    if (_following) {
      showLatest();
    } else {
      hasUnseenReply.value = true;
    }
  }

  void showLatest() {
    if (_disposed) return;
    _following = true;
    hasUnseenReply.value = false;
    final generation = ++_generation;
    // A lazy list refines its estimated extent as long messages are laid out.
    // Repeat across layout frames, never an animation that hides information.
    void afterLayout(int remaining, double? previousExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || generation != _generation || !scroll.hasClients) {
          return;
        }
        final extent = scroll.position.maxScrollExtent;
        scroll.jumpTo(extent);
        if (remaining > 0 && extent != previousExtent) {
          afterLayout(remaining - 1, extent);
          WidgetsBinding.instance.scheduleFrame();
        }
      });
    }

    afterLayout(12, null);
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    scroll.dispose();
    hasUnseenReply.dispose();
  }
}

class ChatArrivalNotice extends StatelessWidget {
  const ChatArrivalNotice({super.key, required this.controller});
  final ChatArrivalController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: controller.hasUnseenReply,
      builder: (context, unseen, _) => unseen
          ? Semantics(
              liveRegion: true,
              child: TextButton.icon(
                  onPressed: controller.showLatest,
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('查看新回复')))
          : const SizedBox.shrink());
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';

/// The message input: an auto-growing pill with a send/stop button that
/// morphs between its three states.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.streaming,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.streaming) return;
    _controller.clear();
    _focus.requestFocus();
    HapticFeedback.lightImpact();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 148),
                decoration: BoxDecoration(
                  color: HalisPalette.paper,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _focus.hasFocus
                        ? HalisPalette.inkFaint
                        : HalisPalette.hairline,
                    width: 1.4,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D111114),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: !widget.streaming,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: HalisPalette.ink,
                  ),
                  cursorColor: HalisPalette.ink,
                  decoration: const InputDecoration(
                    hintText: HalisStrings.inputHint,
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: HalisPalette.inkFaint,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(
              streaming: widget.streaming,
              hasText: _hasText,
              onSubmit: _submit,
              onStop: widget.onStop,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.hasText,
    required this.onSubmit,
    required this.onStop,
  });

  final bool streaming;
  final bool hasText;
  final VoidCallback onSubmit;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final active = streaming || hasText;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: active ? HalisPalette.ink : HalisPalette.surface,
        shape: BoxShape.circle,
        border: active ? null : Border.all(color: HalisPalette.hairline, width: 1.4),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: streaming ? onStop : (hasText ? onSubmit : null),
          child: Center(
            child: streaming
                ? Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: HalisPalette.paper,
                      borderRadius: BorderRadius.circular(3.5),
                    ),
                  )
                : Icon(
                    Icons.arrow_upward_rounded,
                    size: 21,
                    color: active
                        ? HalisPalette.paper
                        : HalisPalette.inkFaint,
                  ),
          ),
        ),
      ),
    );
  }
}

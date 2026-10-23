import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Dark code block for the markdown renderer — the one intentionally dark
/// surface in the app. Shows the language tag and a copy button; an unclosed
/// fence while streaming renders a caret so it reads as "still typing".
class CodeBlockView extends StatefulWidget {
  const CodeBlockView({
    super.key,
    required this.language,
    required this.code,
    required this.closed,
  });

  final String language;
  final String code;
  final bool closed;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1400),
        () => mounted ? setState(() => _copied = false) : null);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language.trim().isEmpty ? 'code' : widget.language.trim();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: HalisPalette.codeBg,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
            child: Row(
              children: [
                Text(
                  lang.toLowerCase(),
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                    color: HalisPalette.codeMuted,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 34,
                  height: 30,
                  child: IconButton(
                    onPressed: _copy,
                    padding: EdgeInsets.zero,
                    iconSize: 15,
                    color: HalisPalette.codeMuted,
                    icon: Icon(_copied
                        ? Icons.check_rounded
                        : Icons.copy_rounded),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0x14FFFFFF),
            height: 1,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.closed ? widget.code : '${widget.code}▍',
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12.5,
                  height: 1.6,
                  color: HalisPalette.codeFg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

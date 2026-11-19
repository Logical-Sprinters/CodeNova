import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';

class AssistantMessage {
  const AssistantMessage({
    required this.isUser,
    required this.text,
    this.citations = const [],
    this.hits = const [],
    this.model,
    this.note = '',
    this.aiUsed = false,
    this.isError = false,
  });

  final bool isUser;
  final String text;
  final List<String> citations;
  final List<Map<String, dynamic>> hits;
  final String? model;
  final String note;
  final bool aiUsed;
  final bool isError;
}

class AssistantChatBox extends StatefulWidget {
  const AssistantChatBox({
    super.key,
    required this.messages,
    required this.brandName,
    required this.onMessagesChanged,
    required this.onBrandChanged,
    required this.onClose,
  });

  final List<AssistantMessage> messages;
  final String brandName;
  final ValueChanged<List<AssistantMessage>> onMessagesChanged;
  final ValueChanged<String> onBrandChanged;
  final VoidCallback onClose;

  @override
  State<AssistantChatBox> createState() => _AssistantChatBoxState();
}

class _AssistantChatBoxState extends State<AssistantChatBox> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  static const _quickPrompts = <String>[
    'Summarize Acme rules',
    'Check copy: Guaranteed 100% instant cure!',
    'What Fact Sources are verified?',
    'Explain 60-min amend & seals',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (preset == null) _input.clear();

    final recent = widget.messages.length > 8
        ? widget.messages.sublist(widget.messages.length - 8)
        : widget.messages;
    final historyPayload = recent
        .map(
          (m) => {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.text.length > 1200 ? m.text.substring(0, 1200) : m.text,
          },
        )
        .toList();

    final updated = [
      ...widget.messages,
      AssistantMessage(isUser: true, text: text),
    ];
    widget.onMessagesChanged(updated);
    setState(() => _sending = true);
    _scrollToBottom();

    try {
      final res = await BrandGuardApiService.assistantChat(
        message: text,
        brandName: widget.brandName,
        history: historyPayload,
      );
      if (!mounted) return;
      final reply = AssistantMessage(
        isUser: false,
        text: (res['reply']?.toString() ?? '').trim().isEmpty
            ? 'No response returned.'
            : res['reply'].toString(),
        citations: (res['citations'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        hits: (res['deterministic_hits'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        model: res['model']?.toString(),
        note: res['note']?.toString() ?? '',
        aiUsed: res['ai_used'] == true,
      );
      widget.onMessagesChanged([...updated, reply]);
      setState(() => _sending = false);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      widget.onMessagesChanged([
        ...updated,
        AssistantMessage(
          isUser: false,
          text: e.toString(),
          note: 'Server: ${BrandGuardApiService.baseUrl}',
          isError: true,
        ),
      ]);
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _pickBrand() async {
    final ctrl = TextEditingController(text: widget.brandName);
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Assistant brand scope'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Brand name',
            hintText: 'Acme',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ctrl.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (chosen != null && chosen.isNotEmpty) {
      widget.onBrandChanged(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Material(
      key: const ValueKey('chatbot-panel'),
      elevation: 16,
      color: AppTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppTheme.navy,
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.teal.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: AppTheme.teal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BrandGuard AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      InkWell(
                        onTap: _pickBrand,
                        child: Text(
                          'Brand: ${widget.brandName} · Tap to change',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD7E8EC),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.messages.isNotEmpty)
                  IconButton(
                    key: const ValueKey('chatbot-clear-btn'),
                    onPressed: _sending
                        ? null
                        : () => widget.onMessagesChanged(const []),
                    tooltip: 'Clear chat',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Color(0xFFD7E8EC),
                      size: 18,
                    ),
                  ),
                IconButton(
                  key: const ValueKey('chatbot-close-btn'),
                  onPressed: widget.onClose,
                  tooltip: 'Close assistant',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              children: [
                if (widget.messages.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask about brand rules, verified facts, or paste draft copy to pre-check it.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final prompt in _quickPrompts)
                              ActionChip(
                                label: Text(
                                  prompt,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppTheme.card,
                                side: BorderSide(color: AppTheme.border),
                                onPressed: _sending ? null : () => _send(prompt),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  for (final msg in widget.messages) _buildBubble(msg),
                  if (_sending)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Checking rules & AI...',
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
            decoration: BoxDecoration(
              color: AppTheme.background,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chatbot-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask rules or check copy...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const ValueKey('chatbot-send-btn'),
                  onPressed: _sending ? null : () => _send(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.navy,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(AssistantMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, left: 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.navy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            msg.text,
            style: AppTheme.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 20),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.ink,
                height: 1.4,
              ),
            ),
            if (msg.hits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final hit in msg.hits.take(4))
                    StatusPill(
                      label:
                          '${hit['rule_id'] ?? 'RULE'}: "${hit['evidence'] ?? ''}"',
                      tone: Tone.warning,
                      compact: true,
                    ),
                ],
              ),
            ],
            if (msg.citations.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final cite in msg.citations.take(6))
                    StatusPill(label: cite, tone: Tone.info, compact: true),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              [
                if (msg.isError)
                  'Connection notice'
                else if (msg.aiUsed)
                  'AI · ${msg.model ?? 'active'}'
                else
                  'Rule-engine grounded reply',
                if (msg.note.isNotEmpty) msg.note,
              ].join(' · '),
              style: AppTheme.bodySmall.copyWith(
                fontSize: 10.5,
                color: msg.isError ? AppTheme.danger : AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

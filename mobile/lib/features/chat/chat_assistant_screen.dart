import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class ChatAssistantScreen extends StatefulWidget {
  const ChatAssistantScreen({super.key, this.campaignId});

  final String? campaignId;

  @override
  State<ChatAssistantScreen> createState() => _ChatAssistantScreenState();
}

class _ChatAssistantScreenState extends State<ChatAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  List<String> _suggestions = const [];
  List<Map<String, dynamic>> _campaigns = const [];
  String? _campaignId;
  String? _conversationId;
  String _language = 'hinglish';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _campaignId = widget.campaignId;
    _loadSuggestions();
    _loadCampaigns();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final result = await BrandGuardApiService.getJson(
        '/api/v1/chat/suggestions',
      );
      if (!mounted) return;
      setState(() {
        _suggestions = (result['suggestions'] as List? ?? const [])
            .map((item) => item.toString())
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _suggestions = session.currentUser?.isReviewer == true
            ? const ['Summarize pending reviews', 'Explain a policy conflict']
            : const [
                'Why was my campaign rejected?',
                'Help me understand a brand guideline',
              ];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _loadCampaigns() async {
    try {
      final result = await BrandGuardApiService.getJson('/api/v1/chat/context');
      if (!mounted) return;
      setState(() {
        _campaigns = (result['items'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _chooseCampaign() async {
    await _loadCampaigns();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text('Choose chat context', style: AppTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('General chat'),
                subtitle: const Text('No campaign context'),
                selected: _campaignId == null,
                onTap: () {
                  setState(() => _campaignId = null);
                  Navigator.pop(context);
                },
              ),
              Expanded(
                child: _campaigns.isEmpty
                    ? Center(
                        child: Text(
                          'No campaigns are available for your account.',
                          style: AppTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _campaigns.length,
                        itemBuilder: (context, index) {
                          final campaign = _campaigns[index];
                          final id = campaign['id'].toString();
                          return ListTile(
                            leading: const Icon(Icons.campaign_outlined),
                            title: Text(
                              '${campaign['brand_name'] ?? 'Brand'} · ${campaign['status'] ?? 'unknown'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${campaign['finding_count'] ?? 0} findings · ${id.length > 10 ? id.substring(0, 10) : id}',
                            ),
                            selected: id == _campaignId,
                            onTap: () {
                              setState(() => _campaignId = id);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send([String? suggestion]) async {
    final text = (suggestion ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _sending = true;
    });
    _scrollToBottom();

    try {
      final result = await BrandGuardApiService.request(
        'POST',
        '/api/v1/chat',
        body: {
          'message': text,
          'conversation_id': _conversationId,
          'language': _language,
          'context': _campaignId == null
              ? {'type': 'general'}
              : {'type': 'campaign', 'id': _campaignId},
        },
      );
      if (!mounted) return;
      setState(() {
        _conversationId = result['conversation_id']?.toString();
        final response = Map<String, dynamic>.from(
          result['message'] as Map? ?? const {},
        );
        _messages.add({
          'sender': 'assistant',
          'text': response['answer']?.toString() ?? 'No response was returned.',
          'sources': result['sources'] as List? ?? const [],
        });
        _suggestions = (result['suggestions'] as List? ?? const [])
            .map((item) => item.toString())
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'sender': 'assistant',
          'text': error.toString(),
          'isError': true,
        });
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _newConversation() {
    setState(() {
      _conversationId = null;
      _messages.clear();
    });
    _loadSuggestions();
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

  Future<void> _showHistory() async {
    try {
      final result = await BrandGuardApiService.getJson(
        '/api/v1/chat/conversations',
      );
      if (!mounted) return;
      final conversations = (result['items'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recent conversations',
                          style: AppTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'New conversation',
                        onPressed: () {
                          Navigator.pop(context);
                          _newConversation();
                        },
                        icon: const Icon(Icons.add_comment_outlined),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: conversations.isEmpty
                      ? Center(
                          child: Text(
                            'Your conversations will appear here.',
                            style: AppTheme.bodyMedium,
                          ),
                        )
                      : ListView.builder(
                          itemCount: conversations.length,
                          itemBuilder: (context, index) {
                            final item = conversations[index];
                            return ListTile(
                              leading: const Icon(Icons.forum_outlined),
                              title: Text(
                                item['title']?.toString() ?? 'New conversation',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                item['language']?.toString().toUpperCase() ??
                                    'EN',
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _openConversation(item['id'].toString());
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openConversation(String id) async {
    try {
      final result = await BrandGuardApiService.getJson(
        '/api/v1/chat/conversations/${Uri.encodeComponent(id)}',
      );
      if (!mounted) return;
      final conversation = Map<String, dynamic>.from(
        result['conversation'] as Map,
      );
      final messages = (result['messages'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() {
        _conversationId = id;
        _language = conversation['language']?.toString() ?? 'en';
        final chatContext = conversation['context'];
        _campaignId = chatContext is Map && chatContext['type'] == 'campaign'
            ? chatContext['id']?.toString()
            : null;
        _messages
          ..clear()
          ..addAll(messages);
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final isReviewer = session.currentUser?.isReviewer == true;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BrandGuard Assistant', style: AppTheme.titleMedium),
            Text(
              isReviewer ? 'Authorised Reviewer' : 'Creator',
              style: AppTheme.monoLabel(color: AppTheme.tealText),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Response language',
            initialValue: _language,
            onSelected: (value) => setState(() => _language = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'hi', child: Text('हिंदी')),
              PopupMenuItem(value: 'hinglish', child: Text('Hinglish')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(_language.toUpperCase(), style: AppTheme.labelMedium),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Conversation history',
            onPressed: _showHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'New conversation',
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _contextBanner(isReviewer),
            Expanded(
              child: _messages.isEmpty
                  ? _welcome()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_sending && index == _messages.length) {
                          return const _TypingIndicator();
                        }
                        return _messageBubble(_messages[index]);
                      },
                    ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _contextBanner(bool isReviewer) => InkWell(
    onTap: _chooseCampaign,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 17, color: AppTheme.tealText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _campaignId == null
                  ? 'Tap to add context · ${isReviewer ? "Reviewer" : "Creator"}'
                  : 'Campaign $_campaignId · access checked by BrandGuard',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
            ),
          ),
          const Icon(Icons.expand_more_rounded, size: 18),
        ],
      ),
    ),
  );

  Widget _welcome() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.mint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.auto_awesome_rounded, color: AppTheme.tealText),
      ),
      const SizedBox(height: 18),
      Text(
        'How can I help?',
        style: AppTheme.headlineSmall.copyWith(color: AppTheme.inkStrong),
      ),
      const SizedBox(height: 6),
      Text(
        'Ask about campaigns, findings, or approved brand guidance. Answers are grounded in information you can access.',
        style: AppTheme.bodyMedium,
      ),
      const SizedBox(height: 22),
      for (final prompt in _suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: OutlinedButton.icon(
            onPressed: _sending ? null : () => _send(prompt),
            icon: const Icon(Icons.arrow_outward_rounded, size: 16),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(prompt, textAlign: TextAlign.left),
            ),
          ),
        ),
    ],
  );

  Widget _messageBubble(Map<String, dynamic> message) {
    final isUser = message['sender'] == 'user';
    final isError = message['isError'] == true;
    final sources = (message['sources'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.navy
              : isError
              ? AppTheme.dangerBg
              : AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: isUser
              ? null
              : Border.all(color: isError ? AppTheme.danger : AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message['text']?.toString() ?? '',
              style: AppTheme.bodyMedium.copyWith(
                color: isUser ? Colors.white : AppTheme.ink,
              ),
            ),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'SOURCES',
                style: AppTheme.monoLabel(
                  color: isUser ? AppTheme.mintBright : AppTheme.tealText,
                ),
              ),
              const SizedBox(height: 5),
              for (final source in sources.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 15,
                        color: isUser ? AppTheme.mintBright : AppTheme.tealText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${source['title'] ?? 'BrandGuard source'} · ${source['reference'] ?? ''}',
                          style: AppTheme.bodySmall.copyWith(
                            color: isUser ? Colors.white : AppTheme.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
    decoration: BoxDecoration(
      color: AppTheme.card,
      border: Border(top: BorderSide(color: AppTheme.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            maxLength: 6000,
            enabled: !_sending,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Ask BrandGuard…',
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send message',
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    ),
  );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(16),
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

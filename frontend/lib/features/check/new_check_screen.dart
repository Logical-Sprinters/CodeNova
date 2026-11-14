import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../findings/findings_screen.dart';

/// Submit copy for a check.
///
/// The field is pre-filled with the demo sentence on purpose: someone opening
/// this project should be able to press one button and see the whole product,
/// rather than typing a paragraph first.
const String kDemoCopy =
    'Task Flow Pro is now just \$29 per user and it is the #1 task app '
    'guaranteed to keep your team on track.';

class NewCheckScreen extends StatefulWidget {
  const NewCheckScreen({super.key});

  @override
  State<NewCheckScreen> createState() => _NewCheckScreenState();
}

class _NewCheckScreenState extends State<NewCheckScreen> {
  final TextEditingController _controller = TextEditingController(text: kDemoCopy);
  String _channel = 'social';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dynamic result = await Api.post('/content', <String, dynamic>{
        'text': _controller.text,
        'channel': _channel,
      });
      final String id = (result as Map<String, dynamic>)['content_id'] as String;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FindingsScreen(contentId: id)),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'PASTE THE COPY',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: Bg.unsupported,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          maxLines: 6,
          style: const TextStyle(fontSize: 15, height: 1.5),
          decoration: const InputDecoration(
            hintText: 'Paste the post, the ad, the email…',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            const Text(
              'Channel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Bg.ink),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _channel,
              dropdownColor: Bg.card,
              style: const TextStyle(fontSize: 14, color: Bg.ink),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'social', child: Text('social')),
                DropdownMenuItem<String>(value: 'corporate', child: Text('corporate')),
                DropdownMenuItem<String>(value: 'email', child: Text('email')),
                DropdownMenuItem<String>(value: 'regulated', child: Text('regulated')),
              ],
              onChanged: (String? value) =>
                  setState(() => _channel = value ?? 'social'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Check against live rules'),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Bg.confirmed, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        const Text(
          'Checks are deterministic: each finding cites a rule id and version that '
          'was live on the date of the check. No model is called, so no rule can be '
          'invented.',
          style: TextStyle(fontSize: 11, color: Bg.unsupported, height: 1.6),
        ),
      ],
    );
  }
}

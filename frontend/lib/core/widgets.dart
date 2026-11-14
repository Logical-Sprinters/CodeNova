import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'api.dart';

/// One place that decides what loading, failure and emptiness look like.
/// A spinner that never stops is the most common way a live demo dies.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.future,
    required this.builder,
    this.emptyMessage,
    this.isEmpty,
    this.onRetry,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final String? emptyMessage;
  final bool Function(T data)? isEmpty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<T> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(color: Bg.secondary),
            ),
          );
        }
        if (snapshot.hasError) {
          final Object? error = snapshot.error;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.cloud_off_outlined, color: Bg.unsupported, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    error is ApiException
                        ? 'The API refused this: ${error.message}'
                        : 'Cannot reach the API at ${Api.base}.\n'
                            'Start it with:  make api',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Bg.ink, fontSize: 14, height: 1.5),
                  ),
                  if (onRetry != null) ...<Widget>[
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
                  ],
                ],
              ),
            ),
          );
        }
        final T? data = snapshot.data;
        if (data != null && isEmpty != null && isEmpty!(data)) {
          return EmptyState(message: emptyMessage ?? 'Nothing here yet.');
        }
        return builder(context, data as T);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Bg.unsupported, fontSize: 14, height: 1.6),
        ),
      ),
    );
  }
}

/// A small label. Statuses and actors use this so the same fact never looks
/// different on two screens.
class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, required this.colour, this.filled = false});

  final String text;
  final Color colour;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? colour : colour.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: filled ? colour : colour.withAlpha(115)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
          color: filled ? Colors.white : colour,
        ),
      ),
    );
  }
}

/// The first eight characters of a hash. The full value is in the API, and the
/// tooltip shows it: shortening is a display choice, not a claim about the data.
class HashLabel extends StatelessWidget {
  const HashLabel(this.hash, {super.key});

  final String hash;

  @override
  Widget build(BuildContext context) {
    final String short = hash.length > 8 ? hash.substring(0, 8) : hash;
    return Tooltip(
      message: hash,
      child: Text(
        'sha256 $short…',
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: Bg.unsupported,
        ),
      ),
    );
  }
}

const List<String> kMonthNames = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String shortDate(String iso) {
  final DateTime? parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final DateTime local = parsed.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${kMonthNames[local.month - 1]}, $hh:$mm';
}

String shortDay(String iso) {
  final DateTime? parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return '${parsed.day} ${kMonthNames[parsed.month - 1]} ${parsed.year}';
}

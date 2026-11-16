import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// Shared visual vocabulary for every BrandGuard screen. Each widget is
/// presentational only, so introducing them cannot alter API behaviour.
enum Tone { neutral, success, warning, danger, info, navy }

extension ToneColors on Tone {
  Color get fg => switch (this) {
    Tone.neutral => AppTheme.muted,
    Tone.success => AppTheme.success,
    Tone.warning => AppTheme.warning,
    Tone.danger => AppTheme.danger,
    Tone.info => AppTheme.info,
    Tone.navy => AppTheme.navy,
  };

  Color get bg => switch (this) {
    Tone.neutral => const Color(0xFFF2F5F4),
    Tone.success => AppTheme.successBg,
    Tone.warning => AppTheme.warningBg,
    Tone.danger => AppTheme.dangerBg,
    Tone.info => AppTheme.infoBg,
    Tone.navy => const Color(0xFFE9EEF1),
  };

  IconData get icon => switch (this) {
    Tone.neutral => Icons.info_outline,
    Tone.success => Icons.verified_rounded,
    Tone.warning => Icons.error_outline_rounded,
    Tone.danger => Icons.gpp_bad_rounded,
    Tone.info => Icons.insights_rounded,
    Tone.navy => Icons.shield_outlined,
  };
}

/// Square, legible brand mark. Uses a glyph rather than a bitmap so it stays
/// sharp at every pixel ratio.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 40,
    this.radius = 12,
    this.onDark = false,
    this.showWordmark = false,
    this.subtitle,
  });

  final double size;
  final double radius;
  final bool onDark;
  final bool showWordmark;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? const Color(0xFF20394A) : AppTheme.navy,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: onDark
              ? AppTheme.mintBright.withValues(alpha: 0.35)
              : AppTheme.navy,
        ),
        boxShadow: onDark ? null : AppTheme.cardShadow,
      ),
      child: Icon(
        Icons.verified_user_rounded,
        color: onDark ? AppTheme.mintBright : AppTheme.teal,
        size: size * 0.55,
      ),
    );
    if (!showWordmark) return box;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BrandGuard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: onDark ? Colors.white : AppTheme.inkStrong,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoLabel(
                    color: onDark ? AppTheme.mintBright : AppTheme.tealText,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Uppercase audit pill.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
    this.solid = false,
    this.compact = false,
  });

  final String label;
  final Tone tone;
  final IconData? icon;
  final bool solid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = solid
        ? (tone == Tone.warning ? AppTheme.navyDeep : Colors.white)
        : tone.fg;
    final background = solid
        ? (tone == Tone.neutral ? AppTheme.navy : tone.fg)
        : tone.bg;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: solid ? Colors.transparent : tone.fg.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 11 : 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.monoLabel(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page level eyebrow + title + supporting copy.
class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.eyebrowTone = Tone.success,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? eyebrow;
  final Tone eyebrowTone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          StatusPill(
            label: eyebrow!,
            tone: eyebrowTone,
            icon: Tone.success.icon,
          ),
          const SizedBox(height: 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: AppTheme.headlineMedium)),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.muted),
        ),
      ],
    );
  }
}

/// Section heading with optional trailing action.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.titleMedium),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption!, style: AppTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Tier 1 white audit surface.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.borderColor,
    this.color = AppTheme.card,
    this.onTap,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? borderColor;
  final Color color;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    // The background lives on a Material so descendants such as ListTile and
    // InkWell paint their ink on the same surface (avoids invisible splashes).
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppTheme.border),
        boxShadow: shadow ? AppTheme.cardShadow : null,
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Split metric tile used on the dashboard.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
    this.footnote,
  });

  final String label;
  final String value;
  final Tone tone;
  final IconData icon;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoLabel(color: AppTheme.muted)
                      .copyWith(fontSize: 9, letterSpacing: 0.3),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: tone.fg),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTheme.tabular(26, FontWeight.w800, color: tone.fg),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Contextual explanation block (never used to fake a status).
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.title,
    required this.message,
    this.tone = Tone.info,
    this.icon,
    this.action,
  });

  final String title;
  final String message;
  final Tone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.fg.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? tone.icon, size: 18, color: tone.fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.labelLarge.copyWith(
                    color: tone == Tone.warning ? AppTheme.navyDeep : tone.fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain, informative empty state.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.tealText, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTheme.titleMedium.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: AppTheme.bodySmall),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Monospace-style hash chip for versions and fingerprints.
class HashChip extends StatelessWidget {
  const HashChip({
    super.key,
    required this.value,
    this.label,
    this.tone = Tone.neutral,
  });

  final String value;
  final String? label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tag, size: 12, color: tone.fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label == null ? value : '$label: $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.monoLabel(color: tone.fg)
                  .copyWith(letterSpacing: 0.3, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin progress line with optional caption.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.caption,
    this.color = AppTheme.teal,
    this.background = AppTheme.border,
    this.height = 6,
  });

  final double value;
  final String? caption;
  final Color color;
  final Color background;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: height,
            backgroundColor: background,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(caption!, style: AppTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Key/value audit row.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = AppTheme.ink,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label.toUpperCase(), style: AppTheme.monoLabel()),
          ),
          Expanded(
            child: Text(
              value,
              style: monospace
                  ? AppTheme.monoLabel(color: valueColor).copyWith(fontSize: 11)
                  : AppTheme.bodyMedium.copyWith(
                      color: valueColor,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row item used by hub / settings lists.
class NavigationRow extends StatelessWidget {
  const NavigationRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.tone = Tone.success,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      radius: 16,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: tone.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              const Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
        ],
      ),
    );
  }
}

/// Small circular avatar with initials. No photo upload is implied.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 26,
    this.onDark = false,
  });

  final String name;
  final double radius;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials = parts.isEmpty
        ? 'BG'
        : parts.take(2).map((p) => p.characters.first).join().toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onDark
            ? AppTheme.mintBright.withValues(alpha: 0.16)
            : AppTheme.mint,
        shape: BoxShape.circle,
        border: Border.all(
          color: onDark
              ? AppTheme.mintBright.withValues(alpha: 0.4)
              : AppTheme.teal.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        initials,
        style: AppTheme.labelLarge.copyWith(
          fontWeight: FontWeight.w800,
          color: onDark ? AppTheme.mintBright : AppTheme.tealText,
          fontSize: radius * 0.62,
        ),
      ),
    );
  }
}

/// Loading placeholder with an indefinite animation.
///
/// While a request is in flight nothing blocks the frame, so a spinner is the
/// honest signal. Callers that hold this widget for a long time should pass
/// `animate: false` to avoid an endless animation loop.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({
    super.key,
    this.label = 'Loading server records…',
    this.animate = true,
  });

  final String label;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: animate
                ? const CircularProgressIndicator(strokeWidth: 2.5)
                : const Icon(
                    Icons.hourglass_top_rounded,
                    size: 22,
                    color: AppTheme.teal,
                  ),
          ),
          const SizedBox(height: 12),
          Text(label, style: AppTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Inline retry block for failed requests. Never shows a raw stack trace.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Could not load this section',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: AppTheme.danger.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: AppTheme.danger,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.labelLarge.copyWith(color: AppTheme.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_type.dart';

/// Page scaffold body: scrolls, applies the shared gutters, caps the content
/// width, and leaves room at the bottom. Phone is its own composition: one
/// column, 16px gutters.
class AppPage extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  const AppPage({
    super.key,
    required this.children,
    this.onRefresh,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: AppSpacing.page(context),
      children: [
        for (final c in children)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SizedBox(width: double.infinity, child: c),
            ),
          ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.raised,
      onRefresh: onRefresh!,
      child: list,
    );
  }
}

/// Two columns from 900px up, one stacked column below. [ratio] is the share
/// of the first column on wide layouts.
class AppSplit extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final double ratio;
  final double gap;

  /// Minimum width of the space AppSplit itself gets (not the window).
  final double breakpoint;

  const AppSplit({
    super.key,
    required this.primary,
    required this.secondary,
    this.ratio = 0.6,
    this.gap = 24,
    this.breakpoint = 880,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [primary, SizedBox(height: gap), secondary],
        );
      }
      final a = (ratio * 100).round();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: a, child: primary),
          SizedBox(width: gap),
          Expanded(flex: 100 - a, child: secondary),
        ],
      );
    });
  }
}

/// Page title block: 24/800 title, optional meta line, actions on the right
/// (wrapping under the title on phones).
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final compact = AppSpacing.isCompact(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title,
              style: AppType.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppType.meta),
        ],
      ],
    );
    final lead = leading == null
        ? titleBlock
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading!,
              const SizedBox(width: 12),
              Expanded(child: titleBlock),
            ],
          );

    Widget body;
    if (actions.isEmpty) {
      body = lead;
    } else if (compact) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: lead),
          const SizedBox(width: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.section(context) - 8),
      child: body,
    );
  }
}

/// Section heading (16/800) with an optional trailing widget and a gap
/// before the content.
class AppSection extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final bool last;

  const AppSection({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.section(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                            header: true,
                            child: Text(title!, style: AppType.heading)),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!, style: AppType.meta),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Entrance: fade + 16px rise, staggered by [index] (max 6 steps). Plays once.
/// With reduced motion it renders the child immediately.
class Reveal extends StatelessWidget {
  final int index;
  final Widget child;

  const Reveal({super.key, this.index = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    final step = index.clamp(0, 5);
    final delay = AppMotion.stagger * step;
    final total = AppMotion.base + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: AppMotion.curve),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
      ),
    );
  }
}

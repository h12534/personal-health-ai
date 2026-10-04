import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../theme/app_tokens.dart';

/// Presentation-only patterns. These widgets never fetch or infer health data.
class RootPageHeader extends StatelessWidget {
  const RootPageHeader(
      {super.key, required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Semantics(
                    header: true,
                    child: Text(title, style: AppTypography.pageTitle))),
            if (action != null) action!,
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle!,
                style: AppTypography.secondary
                    .copyWith(color: AppColors.of(context).secondaryText)),
          ],
          const SizedBox(height: AppSpacing.section),
        ],
      );
}

class DetailPageHeader extends AppBar {
  DetailPageHeader({super.key, required String label, super.actions})
      : super(title: Text(label), centerTitle: false);
}

class AppSection extends StatelessWidget {
  const AppSection(
      {super.key, required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.section),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              children: [
                Semantics(
                    header: true,
                    child: Text(title, style: AppTypography.sectionTitle)),
                if (action != null) action!,
              ]),
          const SizedBox(height: AppSpacing.md),
          child,
        ]),
      );
}

class MetricHero extends StatelessWidget {
  const MetricHero(
      {super.key,
      required this.label,
      required this.value,
      this.unit = '',
      this.detail});
  final String label, value, unit;
  final String? detail;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTypography.metricLabel),
        const SizedBox(height: AppSpacing.sm),
        Text.rich(
            TextSpan(text: value, children: [
              if (unit.isNotEmpty)
                TextSpan(
                    text: ' $unit',
                    style: AppTypography.secondary
                        .copyWith(color: AppColors.of(context).secondaryText)),
            ]),
            style: AppTypography.heroMetric),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(detail!,
              style: AppTypography.secondary
                  .copyWith(color: AppColors.of(context).secondaryText)),
        ],
      ]);
}

class MetricRow extends StatelessWidget {
  const MetricRow(
      {super.key, required this.label, required this.value, this.detail});
  final String label, value;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(17) > 25;
    final labelWidget =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTypography.metricLabel),
      if (detail != null)
        Text(detail!,
            style: AppTypography.caption
                .copyWith(color: AppColors.of(context).secondaryText)),
    ]);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                labelWidget,
                const SizedBox(height: 4),
                Text(value, style: AppTypography.metric)
              ])
            : Row(children: [
                Expanded(child: labelWidget),
                const SizedBox(width: 12),
                Text(value, style: AppTypography.metric)
              ]));
  }
}

class ProgressMetric extends StatelessWidget {
  const ProgressMetric(
      {super.key,
      required this.label,
      required this.value,
      required this.amount,
      this.target,
      this.unit = ''});
  final String label, value, unit;
  final double? amount, target;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final validTarget = target != null && target!.isFinite && target! > 0;
    final hasAmount = amount != null && amount!.isFinite;
    final valueIncludesUnit = unit.isNotEmpty && value.endsWith(' $unit');
    final ratioParts = value.split(' / ');
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTypography.metricLabel),
          const SizedBox(height: 6),
          Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                if (ratioParts.length == 2)
                  Text.rich(
                      TextSpan(text: ratioParts.first, children: [
                        TextSpan(
                            text: ' / ${ratioParts.last}',
                            style: AppTypography.secondary
                                .copyWith(color: colors.secondaryText)),
                      ]),
                      style: AppTypography.metric)
                else if (valueIncludesUnit)
                  Text.rich(
                      TextSpan(
                          text: value.substring(
                              0, value.length - unit.length - 1),
                          children: [
                            TextSpan(
                                text: ' $unit',
                                style: AppTypography.secondary
                                    .copyWith(color: colors.secondaryText)),
                          ]),
                      style: AppTypography.metric)
                else
                  Text(value, style: AppTypography.metric),
                if (unit.isNotEmpty && !valueIncludesUnit)
                  Text(unit,
                      style: AppTypography.secondary
                          .copyWith(color: colors.secondaryText)),
              ]),
          const SizedBox(height: 6),
          if (!validTarget || ratioParts.length != 2)
            Text(
                validTarget
                    ? '目标 ${AppFormat.number(target!)}${unit.isEmpty ? '' : ' $unit'}'
                    : '目标待设置',
                style: AppTypography.caption
                    .copyWith(color: colors.secondaryText)),
          if (validTarget && hasAmount) ...[
            const SizedBox(height: 10),
            Semantics(
                label:
                    '$label，$value $unit，目标 ${AppFormat.number(target!)} $unit',
                child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                        value: math.max(0, math.min(1, amount! / target!)),
                        minHeight: 3,
                        backgroundColor: colors.divider,
                        color: colors.primary))),
            if (amount! > target!)
              Text('已超过目标',
                  style:
                      AppTypography.caption.copyWith(color: colors.attention)),
          ],
        ]));
  }
}

class InsightBlock extends StatelessWidget {
  const InsightBlock(
      {super.key,
      required this.title,
      required this.message,
      this.action,
      this.prominent = false});
  final String title, message;
  final Widget? action;
  final bool prominent;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.page),
      decoration: BoxDecoration(
          color: prominent ? colors.softTint : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.hero)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            header: true,
            child: Text(title, style: AppTypography.sectionTitle)),
        const SizedBox(height: AppSpacing.sm),
        Text(message,
            style: AppTypography.body.copyWith(
                color: prominent ? colors.primaryText : colors.secondaryText)),
        if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
      ]),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow(
      {super.key,
      required this.title,
      required this.status,
      this.subtitle,
      this.onTap});
  final String title, status;
  final String? subtitle;
  final VoidCallback? onTap;
  static String statusLabel(String status) => switch (status) {
        'completed' => '已完成',
        'pending' => '待完成',
        'skipped' => '已跳过',
        _ => '状态待确认',
      };
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icon = switch (status) {
      'completed' => Icons.check_circle,
      'skipped' => Icons.remove_circle_outline,
      _ => Icons.radio_button_unchecked,
    };
    return Semantics(
        label: '$title，${statusLabel(status)}',
        button: onTap != null,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                          child: Icon(icon,
                              size: 22,
                              color: status == 'completed'
                                  ? colors.positive
                                  : colors.secondaryText)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            ExcludeSemantics(
                                child: Text(title, style: AppTypography.body)),
                            if (subtitle != null)
                              Text(subtitle!,
                                  style: AppTypography.caption
                                      .copyWith(color: colors.secondaryText)),
                            if (status != 'pending')
                              ExcludeSemantics(
                                  child: Text(statusLabel(status),
                                      style: AppTypography.caption.copyWith(
                                          color: colors.secondaryText))),
                          ])),
                    ]))));
  }
}

class ListRow extends StatelessWidget {
  const ListRow(
      {super.key,
      required this.title,
      this.subtitle,
      this.icon,
      this.trailing,
      this.onTap});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 12,
        leading: icon == null ? null : Icon(icon, size: AppIconSize.standard),
        title: Text(title, style: AppTypography.cardTitle),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: AppTypography.secondary),
        trailing: trailing ??
            (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      );
}

class TrendIndicator extends StatelessWidget {
  const TrendIndicator({super.key, required this.label, this.note});
  final String label;
  final String? note;
  @override
  Widget build(BuildContext context) =>
      ListRow(title: label, subtitle: note, icon: Icons.show_chart_outlined);
}

class BottomActionArea extends StatelessWidget {
  const BottomActionArea({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: child));
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.title,
      required this.message,
      this.actionLabel,
      this.onAction,
      this.icon = Icons.inbox_outlined});
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.of(context).secondaryText),
        const SizedBox(height: 12),
        Text(title, style: AppTypography.cardTitle),
        const SizedBox(height: 8),
        Text(message,
            style: AppTypography.secondary
                .copyWith(color: AppColors.of(context).secondaryText)),
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel!))
        ],
      ]));
}

class ErrorState extends StatelessWidget {
  const ErrorState(
      {super.key, required this.error, required this.onRetry, this.title});
  final Object error;
  final VoidCallback onRetry;
  final String? title;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: AppSpacing.pageInsets,
      child: EmptyState(
          title: title ?? UiFailure.title(error),
          message: UiFailure.message(error),
          actionLabel: '重试',
          onAction: onRetry,
          icon: Icons.info_outline));
}

/// Static skeleton deliberately avoids a forever-running shimmer / ticker.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = '正在读取记录'});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
          child: ListView(padding: AppSpacing.pageInsets, children: [
        for (final height in [38.0, 18.0, 132.0, 18.0, 72.0, 72.0])
          Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                  height: height,
                  decoration: BoxDecoration(
                      color: AppColors.of(context).elevatedSurface,
                      borderRadius: BorderRadius.circular(10)))),
      ])));
}

abstract final class UiFailure {
  static String? _code(Object error) =>
      error is ApiException ? error.code : null;
  static bool _connection(Object error) =>
      error is ApiException && error.message == '无法连接服务器，请检查网络和 API 地址。';
  static String title(Object error) => switch (_code(error)) {
        'ai_not_configured' => 'AI 暂不可用',
        'not_authenticated' ||
        'invalid_access_token' ||
        'inactive_user' =>
          '登录状态需要更新',
        'admin_required' => '没有访问权限',
        'coach_daily_limit' => '今日教练额度已用完',
        _ => _connection(error) ? '连接暂不可用' : '暂时无法完成',
      };
  static String message(Object error) => switch (_code(error)) {
        'ai_not_configured' => '教练服务尚未配置。你的记录不会受影响，可以稍后重试。',
        'not_authenticated' ||
        'invalid_access_token' ||
        'inactive_user' =>
          '请重新登录后再试。',
        'admin_required' => '当前账户不能访问此内容。',
        'coach_daily_limit' => '请明天再试，或先查看已经保存的建议。',
        _ => _connection(error)
            ? '请检查网络和服务地址后重试。未确认保存的内容仍需重试。'
            : '暂时无法确认结果。请检查记录后重试。',
      };
}

abstract final class AppFormat {
  static String number(num value, {int decimals = 0, bool grouped = false}) {
    final raw = value.toStringAsFixed(decimals);
    if (!grouped) return raw;
    return raw.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  static String date(DateTime value) => '${value.month}月${value.day}日';
  static String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

/// A focused quantity editor. The supplied existing action owns persistence.
class NumberEntryDialog extends StatefulWidget {
  const NumberEntryDialog(
      {super.key,
      required this.title,
      required this.initialValue,
      required this.unit,
      required this.onSave});
  final String title, initialValue, unit;
  final Future<void> Function(double) onSave;
  @override
  State<NumberEntryDialog> createState() => _NumberEntryDialogState();
}

class _NumberEntryDialogState extends State<NumberEntryDialog> {
  late final _input = TextEditingController(text: widget.initialValue);
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  Object? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(double.parse(_input.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                        controller: _input,
                        enabled: !_saving,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: '份量', suffixText: widget.unit),
                        validator: (text) {
                          final value = double.tryParse(text?.trim() ?? '');
                          return value == null || !value.isFinite || value <= 0
                              ? '请输入大于 0 的有效数值'
                              : null;
                        },
                        onFieldSubmitted: (_) => _save()),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text('${UiFailure.title(_error!)}。输入已保留，请重试。',
                              style: AppTypography.secondary.copyWith(
                                  color: AppColors.of(context).danger)))
                    ],
                  ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? '正在保存…'
                    : _error == null
                        ? '保存'
                        : '重试保存')),
          ]));
}

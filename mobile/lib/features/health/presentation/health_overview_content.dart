import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
import '../data/health_models.dart';
import 'health_trend_chart.dart';

enum HealthOverviewVariant { clinical, warm, dataForward }

String labFlagLabel(String flag) => switch (flag) {
      'high' => '高于本报告范围',
      'low' => '低于本报告范围',
      'normal' => '报告范围内',
      'critical' => '报告标记：危急',
      _ => '状态待核对',
    };

Color labFlagColor(AppColors colors, String flag) => switch (flag) {
      'high' || 'low' => colors.attention,
      'critical' => colors.danger,
      'normal' => colors.positive,
      _ => colors.secondaryText,
    };

LabResultModel? overviewFocus(LabReportModel report) {
  if (report.results.isEmpty) return null;
  return report.results.firstWhere(
    (item) => const ['high', 'low', 'critical'].contains(item.flag),
    orElse: () => report.results.first,
  );
}

/// One data contract, three visual compositions. Production uses dataForward.
class HealthOverviewContent extends StatelessWidget {
  const HealthOverviewContent({
    super.key,
    required this.report,
    required this.onOpenReports,
    required this.onOpenIndicator,
    required this.onAsk,
    this.trend,
    this.trendLoading = false,
    this.onRetryTrend,
    this.variant = HealthOverviewVariant.dataForward,
  });

  final LabReportModel report;
  final LabTrendModel? trend;
  final bool trendLoading;
  final VoidCallback onOpenReports;
  final ValueChanged<LabResultModel> onOpenIndicator, onAsk;
  final VoidCallback? onRetryTrend;
  final HealthOverviewVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final focus = overviewFocus(report);
    final other = report.results.where((item) => item.id != focus?.id).toList();
    // Attention comes from report flags, not new clinical thresholds.
    other.sort((a, b) {
      int group(LabResultModel item) =>
          const ['high', 'low', 'critical'].contains(item.flag) ? 0 : 1;
      return group(a).compareTo(group(b));
    });
    final reportHeader = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
          Semantics(header: true, child: Text('上次体检', style: text.titleMedium)),
          Text(AppFormat.fullDate(report.reportDate),
              style: text.bodySmall?.copyWith(color: colors.secondaryText)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Text('需要关注 ${report.attentionCount} 项 · 以报告参考范围为准',
            style: text.bodySmall?.copyWith(color: colors.secondaryText)),
        if (report.results.any((item) => item.flag == 'critical'))
          Text('含报告标记的危急项，请优先联系医生。',
              style: text.bodyMedium?.copyWith(color: colors.danger)),
      ],
    );
    final dataFocus = focus == null
        ? const Text('报告已确认，但没有可展示的指标。请打开报告核对。')
        : MetricFocus(
            result: focus,
            date: report.reportDate,
            filled: variant == HealthOverviewVariant.dataForward,
            compact: variant == HealthOverviewVariant.clinical,
            onTap: () => onOpenIndicator(focus),
          );
    final history = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
            header: true,
            child: Text(variant == HealthOverviewVariant.warm ? '你的记录' : '个人趋势',
                style: text.titleMedium)),
        const SizedBox(height: AppSpacing.md),
        if (trend case final history?)
          if (variant == HealthOverviewVariant.warm)
            ...history.points.map((point) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                      '${AppFormat.fullDate(point.date)}   ${point.value} ${point.unit}',
                      style: text.bodyMedium),
                ))
          else
            LabTrendChart(trend: history, detailKey: false)
        else if (trendLoading)
          const HealthSkeleton(label: '正在读取历史记录', compact: true)
        else if (onRetryTrend != null)
          Text('历史记录暂时无法读取，请重试。',
              style: text.bodyMedium?.copyWith(color: colors.secondaryText))
        else
          Text('暂无可比较的历史记录。单次结果不能说明趋势。',
              style: text.bodyMedium?.copyWith(color: colors.secondaryText)),
        if (trend == null && !trendLoading && onRetryTrend != null)
          TextButton(onPressed: onRetryTrend, child: const Text('重新读取历史')),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        reportHeader,
        const SizedBox(height: AppSpacing.section),
        dataFocus,
        const SizedBox(height: AppSpacing.section),
        if (focus?.value != null) history,
        if (other.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.section),
          Semantics(header: true, child: Text('其他指标', style: text.titleMedium)),
          for (final result in other.take(3))
            HealthMetricRow(
                result: result, onTap: () => onOpenIndicator(result)),
        ],
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: onOpenReports,
          child: Text('查看完整报告 · ${report.results.length} 项指标'),
        ),
        const SizedBox(height: AppSpacing.section),
        if (focus != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('一起理解这个指标', style: text.titleMedium),
            subtitle: const Text('结合报告与可靠来源，不做自动诊断。'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onAsk(focus),
          ),
        const SizedBox(height: AppSpacing.md),
        const HealthSafetyContext(),
      ],
    );
  }
}

class MetricFocus extends StatelessWidget {
  const MetricFocus(
      {super.key,
      required this.result,
      required this.date,
      required this.onTap,
      this.filled = false,
      this.compact = false});
  final LabResultModel result;
  final DateTime date;
  final VoidCallback onTap;
  final bool filled, compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      onTap: onTap,
      label:
          '${result.testName}，${result.displayValue} ${result.unit ?? ''}，${labFlagLabel(result.flag)}，参考 ${result.referenceDisplay}，${AppFormat.fullDate(date)}。查看详情',
      excludeSemantics: true,
      child: Material(
        color: filled ? colors.softTint : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: InkWell(
          key: Key('lab-result-${result.normalizedName}'),
          borderRadius: BorderRadius.circular(AppRadius.hero),
          onTap: onTap,
          child: Padding(
            padding:
                EdgeInsets.all(filled ? AppSpacing.section : AppSpacing.xs),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(result.testName, style: text.titleMedium)),
                Icon(Icons.chevron_right,
                    size: AppIconSize.small, color: colors.primary),
              ]),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpacing.sm,
                  children: [
                    Text(result.displayValue,
                        style:
                            (compact ? text.headlineMedium : text.displayLarge)
                                ?.copyWith(color: colors.primary)),
                    if (result.unit?.isNotEmpty == true)
                      Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(result.unit!,
                              style: text.titleMedium
                                  ?.copyWith(color: colors.secondaryText))),
                  ]),
              const SizedBox(height: AppSpacing.md),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                    result.flag == 'normal'
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: labFlagColor(colors, result.flag),
                    size: AppIconSize.small),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                    child: Text(labFlagLabel(result.flag),
                        style: text.bodyMedium?.copyWith(
                            color: labFlagColor(colors, result.flag)))),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text('本报告参考：${result.referenceDisplay} ${result.unit ?? ''}',
                  style: text.bodySmall?.copyWith(color: colors.secondaryText)),
            ]),
          ),
        ),
      ),
    );
  }
}

class HealthMetricRow extends StatelessWidget {
  const HealthMetricRow({super.key, required this.result, required this.onTap});
  final LabResultModel result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      key: Key('lab-result-${result.normalizedName}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppComponentSize.minTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.testName, style: text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(result.displayValue, style: AppTypography.metric),
                  if (result.unit?.isNotEmpty == true)
                    Text(result.unit!,
                        style: AppTypography.secondary
                            .copyWith(color: colors.secondaryText))
                ]),
            Text('${labFlagLabel(result.flag)} · 参考：${result.referenceDisplay}',
                style: text.bodySmall
                    ?.copyWith(color: labFlagColor(colors, result.flag))),
          ]),
        ),
      ),
    );
  }
}

class HealthSafetyContext extends StatelessWidget {
  const HealthSafetyContext({super.key});
  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text('医疗安全边界', style: Theme.of(context).textTheme.bodySmall),
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: const [
          Text('危急症状优先就医；AI 不确诊、不改药，也不会因轻度异常罗列严重疾病。体重、睡眠、训练和体检只描述共同变化，不轻易断言因果。')
        ],
      );
}

class HealthSkeleton extends StatelessWidget {
  const HealthSkeleton(
      {super.key, this.label = '正在读取体检记录', this.compact = false});
  final String label;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return LoadingState(inline: true, label: label);
  }
}

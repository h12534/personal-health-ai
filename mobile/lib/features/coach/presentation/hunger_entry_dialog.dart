import 'package:flutter/material.dart';
import '../../../core/widgets/app_components.dart';

/// Presentation-only editor; caller supplies the existing persistence action.
class HungerEntryDialog extends StatefulWidget {
  const HungerEntryDialog({super.key, required this.onSave});
  final Future<void> Function(
      int hunger, int craving, String context, String? note) onSave;
  @override
  State<HungerEntryDialog> createState() => _HungerEntryDialogState();
}

class _HungerEntryDialogState extends State<HungerEntryDialog> {
  double _hunger = 3, _craving = 2;
  String _context = 'before_dinner';
  final _note = TextEditingController();
  bool _saving = false;
  Object? _error;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_hunger.round(), _craving.round(), _context,
          _note.text.trim().isEmpty ? null : _note.text.trim());
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
          title: const Text('记录饥饿感'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('饥饿程度：${_hunger.round()} / 5'),
                Semantics(
                    label: '饥饿程度',
                    child: Slider(
                        value: _hunger,
                        min: 1,
                        max: 5,
                        divisions: 4,
                        semanticFormatterCallback: (v) => '${v.round()}分，满分5分',
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _hunger = v))),
                Text('想吃特定食物：${_craving.round()} / 5'),
                Semantics(
                    label: '想吃特定食物',
                    child: Slider(
                        value: _craving,
                        min: 1,
                        max: 5,
                        divisions: 4,
                        semanticFormatterCallback: (v) => '${v.round()}分，满分5分',
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _craving = v))),
                DropdownButtonFormField<String>(
                    initialValue: _context,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(labelText: '时间'),
                    items: const [
                      DropdownMenuItem(
                          value: 'before_breakfast', child: Text('早餐前')),
                      DropdownMenuItem(
                          value: 'before_lunch', child: Text('午餐前')),
                      DropdownMenuItem(
                          value: 'before_dinner', child: Text('晚餐前')),
                      DropdownMenuItem(value: 'before_bed', child: Text('睡前'))
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _context = v ?? _context)),
                TextField(
                    controller: _note,
                    enabled: !_saving,
                    minLines: 1,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: '备注（压力、食堂选择、训练后等）')),
                if (_error != null)
                  Semantics(
                      liveRegion: true,
                      child: Text('${UiFailure.title(_error!)}。输入已保留，请重试。')),
              ]),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? '正在保存…'
                    : _error == null
                        ? '保存'
                        : '重试保存'))
          ]));
}

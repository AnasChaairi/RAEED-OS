import 'package:flutter/material.dart';

import '../theme/raeed_theme.dart';

/// One choice in a [SelectField] or [MultiSelectField].
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.subtitle, this.leading, this.key});

  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;

  /// Kept on the choice's button when the list is short enough to show inline.
  final Key? key;
}

/// Lists up to this many choices inline as buttons. Longer lists open a sheet with search.
const inlineChoiceLimit = 8;

/// The sheet shows its search box from this many choices.
const _searchFrom = 7;

/// Folds the spellings people mix up when typing Arabic, so «احمد» finds «أحمد».
String foldArabic(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ً-ْٰـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .trim();

bool _matches<T>(SelectOption<T> o, String query) {
  final q = foldArabic(query);
  if (q.isEmpty) return true;
  return foldArabic(o.label).contains(q) || (o.subtitle != null && foldArabic(o.subtitle!).contains(q));
}

/// Picks one value. Shows as a form field; a tap opens a scrollable sheet with search.
/// With [noneLabel], the sheet also offers no value at all.
class SelectField<T> extends StatelessWidget {
  const SelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.fieldKey,
    this.noneLabel,
    this.validator,
    this.searchHint,
  });

  final String label;
  final List<SelectOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final Key? fieldKey;
  final String? noneLabel;
  final String? Function(T?)? validator;
  final String? searchHint;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.value == value).firstOrNull;
    return FormField<T>(
      key: fieldKey,
      initialValue: value,
      validator: validator == null ? null : (_) => validator!(value),
      builder: (state) => InkWell(
        onTap: () async {
          final picked = await showModalBottomSheet<(T?,)>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _SingleSheet<T>(
              title: label,
              options: options,
              value: value,
              noneLabel: noneLabel,
              searchHint: searchHint,
            ),
          );
          if (picked == null) return;
          onChanged(picked.$1);
          state.didChange(picked.$1);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: state.errorText,
            suffixIcon: const Icon(Icons.expand_more),
          ),
          child: Row(
            children: [
              if (current?.leading != null) ...[current!.leading!, const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  current?.label ?? noneLabel ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: current == null ? const TextStyle(color: RaeedColors.grey) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks any number of values. A short list stays as buttons; a long one shows the
/// chosen values and opens a scrollable sheet with search.
class MultiSelectField<T> extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.searchHint,
  });

  /// Heads the sheet, such as «المؤطرون».
  final String title;
  final List<SelectOption<T>> options;
  final Set<T> selected;
  final void Function(T value, bool on) onChanged;
  final String? searchHint;

  @override
  Widget build(BuildContext context) {
    if (options.length <= inlineChoiceLimit) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in options)
            FilterChip(
              key: o.key,
              avatar: o.leading,
              label: Text(o.label),
              selected: selected.contains(o.value),
              onSelected: (on) => onChanged(o.value, on),
            ),
        ],
      );
    }
    final chosen = [
      for (final o in options)
        if (selected.contains(o.value)) o,
    ];
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _MultiSheet<T>(
          title: title,
          options: options,
          selected: selected,
          onChanged: onChanged,
          searchHint: searchHint,
        ),
      ),
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: 'اختر من القائمة',
          suffixIcon: const Icon(Icons.expand_more),
          helperText: chosen.isEmpty ? null : 'تم اختيار ${chosen.length} من ${options.length}',
        ),
        isEmpty: chosen.isEmpty,
        child: chosen.isEmpty
            ? null
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in chosen)
                    InputChip(
                      avatar: o.leading,
                      label: Text(o.label),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => onChanged(o.value, false),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint, required this.onChanged});

  final String? hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: TextField(
      key: const Key('select-search'),
      decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: hint ?? 'ابحث بالاسم'),
      onChanged: onChanged,
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, this.trailing, required this.children, this.footer, required this.tall});

  final String title;
  final String? trailing;
  final List<Widget> children;
  final Widget? footer;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final list = ListView(shrinkWrap: !tall, children: children);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (trailing != null)
                      Text(
                        trailing!,
                        key: const Key('select-count'),
                        style: const TextStyle(color: RaeedColors.grey),
                      ),
                  ],
                ),
              ),
              if (tall) Expanded(child: list) else Flexible(child: list),
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}

const _noMatch = Padding(
  padding: EdgeInsets.symmetric(vertical: 32),
  child: Text(
    'لا توجد نتيجة مطابقة.',
    textAlign: TextAlign.center,
    style: TextStyle(color: RaeedColors.grey),
  ),
);

class _SingleSheet<T> extends StatefulWidget {
  const _SingleSheet({
    required this.title,
    required this.options,
    required this.value,
    required this.noneLabel,
    required this.searchHint,
  });

  final String title;
  final List<SelectOption<T>> options;
  final T? value;
  final String? noneLabel;
  final String? searchHint;

  @override
  State<_SingleSheet<T>> createState() => _SingleSheetState<T>();
}

class _SingleSheetState<T> extends State<_SingleSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final search = widget.options.length >= _searchFrom;
    final shown = [
      for (final o in widget.options)
        if (_matches(o, _query)) o,
    ];
    Widget tile({
      required Key key,
      Widget? leading,
      required String label,
      String? subtitle,
      required bool on,
      required T? value,
    }) => ListTile(
      key: key,
      leading: leading,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: on ? const Icon(Icons.check_circle, color: RaeedColors.blue) : null,
      selected: on,
      onTap: () => Navigator.pop(context, (value,)),
    );
    return _SheetFrame(
      title: widget.title,
      tall: search,
      children: [
        if (search) _SearchBox(hint: widget.searchHint, onChanged: (v) => setState(() => _query = v)),
        if (widget.noneLabel != null && _query.trim().isEmpty)
          tile(key: const Key('select-none'), label: widget.noneLabel!, on: widget.value == null, value: null),
        for (final o in shown)
          tile(
            key: Key('select-${o.value}'),
            leading: o.leading,
            label: o.label,
            subtitle: o.subtitle,
            on: o.value == widget.value,
            value: o.value,
          ),
        if (shown.isEmpty) _noMatch,
      ],
    );
  }
}

class _MultiSheet<T> extends StatefulWidget {
  const _MultiSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.searchHint,
  });

  final String title;
  final List<SelectOption<T>> options;
  final Set<T> selected;
  final void Function(T value, bool on) onChanged;
  final String? searchHint;

  @override
  State<_MultiSheet<T>> createState() => _MultiSheetState<T>();
}

class _MultiSheetState<T> extends State<_MultiSheet<T>> {
  String _query = '';
  late final Set<T> _on = {...widget.selected};

  void _toggle(T value, bool on) {
    setState(() => on ? _on.add(value) : _on.remove(value));
    widget.onChanged(value, on);
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final o in widget.options)
        if (_matches(o, _query)) o,
    ];
    return _SheetFrame(
      title: widget.title,
      trailing: '${_on.length} / ${widget.options.length}',
      tall: true,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('select-done'),
            onPressed: () => Navigator.pop(context),
            child: const Text('تم'),
          ),
        ),
      ),
      children: [
        _SearchBox(hint: widget.searchHint, onChanged: (v) => setState(() => _query = v)),
        for (final o in shown)
          CheckboxListTile(
            key: Key('select-${o.value}'),
            value: _on.contains(o.value),
            onChanged: (v) => _toggle(o.value, v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: o.leading,
            title: Text(o.label),
            subtitle: o.subtitle == null ? null : Text(o.subtitle!),
          ),
        if (shown.isEmpty) _noMatch,
      ],
    );
  }
}

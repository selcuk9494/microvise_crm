import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format/search_normalize.dart';
import 'customer_model.dart';

String customerInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return '?';
  return parts.map((part) => part[0].toUpperCase()).join();
}

class CustomerSelectField extends StatefulWidget {
  const CustomerSelectField({
    super.key,
    required this.customers,
    required this.selectedCustomerId,
    required this.label,
    required this.onSelected,
    required this.onCreateNew,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;
  final String label;
  final ValueChanged<Customer?> onSelected;
  final Future<Customer?> Function() onCreateNew;

  @override
  State<CustomerSelectField> createState() => _CustomerSelectFieldState();
}

class _CustomerSelectFieldState extends State<CustomerSelectField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedName());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant CustomerSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCustomerId != widget.selectedCustomerId ||
        oldWidget.customers != widget.customers) {
      final next = _selectedName();
      if (_controller.text != next && !_focusNode.hasFocus) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      final selected = _selectedName();
      if (_controller.text != selected) {
        _controller.value = TextEditingValue(
          text: selected,
          selection: TextSelection.collapsed(offset: selected.length),
        );
      }
      return;
    }
    if (_controller.text.isEmpty) return;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  String _selectedName() {
    final id = widget.selectedCustomerId;
    if (id == null || id.isEmpty) return '';
    for (final customer in widget.customers) {
      if (customer.id == id) return customer.name;
    }
    return '';
  }

  bool _matchesCustomer(Customer customer, String query) {
    return matchesSearchQuery(
      [
        customer.name,
        customer.vkn ?? '',
        customer.tcknMs ?? '',
        customer.city ?? '',
        customer.phone1 ?? '',
        customer.email ?? '',
        customer.id,
      ].join(' '),
      query,
    );
  }

  Iterable<Customer> _optionsFor(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return widget.customers.take(40);
    }
    return widget.customers
        .where((customer) => _matchesCustomer(customer, query))
        .take(120);
  }

  Future<void> _createCustomer() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final created = await widget.onCreateNew();
      if (!mounted || created == null) return;
      _controller.value = TextEditingValue(
        text: created.name,
        selection: TextSelection.collapsed(offset: created.name.length),
      );
      _focusNode.unfocus();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.selectedCustomerId,
      validator: (_) =>
          (widget.selectedCustomerId ?? '').isEmpty ? 'Cari seçin' : null,
      builder: (field) {
        return RawAutocomplete<Customer>(
          textEditingController: _controller,
          focusNode: _focusNode,
          displayStringForOption: (customer) => customer.name,
          optionsBuilder: (value) => _optionsFor(value.text),
          onSelected: (customer) {
            widget.onSelected(customer);
            field.didChange(customer.id);
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              onFieldSubmitted: (_) => onFieldSubmitted(),
              onChanged: (value) {
                if (value.trim().isEmpty &&
                    (widget.selectedCustomerId ?? '').isNotEmpty) {
                  widget.onSelected(null);
                  field.didChange(null);
                }
              },
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: 'Ad, VKN, telefon veya şehir ara',
                errorText: field.errorText,
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: IconButton(
                  tooltip: _creating ? 'Oluşturuluyor…' : 'Yeni cari ekle',
                  onPressed: _creating ? null : _createCustomer,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.userPlus),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final items = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 520,
                    maxHeight: 360,
                  ),
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Cari bulunamadı.'),
                              const Gap(8),
                              OutlinedButton.icon(
                                onPressed: _creating ? null : _createCustomer,
                                icon: const Icon(LucideIcons.userPlus),
                                label: const Text('Yeni cari oluştur'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = items[index];
                            final selected =
                                customer.id == widget.selectedCustomerId;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              leading: CircleAvatar(
                                radius: 16,
                                child: Text(customerInitials(customer.name)),
                              ),
                              title: Text(
                                customer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if ((customer.vkn ?? '').isNotEmpty)
                                    'VKN ${customer.vkn}',
                                  if ((customer.city ?? '').isNotEmpty)
                                    customer.city,
                                  if ((customer.phone1 ?? '').isNotEmpty)
                                    customer.phone1,
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: selected
                                  ? const Icon(LucideIcons.circleCheck)
                                  : null,
                              onTap: () => onSelected(customer),
                            );
                          },
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

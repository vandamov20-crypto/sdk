import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help')) {
    _printUsage();
    exit(args.contains('--help') ? 0 : 64);
  }

  final inputPath = args.first;
  double? taxOverride;
  double? discountOverride;
  String currencySymbol = '₽';
  String sortField = 'category';

  for (final arg in args.skip(1)) {
    if (arg.startsWith('--tax-rate=')) {
      taxOverride = _parsePercent(arg.split('=').last, '--tax-rate');
    } else if (arg.startsWith('--discount=')) {
      discountOverride = _parsePercent(arg.split('=').last, '--discount');
    } else if (arg.startsWith('--currency=')) {
      currencySymbol = arg.split('=').skip(1).join('=');
    } else if (arg.startsWith('--sort=')) {
      sortField = arg.split('=').last;
    } else {
      stderr.writeln('Unknown option: $arg');
      _printUsage();
      exit(64);
    }
  }

  try {
    final estimate = Estimate.fromFile(
      inputPath,
      taxOverride: taxOverride,
      discountOverride: discountOverride,
    );

    estimate.render(currencySymbol: currencySymbol, sortField: sortField);
  } on EstimateException catch (error) {
    stderr.writeln('Error: ${error.message}');
    exit(64);
  }
}

void _printUsage() {
  stdout.writeln('''Usage: dart run samples/estimate/bin/estimate.dart <path-to-json> [options]\n\n'
      'Options:\n'
      '  --tax-rate=<percent>   Override the tax rate (e.g., 20 for 20%).\n'
      '  --discount=<percent>   Override the discount applied before tax.\n'
      '  --currency=<symbol>    Currency prefix to use when printing amounts (default: ₽).\n'
      '  --sort=category|description|total\n'
      '                         Sort items before printing (default: category).\n'
      '  --help                 Show this message.\n');
}

class EstimateException implements Exception {
  EstimateException(this.message);

  final String message;
}

double _parsePercent(String value, String flag) {
  final parsed = double.tryParse(value);
  if (parsed == null) {
    throw EstimateException('Unable to parse $flag value "$value" as a number');
  }
  if (parsed < 0) {
    throw EstimateException('$flag cannot be negative');
  }
  return parsed / 100;
}

class LineItem {
  LineItem({
    required this.description,
    required this.quantity,
    required this.unitCost,
    required this.category,
    required this.taxable,
  });

  final String description;
  final double quantity;
  final double unitCost;
  final String category;
  final bool taxable;

  double get subtotal => quantity * unitCost;

  static LineItem fromJson(Map<String, dynamic> json) {
    final description = json['description'] as String?;
    final quantity = (json['quantity'] as num?)?.toDouble() ?? 1;
    final unitCost = (json['unitCost'] as num?)?.toDouble();
    final category = (json['category'] as String?)?.trim();
    final taxable = json['taxable'] is bool ? json['taxable'] as bool : true;

    if (description == null || description.trim().isEmpty) {
      throw EstimateException('Each item must include a non-empty "description"');
    }
    if (unitCost == null) {
      throw EstimateException('Item "$description" is missing "unitCost"');
    }
    if (quantity <= 0 || unitCost < 0) {
      throw EstimateException(
        'Item "$description" must have positive quantity and non-negative unitCost',
      );
    }

    return LineItem(
      description: description.trim(),
      quantity: quantity,
      unitCost: unitCost,
      category: category?.isNotEmpty == true ? category! : 'General',
      taxable: taxable,
    );
  }
}

class Estimate {
  Estimate({
    required this.items,
    required this.taxRate,
    required this.discountRate,
    this.source,
  });

  final List<LineItem> items;
  final double taxRate;
  final double discountRate;
  final String? source;

  double get subtotal => items.fold(0, (total, item) => total + item.subtotal);
  double get discountAmount => subtotal * discountRate;
  double get taxableSubtotal =>
      items.where((item) => item.taxable).fold(0, (total, item) => total + item.subtotal);

  double get taxableAfterDiscount {
    if (subtotal == 0) return 0;
    final ratioAfterDiscount = (subtotal - discountAmount) / subtotal;
    return taxableSubtotal * ratioAfterDiscount;
  }

  double get taxAmount => taxableAfterDiscount * taxRate;
  double get total => subtotal - discountAmount + taxAmount;

  Map<String, double> totalsByCategory() {
    final totals = <String, double>{};
    for (final item in items) {
      totals.update(item.category, (value) => value + item.subtotal, ifAbsent: () => item.subtotal);
    }
    return totals;
  }

  static Estimate fromFile(
    String path, {
    double? taxOverride,
    double? discountOverride,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      throw EstimateException('Could not find input file at "$path"');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw EstimateException('Invalid JSON: ${error.message}');
    }

    final items = _parseItems(decoded);
    final defaultTax = _parseTopLevelRate(decoded, 'taxRate');
    final defaultDiscount = _parseTopLevelRate(decoded, 'discount');

    final taxRate = taxOverride ?? defaultTax;
    final discountRate = discountOverride ?? defaultDiscount;

    return Estimate(
      items: items,
      taxRate: taxRate,
      discountRate: discountRate,
      source: path,
    );
  }

  static List<LineItem> _parseItems(dynamic decoded) {
    final rawItems = switch (decoded) {
      List<dynamic> list => list,
      Map<String, dynamic> map when map['items'] is List<dynamic> => map['items'] as List<dynamic>,
      _ => null,
    };

    if (rawItems == null) {
      throw EstimateException('Expected either an array of items or a map with an "items" array');
    }

    if (rawItems.isEmpty) {
      throw EstimateException('No items found in the input file');
    }

    return rawItems
        .map((item) => LineItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  static double _parseTopLevelRate(dynamic decoded, String key) {
    final value = decoded is Map<String, dynamic> ? decoded[key] : null;
    if (value == null) return 0;
    if (value is num) {
      if (value < 0) {
        throw EstimateException('$key cannot be negative');
      }
      return value.toDouble() / 100;
    }
    throw EstimateException('Top-level "$key" must be a number');
  }

  void render({String currencySymbol = '₽', String sortField = 'category'}) {
    final sortedItems = [...items];
    switch (sortField) {
      case 'description':
        sortedItems.sort((a, b) => a.description.compareTo(b.description));
        break;
      case 'total':
        sortedItems.sort((a, b) => b.subtotal.compareTo(a.subtotal));
        break;
      default:
        sortedItems.sort((a, b) {
          final categoryCompare = a.category.compareTo(b.category);
          if (categoryCompare != 0) return categoryCompare;
          return a.description.compareTo(b.description);
        });
    }

    final categoryWidth = sortedItems.map((i) => i.category.length).fold<int>(7, max);
    final descriptionWidth = sortedItems.map((i) => i.description.length).fold<int>(11, max);

    stdout.writeln();
    if (source != null) {
      stdout.writeln('Estimate for ${source!}');
    } else {
      stdout.writeln('Estimate');
    }
    stdout.writeln('-' * 40);
    stdout.writeln(
        '${_pad('Category', categoryWidth)}  ${_pad('Description', descriptionWidth)}  Qty   Unit       Subtotal');
    stdout.writeln('-' * 40);

    for (final item in sortedItems) {
      final quantity = item.quantity % 1 == 0 ? item.quantity.toStringAsFixed(0) : item.quantity.toStringAsFixed(2);
      final taxableNote = item.taxable ? '' : ' (без налога)';
      stdout.writeln(
        '${_pad(item.category, categoryWidth)}  ${_pad(item.description, descriptionWidth)}  '
        '${_pad(quantity, 4)}  ${_pad(_money(item.unitCost, currencySymbol), 9)}  '
        '${_pad(_money(item.subtotal, currencySymbol), 10)}$taxableNote',
      );
    }

    stdout.writeln('-' * 40);
    stdout.writeln('Subtotal:            ${_money(subtotal, currencySymbol)}');
    stdout.writeln('Discount (${(discountRate * 100).toStringAsFixed(1)}%):'
        '${_pad('-', 5)}${_money(discountAmount, currencySymbol)}');
    stdout.writeln('Taxable after discount: ${_money(taxableAfterDiscount, currencySymbol)}');
    stdout.writeln('Tax (${(taxRate * 100).toStringAsFixed(1)}%):     ${_money(taxAmount, currencySymbol)}');
    stdout.writeln('Total:               ${_money(total, currencySymbol)}');

    final categories = totalsByCategory();
    if (categories.isNotEmpty) {
      stdout.writeln('\nBy category:');
      for (final entry in categories.entries) {
        stdout.writeln('  - ${entry.key}: ${_money(entry.value, currencySymbol)}');
      }
    }
    stdout.writeln();
  }
}

String _money(double amount, String currencySymbol) => '$currencySymbol${amount.toStringAsFixed(2)}';

String _pad(String value, int width) => value.padRight(width);

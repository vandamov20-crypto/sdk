# Estimate sample

This sample shows how to build a small command-line tool in Dart for preparing a project estimate (смета). It loads a JSON file that lists line items, applies discounts and taxes, and prints a breakdown along with category subtotals.

## Input format

The tool accepts either an array of items or a map that contains an `items` array. Each item supports these fields:

- `description` (required): Short name of the work or material.
- `quantity` (number, defaults to `1`).
- `unitCost` (number): Cost per unit.
- `category` (string, defaults to `General`): Groups related items for reporting.
- `taxable` (bool, defaults to `true`): Whether the item participates in the tax calculation.

If the JSON object contains top-level `taxRate` or `discount` numbers they will be used unless command-line options override them. Tax and discount values are expressed in percentages (for example `20` is 20%).

See [`data/sample_estimate.json`](data/sample_estimate.json) for a complete example.

## Running the sample

From the repository root:

```bash
# Format the source (optional but recommended)
$ dart format samples/estimate

# Print an estimate using the bundled sample data
$ dart run samples/estimate/bin/estimate.dart samples/estimate/data/sample_estimate.json \
    --tax-rate=20 --discount=5 --currency=₽
```

Command-line options:

- `--tax-rate=<percent>`: Override tax rate (default is 0 or the value in the JSON file).
- `--discount=<percent>`: Override discount applied before tax.
- `--currency=<symbol>`: Prefix used when printing money (defaults to `₽`).
- `--sort=category|description|total`: Sort items in the report (default `category`).
- `--help`: Show usage help.

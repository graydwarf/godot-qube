# Godot Qube - Ignore Rules

Suppress specific warnings when code is intentionally written a certain way.

## File Ignores

Place within the first 10 lines of the file.

```gdscript
# qube:ignore-file
extends Node
# This file will have ALL checks ignored

# Or ignore specific checks for the entire file:
# qube:ignore-file:file-length,long-function
extends Node
```

## Below Ignores

Ignore from this line to end of file. Useful for generated code, data tables, or legacy sections.

```gdscript
# ... maintained code above ...

# qube:ignore-below
# Everything below this line is ignored

var GENERATED_DATA = [1, 2, 3, 4, 5]  # No magic-number warnings
func _legacy_code(): pass            # No long-function warnings

# Or ignore specific checks only:
# qube:ignore-below:magic-number,missing-type
```

## Line Ignores

```gdscript
# Ignore all checks on next line
# qube:ignore-next-line
var magic = 42

# Ignore all checks on same line
var another_magic = 100  # qube:ignore

# Ignore specific check (or comma-separated list)
var debug_print = true  # qube:ignore:magic-number
var config = 255  # qube:ignore:magic-number,missing-type
```

## Function Ignores

Place the comment directly above the `func` declaration.

```gdscript
# Ignore ALL checks in function
# qube:ignore-function
func _print_help() -> void:
    print("Usage: ...")
    print("Options:")
    print("  --help  Show this message")

# Ignore specific checks (comma-separated)
# qube:ignore-function:print-statement,long-function
func _output_results() -> void:
    print("Results:")
    # ... many lines of output formatting ...
```

## Block Ignores

```gdscript
# Ignore all checks in block
# qube:ignore-block-start
var magic1 = 42
var magic2 = 100
# qube:ignore-block-end

# Ignore specific check in block
# qube:ignore-block-start:magic-number
var threshold = 1000
var limit = 5000
# qube:ignore-block-end
```

## Common Rule Names

| Rule ID | Description |
|---------|-------------|
| `long-function` | Function exceeds line limit |
| `file-length` | File exceeds line limit |
| `print-statement` | Print statement detected |
| `magic-number` | Unexplained numeric literal |
| `cyclomatic-complexity` | High branching complexity |
| `too-many-parameters` | Function has too many params |
| `deep-nesting` | Excessive indentation depth |
| `missing-type` | Missing type annotation |
| `unused-variable` | Variable declared but never used |
| `unused-parameter` | Parameter declared but never used |


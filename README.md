# Godot Qube

![Version](https://img.shields.io/badge/version-1.1.3-blue.svg)
![Godot](https://img.shields.io/badge/Godot-4.0%2B-blue.svg)

A static code analysis plugin for GDScript that helps you maintain code quality, identify technical debt, and enforce best practices in your Godot 4.x projects.

Runs in seconds with no external dependencies. Can help reduce token usage on large projects.

<p align="center">
  <img src="screenshots/godot-qube.png" width="700" alt="Godot Qube Editor Dock">
</p>

## Features

### Code Quality Checks

| Check | Severity | Description |
|-------|----------|-------------|
| **File Length** | Warning/Critical | Files exceeding soft/hard line limits |
| **Function Length** | Warning/Critical | Functions that are too long |
| **Cyclomatic Complexity** | Warning/Critical | Functions with too many decision paths |
| **Parameter Count** | Warning | Functions with too many parameters |
| **Nesting Depth** | Warning | Deeply nested code blocks |
| **TODO/FIXME Comments** | Info/Warning | Tracks technical debt markers |
| **Print Statements** | Warning | Debug prints left in code |
| **Empty Functions** | Info | Functions with no implementation |
| **Magic Numbers** | Info | Hardcoded numbers that should be constants |
| **Commented-Out Code** | Info | Dead code left in comments |
| **Missing Type Hints** | Info | Variables and functions without type annotations |
| **God Classes** | Warning | Classes with too many public functions or signals |
| **Naming Conventions** | Info/Warning | Non-standard naming (snake_case, PascalCase, etc.) |
| **Unused Variables** | Warning | Local variables declared but never used |
| **Unused Parameters** | Info | Function parameters declared but never used |

### Editor Integration

- Bottom panel dock with full analysis results
- Clickable file:line links to navigate directly to issues
- Filter by severity (Critical/Warning/Info)
- Filter by issue type (linked to severity selection)
- Filter by filename
- Configurable thresholds via settings panel
- Real-time debt score calculation
- Export to JSON or interactive HTML report

### HTML Reports

- Self-contained dark-themed HTML file
- Interactive filtering by severity, type, and filename
- Linked filters: type dropdown updates based on selected severity
- Summary stats with issue counts and debt score
- Opens automatically in your default browser

<p align="center">
  <img src="screenshots/godot-qube-html.png" width="700" alt="Godot Qube HTML Report">
</p>

### Claude Code Integration

Launch [Claude Code](https://claude.ai/code) directly from scan results to get AI-assisted fixes:

- Enable in Settings > Claude Code Integration
- Issue context (file, line, type, message) is passed automatically
- Add custom instructions to customize the AI prompt
- Requires [claude-code CLI](https://github.com/anthropics/claude-code) installed

**Interaction Options:**

| Action | Behavior |
|--------|----------|
| **Click** | Launch Claude Code in plan mode (safe - reviews before making changes) |
| **Shift+Click** | Launch Claude Code in immediate mode (fixes without planning) |
| **Right-click** | Context menu with "Plan Fix" and "Fix Immediately" options |

Hover over any Claude icon to see a tooltip with these options.

### CLI Support

Run analysis from command line for CI/CD integration:

```bash
# Analyze current project
godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd

# Analyze external project
godot --headless --path /path/to/godot-qube --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --path "C:/my/project"

# Output formats
godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --clickable  # Godot Output panel format
godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --json       # JSON format
godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --html -o report.html  # HTML report
```

**Exit Codes:**
- `0` - No issues found
- `1` - Warnings only
- `2` - Critical issues found

## Installation

### From Asset Library

1. Open Godot Editor
2. Go to AssetLib tab
3. Search for "Godot Qube"
4. Download and install
5. Enable plugin: Project > Project Settings > Plugins > Godot Qube > Enable

### Manual Installation

1. Download or clone this repository
2. Copy the `addons/godot-qube` folder to your project's `addons/` directory
3. Enable plugin: Project > Project Settings > Plugins > Godot Qube > Enable

## Usage

### Editor Dock

1. After enabling the plugin, find "Code Quality" in the bottom panel
2. Click "Scan" to analyze your codebase
3. Click any issue to navigate to the source location
4. Use filters to focus on specific severity levels or issue types
5. Click the settings icon to adjust thresholds

### Inline Ignore Comments

Suppress specific warnings with inline comments:

```gdscript
# Ignore the next line
# qube:ignore-next-line
var magic = 42

# Ignore on same line
var another_magic = 100  # qube:ignore

# Ignore specific check
var debug_print = true  # qube:ignore:magic-number
```

### Function and Block Ignores

Ignore all issues within an entire function:

```gdscript
# qube:ignore-function - CLI output requires print statements
func _print_help() -> void:
    print("Usage: ...")
    print("Options:")
    print("  --help  Show this message")

# Ignore only specific check in function
# qube:ignore-function:print-statement
func _output_results() -> void:
    print("Results:")
    print(data)
```

Ignore a block of code:

```gdscript
# qube:ignore-block-start
var magic1 = 42
var magic2 = 100
var magic3 = 256
# qube:ignore-block-end

# Ignore specific check in block
# qube:ignore-block-start:magic-number
var threshold = 1000
var limit = 5000
# qube:ignore-block-end
```

### Project Configuration

Create a `.gdqube.cfg` file in your project root to customize settings:

```ini
[limits]
file_lines_soft = 200
file_lines_hard = 300
function_lines = 30
function_lines_critical = 60
max_parameters = 4
max_nesting = 3
cyclomatic_warning = 10
cyclomatic_critical = 15

[checks]
file_length = true
function_length = true
cyclomatic_complexity = true
parameters = true
nesting = true
todo_comments = true
print_statements = true
empty_functions = true
magic_numbers = true
commented_code = true
missing_types = true
god_class = true
naming_conventions = true
unused_variables = true
unused_parameters = true
ignore_underscore_prefix = true

[exclude]
paths = addons/, .godot/, tests/mocks/
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Code Quality

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download Godot
        run: |
          wget -q https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip
          unzip -q Godot_v4.5-stable_linux.x86_64.zip
          chmod +x Godot_v4.5-stable_linux.x86_64

      - name: Run Code Analysis
        run: |
          ./Godot_v4.5-stable_linux.x86_64 --headless --path . --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --clickable
```

## Default Thresholds

| Setting | Soft/Warning | Hard/Critical |
|---------|--------------|---------------|
| File lines | 200 | 300 |
| Function lines | 30 | 60 |
| Cyclomatic complexity | 10 | 15 |
| Max parameters | 4 | - |
| Max nesting depth | 3 | - |
| God class functions | 20 | - |
| God class signals | 10 | - |

<p align="center">
  <img src="screenshots/godot-qube-settings.png" width="500" alt="Godot Qube Settings Panel">
</p>

## Allowed Magic Numbers

These numbers are not flagged as they are commonly self-explanatory:
`0, 1, -1, 2, 0.0, 1.0, 0.5, 2.0, -1.0, 10, 60, 90, 100, 180, 255, 360`

## Requirements

- Godot 4.0+
- GDScript only (no C# support)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Roadmap

Nothing planned. Waiting for feedback...

---

*This project was built with the assistance of [Claude Code](https://claude.ai/code), an AI coding assistant by Anthropic.*

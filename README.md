# Godot Qube

A code quality analyzer plugin for GDScript with clickable issue navigation.

## Features

- **Static Analysis**: Analyzes GDScript files for code quality issues
- **Clickable Navigation**: Click on issues to jump directly to the problematic code
- **Severity Levels**: Issues categorized as Critical, Warning, or Info
- **Configurable Thresholds**: Customize limits for file length, function length, complexity, etc.
- **Export to JSON**: Export full analysis results for CI integration or external tools
- **Filename Filter**: Filter results by filename to focus on specific areas

## Checks Included

### Critical Issues
- File length exceeds 300 lines
- Function exceeds 60 lines
- Cyclomatic complexity > 15

### Warnings
- File length exceeds 200 lines
- Function exceeds 30 lines
- Function has > 4 parameters
- Nesting depth > 3 levels
- Cyclomatic complexity > 10
- TODO/FIXME/HACK comments
- Debug print statements
- God class detection (> 20 public functions or > 10 signals)

### Info
- Long lines (> 120 chars)
- Empty functions
- Magic numbers
- Commented-out code
- Missing type hints

## Installation

### As a Plugin (Recommended)
1. Copy `addons/godot-qube/` to your project's `addons/` folder
2. Enable the plugin in Project Settings → Plugins
3. Click "Godot Qube" in the bottom panel

### CLI Usage
```bash
godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --clickable
```

Options:
- `--path <dir>` - Analyze a different project
- `--json` - Output as JSON
- `--clickable` - Use Godot Output panel clickable format
- `--help` - Show help

## Configuration

Edit `addons/godot-qube/analyzer/analysis-config.gd` to customize:
- Line limits (soft/hard)
- Function limits
- Complexity thresholds
- Excluded paths
- Allowed magic numbers
- TODO patterns

## Exit Codes (for CI)

- `0` - No issues found
- `1` - Warnings only
- `2` - Critical issues found

## License

MIT License

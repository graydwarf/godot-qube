# GDScript Linter - CLI/Headless Mode Feature

## Implementation Status: ✅ COMPLETE

**Implemented:** 2025-01-11

All features described below have been implemented. See `addons/gdscript-linter/CLI.md` for usage documentation.

### What Was Implemented

1. **Config System Overhaul**
   - JSON config format (`gdlint.json`) - save and load
   - Auto-sync from editor to `gdlint.json` on every setting change
   - "Export Config..." button for custom config files
   - CLI `--config` flag to specify alternate config

2. **CLI Enhancements**
   - Multiple paths as positional arguments
   - `--severity` filter (info, warning, critical)
   - `--check` filter (comma-separated check IDs)
   - `--github` output format for GitHub Actions annotations
   - Updated help text with examples

3. **Documentation**
   - `CLI.md` - comprehensive CLI documentation
   - CI/CD integration examples (GitHub Actions, GitLab CI)

### Breaking Changes

- Config format is now JSON (`gdlint.json`) - old `.gdlint.cfg` files are no longer supported
- **Action Required:** Bump version tag after merge

---

## Overview

Add CLI support to the gdscript-linter plugin so users can run analysis from the command line using Godot's headless mode. The CLI should use the same configuration as the in-editor plugin.

## Current State

- **Plugin location**: `addons/gdscript-linter/`
- **Existing CLI script**: `analyzer/analyze-cli.gd` (needs enhancement)
- **Configuration**: `analyzer/analysis-config.gd` - holds all check settings and thresholds
- **Core analyzer**: `analyzer/code-analyzer.gd` - performs the actual analysis
- **Ignore handling**: `analyzer/ignore-handler.gd` - processes `# gdlint:ignore-*` directives

## Requirements

### 1. Configuration Persistence

The plugin should save/load configuration so CLI uses the same settings as the editor:

- Save config to `res://addons/gdscript-linter/gdlint.json` (or `.gdlint` in project root)
- Load config on both editor startup AND CLI invocation
- If no config file exists, use defaults
- Editor UI should have "Save Config" button (or auto-save on change)

Example config file structure:
```json
{
  "check_function_length": true,
  "function_line_limit": 30,
  "function_line_critical": 50,
  "check_cyclomatic_complexity": true,
  "cyclomatic_warning": 10,
  "cyclomatic_critical": 15,
  "check_parameters": true,
  "max_parameters": 5,
  "check_nesting": true,
  "max_nesting": 4,
  "check_file_length": true,
  "file_line_limit": 500,
  "file_line_critical": 1000
}
```

### 2. CLI Script Enhancement (`analyze-cli.gd`)

Update to support headless execution:

```gdscript
# Should work when run as:
# godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- [options] <paths>
```

**Required functionality:**
- Parse command line arguments after `--`
- Load config from file (same as editor uses)
- Run analysis on specified files/directories
- Output results to stdout in readable format
- Exit with appropriate code (0 = clean, 1 = warnings, 2 = errors/critical)
- Support `--help` flag

**CLI Arguments to support:**
```
Usage: godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- [options] <paths>

Arguments:
  <paths>                 Files or directories to analyze (required)

Options:
  --help                  Show this help message
  --format <format>       Output format: text (default), json, github
  --severity <level>      Minimum severity to report: info, warning, critical
  --check <checks>        Comma-separated list of checks to run (default: all)
  --config <path>         Path to config file (default: res://gdlint.json)
  --no-config             Ignore config file, use defaults

Exit codes:
  0  No issues found
  1  Warnings found
  2  Critical issues found
```

### 3. Output Formats

**Text (default)** - Human readable:
```
addons/godot-ui-automation/core/test-executor.gd
  Line 737: [critical] high-complexity - Function '_execute_event' has complexity 54 (max 15)
  Line 421: [warning] long-function - Function '_run_replay_internal' exceeds 30 lines (158)

2 issues (1 critical, 1 warning)
```

**JSON** - Machine parseable:
```json
{
  "files": [...],
  "summary": {"total": 2, "critical": 1, "warning": 1, "info": 0}
}
```

**GitHub** - GitHub Actions annotation format:
```
::error file=test-executor.gd,line=737::Function '_execute_event' has complexity 54 (max 15)
::warning file=test-executor.gd,line=421::Function '_run_replay_internal' exceeds 30 lines (158)
```

### 4. Documentation

Add to plugin README or create `CLI.md`:

```markdown
## Command Line Usage

Run the linter from terminal using Godot's headless mode:

### Basic Usage

# Analyze a single file
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- path/to/file.gd

# Analyze a directory
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- addons/my-plugin/

# Analyze multiple paths
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- src/ tests/

### Options

# Show only critical issues
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- --severity critical src/

# Output as JSON
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- --format json src/

# Run specific checks only
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- --check high-complexity,long-function src/

### CI/CD Integration

GitHub Actions example:

```yaml
- name: Lint GDScript
  run: |
    godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- --format github addons/
```

### Configuration

The CLI uses the same configuration as the editor plugin. Configure via:
1. Editor plugin UI (settings are saved to `gdlint.json`)
2. Manually edit `gdlint.json` in project root
3. Use `--config` flag to specify alternate config file
```

## Implementation Steps

1. **Add config persistence to `analysis-config.gd`**
   - Add `save_to_file(path)` method
   - Add `load_from_file(path)` static method
   - Define default config file path

2. **Update editor dock (`dock.gd`)**
   - Load config on `_ready()`
   - Save config when settings change (or add explicit save button)

3. **Enhance `analyze-cli.gd`**
   - Add argument parsing (handle `--` separator from Godot args)
   - Load config file
   - Implement file/directory discovery
   - Run analysis using `code-analyzer.gd`
   - Format and print output
   - Call `get_tree().quit(exit_code)`

4. **Add output formatters**
   - Text formatter (default)
   - JSON formatter
   - GitHub Actions formatter

5. **Write documentation**
   - CLI usage in README or separate CLI.md
   - Examples for common use cases

## Files to Modify/Create

- `analyzer/analysis-config.gd` - Add save/load methods
- `analyzer/analyze-cli.gd` - Main CLI enhancement
- `dock.gd` - Add config persistence on settings change
- `CLI.md` or update `README.md` - Documentation
- `analyzer/output-formatter.gd` (new) - Output formatting logic

## Testing

After implementation, verify:

```bash
# Should show help
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- --help

# Should analyze and find issues
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- addons/godot-ui-automation/

# Should exit 0 on clean file
godot --headless --path . --script res://addons/gdscript-linter/analyze-cli.gd -- some-clean-file.gd
echo $?  # Should be 0

# Should use saved config from editor
# (Configure in editor first, then run CLI - should match)
```

## Notes

- Godot headless has ~2-3s startup overhead - acceptable for CI, may feel slow for interactive use
- The `--` in the command separates Godot args from script args
- Config file should be `.json` for easy manual editing
- Consider adding the CLI command as a shell alias in docs for convenience

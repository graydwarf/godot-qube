# GDScript Linter - Markdown Report Generator
# https://poplava.itch.io
@tool
extends RefCounted
## Generates AI-friendly Markdown code quality reports from analysis results

const IssueClass = preload("res://addons/gdscript-linter/analyzer/issue.gd")


static func generate(result, issues: Array, context: String = "") -> String:
	# Categorize issues by severity
	var critical: Array = []
	var warnings: Array = []
	var info: Array = []
	for issue in issues:
		match issue.severity:
			IssueClass.Severity.CRITICAL: critical.append(issue)
			IssueClass.Severity.WARNING: warnings.append(issue)
			IssueClass.Severity.INFO: info.append(issue)

	var md := ""

	# Header
	md += "# GDScript Linter - Code Quality Report\n\n"
	md += "Generated: %s\n" % Time.get_datetime_string_from_system()
	md += "Project: %s\n\n" % ProjectSettings.get_setting("application/config/name", "Unnamed Project")
	md += "---\n\n"

	# Context section
	if not context.is_empty():
		md += "## Context\n\n"
		md += context + "\n\n"
		md += "---\n\n"

	# Summary table
	md += "## Summary\n\n"
	md += "| Metric | Value |\n"
	md += "|--------|-------|\n"
	md += "| Files Analyzed | %d |\n" % result.files_analyzed
	md += "| Total Lines | %d |\n" % result.total_lines
	md += "| Total Issues | %d |\n" % issues.size()
	md += "| Critical | %d |\n" % critical.size()
	md += "| Warnings | %d |\n" % warnings.size()
	md += "| Info | %d |\n" % info.size()
	md += "| Debt Score | %d |\n" % result.get_total_debt_score()
	md += "\n---\n\n"

	# Issues grouped by file
	md += "## Issues by File\n\n"

	if issues.size() == 0:
		md += "*No issues found.*\n\n"
		return md

	var by_file: Dictionary = {}
	for issue in issues:
		if not by_file.has(issue.file_path):
			by_file[issue.file_path] = []
		by_file[issue.file_path].append(issue)

	# Sort files by issue count (descending)
	var file_paths := by_file.keys()
	file_paths.sort_custom(func(a, b): return by_file[a].size() > by_file[b].size())

	for file_path in file_paths:
		var file_issues: Array = by_file[file_path]
		md += "### `%s` (%d issues)\n\n" % [file_path, file_issues.size()]

		# Sort issues by line number
		file_issues.sort_custom(func(a, b): return a.line < b.line)

		for issue in file_issues:
			var severity_label := _get_severity_label(issue.severity)
			md += "- **Line %d** [%s]: %s (`%s`)\n" % [issue.line, severity_label, issue.message, issue.check_id]

		md += "\n"

	md += "---\n\n"

	# Metadata footer
	md += "## Metadata\n\n"
	md += "- **Generator**: GDScript Linter\n"
	md += "- **Analysis Time**: %dms\n\n" % result.analysis_time_ms
	md += "> Ask an AI: \"Review these issues and suggest fixes for each file.\"\n"

	return md


static func _get_severity_label(severity: int) -> String:
	match severity:
		IssueClass.Severity.CRITICAL: return "CRITICAL"
		IssueClass.Severity.WARNING: return "WARNING"
		IssueClass.Severity.INFO: return "INFO"
	return "UNKNOWN"

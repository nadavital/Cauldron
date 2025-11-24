---
description: Review recent Swift code changes with code-reviewer agent
allowed-tools: Task(code-reviewer:*)
---

Launch the **code-reviewer** agent to perform a comprehensive code review of your recent changes.

The agent will automatically:
1. Run `git diff` to see recent changes
2. Identify modified Swift files
3. Read those files in full context
4. Provide feedback organized by priority:
   - 🔴 Critical Issues (security, crashes, data loss)
   - 🟡 Warnings (bugs, performance, maintainability)
   - 🟢 Suggestions (style, readability, optimizations)
   - ✅ Positive Observations (good patterns)

Use the Task tool with:
- subagent_type: 'code-reviewer'
- prompt: 'Review the recent code changes in this repository. Focus on Swift best practices, CloudKit patterns, SwiftUI conventions, memory safety, and any potential issues. Be thorough and constructive.'

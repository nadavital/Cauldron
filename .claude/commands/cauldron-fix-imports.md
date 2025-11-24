---
description: Organize and fix Swift import statements
allowed-tools: Read, Edit, Grep
argument-hint: [file-path]
---

Organize Swift import statements in the specified file or recently modified files.

**Rules for Swift imports:**
1. Remove duplicate imports
2. Sort alphabetically
3. Group imports: Foundation first, then Apple frameworks, then third-party
4. Remove unnecessary imports (imports that aren't used)

**Process:**

If a file path is provided ($1), analyze and fix imports in that file.

Otherwise, find recently modified Swift files:
```
Find .swift files modified in the last git commit or working directory changes
```

For each file:
1. Read the current imports
2. Identify which frameworks are actually used in the file
3. Remove unused imports
4. Sort remaining imports alphabetically with proper grouping
5. Update the file with cleaned imports

Display summary of changes made.

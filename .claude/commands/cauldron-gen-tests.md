---
description: Generate comprehensive XCTest cases for Swift code
allowed-tools: Task(test-generator:*)
---

Launch the **test-generator** agent to create comprehensive test cases.

This agent specializes in:
- XCTest and XCTestCase patterns
- SwiftData mocking with TestModelContainer
- CloudKit mocking with MockCloudKitService
- AAA pattern (Arrange, Act, Assert)
- Edge case testing
- Following Cauldron's testing conventions

**Usage:**
- `/cauldron-gen-tests` - Then specify the file/service/feature to test
- The agent will ask for clarification if needed

**Example:**
```
/cauldron-gen-tests
> Generate tests for RecipeScaler in Core/Services/RecipeScaler.swift
```

The agent will:
1. Read the target file and understand its functionality
2. Identify edge cases and test scenarios
3. Generate comprehensive test cases with proper mocks
4. Follow Cauldron's test organization patterns

Use the Task tool with:
- subagent_type: 'test-generator'
- prompt: 'Generate comprehensive XCTest cases for the code the user specifies. Use TestModelContainer for SwiftData mocks and MockCloudKitService for CloudKit operations. Follow Cauldron testing conventions with AAA pattern, edge case coverage, and proper test organization.'

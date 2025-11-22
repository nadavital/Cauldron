---
description: Get expert iOS/Swift help with Apple frameworks and APIs
allowed-tools: Task(swift-ios-expert:*)
---

Launch the **swift-ios-expert** agent for expert guidance on iOS development.

This agent specializes in:
- Swift 5.0+ and modern concurrency (async/await, actors)
- SwiftUI and Combine
- CloudKit (sync, sharing, schema design)
- SwiftData and Core Data
- Apple Intelligence and FoundationModels
- iOS frameworks (WidgetKit, UserNotifications, App Intents, etc.)

The agent has access to **Apple Docs MCP** for accurate, up-to-date API information.

**Usage:**
- `/cauldron-ios-help` - General iOS question (agent will ask for specifics)
- Provide your question in the conversation after invoking

Use the Task tool with:
- subagent_type: 'swift-ios-expert'
- prompt: 'Help the user with their iOS/Swift development question. Use Apple documentation when needed for accurate API information. Provide clear explanations with code examples following Swift best practices.'

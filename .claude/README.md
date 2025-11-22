# Cauldron Claude Code Configuration

This directory contains custom Claude Code configurations to enhance your iOS development workflow.

## 📋 What's Included

### 1. Project Memory (`CLAUDE.md`)
Comprehensive documentation about Cauldron's:
- Architecture (Clean Architecture with SwiftUI + CloudKit)
- Technology stack and conventions
- Code organization and feature modules
- CloudKit sync patterns
- Testing conventions
- Common workflows

This gives Claude full context about your project in every conversation.

### 2. Slash Commands (`commands/`)

Quick commands for Cauldron-specific tasks (all prefixed with `cauldron-` for clarity):

**Build & Deploy:**
- **`/cauldron-build`** - Build Cauldron for iPhone 16 simulator
- **`/cauldron-install [device]`** - Build AND install on simulator/device
- **`/cauldron-test`** - Run XCTest suite with coverage report
- **`/cauldron-clean`** - Clean derived data and rebuild from scratch

**Code Quality:**
- **`/cauldron-fix-imports [file]`** - Organize Swift imports

**Expert Help (Agent Invokers):**
- **`/cauldron-review`** - Launch code-reviewer agent for recent changes
- **`/cauldron-ios-help`** - Launch swift-ios-expert agent for iOS/Swift questions
- **`/cauldron-gen-tests`** - Launch test-generator agent to create tests
- **`/cauldron-debug-cloudkit`** - Activate cloudkit-debugging skill

**Usage:** Just type `/cauldron-build` in your conversation with Claude Code.

**Why the prefix?** The `cauldron-` prefix makes it crystal clear these are project-specific commands, not generic ones. It also prevents namespace collisions with other projects or global commands.

### 3. Specialized Sub-Agents (`agents/`)

Expert AI assistants for specific tasks:

#### `swift-ios-expert`
- SwiftUI, CloudKit, and Apple frameworks specialist
- Has access to Apple Docs MCP for accurate API information
- Use for: Architecture questions, API usage, Apple best practices

**Invoke:** `/cauldron-ios-help` (guaranteed) or natural language

#### `code-reviewer`
- Swift code review specialist
- Automatically reviews recent git changes
- Checks: Quality, security, performance, Swift conventions, CloudKit patterns

**Invoke:** `/cauldron-review` (guaranteed) or natural language

#### `test-generator`
- XCTest specialist for comprehensive test generation
- Knows SwiftData and CloudKit mocking patterns
- Generates tests following Cauldron conventions

**Invoke:** `/cauldron-gen-tests` (guaranteed) or natural language

### 4. Smart Hooks (`settings.json`)

Automated workflows that run at specific times:

- **PostToolUse (Edit/Write)** - Notes when Swift files are modified
- **Stop** - Displays session summary when Claude finishes

These run automatically - no manual invocation needed.

### 5. Skills (`skills/cloudkit-debugging/`)

Model-invoked capabilities that Claude uses automatically:

#### `cloudkit-debugging`
- Activates when dealing with CloudKit issues
- Knows Cauldron's CloudKit architecture
- Helps with: Sync failures, sharing bugs, schema problems, CKRecord errors

**Activation:** `/cauldron-debug-cloudkit` (guaranteed) or automatic when you mention CloudKit issues

### 6. MCP Integration (`.mcp.json`)

External tool integrations:

- **apple-docs-mcp** - Access to Apple's Swift/SwiftUI/iOS documentation
  - Search official docs
  - Reference WWDC videos
  - Query API documentation

The `swift-ios-expert` agent uses this for accurate Apple framework information.

## 🚀 Quick Start

After setting up, you can:

1. **Build your app:**
   ```
   /cauldron-build
   ```

2. **Install on simulator:**
   ```
   /cauldron-install
   ```

3. **Run tests:**
   ```
   /cauldron-test
   ```

4. **Review your code:**
   ```
   /cauldron-review
   ```

5. **Get iOS expert help:**
   ```
   /cauldron-ios-help
   ```
   Then ask: "How should I structure this CloudKit relationship?"

6. **Generate tests:**
   ```
   /cauldron-gen-tests
   ```
   Then specify: "Generate tests for the ConnectionManager service"

7. **Debug CloudKit issues:**
   ```
   /cauldron-debug-cloudkit
   ```
   Then describe the sync/sharing problem you're facing

## 📁 Directory Structure

```
.claude/
├── CLAUDE.md                        # Project context & documentation
├── settings.json                    # Hooks configuration (team-shared)
├── settings.local.json              # Personal permissions (gitignored)
├── README.md                        # This file
├── commands/                        # Slash commands (all prefixed with cauldron-)
│   ├── cauldron-build.md            # Build app
│   ├── cauldron-install.md          # Install on device
│   ├── cauldron-test.md             # Run tests
│   ├── cauldron-clean.md            # Clean derived data
│   ├── cauldron-fix-imports.md      # Organize imports
│   ├── cauldron-review.md           # Launch code-reviewer agent
│   ├── cauldron-ios-help.md         # Launch swift-ios-expert agent
│   ├── cauldron-gen-tests.md        # Launch test-generator agent
│   └── cauldron-debug-cloudkit.md   # Activate cloudkit-debugging skill
├── agents/                          # Sub-agents
│   ├── swift-ios-expert.md          # iOS/Swift expert with Apple Docs
│   ├── code-reviewer.md             # Code review specialist
│   └── test-generator.md            # XCTest generator
└── skills/                          # Model-invoked skills
    └── cloudkit-debugging/
        └── SKILL.md                 # CloudKit debugging expertise
```

## 🔧 Customization

### Adding a New Slash Command

1. Create `commands/cauldron-my-command.md`:
```markdown
---
description: What this command does
allowed-tools: Bash, Read, Edit
---

Your command instructions here.
```

2. Use it: `/cauldron-my-command`

**Tip:** Always prefix with `cauldron-` to keep commands organized and avoid conflicts.

### Creating a New Sub-Agent

1. Create `agents/my-agent.md`:
```markdown
---
name: my-agent
description: What this agent does. Use when...
tools: Read, Write, Bash
---

Your agent instructions here.
```

2. Invoke: "Use my-agent to..."

### Updating CLAUDE.md

Edit `CLAUDE.md` to add:
- New architecture decisions
- Updated coding conventions
- Project-specific patterns
- Common gotchas

Claude reads this automatically in every conversation.

## 🎯 Best Practices

1. **Keep CLAUDE.md updated** - It's Claude's memory of your project
2. **Use slash commands** - Faster than typing full instructions
3. **Leverage sub-agents** - They're specialized experts
4. **Trust the hooks** - They automate tedious tasks
5. **Let skills activate automatically** - They know when they're needed

## 🛠 Troubleshooting

### Slash command not found?
- Ensure the `.md` file is in `commands/`
- Restart Claude Code to reload commands

### Sub-agent not working?
- Check the `description` field - it determines when Claude uses it
- Be explicit: "Use [agent-name] to..."

### MCP server issues?
- Verify `.mcp.json` configuration
- Check that npx can access `@kimsungwhee/apple-docs-mcp`
- Enable MCP servers in settings

### Hooks not running?
- Check `settings.json` syntax
- Review hook logs in Claude Code output
- Test with simple echo commands first

## 📚 Learn More

- **Claude Code Docs:** https://code.claude.com/docs/
- **Slash Commands:** https://code.claude.com/docs/en/slash-commands.md
- **Sub-Agents:** https://code.claude.com/docs/en/agents.md
- **Hooks:** https://code.claude.com/docs/en/hooks.md
- **MCP Servers:** https://modelcontextprotocol.io/

## ✨ What's Next?

Consider adding:
- Additional MCP servers (GitHub, Sentry if you use it)
- More slash commands for your specific workflow
- Project-specific code templates
- Additional skills for other problem domains

This setup is designed to grow with your needs. Start with what's here, then customize as you discover new patterns!

---

**Happy coding with Claude! 🚀**

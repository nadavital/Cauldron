---
description: Debug CloudKit sync, sharing, or schema issues
allowed-tools: Skill(cloudkit-debugging)
---

Activate the **cloudkit-debugging** skill to investigate CloudKit issues.

This skill provides systematic debugging for:
- **Sync Issues** - Records not syncing, conflicts, change tokens
- **Sharing Issues** - Share creation, participant access, permissions
- **Schema Issues** - Record type mismatches, field errors, type conversion
- **Performance Issues** - Slow queries, quota exceeded, batch failures

The skill knows Cauldron's CloudKit architecture:
- Container: `iCloud.Nadav.Cauldron`
- Custom zones and record types (`CD_Recipe`, `CD_Collection`, etc.)
- SwiftData ↔ CloudKit mapping
- Image handling with CKAssets
- Sharing patterns

**What to Provide:**
Describe the CloudKit issue you're experiencing:
- What operation is failing?
- Any error messages or codes?
- Which record types are affected?
- When did it start happening?

The skill will:
1. Read relevant CloudKit service code
2. Check recent git changes
3. Identify the root cause
4. Provide a fix with explanation
5. Suggest prevention strategies

Use the Skill tool with:
- skill: 'cloudkit-debugging'

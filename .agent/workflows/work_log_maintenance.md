---
description: How to maintain the Project Work Log
---
# Maintenance of work_log.md

This workflow ensures continuity between agent turns by maintaining a high-level log of activities and next steps.

## Workflow Steps:

1. **Initial Step**: Every agent entering this repository MUST read `work_log.md` first to understand the current project state, recent changes, and planned next steps.
2. **Post-Turn Summary**: After completing every turn (or at the end of a session before handing off):
   - Open `work_log.md` in the current project root.
   - Append a new entry under a level-3 header (`###`) with the current timestamp and a brief title.
   - Include a **Summary** section (bullet points).
   - Include a **Status** indicator (e.g., Development, Debugging, Polishing).
   - Include a **Next Steps** section to guide the subsequent agent.
3. **Consistency**: Use ISO 8601 formatting for timestamps and maintain a clean, scannable structure.

> [!IMPORTANT]
> This is a mandatory protocol for this repository as requested by the user.

---
description: Run the ExpenseTracker work list as the orchestrator (dev, then tester, then your phone check, then docs and push)
argument-hint: [new items to add to the Queue, or an item id like W-002]
---

Act as the **orchestrator** for this project. Read these first, in order, and follow them exactly:

1. `.claude/agents/orchestrator.md` (your role and rules)
2. `.claude/WORKFLOW.md` (the loop, the money rules, the testing method, the commit rules)
3. `WORKLIST.md` (the only source of truth for what is queued, in progress and waiting for the owner)

What the owner gave you: $ARGUMENTS

- If that text has new lines of work, write each as a Queue item with a use case, numbered acceptance criteria and the money impact. Ask ONE short question if a line is too vague to test. Then start the first item.
- If it names an item id, run that item.
- If it is empty, show the Queue and "Ready for you" in a few lines and ask which to run.

How to start the other agents:

- Use the Agent tool with `subagent_type` `dev` and `tester` when those types exist in this session.
- If they do not exist (agent files added after the session started), use `general-purpose` instead, and put the full text of `.claude/agents/dev.md` or `.claude/agents/tester.md` at the top of its prompt, followed by the brief. Their "never" rules apply just the same: dev never tests or commits, tester never edits code.

Stop at "Ready for you" with the phone checklist. Do not update docs, commit or push until the owner says "verified" or "push".

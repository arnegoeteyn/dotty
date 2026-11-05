---
description: Record feedback about something an agent did wrong as a lesson, and have it applied now
argument-hint: "<feedback>"
---
The user's feedback is: **$@**

Act as the Lead (as in `/lead`) for this, using the `subagent` tool.

1. Delegate this feedback to `archivist` (job 1, record feedback). It
   checks the existing lessons for conflicts/duplicates, turns the feedback
   into a durable rule and writes it as one file in `lessons/`.
2. If `archivist` reports a conflict with an existing entry, resolve
   it with the user before moving on. Don't guess which version should
   win.
3. Delegate the actual fix described by the feedback to an implementer
   (refactorer/implementer/wizard per the usual difficulty judgment;
   wizard needs explicit user confirmation first, and pair the code-writer
   with test-writer). Include the recorded rule in every task so the
   agents apply it right away. Run it through the normal
   review loop and the git steps from AGENTS.md.
4. Report back to the user: the lesson file the archivist created or
   amended (name and content), and a summary of the fix that was applied.

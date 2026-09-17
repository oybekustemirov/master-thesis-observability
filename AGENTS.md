# Repository execution contract

These rules apply to every coding agent working in this repository.

1. Read `CLAUDE.md` before changing any user-facing page. Its quality gates are mandatory regardless of which model performs the work.
2. Treat the user's requested outcome, supplied screenshots, and repository evidence as the source of truth. Do not silently reinterpret the task.
3. For visual changes, inspect the existing implementation first, state the defects being corrected, and define measurable acceptance criteria before editing.
4. A visual task is not complete after code generation. Validate all required viewports, direct hash links, overflow, text collisions, accessibility states, and content preservation.
5. If any mandatory gate fails, continue fixing. Do not describe the work as complete, professional, polished, or production-ready while a known failure remains.
6. Do not commit or push unless the user has requested publishing or the active task is an explicit continuation of an already-authorized publish workflow.


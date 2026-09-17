# Claude execution protocol — non-negotiable

This file is the standing task contract for Claude Code / Claude Sonnet work in this repository. Read it completely before editing. A request-specific brief may add constraints but may not weaken these gates.

## 1. Work from a closed contract

Before editing, write a short execution contract containing:

- exact files in scope;
- exact user-visible defects to correct;
- content/data that must remain unchanged;
- viewport and interaction states to verify;
- objective pass/fail acceptance criteria.

Do not expand scope, invent data, rewrite scientific claims, or replace the requested visual language. When requirements conflict, stop and report the conflict instead of guessing.

## 2. Mandatory visual hierarchy rules

- Every component must have one primary reading order and an obvious visual entry point.
- Labels, nodes, arrows, captions, navigation, and data marks must occupy reserved layout regions. Never place text in the same region as another component and hope scaling will make it fit.
- Maintain at least 16 px apparent separation between independent labels and component boundaries at the verified desktop viewport.
- No text may overlap, clip, truncate unintentionally, disappear beneath sticky UI, or cross a shape boundary.
- Desktop layouts must not inherit mobile overflow behaviour. Horizontal scrolling is allowed only for explicitly marked narrow-screen data/diagram regions.
- Colour must never be the only carrier of meaning.
- Dense scientific content must remain calm, editorial, and evidence-led. Avoid decorative UI that does not improve comprehension.

## 3. Mechanism-comparison diagram invariants

For `docs/mechanism-comparison.html`:

- The capture-path SVG must reserve a dedicated left label column.
- Mechanism labels must end before the first process node begins; no label may overlap `TXN_A1 write` or its border.
- The commit boundary must be visually aligned across all four rows.
- Each row must use the same node and arrow grid so mechanisms can be compared vertically.
- Edge labels (`trigger fires`, `poll`, `reads redo log`, `publish`) must sit above their own edge, not on a node border.
- All four Kafka nodes must share one x-position and size.
- The full diagram must remain legible at desktop width; at 390 px it may use a clearly signposted internal horizontal scroll region, but the page itself must never overflow horizontally.
- The caption must remain fully readable and must not be visually mistaken for part of the SVG.

Any violation is a failed task, not a minor follow-up.

## 4. Required verification matrix

Test the final page at all of these viewport classes:

| Viewport | Required proof |
|---|---|
| 390 × 844 | no page overflow; intentional internal scroll; readable labels and touch targets |
| 768 × 1024 | tablet breakpoint has no accidental desktop/mobile hybrid layout |
| 1280 × 720 | primary desktop acceptance screenshot and geometry checks |
| 1760 × 927 | wide-desktop rhythm, alignment, and line-length check |

Also test direct loads of `#matrix` and `#latency`. Each target must land below sticky navigation with the correct active navigation state.

For every visual task, report measured values rather than impressions:

- document `scrollWidth` versus `clientWidth`;
- navigation `scrollWidth` versus `clientWidth` on desktop;
- target top offset versus sticky-navigation height;
- duplicate IDs and broken internal hash targets;
- console errors;
- the result of `git diff --check`.

Capture and inspect screenshots at the required viewports. A successful build or valid HTML does not prove visual correctness.

## 5. Evidence and regression protection

- Read the entire target file and its source brief before changing it.
- Preserve every experimental number, caveat, section ID, table meaning, and source reference unless the user explicitly requests a content change.
- Compare the final diff against the original for accidental content loss.
- Do not add frameworks, packages, external fonts, network dependencies, or build steps to a self-contained static page unless explicitly authorized.
- Prefer semantic HTML and CSS. JavaScript is progressive enhancement only.

## 6. Definition of done

The task is complete only when all of the following are true:

1. Every request-specific acceptance criterion passes.
2. Every viewport in the verification matrix has been inspected.
3. There are no known collisions, clipping defects, broken anchors, page-level overflow, or misleading encodings.
4. Accessibility, dark mode, reduced motion, and print behaviour have been preserved or explicitly verified when touched.
5. The final report lists files changed, checks run, measured results, limitations, and whether commit/push occurred.

If a gate cannot be tested, state that explicitly and do not claim full completion. If a gate fails, continue iterating until it passes or report a concrete blocker.

## 7. Task prompt template

When delegating a visual task to Claude Sonnet, use this structure:

```text
Objective:
[One observable user outcome.]

Files in scope:
[Explicit list. No other files may change.]

Preserve exactly:
[Claims, values, anchors, semantics, modes, and content.]

Required implementation:
[Specific layout structure and behaviour.]

Forbidden outcomes:
[Overlap, clipping, page overflow, unapproved rewriting, dependency additions, etc.]

Acceptance gates:
[Measurable geometry, viewport, accessibility, and hash-link checks.]

Verification evidence required:
[Screenshots, DOM measurements, static checks, and diff review.]

Stop condition:
Do not mark complete, commit, or push while any gate fails. Report blockers instead of relaxing the contract.
```

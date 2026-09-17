# Senior UI redesign brief — mechanism comparison

## Objective

Redesign `docs/mechanism-comparison.html` as a polished, defence-ready research dashboard. It must let a thesis supervisor understand the decision and the strongest evidence within 30 seconds, while retaining every scientific claim, number, caveat, source reference, anchor, and Q&A answer.

The final page must remain a self-contained static HTML document suitable for GitHub Pages. Do not add packages, frameworks, build steps, external fonts, analytics, or network dependencies. Do not commit or push.

## Non-negotiable constraints

- Treat all experimental values and prose as source evidence, not copy to rewrite casually.
- Preserve the existing section IDs: `matrix`, `latency`, `silent`, `coverage`, `loe`, `refuted`, `recommend`, `config`, and `qa`.
- Preserve semantic HTML and improve it where possible.
- Preserve light mode, dark mode, and print support.
- Support keyboard navigation, visible focus, reduced motion, and WCAG-conscious contrast.
- Support 360 px mobile through wide desktop. No page-level horizontal overflow.
- Tables must remain understandable to screen readers and usable on touch devices.
- Avoid generic SaaS aesthetics, decorative gradients, glassmorphism, excessive shadows, oversized type, and gratuitous animation. The visual language should feel like a rigorous senior-designed scientific report: editorial, calm, data-led, and credible.

## Task 1 — Evidence and content audit

Read the entire current HTML plus `docs/empirical_comparison_results.md`. Inventory the page's sections, claims, figures, tables, caveats, code/configuration details, and interaction states. Identify any content that must not be lost. Do not change experimental claims or values.

## Task 2 — Information architecture

Rebuild the page hierarchy so it has three clear reading depths:

1. Executive scan: research question, four mechanisms, experiment scale, decisive findings, and primary recommendation logic.
2. Comparative evidence: matrix, latency/redo trade-off, semantic CDC failure, writer coverage, effort, and refuted predictions.
3. Audit trail: exact configuration and defence Q&A.

Make the current section navigation compact, legible, sticky, keyboard-friendly, and horizontally usable on mobile without wrapping into a large wall of buttons. Provide clear active/hover/focus states without adding a dependency.

## Task 3 — Hero and executive summary

Design an editorial hero that communicates the subject and experimental credibility immediately. Surface the experiment scale (`175` archived cells and approximately `720,000` transitions) and the four mechanism identities without inventing new conclusions. Add a compact “decision in one view” summary derived only from existing evidence:

- AQ: fastest, but highest redo and availability coupling.
- Outbox: moderate latency, application-writer contract required.
- CDC: near-zero writer overhead and full writer coverage, but seconds of latency and semantic logging risk.
- Hybrid: atomic outbox capture with CDC relay, but coverage still depends on every writer honouring the contract.

Use each mechanism's existing colour consistently across the full page, with labels/icons/patterns so colour is never the only carrier of meaning.

## Task 4 — Comparison matrix redesign

Turn the main matrix into the visual centrepiece. Improve row grouping, scanability, column identity, numeric alignment, status semantics, legends, and explanatory notes. Clearly distinguish “best on this metric,” “measured risk,” and “not statistically significant” without implying a single universal winner.

Desktop requirements: sticky header where appropriate, strong first-column hierarchy, stable column widths, and fast cross-column scanning.

Mobile requirements: do not merely squeeze or clip the desktop table. Provide an intentional comparison experience at 360–430 px—either a well-designed card/transposed layout or a controlled table pattern with sticky context and an explicit scroll cue. There must be no page-level horizontal scrollbar.

## Task 5 — Evidence visualisations

Redesign the existing latency bars and capture-path SVG so the relationship is understandable without reading surrounding paragraphs. Make the 560× latency spread and the inverse redo trade-off visually apparent without misleading linear encoding. Keep all labels readable on mobile and in dark mode.

Use compact evidence callouts for:

- the silent CDC semantic failure (9,003/9,003 counts while two-thirds of payloads were semantically empty);
- F11 writer-bypass coverage (AQ/CDC 0% loss versus Outbox/Hybrid 69%);
- F8 availability coupling (40% payment failure for AQ only);
- the three refuted predictions.

Do not create unsupported charts or scores.

## Task 6 — Recommendation experience

Make “Recommendation, by constraint” a clear decision aid rather than another dense table. A reader should be able to start with a constraint and immediately see the recommended mechanism, the reason, and the cost/trade-off. Preserve the nuance that there is no universal winner and keep the availability-coupling warning prominent.

## Task 7 — Long-form sections and configuration

Improve the reading rhythm of dense configuration content with semantic sub-sections, restrained panels, code wrapping, and progressive disclosure where it genuinely reduces cognitive load. Do not hide essential experimental limitations. Q&A should remain accessible `<details>` content with polished open/closed states and clear “Say:” guidance.

## Task 8 — Design system and implementation quality

Create a coherent token system for spacing, typography, colour, borders, radii, layout width, and mechanism identities. Consolidate repeated inline styles into meaningful classes. Prefer CSS over JavaScript; add only small progressive-enhancement JavaScript if necessary. The page must remain useful with JavaScript disabled.

## Task 9 — Responsive, accessibility, dark mode, and print

Verify at minimum 390×844 mobile and approximately 1280×720 desktop. Add robust breakpoints instead of one-off patches. Ensure:

- no clipped headings, labels, tables, SVG text, or code;
- minimum practical touch targets;
- logical heading order and landmarks;
- table captions or accessible labels where helpful;
- visible `:focus-visible` styles;
- `prefers-reduced-motion` handling;
- dark-mode contrast and semantic colours;
- print output that preserves evidence tables and removes only navigation/interactive chrome.

## Task 10 — Verification and handoff

After implementation:

1. Inspect `git diff -- docs/mechanism-comparison.html` for accidental content loss or changed values.
2. Run available local static/HTML checks that do not require installing dependencies.
3. Search for page-level overflow risks, remaining avoidable inline styles, duplicate IDs, and broken anchor targets.
4. Report exactly what changed, which checks ran, any limitations, and the file modified.

Do not edit experimental source documents or generated results. The deliverable is the redesigned `docs/mechanism-comparison.html` plus this brief.

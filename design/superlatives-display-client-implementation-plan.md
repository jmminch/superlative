# Superlatives Display Client Implementation Plan

## Status
Draft v1, February 18, 2026.

## Purpose
Document the display-client technology decision and define the phased plan for implementing the improved visual experience described in `design/superlatives-improved-display.md`.

## Decision Summary
Primary implementation approach:
- **Vanilla DOM + CSS + Web Animations API (WAAPI)**

Second-best fallback approach:
- **PixiJS (WebGL/canvas scene graph)**

Rationale:
- The display UI is primarily typography, card/grid layout, prompts, and scoreboard content with cinematic transitions.
- The repository currently serves static web assets without a JS build toolchain.
- DOM/CSS/WAAPI provides the best quality-to-effort ratio and lowest integration risk while still supporting polished motion design.

## Alternatives Considered
### 1. DOM + CSS + WAAPI (selected)
Advantages:
- Best fit for text-heavy, phase-based layouts.
- Fast iteration for motion, transitions, and responsive design.
- Works directly with current `web/` static hosting model.
- Lowest maintenance and onboarding cost.

Disadvantages:
- Complex particle-heavy effects are harder than WebGL approaches.

### 2. PixiJS (second choice)
Advantages:
- Strong for advanced reveal animation, particles, and visual effects.
- Frame-accurate animation control.

Disadvantages:
- More complex rendering/state architecture.
- Text and layout-heavy views are harder than in DOM.
- Higher integration and long-term maintenance overhead.

### 3. HTML Canvas 2D (not chosen)
Advantages:
- Full render control.

Disadvantages:
- Requires custom layout/rendering systems for text and UI components.
- High implementation complexity for this product shape.

### 4. SPA frameworks (React/Vue/Svelte; not chosen)
Advantages:
- Strong component models.

Disadvantages:
- Introduces tooling/build complexity not currently needed.
- Limited incremental benefit for this specific display client.

## Constraints and Non-Goals
Constraints:
- Keep compatibility with current server protocol payloads and state phases.
- Keep deployment model as static files under `web/`.
- Must perform well in fullscreen on 16:9 displays (target 1920x1080).

Non-goals in this effort:
- No rewrite of server state model.
- No required migration to WebGL/canvas architecture.
- No account/auth or gameplay rule changes.
- Sound effects are deferred for this milestone.

## Resolved Product Decisions
1. `GameStarting` behavior is in scope for this implementation, including:
   - first-game long instructional reveal,
   - later-game short title-only reveal,
   - host interrupt support.
2. Sound effects are out of scope for this milestone and deferred.
3. Lobby cards use placeholder/generated avatar icons for now.
4. Display UI styles move to a dedicated display-specific stylesheet.
5. External animation libraries are allowed if they provide clear delivery or quality benefits.

## Implementation Strategy
## Phase 0: Product Clarifications and Motion Spec
Deliverables:
- Resolved visual and motion decisions needed before coding.
- Reference timing table per phase transition.

Tasks:
- Confirm brand direction (color palette, typography, style references).
- Confirm animation timing/cadence and audio trigger policy.
- Confirm whether first-game vs subsequent-game intro text behavior is required in this scope.

Exit criteria:
- No unresolved product decisions that block implementation.

## Phase 1: Display UI Architecture Refactor
Deliverables:
- Structured display renderer modules in `web/display.js`.
- Stable render lifecycle for phase mount/update/unmount.

Tasks:
- Introduce phase-specific render functions:
  - `renderLobby`, `renderGameStarting`, `renderRoundIntro`, `renderEntryInput`, `renderVoteInput`, `renderVoteReveal`, `renderRoundSummary`, `renderGameSummary`.
- Add animation coordinator utilities for enter/exit transitions.
- Add shared helpers for timing, asset preloading, and resilient state updates.

Exit criteria:
- Existing behavior preserved with no visual redesign yet.

## Phase 2: Visual System Foundation
Deliverables:
- New display-focused design tokens in `web/client.css` (or display-specific CSS file).
- Responsive fullscreen layout framework for header area + gameplay area.

Tasks:
- Define CSS custom properties for colors, typography, spacing, and depth.
- Implement header area (game title + room code) with polished styling.
- Implement gameplay-area base layers (background treatment, overlays, readable content framing).

Exit criteria:
- Visual baseline applied across all display phases.

## Phase 3: Phase-by-Phase UI Buildout
Deliverables:
- Completed redesigned display screens for all game phases.

Tasks:
- Lobby:
  - Player card grid with join/leave transitions.
  - Placeholder avatar icons and animated card ordering.
- Game Starting:
  - Transition from lobby to game background.
  - Line-by-line instructional text reveal.
  - Alternate short intro path for subsequent games.
  - Host interrupt support for immediate continue.
- RoundIntro / EntryInput / VoteInput:
  - Large, clear category/prompt typography.
  - Strong visual hierarchy for “what players do now.”
- VoteReveal:
  - Animated reveal of set results and cumulative round points.
- RoundSummary / GameSummary:
  - Leaderboard emphasis with rank progression cues.

Exit criteria:
- All phases render with consistent visual language and readable hierarchy.

## Phase 4: Motion, Audio, and Timing Polish
Deliverables:
- Finalized transitions and timing polish.

Tasks:
- Tune transition durations/easing for each phase pair.
- Add staggered reveals and continuity motion where useful.
- Ensure animations remain deterministic when rapid state updates occur.

Exit criteria:
- No obvious jank; transitions feel intentional and synchronized.

## Phase 5: Performance, Reliability, and QA
Deliverables:
- QA pass complete on desktop and TV-like fullscreen usage.
- Regression checklist and bug fixes.

Tasks:
- Validate rendering performance on target hardware.
- Handle reconnects and out-of-order/rapid state events safely.
- Verify readability and scale at 1080p and smaller sizes.
- Verify behavior under multiple display clients in the same room.

Exit criteria:
- Stable multiplayer playthrough with redesigned display and no critical regressions.

## Testing and Validation Plan
Manual validation:
- Full game loop with 3+ players and one display client.
- Join/leave during lobby and in-round states.
- Host disconnect and reconnect scenarios.
- Long session with repeated rounds for animation memory/perf issues.

Automated support (where feasible):
- Add lightweight unit checks for display state mapping utilities.
- Add protocol/render smoke tests for phase routing logic.

## Risks and Mitigations
Risk:
- Scope growth in visual effects delays delivery.
Mitigation:
- Deliver per-phase visual baseline first; treat advanced effects as polish.

Risk:
- Animation race conditions with frequent state updates.
Mitigation:
- Centralize transition orchestration and cancel/replace policies.

Risk:
- Text readability on TV at distance.
Mitigation:
- Define minimum typography scales and contrast requirements early.

## Definition of Done
- Technology choice remains DOM/CSS/WAAPI and is documented.
- Display redesign implemented across all in-game phases.
- Animations and timing feel synchronized with server-driven phase changes.
- UI is readable and polished on fullscreen 16:9 displays.
- End-to-end multiplayer session is stable with display client active.

## Clarification Status
All blocking clarifications for implementation are resolved.

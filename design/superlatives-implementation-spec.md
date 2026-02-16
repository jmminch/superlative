# Superlatives Implementation Specification

## Status
Draft v1, created February 16, 2026.

## Purpose
Define a production-ready implementation specification for **Superlatives** as the sole game in this repository, with a migration path that reuses current infrastructure only temporarily and then removes all What If-specific logic/assets.

## Design Principles
- Server authoritative: all game truth and scoring live on the server.
- Deterministic transitions: explicit state machine with guarded transitions.
- Thin clients: clients render server state and send intent events.
- Extensibility first: support future twists (elimination, superlative voting, steal).
- Display + player separation: display client has role-specific state and controls.

## Scope
### In Scope (v1)
- Multiple rooms by room code.
- Two client roles:
  - `player`: phone/laptop participant.
  - `display`: shared screen view (TV/monitor).
- 3 rounds per game.
- Each round:
  - category reveal.
  - answer submission.
  - three superlative votes over the same answer set.
  - score updates after each vote.
- Return to lobby after final scoreboard.

### Out of Scope (v1)
- Full moderation tooling.
- Persistent accounts.
- Skill/rank matchmaking.
- Cross-room global leaderboards.

## Core Gameplay Rules (v1)
1. Host starts game from lobby.
2. For each round, server picks a category.
3. Every active player submits one free-text entry in the category.
4. Server runs exactly 3 vote phases, each with a superlative prompt.
5. In each vote phase, each active player picks one submitted entry.
6. Score pool is 1000 points per vote phase, distributed by vote share:
   - `round_points(entry) = floor(1000 * votes_for_entry / total_valid_votes)`
7. Entry owner receives that entry's points for that vote phase.
8. Optional tiebreak display rules do not alter scoring (show ties visually, keep proportional score).
9. Total game score is sum across 9 vote phases (3 rounds x 3 votes).

## Non-Functional Requirements
- Support 3-12 players in a room.
- Handle reconnect without losing player identity or score.
- No single client may force invalid transition.
- No server crash on malformed input.
- Idle/disconnected users should not block progression.

## Implementation Strategy (recommended)
Adopt these upgrades now to reduce future rewrite cost:
1. **Phase-based nested state model**
   - Replace a single flat enum with `GamePhase` + phase payload structs.
   - Example phase IDs: `Lobby`, `RoundIntro`, `EntryInput`, `VoteInput`, `VoteReveal`, `RoundSummary`, `GameSummary`.
   - Benefit: future twists become data/config changes instead of enum explosion.

2. **Typed protocol messages (JSON objects, no JSON-string-in-JSON)**
   - Replace `{"eventName":..., "data":"{...}"}` with `{"event":"state", "payload":{...}}`.
   - Add version field: `{"protocolVersion":1,...}`.
   - Benefit: safer decoding, clearer contracts, easier multi-client evolution.

3. **Role-scoped state payloads**
   - Build payload from one canonical snapshot, then project to role views:
     - display view (full board data).
     - player view (private flags, e.g., "you already voted").
   - Benefit: consistent display/player behavior and less duplicated rendering logic.

4. **Game configuration object**
   - Move constants into room config:
     - round count, timers, vote count per round, scoring mode.
   - Benefit: supports custom modes and test scenarios without hard-coded edits.

5. **Content provider abstraction**
   - Add `CategoryProvider` and `SuperlativeProvider` interfaces.
   - Seed from static JSON now; support curated packs later.
   - Benefit: clean pipeline for user-generated or seasonal content.

## Data Model

## Entities
### Room
- `code: String`
- `state: GamePhaseState`
- `hostPlayerId: String?`
- `config: RoomConfig`
- `players: Map<PlayerId, PlayerSession>`
- `currentGame: GameInstance?`
- `lastActivityAt: DateTime`

### PlayerSession
- `playerId: String` (server-generated stable ID in room)
- `displayName: String`
- `state: active | pending | idle | disconnected`
- `socket: WebSocketChannel?`
- `scoreTotal: int`
- `currentEntryId: EntryId?`
- `missedActions: int`

### GameInstance
- `gameId: String`
- `roundIndex: int` (0-based)
- `rounds: List<RoundInstance>`
- `scoreboard: Map<PlayerId, int>`

### RoundInstance
- `roundId: String`
- `categoryId: String`
- `categoryLabel: String`
- `entries: List<Entry>`
- `votePhases: List<VotePhase>` (length = config.votePhasesPerRound, default 3)
- `status: pending | active | complete`

### Entry
- `entryId: String`
- `ownerPlayerId: String`
- `textOriginal: String`
- `textNormalized: String`
- `status: active | eliminated | stolen` (future-proof)

### VotePhase
- `voteIndex: int`
- `superlativeId: String`
- `promptText: String`
- `votesByPlayer: Map<PlayerId, EntryId>`
- `results: VoteResults?`

### VoteResults
- `voteCountByEntry: Map<EntryId, int>`
- `pointsByEntry: Map<EntryId, int>`
- `pointsByPlayer: Map<PlayerId, int>`

## RoomConfig (defaults)
- `roundCount = 3`
- `votePhasesPerRound = 3`
- `entryInputSeconds = 30`
- `voteInputSeconds = 20`
- `revealSeconds = 12` (auto-advance fallback)
- `scorePoolPerVote = 1000`
- `allowSelfVote = true` (configurable)
- `maxEntryLength = 40`
- `minPlayersToStart = 3`

## State Machine

## Top-level phases
1. `Lobby`
2. `GameStarting` (score reset, player eligibility snapshot)
3. `RoundIntro`
4. `EntryInput`
5. `VoteInput`
6. `VoteReveal`
7. `RoundSummary`
8. `GameSummary`

## Transition rules
- `Lobby -> GameStarting`: host `startGame`, `activePlayers >= minPlayersToStart`.
- `GameStarting -> RoundIntro`: immediate.
- `RoundIntro -> EntryInput`: intro timer expires or host continue.
- `EntryInput -> VoteInput`: all eligible entries submitted or timeout.
- `VoteInput -> VoteReveal`: all eligible votes received or timeout.
- `VoteReveal -> VoteInput`: if more vote phases remain in round.
- `VoteReveal -> RoundSummary`: after final vote phase.
- `RoundSummary -> RoundIntro`: if more rounds remain.
- `RoundSummary -> GameSummary`: if last round complete.
- `GameSummary -> Lobby`: host end game or timeout fallback.

## Guardrails
- Ignore out-of-phase events.
- Ignore non-host control events.
- Enforce idempotency for duplicate events (same vote overwrite policy configurable; default last-write-wins before lock).

## Networking Protocol

## Envelope (recommended)
Server -> client:
```json
{
  "protocolVersion": 1,
  "event": "state",
  "payload": { "phase": "VoteInput", "room": "ABCD", "...": "..." }
}
```

Client -> server examples:
```json
{ "event": "login", "room": "ABCD", "name": "NOEL", "role": "player" }
{ "event": "login", "room": "ABCD", "role": "display" }
{ "event": "startGame" }
{ "event": "submitEntry", "text": "RACCOON" }
{ "event": "submitVote", "entryId": "e_12" }
{ "event": "advance" }
{ "event": "endGame" }
{ "event": "pong" }
```

## Required events
- Client -> server:
  - `login`, `logout`, `startGame`, `submitEntry`, `submitVote`, `advance`, `endGame`, `pong`
- Server -> client:
  - `success`, `error`, `state`, `ping`, `disconnect`

## Input and Validation Rules
- Names and room codes: current sanitizer baseline retained; optionally preserve mixed case in display while canonicalizing identifiers internally.
- Entry text:
  - trim, collapse internal whitespace.
  - reject empty post-sanitize.
  - enforce `maxEntryLength`.
  - optional dedupe policy (default: allow duplicates; flag collisions for UI).
- Votes:
  - `entryId` must exist and be vote-eligible.
  - if `allowSelfVote=false`, reject own entry vote.

## Scoring Specification
Per vote phase:
- `total_valid_votes = sum(voteCountByEntry.values)`
- If `total_valid_votes == 0`: no points awarded.
- Otherwise:
  - each entry gets proportional share of `scorePoolPerVote`.
  - assign points to entry owner.
- Rounding method:
  - floor shares, then distribute remaining points one-by-one to highest fractional remainders (deterministic tie break by `entryId`).

Rationale:
- Guarantees exact 1000 points distributed each vote phase.
- Removes tie-special-case complexity.
- Keeps feedback intuitive: more votes always means more points.

## Reconnect, Presence, and Host Failover
- Reconnect semantics:
  - duplicate login for same identity kicks previous socket.
  - reconnect restores active status.
- Improve identity handling:
  - generate server `playerId`; treat display name as mutable label.
- Host failover policy (recommended):
  - if host disconnects for > `hostGraceSeconds` (default 10), elect earliest active joiner.
  - display role never becomes host.

## Display Client Requirements
- Login with `role=display` and no player name.
- Display never votes/submits entries.
- Display shows:
  - room code + phase instructions.
  - category and superlative prompt.
  - live countdown.
  - reveal visualizations.
  - cumulative scoreboard.
- If multiple displays connect, all receive same display payload.

## Client UX Requirements
Player client:
- fast submit flow for free-text entry.
- clear "submitted" state and lock behavior.
- vote buttons with disabled/selected visuals.
- robust handling of reconnect and stale timers.

Display client:
- large typography and high-contrast vote/reveal layouts.
- no hidden controls except host controls when host is also on display (optional mode).

## Server Architecture Plan

## Recommended architecture
- Keep `GameRoom` as orchestrator; split logic by components:
  - `RoomStateMachine` (phase + transitions)
  - `GameEngine` (round/vote progression)
  - `ScoringEngine` (pure scoring functions)
  - `StateProjector` (display/player payload generation)
  - `ProtocolAdapter` (socket I/O + validation)
- Benefit: each component unit-testable in isolation.

## Content Data Format
Create new content file, example `data/superlatives.json`:
```json
{
  "categories": [
    {
      "id": "animals",
      "label": "Animals",
      "superlatives": ["Cutest", "Most likely to steal your lunch", "Best sidekick"]
    }
  ]
}
```

Rules:
- Category must have at least `votePhasesPerRound` superlatives.
- Select without replacement within round.
- Category reuse across rounds configurable (default false for 3-round game).

## Security and Abuse Guardrails
- Keep message length cap; raise carefully if needed for entry text payloads.
- Rate limit client events per socket (simple token bucket).
- Sanitize/escape all user text in UI rendering.
- Restrict control events (`startGame`, `advance`, `endGame`) to host only.
- Log invalid events with room + player identifiers.

## Testing Strategy

## Unit tests
- Transition validity matrix.
- Scoring edge cases:
  - zero votes.
  - one vote only.
  - ties/fractional rounding.
  - all votes on one entry.
- Entry validation and normalization.
- Host failover election.

## Integration tests
- Full 3-round game with deterministic seed.
- Reconnect during `EntryInput`, `VoteInput`, and `VoteReveal`.
- Host disconnect auto-advance/failover behavior.
- Display and player clients in same room.

## Manual test checklist
- 3+ players complete game with no disconnects.
- Late join during round marked pending and admitted next round (or next game per policy).
- Duplicate player name behavior is explicit and stable.
- Multiple displays render consistently.

## Observability
- Structured server logs by room/game/phase.
- Metrics counters:
  - active rooms
  - active players
  - reconnect count
  - invalid event count
  - average phase duration

## Rollout Plan
1. Implement protocol + data model scaffolding (flag may be used temporarily during development).
2. Implement server FSM and scoring engine with tests.
3. Implement player client views.
4. Implement display client views.
5. Run internal multiplayer playtests.
6. Cut over to Superlatives-only runtime and remove What If logic/assets.

## Open Decisions
1. Should self-voting be allowed by default?
2. Should duplicate entry texts be merged visually or shown separately?
3. Should pending joins enter next vote phase, next round, or next game only?
4. Should host controls be available from display role?

## Recommended Decisions (for first implementation)
- `allowSelfVote = true`.
- Duplicate entries allowed and shown as separate cards (ownership matters).
- Pending joiners enter at next **round**, not mid-round.
- Host controls remain player-only; display is read-only.

## Mapping to Current Code
- Use current room lifecycle/socket plumbing in `bin/game.dart` and `bin/server.dart` only as migration scaffolding.
- Replace question-target model with category/entry/vote model.
- Replace single client flow (`web/client.js`) with role-aware routes/screens.
- Keep existing `web/` static hosting model.
- Remove What If-specific codepaths/assets after Superlatives cutover is stable.

## Suggested File Additions/Refactors
- `bin/superlatives_game.dart` (new engine and state machine)
- `bin/protocol.dart` (typed event payload codecs)
- `bin/scoring.dart` (pure scoring functions)
- `data/superlatives.json` (content)
- `web/player.js` and `web/display.js` (role-specific clients)
- `web/display.html` (display entry point)

## Success Criteria
- A full 3-round game runs end-to-end with player + display clients.
- Timers, reconnects, and host controls behave deterministically.
- Score distribution matches specification and is test-covered.
- Architecture supports adding elimination/superlative-vote/steal twists without protocol redesign.
- Repository no longer contains runtime What If game code/assets.

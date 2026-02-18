# Superlatives Implementation Specification

## Status
Current v2, updated February 18, 2026.

## Purpose
Define the implemented, current behavior of **Superlatives** as the sole game in this repository.

## Design Principles
- Server authoritative: game state and scoring are server-owned.
- Deterministic transitions: explicit phase transitions with guarded controls.
- Thin clients: clients render projected state and send intent events.
- Role-aware projection: player and display payloads are derived from one canonical room snapshot.
- Extensibility: model leaves room for additional between-set twists.

## Scope
### In Scope (current)
- Multiple rooms by room code.
- Two client roles:
  - `player`: participant.
  - `display`: shared read-only screen.
- 3 rounds per game.
- Each round:
  - category reveal.
  - entry submission.
  - 3 vote sets x 3 prompts (9 prompts total).
  - set-end reveal using cumulative round points.
  - elimination after set 1 and set 2.
  - round-end scoreboard application.
- Return to lobby after final scoreboard.

### Out of Scope (current)
- Persistent accounts.
- Skill/rank matchmaking.
- Cross-room global leaderboard.
- Multiple twist randomization (only elimination twist implemented).

## Core Gameplay Rules
1. In `Lobby`, any active player may start the game.
2. The first accepted `startGame` event assigns `hostPlayerId`.
3. For each round, server selects one category.
4. Each active player submits one free-text entry.
5. Round voting is 3 sets x 3 prompts.
6. Set flow is asynchronous per player:
   - each player answers prompt 1, then 2, then 3 for the active set.
   - players do not wait for each other between prompts.
7. A set resolves when all active players finish the set or the set timer expires.
8. Missing votes at timeout are treated as no-votes.
9. Prompt scoring uses proportional 1000-point pool allocation.
10. Prompt points accumulate in `roundPointsByEntry` during the round.
11. Global player totals update once per round at round summary.
12. Elimination checkpoints:
   - after set 1: eliminate bottom third, keep at least 3.
   - after set 2: eliminate bottom half, keep at least 2.
   - ties at cutoff are kept together.
13. When only 2 active entries remain, self-vote is allowed.

## Data Model
### Room
- `code: String`
- `state: GamePhaseState`
- `hostPlayerId: String?`
- `config: RoomConfig`
- `players: Map<PlayerId, PlayerSession>`
- `currentGame: GameInstance?`

### PlayerSession
- `playerId: String`
- `displayName: String`
- `state: active | pending | idle | disconnected`
- `socket: WebSocketChannel?`

### GameInstance
- `gameId: String`
- `roundIndex: int`
- `rounds: List<RoundInstance>`
- `scoreboard: Map<PlayerId, int>`

### RoundInstance
- `roundId: String`
- `categoryId: String`
- `categoryLabel: String`
- `entries: List<Entry>`
- `sets: List<VoteSet>`
- `roundPointsByEntry: Map<EntryId, int>`
- `status: pending | active | complete`

### Entry
- `entryId: String`
- `ownerPlayerId: String`
- `textOriginal: String`
- `textNormalized: String`
- `status: active | eliminated`

### VoteSet
- `setIndex: int`
- `prompts: List<VotePromptState>`
- `status: pending | active | reveal | complete`

### VotePromptState
- `promptIndex: int`
- `superlativeId: String`
- `promptText: String`
- `votesByPlayer: Map<PlayerId, EntryId>`
- `results: VoteResults?`

### VoteResults
- `voteCountByEntry: Map<EntryId, int>`
- `pointsByEntry: Map<EntryId, int>`
- `pointsByPlayer: Map<PlayerId, int>`

## RoomConfig Defaults
- `roundCount = 3`
- `setCount = 3`
- `promptsPerSet = 3`
- `entryInputSeconds = 30`
- `setInputSeconds = 45`
- `revealSeconds = 12`
- `scorePoolPerVote = 1000`
- `allowSelfVote = true`
- `maxEntryLength = 40`
- `minPlayersToStart = 3`

## State Machine
### Top-Level Phases
1. `Lobby`
2. `GameStarting`
3. `RoundIntro`
4. `EntryInput`
5. `VoteInput`
6. `VoteReveal`
7. `RoundSummary`
8. `GameSummary`

### Transition Rules
- `Lobby -> GameStarting`: accepted `startGame` and minimum players met.
- `GameStarting -> RoundIntro`: immediate.
- `RoundIntro -> EntryInput`: timer expires or host advance.
- `EntryInput -> VoteInput`: all entries in or timeout.
- `VoteInput -> VoteReveal`: active set resolves.
- `VoteReveal -> VoteInput`: next set exists.
- `VoteReveal -> RoundSummary`: final set resolved.
- `RoundSummary -> RoundIntro`: more rounds remain.
- `RoundSummary -> GameSummary`: final round complete.
- `GameSummary -> Lobby`: host end or timeout fallback.

### Guardrails
- Ignore out-of-phase events.
- Non-host controls rejected outside lobby start semantics.
- Duplicate votes before prompt lock are idempotent with deterministic overwrite behavior.

## Networking Protocol
### Envelope
Server -> client:
```json
{
  "protocolVersion": 1,
  "event": "state",
  "payload": { "phase": "VoteInput", "room": "ABCD" }
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

### Required Events
- Client -> server: `login`, `logout`, `startGame`, `submitEntry`, `submitVote`, `advance`, `endGame`, `pong`
- Server -> client: `success`, `error`, `state`, `ping`, `disconnect`

## Projection and Privacy Contract
- During round phases before summary:
  - owner identity is hidden in player-facing entry lists.
  - vote/reveal display cumulative round points by entry.
- `VoteInput` includes set progress fields and player-local prompt progress.
- `RoundSummary` includes per-player row data:
  - total score
  - submitted entry text
  - points earned this round
- `RoundSummary` also includes top-entry results per superlative with deterministic tie ordering.

## Scoring Specification
Per prompt:
- `totalValidVotes = sum(voteCountByEntry.values)`
- If zero votes: no points.
- Else: proportional allocation from `scorePoolPerVote`.
- Rounding: floor shares, then assign remainder by highest fractional remainder with deterministic tie-break by `entryId`.

Round scoring:
- Prompt points aggregate into `roundPointsByEntry`.
- At round end, entry totals map to owners and are applied once to `GameInstance.scoreboard`.

## Reconnect and Presence
- Reconnect restores player identity in room.
- Duplicate login for same identity replaces prior socket.
- Disconnected/idle players do not block progression.

## Testing Requirements
- State transitions and timeout paths.
- Set-based engine lifecycle and timeout behavior.
- Elimination rules including tie-at-cutoff behavior.
- Deferred scoreboard application at round end.
- Projector privacy assertions (no owner leak pre-summary).
- Runtime tests for lobby start race and host assignment.

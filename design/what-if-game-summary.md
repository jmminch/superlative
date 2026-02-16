# What If? Game and Design Summary

## Purpose and Core Loop
What If? is a synchronous social party game. Players join a shared room, answer multiple-choice prompts about one target player, and try to pick the answer that gets the most votes from the group.

Core loop:
1. Players join lobby with `name` + `room`.
2. A player starts the game and becomes host.
3. For each question, everyone votes on one answer.
4. Host reveals results and advances.
5. After the question limit, final standings are shown and host ends the game.

The design assumes players can talk to each other (in person or voice/video chat).

## Gameplay Rules
- Questions are “If ___ were ...” style prompts where `___` is replaced with the target player name.
- Each question shows up to 6 answers.
- Players score by matching the most popular answer.
- Target player gets a penalty if they fail to pick the winning answer.

Scoring (`bin/game.dart`):
- Winning answer voters:
  - `+1000` if one answer is uniquely most popular.
  - `+500` if two answers tie for most popular.
  - `+250` if 3+ answers tie for most popular.
- No one scores if no majority signal exists (`max votes <= 1`).
- Target penalty: `-500` if target picked a non-winning answer (applies only when scoring is active).

## Match Structure
- Default game length: 12 total questions.
- Questions are grouped into rounds based on targets:
  - Active players are shuffled.
  - Each question targets one player from that shuffled list.
  - When target list is exhausted, next round reshuffles active players.
- If question bank is exhausted, it refreshes from master list and reshuffles.

## Player Lifecycle and Presence Model
Player states (`PlayerState`):
- `pending`: joined during active play; can fully join on next question/lobby.
- `active`: normal participant.
- `idle`: connected but not answering; server does not block waiting for them.
- `disconnected`: socket dropped; can reconnect as same name.

Behavior details:
- Missing answers increments `missedQuestions`.
- Player becomes `idle` after missing 2 in a row, or missing the very first question.
- Reconnecting a known player restores them to active.
- If duplicate login occurs for same name, prior socket is told to disconnect.

## Room and Host Behavior
- Room code defines game instance. Names and room codes are uppercased/sanitized.
- First created player is initial host, but pressing “Start Game” sets host to that player.
- Host controls reveal/continue/final completion.
- If host disconnects during reveal/results/final, server auto-advances with timers.
- Room is considered defunct if all players are disconnected and host has been gone >= 5 minutes; next login recreates room.

## State Machine (Server-Authoritative)
Game states:
- `Lobby`
- `GameSetup`
- `RoundSetup`
- `Countdown` (3s)
- `Question` (~31s answer window)
- `ConfirmResults` (host reveal gate)
- `Results`
- `Final`

Transition style:
- Strict allowed transitions are enforced in `changeState`.
- Timers drive countdown/question timeout and host-fallback progression.
- Client is a thin renderer of server state; server is source of truth.

## Networking and Protocol
Transport:
- WebSocket for gameplay events.
- Static files served from `web/` by same Dart process.

Envelope format:
- Server -> client: `{ "eventName": "...", "data": "..." }` where `data` is usually JSON string for state.
- Client -> server: JSON with `"event"` plus payload.

Key client events:
- `login`, `startGame`, `answer`, `doConfirmResults`, `doCompleteResults`, `doCompleteFinal`, `endGame`, `logout`, `pong`

Key server events:
- `success`, `error`, `state`, `ping`, `disconnect`

Resilience:
- Ping/pong keepalive every 30s; disconnect after repeated misses.
- Browser client auto-reconnects unless server explicitly sends `disconnect`.

## Content Pipeline
- Authoring source: `data/questions.yaml`.
- Runtime source: `data/questions.json`.
- Make target `questions` converts YAML -> JSON via `yaml2json`.
- `Question.getAnswers()` enforces max 6 displayed answers by randomly dropping extras while keeping order of remaining entries.

## Frontend/UI Design
- Plain HTML/CSS/JS in `web/` (no framework).
- Single-page, screen-swapping UI (`login`, `lobby`, `answer`, `results`, `final`).
- Mobile-friendly layout with sticky header and simple controls.
- Minimal visual language: card chips for players, highlighted winning answers, visible countdown/timers.

## Security and Input Guardrails
- Incoming message size capped (1024 bytes).
- Login inputs sanitized:
  - Uppercased.
  - Non-ASCII removed.
  - HTML-sensitive chars stripped.
  - Trimmed; empty rejected.
- No authentication/account system; identity is room + displayed name.

## Operational/Engineering Notes
- Backend: Dart + Shelf + `shelf_web_socket` + `shelf_static`.
- Single process serves API and static client.
- Port and listen IP configurable via environment (`PORT`, `LISTENIP`).
- Optional room suffix format `ROOM:N` (while in lobby) limits question list to last `N` questions.
- Special `_DEBUG...` room names disable question shuffle for deterministic testing.

## Design Patterns Worth Reusing
- Server-authoritative finite-state machine with explicit transition rules.
- Lightweight websocket event protocol with one canonical `state` payload.
- Resilient session model (reconnect, host failover, pending joiners).
- Data-driven content with simple offline build step.
- Frontend kept intentionally thin to simplify future gameplay changes.

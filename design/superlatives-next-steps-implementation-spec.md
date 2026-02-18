# Superlatives Next Steps Implementation Spec

## Status
Completed v1, updated February 18, 2026.

## Purpose
Capture the implemented behavior for the release-blocking items from `design/superlatives-next-steps.md`, including exact gameplay, server-control, and player-UI behavior.

## Scope
In scope:
- Set-based voting (3 sets per round, 3 superlatives per set, 9 superlatives total per round).
- Set-end scoring and between-set elimination twist.
- Lobby start control change: any player can start; starter becomes host.
- Player client usability and reveal/privacy changes listed in next steps.

Out of scope:
- Random selection across multiple twist types (only elimination twist implemented now).
- New account/auth model.
- Display-client redesign beyond data compatibility.

## Implemented Behavior Summary
- Round structure is 3 sets x 3 prompts each.
- Scoring accrues to per-entry round points during sets; player totals update once at round end.
- Elimination occurs after set 1 and set 2 before next set begins.
- Player attribution remains hidden until round summary.

## Functional Requirements

## 1. Round and Set Model
- Each round contains exactly 3 sets (configurable later, fixed now).
- Each set contains exactly 3 superlative prompts (configurable later, fixed now).
- Total prompts per round: 9.
- Content validation: each category must include at least 9 unique superlatives.

Data model additions:
- `RoundInstance`
  - `sets: List<VoteSet>` (length 3).
  - `roundPointsByEntry: Map<EntryId, int>` cumulative across completed prompts in this round.
  - `roundPointsByPlayerPending: Map<PlayerId, int>` derived at round end only.
- `VoteSet`
  - `setIndex: int` (0..2)
  - `prompts: List<VotePromptState>` (length 3)
  - `status: pending | active | reveal | complete`
- `VotePromptState`
  - `promptIndex: int` (0..2 within set)
  - `superlativeId`, `promptText`
  - `votesByPlayer: Map<PlayerId, EntryId>`
  - `results: VoteResults?`

## 2. Set-Based Voting Flow
- Entry input remains a single pre-set phase.
- After entry close:
  - Open set 1 prompt 1.
  - Each player submits votes for prompts 1, 2, 3 sequentially.
- Server tracks each player’s current prompt index for the active set.
- A player can continue to next prompt immediately after voting; no need to wait for others.
- Set resolves when all active players submitted all 3 prompt votes or set timer expires.

Timing:
- Add `setInputSeconds` config (default 45 seconds).
- Timer is set-level, not per prompt.
- If set timer expires, missing votes are treated as no-vote for those prompts.

## 3. Scoring Semantics
- Each prompt still has a 1000-point pool and proportional allocation by vote share (existing scoring math retained).
- Prompt results are accumulated into `roundPointsByEntry` (not yet added to global player scores).
- During round, reveal UI shows each entry’s cumulative points gained in this round so far.
- At round end:
  - Convert `roundPointsByEntry` to `roundPointsByPlayerPending` by entry owner.
  - Add those points to `GameInstance.scoreboard`.
  - Round summary shows total score, submitted entry, and points earned this round.

## 4. Elimination Twist (only twist in v1)
- Trigger after set 1 and set 2 resolves.
- After set 1:
  - Eliminate bottom third of active entries by current `roundPointsByEntry`.
  - Always keep at least 3 entries active.
- After set 2:
  - Eliminate bottom half of remaining active entries.
  - Always keep at least 2 entries active.
- Eliminated entries cannot receive votes in subsequent sets.

Tie handling at elimination cutoff:
- Keep all tied entries at the cutoff (entry count may exceed the nominal keep target).

## 5. Lobby Start/Host Rule
- In `Lobby`, any active player may send `startGame`.
- Player who successfully starts game becomes `hostPlayerId`.
- If multiple start events race, first accepted event wins host assignment.
- Existing host-only control rules remain for `advance` and `endGame` after game starts.

## 6. Player Client UX Requirements
- Remove visible internal phase label from header.
- Hide `leave room` button when not in room.
- Replace numeric countdown with progress bar timer.
- For entry timeout extension loops, keep bar empty (do not visually refill each 5-second extension).
- Entry screen copy:
  - Header unchanged.
  - Prompt body becomes `Enter a <category>`.
  - Minimal layout: prompt, text input, submit button.
- Pressing Enter in entry input submits (same as submit button).
- Hide all submitted entries from players until entry input closes.
- Voting header:
  - Remove `Vote #`.
  - Show only `Which of these is the <superlative>?`.
- During round phases before round summary:
  - Do not show entry owner names.
  - Reveal shows cumulative round points per entry, not owner attribution.
- Round summary:
  - Show each player’s total score.
  - Show that player’s submitted entry for the round.
  - Show points earned during this round.
  - If an entry was eliminated earlier in the round, still show that original entry text and points earned before elimination.

## 7. Payload/Projection Contract Changes
- Add role-safe, phase-safe projection fields needed for set progress and privacy:
  - `round.currentSetIndex`
  - `round.setPromptCount`
  - `round.currentPromptIndexForYou` (player only)
  - `round.setTimeoutSeconds`
  - `vote.promptText`/`vote.superlativeId` projected per-player from that player's current prompt index during `VoteInput`.
  - `round.entries` should omit `ownerDisplayName` until round summary.
  - `reveal.roundPointsByEntry` cumulative map.
  - `roundSummary.playerRoundResults[]` with `{ playerId, displayName, totalScore, entryText, pointsThisRound }`.
  - `roundSummary.superlativeResults[]` with:
    - `{ superlativeId, promptText, topEntries[] }`
    - each `topEntries` row: `{ rank, entryId, entryText, ownerDisplayName, voteCount }`
    - max 3 rows, zero-vote entries excluded, deterministic tie-break by `entryId`.
- Keep existing envelope format (`protocolVersion`, `event`, `payload`) unless intentionally versioned.

## 8. Testing Requirements
- Engine/state tests for:
  - 3-set lifecycle with sequential per-player prompt progression.
  - Early completion when all players finish set.
  - Set timeout with partial votes.
  - Elimination counts and minimum-keep rules.
  - Deterministic elimination tie behavior.
  - Deferred scoreboard application until round end.
- Projector tests for:
  - Hidden owner attribution pre-summary.
  - Round-summary per-player entry and round points.
  - Progress/timer payload shape.
- Runtime/integration tests for:
  - Any-player start sets host to starter.
  - Start race semantics: first accepted start event wins host assignment.
  - Non-host cannot advance after start.
  - End-to-end 1 round with eliminations across two checkpoints.

## Resolved Product Decisions
1. Set timer:
   - `setInputSeconds = 45` for all sets.
2. Elimination ties:
   - Keep ties together at cutoff even if this exceeds nominal keep counts.
3. Very small pools:
   - When only 2 active entries remain, allow self-voting regardless of `allowSelfVote`.
4. Reveal cadence:
   - Reveal once per set (not per prompt).
5. Round summary for eliminated entries:
   - Always show original entry text and round points earned before elimination.
6. Lobby start race:
   - First accepted `startGame` event becomes host.

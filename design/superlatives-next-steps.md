# Next Steps (Completed)

This document captures the release-blocking Superlatives enhancements that
have now been implemented.

## Gameplay

- Rounds now use streamlined set-based voting.
- Each round has 3 sets, each set has 3 superlatives (9 total prompts per
  round).
- Players progress through set prompts sequentially without waiting for all
  other players between prompts.
- Scoring resolves from collected set responses and timeout behavior.
- Elimination twist is implemented:
  - after set 1, bottom third is eliminated while keeping at least 3 entries.
  - after set 2, bottom half is eliminated while keeping at least 2 entries.

## Server

- Any active lobby player can start the game.
- The first accepted `startGame` event becomes the host assignment.

## Player Client

- Internal phase labels are hidden.
- `Leave room` is hidden when not in a room.
- Timer is an unobtrusive progress bar instead of a numeric countdown.
- Entry-timeout extension loops keep the timer bar visually empty.
- Entry prompt is simplified to `Enter a <category>` with input and submit.
- Pressing Enter in the entry input submits.
- Other players' entries remain hidden until entry input closes.
- Voting prompt removes `Vote #` and uses plain question wording.
- Entry ownership is hidden until round summary.
- During round reveal, UI shows cumulative round points per entry.
- Round summary shows each player's total score, submitted entry, and points
  earned that round.

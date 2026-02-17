# Next Steps

This document describes desired enhancements to Superlatives before it is
ready for release.

## Gameplay

- Each round will have more votes, but they will be streamlined. Players
  will be asked to vote on entries for multiple superlatives (probably three
  at once, call this a "set") sequentially without needing to wait for all
  other players. The server will track all the votes and then resolve the
  scoring after all the responses are in or the timer expires.
- There will be 3 sets in a round (initial implementation), for a total of
  voting on 9 superlatives. So each category needs at least that many
  potential superlatives associated with it.
- Between sets, various twists can happen. These will eventually be selected
  randomly. The first one that I want to implement is to eliminate some of
  the lower-scoring entries. If this one occurs, then after the first set,
  the bottom third of entries will be eliminated (always keeping at least 3
  entries.)  After the second set, then half of the remainder will be
  eliminated (keeping at least 2 entries)

## Server

- At the game lobby phase, any player should be able to start the game. That
  player will become the host.

## Player client

Several improvements to the player client are needed to make it more usable
and visually appealing.

- The internal "phase" should not be displayed on the client.
- The "leave room" button should be hidden when not in a room.
- rather than a timer showing seconds, I would like an unobtrusive progress
  bar that empties until the timer expires.
- When the entry input timer is extended past the normal timeout, the client
  should simply show an empty timer rather than resetting to 5 seconds and
  counting down over and over.
- The submit entry page has too much text. Below the header, I would like
  the prompt to simply say "Enter a *xxx*" (where xxx is the category) with
  a text box and a submit button.
- Pressing enter in the submit entry text box should be an alternative to
  clicking the submit button.
- Other players' entries should not be shown until entry input closes.
- The voting interface should get rid of the header that says "Vote #".
  Instead it should just say "Which of these is the *xxx*" where xxx is the
  superlative.
- The interface should not reveal which player submitted which entry until
  the end of the round. The vote reveals during the round should show
  instead how many points each entry has gained during the round, and then
  those points will be added to the player's scores at the end of the round.
  The round summary should show each player's score, and their entry and how
  many points they earned during this round.


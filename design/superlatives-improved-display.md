The display will still be a browser client. I am targeting full-screen mode
on a 16:9 display such as a 1080p TV. The display should look professional,
and use visuals that are consistent with the "party game" aesthetic.

We should discuss whether the best framework for this would be to use DOM
objects, or render to HTML canvas, or use another framework.

There will be a persistent header that shows the name of the game and the
room code, which players can use to join the in-progress game. The following
is my vision for how the display client will look and behave in the
different phases. Pixel dimensions given are assuming a resolution/window
size of 1920x1080; we may need to scale them for different resolutions.

I will refer the the header as the "header area"; it occupies the full width
of the top 15% of the display window. The remaining portion of the display
will be referred to as the "gameplay area".

In phases where the timer bar is visible, it should be placed along the
bottom of the screen.

- Lobby Phase
    - Show cards with all logged-in players. Each card has the player's name
      and an avatar icon (size 128x128) that will represent them.
    - When a new player logs in or disconnects, there will be an animated
      transition for the card to appear or disappear.
    - There will also be a sound effect played when players log in or
      disconnect.
    - There will be a lobby background image displayed behind the UI
      elements.
    - No timer bar visible in this phase
    
- Game Starting Phase
    - This phase will be used to present the game to the players (who may
      not have played before.)
    - There will be an animated transition between the lobby and game start.
      The lobby background and player cards (everything in the gamplay area)
      will fade out and be replaced by a "game background" image.
    - The game background image will be used for all remaining phases until
      the Game Summary Phase.
    - Then there will be text that appears, starting at the top of the
      gameplay area, revealed line by line with a short delay for each line.
      It will start with the centered text "the game of SUPERLATIVES", and
      then will follow with a short 1-paragraph explanation of the game.
    - The phase will wait a short time (15 seconds) after all the text is
      displayed to give sufficient time for players to read it before moving
      to the first round.
    - After the first game of a session, instead of showing the
      instructions, only the text "the game of SUPERLATIVES" will be shown.
      After 5 seconds, the phase will automatically move to the next round.
    - Some changes in behavior outside the display client are required:
        - Waiting for the appropriate time to transition to the next phase
        - Telling the display client whether to show the explanatory text or
          not
        - The host player should be able to interrupt the delay from the
          player client and immediately move the the next phase.
    - No timer bar visible in this phase

- Round Intro Phase
    - This phase is used to display the category and the superlatives that
      will be used for the first set.
    - The superlatives for the later sets will not be visible.
    - At the top in large centered text will be the category name
    - Below it will be the first three superlatives, in a horizontal row.
    - No timer bar visible in this phase

- Entry Input Phase
    - Display will keep the category text and first set superlatives
      visible.
    - Below the superlatives will be cards for each player showing the
      player and their avatar icon. Each player's card starts dimmed
    - When a player submits an entry, the associated player's card is
      highlighted.
    - A sound effect will be played when a player submits their entry.
    - The timer bar is visible in this phase.

- Vote Input Phase
    - Display layout will be similar to the Entry Input phase display
      layout.
    - Again, the player cards start dimmed.
    - When a player has completed all votes for the set, then that player's
      card is highlighted.
    - A sound effect will be played when a player completes voting.
    - The timer bar is visible in this phase.

- Vote Reveal Phase
    - There should be an animated transition to clear the elements from the
      vote input phase gameplay area
    - The top three vote-getters for each superlative will be revealed,
      along with how many points each of those entries earned.
    - This will be done one superlative at a time, with a delay in between.
    - For each superlative, there will be centered text with the
      superlative, and then below it will appear the three top entries, in a
      horizontal row.
    - Next to each entry will be listed a number of points with a '+'; the
      layout will look something like this:
```

                     Biggest
Elephant +400       Horse +200       Iguana +100
```
    - There will be a sound effect played when the votes are revealed for
      each superlative.
    - After a delay, then the gameplay area will be cleared and replaced
      with a list of all entries, sorted from most points earned so far to
      least. The list will show the entry, the total points, and then the
      points earned during the previous set.
    - Any entries that have already been eliminated should be shown, but
      dimmed so it is apparent that they are no longer in play.
    - Any entries that are being eliminated before the next set should have
      an animated transition (fading to a dimmed state).
    - If the list is too long to display on the screen, then after two
      seconds the list should smoothly scroll down until the bottom is visible.
    - No timer bar visible in this phase

- Round Summary Phase
    - The round summary phase will show a scoreboard update.
    - There will be a list of player names, along with their avatar icon;
      the entry that player submitted; how many points that entry scored
      during this round; and the player's total score.
    - The list should be sorted by total player score, from highest to
      lowest.
    - If the list is too long to display on the screen, then after two
      seconds the list should smoothly scroll down until the bottom is visible.
    - No timer bar visible in this phase

- Game Summary Phase
    - There should be an animated transition from the round summary to game
      summary screen.
    - There will be a different background image to use for the game
      summary.
    - The top three scoring players will be displayed.
    - First, after a 1 second delay, the third-place player's icon, name,
      and score will be displayed on the left side of the screen.
    - After another 1 second delay, the second-place player's icon, name, and
      score will be displayed on the right side of the screen.
    - After another 1 second delay, the first-place player's icon, name,
      and score will be displayed in larger text in the center of the
      screen.
    - This screen will persist until the host clicks the back to lobby
      button.
    - No timer bar visible in this phase

# Superlatives game vision

This document describes my initial vision for how the Superlatives game will
function.

The approach will be similar to my game What If?, as well as Jackbox-style
games. Players connect to the server using their phone or other device to
give their responses. There will also be support for a display client,
intended for use on a TV or computer monitor which all players can see, and
will display instructions, the scoreboard, etc. What If? did not have an
independent display client, but the Jackbox games do.

The general idea of Superlatives is that during each round of the game, a
category of items will be given to players, such as Animals, Movies, or
Food. Each player will select an item in that category (free text entry on
their phone). Then there will be several rounds of voting, where a relevant
"superlative" for the category is displayed, and players choose which entry
best fits that superlative. For example, for the Animals category, some of
the superlatives could be "cutest", "smallest", and "most likely to be found
in your neighborhood." Players score points based on the proportion of
voters that pick their answer.

For the eventual full game, I intend to have several twists that can happen
within the round, including eliminating lower-scoring answers partway
through the round; allowing players to vote on which superlatives to use;
and allowing players to "steal" another player's answer. We should make sure
that the design of the server and client will be able to accomodate those
types of extensions, although for the first implementation

## Interface and game flow

Similar to What If, the game server will manage multiple rooms. When
connecting to the server, either as a display client or player client, the
user enters a room code, and all players that use the same room code will
play together.

To start either the display or player client, the user connects to the
server using their web browser. For the display client, only the room code
is necessary; for the player client, the user also specifies their display
name. I do not want to have to maintain secure player accounts, but we will
work later on methods to help prevent problems with multiple players trying
to use the same name.

Initially the game will be in a waiting to start state. The display and
player clients will show a list of players who are in the room. There will
be a button in the interface to start the game when all the players that are
expected have connected.

There will be multiple rounds, first implementation will have three rounds.
The display client will display the category for the first round, and
the player clients will give them a text box to enter an item/object from
that category. They will have a maximum of 30 seconds to select an item.
When the 30 seconds expires, or all players have made an entry, then the
game moves on.

There will then be three sets of votes, each for a different superlative for
that category. For each vote, the display client will show the entries, and
in the center of the screen a question like "Which ANIMAL is the CUTEST?"
The player client will allow the players to pick one of the entries as the
cutest. They will have a maximum of 20 seconds to select one.

After the time expires or all players have voted, the display client will
show the results of the vote. Each set of votes is worth 1000 points, which
is split between the players by how many votes each player's item got.

This process is repeated three times with different superlatives for the
same category, after which a new round starts with a different category.
After three categories, a final scoreboard will be displayed.

After the final scores, then there is a button to return to the waiting
room, where a new game can be started.

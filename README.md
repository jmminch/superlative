# Superlatives

A synchronous party game where players submit one entry per category and then
vote on superlative prompts (for example, "Cutest" or "Most chaotic").

The game supports both:
- `player` clients (phones/laptops)
- `display` clients (shared TV/monitor view)

## Running

The server is written in Dart.

1. Install Dart SDK.
2. Install dependencies:
   `dart pub get`
3. Start server:
   `dart bin/server.dart`

By default, the server listens on `127.0.0.1:36912`.

Environment variables:
- `PORT` (default `36912`)
- `LISTENIP` (default loopback)

## Client URLs

- Player client: `http://<host>:<port>/`
- Display client: `http://<host>:<port>/display.html`

## Content

Superlatives content is loaded directly from:
- `data/superlatives.yaml`

No YAML-to-JSON conversion step is required.

# Phone Pong

A tiny Godot 4 game to test a phone-only workflow: an AI agent edits the code,
GitHub builds it, and you play the result in your phone's browser.

## How to play
Hold the phone upright. You're the yellow paddle at the bottom; drag anywhere
to move it. On a computer, move the mouse or use the arrow keys.
On a wide screen (computer, Steam Deck, or a phone turned sideways) the game
plays left to right: you're on the right.

It's a roguelike: score 3 on the CPU to clear a stage, then pick 1 of 3
upgrades (wider paddle, extra heart, shield, magnet and more). Every goal
against you costs a heart, and when they're gone the run is over. The CPU gets
faster each stage, and every 4th stage is a boss with a giant paddle.

Every return in a row grows your combo and is worth more points. Hit the ball
with the middle of your paddle for a PERFECT (double points). Long combos make
the colours and music go wild. Your best score is saved.

## How the pipeline works
1. Code changes are pushed to the `main` branch.
2. `.github/workflows/deploy.yml` runs Godot headless in the cloud and exports
   a web build (no threads, so it runs on any static host, including iPhone Safari).
3. The build is published to GitHub Pages at
   `https://<your-username>.github.io/<repo-name>/`.

## One-time setup
In the repo on GitHub: **Settings → Pages → Build and deployment → Source:
GitHub Actions.** After that, every push updates the playable link.

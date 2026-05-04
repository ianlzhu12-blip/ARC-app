# ARC Flight Optimizer

A clean, outdoor-readable web app for logging and optimizing American Rocketry Challenge model rocket flights.

## iPhone App

A native SwiftUI iPhone app is available at:

```text
ios/ARCFlightOptimizer/ARCFlightOptimizer.xcodeproj
```

See `ios/README.md` for iOS-specific setup notes.

## Features

- Local-first flight logging for teams, rockets, motor choice, mass, weather, altitude, parachute size, and notes.
- Live weather lookup by location using Open-Meteo, with manual fallback for offline launch sites.
- Canvas charts for altitude trend and mass-vs-altitude regression.
- Explainable altitude prediction using ridge regression over mass, motor class, temperature, wind, and humidity.
- Smart recommendations for target altitude tuning, including mass and motor-impact reasoning.
- Nationals Mode with launch-window countdown, quick-entry workflow, locked-configuration flagging for new rockets, and best-two target matches.
- CSV import, CSV judge report export, and JSON local backup export.

## Run

Install the small server dependency once:

```bash
npm install
```

Run the included Node server:

```bash
npm run dev
```

Then open:

```text
http://localhost:5173
```

## GPT Spreadsheet Import

The iPhone app does not store an OpenAI API key directly. For the most accurate spreadsheet conversion, run this project server with the key on your Mac or a deployed host:

```bash
export OPENAI_API_KEY="your_api_key_here"
npm run dev
```

By default the server uses `gpt-5`. You can override it:

```bash
export OPENAI_MODEL="gpt-5"
```

In the iPhone app, go to Account -> Flight Sheet Attachments -> GPT Import Server and enter your server URL. The simulator can usually use:

```text
http://127.0.0.1:5173
```

For a real iPhone on the same Wi-Fi as your Mac, use your Mac's local IP address, for example:

```text
http://192.168.1.25:5173
```

When that server is reachable, the app sends spreadsheet text to GPT with a strict flight-log schema, then converts the result into editable logs. If the server is offline, the app falls back to the local parser so launch-day use still works.

If your shell does not have `node` on the path in Codex, use the bundled runtime:

```bash
/Users/xiaoliu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node server.mjs
```

## Architecture

- `index.html` mounts the app.
- `src/app.js` contains the Web Component app, local storage, prediction engine, recommendations, weather lookup, CSV import/export, and canvas charts.
- `src/styles.css` contains the responsive, dark-mode, competition-readable UI.
- `server.mjs` serves the static app locally and exposes optional AI endpoints for flight-sheet parsing and rocket recommendations.

## Prediction Logic

The prediction engine starts with a baseline average until there are at least four logged flights. After that, it fits a small ridge-regression model using:

- Rocket mass
- Motor impulse class
- Temperature
- Wind speed
- Humidity

The recommendation system runs small hypothetical changes through the same model and reports approximate impact, so the reasoning stays visible during competition decisions.

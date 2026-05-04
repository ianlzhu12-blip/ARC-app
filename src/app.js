const STORAGE_KEY = "arc-flight-optimizer-state-v1";
const motors = ["A", "B", "C", "D", "E", "F", "G", "H", "Other"];
const motorImpulseScore = { A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, Other: 5 };

const defaultState = {
  teams: [{ id: "team-apogee", name: "Apogee Crew", school: "ARC Demo School" }],
  rockets: [{ id: "rocket-sparrow", teamId: "team-apogee", name: "Sparrow Mk II", dryMassGrams: 612, diameterMm: 66, lockedForNationals: false }],
  flights: [
    flightSeed(18, 725, 748, 72, 6, 42, 18),
    flightSeed(12, 702, 781, 76, 9, 51, 18),
    flightSeed(6, 690, 808, 69, 5, 47, 20)
  ],
  targetAltitudeFt: 800,
  nationalsMode: false,
  launchWindowMinutes: 45
};

function flightSeed(daysAgo, mass, altitude, temp, wind, humidity, chute) {
  return {
    id: crypto.randomUUID(),
    rocketId: "rocket-sparrow",
    teamId: "team-apogee",
    flownAt: new Date(Date.now() - daysAgo * 86400000).toISOString(),
    motorType: "F",
    rocketMassGrams: mass,
    weather: { temperatureF: temp, windMph: wind, humidityPercent: humidity, location: "Manassas, VA" },
    measuredAltitudeFt: altitude,
    parachuteSizeIn: chute,
    descentSystem: chute > 18 ? "standard chute" : "reefed chute",
    notes: "Seed demo flight"
  };
}

function loadState() {
  try {
    return { ...defaultState, ...JSON.parse(localStorage.getItem(STORAGE_KEY)) };
  } catch {
    return defaultState;
  }
}

function featureVector(input) {
  return [1, input.rocketMassGrams, motorImpulseScore[input.motorType] || 5, input.temperatureF, input.windMph, input.humidityPercent];
}

function solveLinearSystem(matrix, values) {
  const n = values.length;
  const augmented = matrix.map((row, index) => [...row, values[index]]);
  for (let pivot = 0; pivot < n; pivot += 1) {
    let maxRow = pivot;
    for (let row = pivot + 1; row < n; row += 1) {
      if (Math.abs(augmented[row][pivot]) > Math.abs(augmented[maxRow][pivot])) maxRow = row;
    }
    [augmented[pivot], augmented[maxRow]] = [augmented[maxRow], augmented[pivot]];
    const divisor = augmented[pivot][pivot] || 1e-9;
    for (let col = pivot; col <= n; col += 1) augmented[pivot][col] /= divisor;
    for (let row = 0; row < n; row += 1) {
      if (row === pivot) continue;
      const factor = augmented[row][pivot];
      for (let col = pivot; col <= n; col += 1) augmented[row][col] -= factor * augmented[pivot][col];
    }
  }
  return augmented.map((row) => row[n]);
}

function trainAndPredict(flights, input) {
  const usable = flights.filter((flight) => Number.isFinite(flight.measuredAltitudeFt));
  if (usable.length < 4) {
    const average = usable.length ? usable.reduce((sum, flight) => sum + flight.measuredAltitudeFt, 0) / usable.length : 750;
    return { altitudeFt: Math.round(average), confidence: Math.min(0.45, usable.length * 0.12), method: "baseline" };
  }

  const features = usable.map((flight) =>
    featureVector({
      motorType: flight.motorType,
      rocketMassGrams: flight.rocketMassGrams,
      temperatureF: flight.weather.temperatureF,
      windMph: flight.weather.windMph,
      humidityPercent: flight.weather.humidityPercent
    })
  );
  const target = usable.map((flight) => flight.measuredAltitudeFt);
  const width = features[0].length;
  const xtx = Array.from({ length: width }, () => Array.from({ length: width }, () => 0));
  const xty = Array.from({ length: width }, () => 0);

  // Ridge regression is intentionally simple and explainable for ARC field use.
  // It estimates altitude from mass, motor impulse class, temperature, wind, and humidity.
  // A tiny regularization term prevents wild coefficients when the team only has a few launches.
  for (let row = 0; row < features.length; row += 1) {
    for (let i = 0; i < width; i += 1) {
      xty[i] += features[row][i] * target[row];
      for (let j = 0; j < width; j += 1) xtx[i][j] += features[row][i] * features[row][j];
    }
  }
  for (let i = 1; i < width; i += 1) xtx[i][i] += 0.001;

  const weights = solveLinearSystem(xtx, xty);
  const altitudeFt = featureVector(input).reduce((sum, value, index) => sum + value * weights[index], 0);
  const meanError =
    usable.reduce((sum, flight, index) => {
      const predicted = features[index].reduce((total, value, featureIndex) => total + value * weights[featureIndex], 0);
      return sum + Math.abs(predicted - flight.measuredAltitudeFt);
    }, 0) / usable.length;

  return {
    altitudeFt: Math.round(altitudeFt),
    confidence: Math.max(0.35, Math.min(0.92, 1 - meanError / 180 + usable.length * 0.015)),
    method: "regression"
  };
}

function makeRecommendations(flights, input, targetAltitudeFt) {
  const current = trainAndPredict(flights, input);
  const delta = targetAltitudeFt - current.altitudeFt;
  const massStep = delta > 0 ? -10 : 10;
  const massPrediction = trainAndPredict(flights, { ...input, rocketMassGrams: input.rocketMassGrams + massStep });
  const massImpact = massPrediction.altitudeFt - current.altitudeFt;
  const currentMotor = motorImpulseScore[input.motorType] || 5;
  const nextMotor = Object.entries(motorImpulseScore).find(([, score]) => score === currentMotor + (delta > 80 ? 1 : -1));

  // Recommendations compare small hypothetical changes against the same model so teams see
  // a direction and rough impact, not a black-box instruction.
  return [
    {
      title: delta > 0 ? "Lighten payload mass" : "Add trim mass",
      detail: `${delta > 0 ? "Reducing" : "Increasing"} mass by ${Math.abs(massStep)}g is projected to move altitude by about ${Math.abs(massImpact)} ft.`,
      priority: Math.abs(delta) > 35 ? "high" : "medium"
    },
    nextMotor && nextMotor[0] !== "Other"
      ? {
          title: `Evaluate ${nextMotor[0]} motor option`,
          detail: `${delta > 0 ? "More impulse may recover altitude margin" : "Less impulse may reduce overshoot"}, but verify ARC rules and motor availability before changing configuration.`,
          priority: Math.abs(delta) > 80 ? "high" : "low"
        }
      : null,
    {
      title: "Tune descent system separately",
      detail: "Use parachute size to target flight time and landing consistency; it should not materially improve apogee once deployment is clean.",
      priority: "low"
    }
  ].filter(Boolean);
}

async function lookupWeather(location) {
  const geoResponse = await fetch(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=en&format=json`);
  if (!geoResponse.ok) throw new Error("Location lookup failed");
  const geoJson = await geoResponse.json();
  const place = geoJson.results?.[0];
  if (!place) throw new Error("No matching location found");

  const weatherResponse = await fetch(
    `https://api.open-meteo.com/v1/forecast?latitude=${place.latitude}&longitude=${place.longitude}&current=temperature_2m,relative_humidity_2m,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph`
  );
  if (!weatherResponse.ok) throw new Error("Weather lookup failed");
  const weatherJson = await weatherResponse.json();
  return {
    temperatureF: Math.round(weatherJson.current.temperature_2m),
    windMph: Math.round(weatherJson.current.wind_speed_10m),
    humidityPercent: Math.round(weatherJson.current.relative_humidity_2m),
    resolvedLocation: [place.name, place.admin1, place.country].filter(Boolean).join(", ")
  };
}

function flightsToCsv(flights) {
  const headers = ["flownAt", "rocketId", "teamId", "motorType", "rocketMassGrams", "temperatureF", "windMph", "humidityPercent", "measuredAltitudeFt", "parachuteSizeIn", "descentSystem", "notes"];
  const rows = flights.map((flight) =>
    [
      flight.flownAt,
      flight.rocketId,
      flight.teamId,
      flight.motorType,
      flight.rocketMassGrams,
      flight.weather.temperatureF,
      flight.weather.windMph,
      flight.weather.humidityPercent,
      flight.measuredAltitudeFt,
      flight.parachuteSizeIn,
      flight.descentSystem,
      flight.notes || ""
    ]
      .map((value) => `"${String(value).replaceAll('"', '""')}"`)
      .join(",")
  );
  return [headers.join(","), ...rows].join("\n");
}

function downloadFile(name, contents, type) {
  const url = URL.createObjectURL(new Blob([contents], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  URL.revokeObjectURL(url);
}

function drawLineChart(canvas, flights, targetAltitudeFt) {
  const context = canvas.getContext("2d");
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  context.scale(dpr, dpr);
  drawChartShell(context, rect.width, rect.height);
  if (!flights.length) return;
  const ordered = [...flights].sort((a, b) => a.flownAt.localeCompare(b.flownAt));
  const values = ordered.map((flight) => flight.measuredAltitudeFt);
  const min = Math.min(targetAltitudeFt - 120, ...values) - 20;
  const max = Math.max(targetAltitudeFt + 120, ...values) + 20;
  const points = values.map((value, index) => ({
    x: 52 + (index / Math.max(1, values.length - 1)) * (rect.width - 82),
    y: map(value, min, max, rect.height - 38, 24)
  }));
  drawPolyline(context, points, "#7cf4c8");
  drawTargetLine(context, rect.width, targetAltitudeFt, min, max, rect.height);
  points.forEach((point) => drawDot(context, point.x, point.y, "#ffcf5c"));
}

function drawScatterChart(canvas, flights, targetAltitudeFt) {
  const context = canvas.getContext("2d");
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  context.scale(dpr, dpr);
  drawChartShell(context, rect.width, rect.height);
  if (!flights.length) return;
  const masses = flights.map((flight) => flight.rocketMassGrams);
  const altitudes = flights.map((flight) => flight.measuredAltitudeFt);
  const minMass = Math.min(...masses) - 20;
  const maxMass = Math.max(...masses) + 20;
  const minAlt = Math.min(targetAltitudeFt - 120, ...altitudes) - 20;
  const maxAlt = Math.max(targetAltitudeFt + 120, ...altitudes) + 20;
  flights.forEach((flight) => {
    drawDot(context, map(flight.rocketMassGrams, minMass, maxMass, 52, rect.width - 30), map(flight.measuredAltitudeFt, minAlt, maxAlt, rect.height - 38, 24), "#ffcf5c");
  });
  drawRegressionLine(context, flights, minMass, maxMass, minAlt, maxAlt, rect);
}

function drawChartShell(context, width, height) {
  context.clearRect(0, 0, width, height);
  context.strokeStyle = "rgba(159, 179, 200, 0.14)";
  context.lineWidth = 1;
  for (let i = 0; i < 5; i += 1) {
    const y = 24 + i * ((height - 62) / 4);
    context.beginPath();
    context.moveTo(46, y);
    context.lineTo(width - 24, y);
    context.stroke();
  }
}

function drawPolyline(context, points, color) {
  context.strokeStyle = color;
  context.lineWidth = 3;
  context.beginPath();
  points.forEach((point, index) => (index ? context.lineTo(point.x, point.y) : context.moveTo(point.x, point.y)));
  context.stroke();
}

function drawDot(context, x, y, color) {
  context.fillStyle = color;
  context.beginPath();
  context.arc(x, y, 5, 0, Math.PI * 2);
  context.fill();
}

function drawTargetLine(context, width, target, min, max, height) {
  const y = map(target, min, max, height - 38, 24);
  context.strokeStyle = "rgba(255, 143, 92, 0.82)";
  context.setLineDash([8, 8]);
  context.beginPath();
  context.moveTo(46, y);
  context.lineTo(width - 24, y);
  context.stroke();
  context.setLineDash([]);
}

function drawRegressionLine(context, flights, minMass, maxMass, minAlt, maxAlt, rect) {
  const n = flights.length;
  if (n < 2) return;
  const sumX = flights.reduce((sum, flight) => sum + flight.rocketMassGrams, 0);
  const sumY = flights.reduce((sum, flight) => sum + flight.measuredAltitudeFt, 0);
  const sumXY = flights.reduce((sum, flight) => sum + flight.rocketMassGrams * flight.measuredAltitudeFt, 0);
  const sumXX = flights.reduce((sum, flight) => sum + flight.rocketMassGrams ** 2, 0);
  const slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX ** 2 || 1);
  const intercept = (sumY - slope * sumX) / n;
  const points = [minMass, maxMass].map((mass) => ({ x: map(mass, minMass, maxMass, 52, rect.width - 30), y: map(slope * mass + intercept, minAlt, maxAlt, rect.height - 38, 24) }));
  drawPolyline(context, points, "#75b8ff");
}

function map(value, inMin, inMax, outMin, outMax) {
  return outMin + ((value - inMin) / (inMax - inMin || 1)) * (outMax - outMin);
}

class ArcFlightApp extends HTMLElement {
  constructor() {
    super();
    this.state = loadState();
    this.selectedRocketId = "all";
    this.weatherLocation = "Manassas, VA";
    this.weatherDraft = { temperatureF: 72, windMph: 6, humidityPercent: 45, location: "Manassas, VA" };
    this.weatherStatus = "Manual values remain available for offline launches.";
    this.timerSeconds = this.state.launchWindowMinutes * 60;
  }

  connectedCallback() {
    this.render();
    this.timer = setInterval(() => {
      if (this.state.nationalsMode && this.timerSeconds > 0) {
        this.timerSeconds -= 1;
        this.render();
      }
    }, 1000);
  }

  disconnectedCallback() {
    clearInterval(this.timer);
  }

  save(nextState = this.state) {
    this.state = nextState;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(this.state));
    this.render();
  }

  activeFlights() {
    return this.selectedRocketId === "all" ? this.state.flights : this.state.flights.filter((flight) => flight.rocketId === this.selectedRocketId);
  }

  predictionInput() {
    const primaryRocket = this.state.rockets[0];
    return {
      motorType: "F",
      rocketMassGrams: primaryRocket ? primaryRocket.dryMassGrams + 90 : 700,
      temperatureF: this.weatherDraft.temperatureF,
      windMph: this.weatherDraft.windMph,
      humidityPercent: this.weatherDraft.humidityPercent
    };
  }

  render() {
    const activeFlights = this.activeFlights();
    const modelFlights = activeFlights.length ? activeFlights : this.state.flights;
    const prediction = trainAndPredict(modelFlights, this.predictionInput());
    const stats = this.getStats(activeFlights);
    const minutes = String(Math.floor(this.timerSeconds / 60)).padStart(2, "0");
    const seconds = String(this.timerSeconds % 60).padStart(2, "0");
    const qualifiers = [...this.state.flights]
      .sort((a, b) => Math.abs(a.measuredAltitudeFt - this.state.targetAltitudeFt) - Math.abs(b.measuredAltitudeFt - this.state.targetAltitudeFt))
      .slice(0, 2);

    this.innerHTML = `
      <main>
        <section class="hero">
          <div>
            <p class="eyebrow">American Rocketry Challenge</p>
            <h1>Flight Optimizer</h1>
            <p class="hero-copy">Log launches in seconds, track altitude trends, pull live weather by location, and get competition-ready recommendations toward your target apogee.</p>
            <div class="hero-actions">
              <button data-action="toggle-nationals">🏆 ${this.state.nationalsMode ? "Exit Nationals Mode" : "Enter Nationals Mode"}</button>
              <label class="ghost-button">Import CSV<input id="csv-import" type="file" accept=".csv"></label>
              <button class="ghost-button" data-action="export-csv">Export Judge Report</button>
            </div>
          </div>
          <div class="target-card">
            <span>Target altitude</span>
            <label><input id="target-altitude" type="number" value="${this.state.targetAltitudeFt}"> ft</label>
            <strong>${prediction.altitudeFt} ft</strong>
            <small>next prediction, ${Math.round(prediction.confidence * 100)}% confidence using ${prediction.method}</small>
          </div>
        </section>
        ${
          this.state.nationalsMode
            ? `<section class="nationals-strip"><div><span>Launch window</span><strong>${minutes}:${seconds}</strong></div><button data-action="reset-timer">Reset Timer</button><div class="qualifiers">${qualifiers
                .map((flight) => `<span>${flight.measuredAltitudeFt} ft (${Math.abs(flight.measuredAltitudeFt - this.state.targetAltitudeFt)} ft off)</span>`)
                .join("")}</div></section>`
            : ""
        }
        <section class="stats-grid">
          ${this.statCard("Average altitude", `${Math.round(stats.average)} ft`, `${activeFlights.length} flights tracked`)}
          ${this.statCard("Best target match", stats.best ? `${stats.best.measuredAltitudeFt} ft` : "No flights", stats.best ? `${Math.abs(stats.best.measuredAltitudeFt - this.state.targetAltitudeFt)} ft from target` : "Log a flight to begin")}
          ${this.statCard("Consistency spread", `${Math.round(stats.spread)} ft`, "Lower is better for repeatability")}
          ${this.statCard("Weather source", this.weatherDraft.location || "Manual", `${this.weatherDraft.temperatureF}F, ${this.weatherDraft.windMph} mph wind`)}
        </section>
        <section class="workspace-grid">
          ${this.quickLogMarkup()}
          ${this.weatherAndRecommendationsMarkup(modelFlights)}
        </section>
        ${this.managementMarkup()}
        ${this.chartsMarkup()}
        ${this.tableMarkup()}
      </main>
    `;
    this.bindEvents();
    requestAnimationFrame(() => {
      drawLineChart(this.querySelector("#altitude-chart"), activeFlights, this.state.targetAltitudeFt);
      drawScatterChart(this.querySelector("#mass-chart"), activeFlights, this.state.targetAltitudeFt);
    });
  }

  statCard(label, value, detail) {
    return `<article class="stat-card"><span>${label}</span><strong>${value}</strong><small>${detail}</small></article>`;
  }

  quickLogMarkup() {
    return `
      <form class="panel quick-log" id="flight-form">
        <div class="panel-heading"><h2>Quick Flight Log</h2><span class="rocket-mark">🚀</span></div>
        <div class="form-grid">
          <label>Rocket<select name="rocketId" required>${this.state.rockets.map((rocket) => `<option value="${rocket.id}">${rocket.name}</option>`).join("")}</select></label>
          <label>Motor<select name="motorType">${motors.map((motor) => `<option ${motor === "F" ? "selected" : ""}>${motor}</option>`).join("")}</select></label>
          <label>Mass (g)<input name="rocketMassGrams" type="number" value="${this.predictionInput().rocketMassGrams}"></label>
          <label>Altitude (ft)<input name="measuredAltitudeFt" type="number" value="${this.state.targetAltitudeFt}"></label>
          <label>Temperature (F)<input name="temperatureF" type="number" value="${this.weatherDraft.temperatureF}"></label>
          <label>Wind (mph)<input name="windMph" type="number" value="${this.weatherDraft.windMph}"></label>
          <label>Humidity (%)<input name="humidityPercent" type="number" value="${this.weatherDraft.humidityPercent}"></label>
          <label>Parachute (in)<input name="parachuteSizeIn" type="number" value="18"></label>
          <label class="wide">Descent system<input name="descentSystem" value="reefed chute"></label>
          <label class="wide">Notes<input name="notes" placeholder="egg condition, rail angle, delay, recovery notes"></label>
        </div>
        <button class="full-button" type="submit">Save Flight</button>
      </form>
    `;
  }

  weatherAndRecommendationsMarkup(modelFlights) {
    const recommendations = makeRecommendations(modelFlights, this.predictionInput(), this.state.targetAltitudeFt);
    return `
      <aside class="panel">
        <h2>Live Weather</h2>
        <p>Enter a launch site, city, or field location. Data is pulled from Open-Meteo and copied into the quick log.</p>
        <div class="inline-control"><input id="weather-location" value="${this.weatherLocation}" placeholder="The Plains, VA"><button data-action="pull-weather">Pull Weather</button></div>
        <small>${this.weatherStatus}</small>
        <h2>Smart Recommendations</h2>
        <div class="recommendation-list">
          ${recommendations.map((item) => `<article class="recommendation ${item.priority}"><strong>${item.title}</strong><p>${item.detail}</p></article>`).join("")}
        </div>
      </aside>
    `;
  }

  managementMarkup() {
    return `
      <section class="panel management-grid">
        <form id="team-form"><h2>Teams</h2><input name="teamName" placeholder="Team name"><input name="school" placeholder="School / organization"><button>Add Team</button></form>
        <form id="rocket-form"><h2>Rockets</h2><select name="teamId">${this.state.teams.map((team) => `<option value="${team.id}">${team.name}</option>`).join("")}</select><input name="rocketName" placeholder="Rocket name"><input name="dryMassGrams" type="number" placeholder="Dry mass (g)"><input name="diameterMm" type="number" placeholder="Diameter (mm)"><button>Add Rocket</button></form>
        <div><h2>Filters & Backup</h2><select id="rocket-filter"><option value="all">All rockets</option>${this.state.rockets.map((rocket) => `<option value="${rocket.id}" ${this.selectedRocketId === rocket.id ? "selected" : ""}>${rocket.name}</option>`).join("")}</select><button class="ghost-button backup-link" data-action="backup-json">Download Local Backup</button></div>
      </section>
    `;
  }

  chartsMarkup() {
    return `
      <section class="panel charts-grid">
        <div><h2>Altitude Trend</h2><p>Target line plus flight-by-flight apogee.</p><div class="chart-frame"><canvas id="altitude-chart"></canvas></div></div>
        <div><h2>Mass vs. Altitude</h2><p>Scatter plot with a simple regression trend line.</p><div class="chart-frame"><canvas id="mass-chart"></canvas></div></div>
      </section>
    `;
  }

  tableMarkup() {
    return `
      <section class="panel flight-table">
        <h2>Historical Flights</h2>
        <div class="table-wrap"><table><thead><tr><th>Date</th><th>Rocket</th><th>Motor</th><th>Mass</th><th>Weather</th><th>Altitude</th><th>Deviation</th><th>Descent</th></tr></thead>
        <tbody>${this.state.flights
          .map((flight) => {
            const rocket = this.state.rockets.find((item) => item.id === flight.rocketId);
            return `<tr><td>${new Date(flight.flownAt).toLocaleString()}</td><td>${rocket?.name || "Unknown"}</td><td>${flight.motorType}</td><td>${flight.rocketMassGrams}g</td><td>${flight.weather.temperatureF}F / ${flight.weather.windMph} mph / ${flight.weather.humidityPercent}%</td><td>${flight.measuredAltitudeFt} ft</td><td>${Math.abs(flight.measuredAltitudeFt - this.state.targetAltitudeFt)} ft</td><td>${flight.parachuteSizeIn}" ${flight.descentSystem}</td></tr>`;
          })
          .join("")}</tbody></table></div>
      </section>
    `;
  }

  bindEvents() {
    this.querySelector('[data-action="toggle-nationals"]')?.addEventListener("click", () => this.save({ ...this.state, nationalsMode: !this.state.nationalsMode }));
    this.querySelector('[data-action="reset-timer"]')?.addEventListener("click", () => {
      this.timerSeconds = this.state.launchWindowMinutes * 60;
      this.render();
    });
    this.querySelector('[data-action="export-csv"]')?.addEventListener("click", () => downloadFile("arc-flight-report.csv", flightsToCsv(this.state.flights), "text/csv"));
    this.querySelector('[data-action="backup-json"]')?.addEventListener("click", () => downloadFile("arc-flight-optimizer-backup.json", JSON.stringify(this.state, null, 2), "application/json"));
    this.querySelector("#target-altitude")?.addEventListener("change", (event) => this.save({ ...this.state, targetAltitudeFt: Number(event.target.value) || 800 }));
    this.querySelector("#rocket-filter")?.addEventListener("change", (event) => {
      this.selectedRocketId = event.target.value;
      this.render();
    });
    this.querySelector("#weather-location")?.addEventListener("input", (event) => {
      this.weatherLocation = event.target.value;
    });
    this.querySelector('[data-action="pull-weather"]')?.addEventListener("click", async () => {
      this.weatherStatus = "Fetching live weather...";
      this.render();
      try {
        const weather = await lookupWeather(this.weatherLocation);
        this.weatherDraft = { temperatureF: weather.temperatureF, windMph: weather.windMph, humidityPercent: weather.humidityPercent, location: weather.resolvedLocation };
        this.weatherStatus = `Loaded ${weather.resolvedLocation}`;
      } catch (error) {
        this.weatherStatus = error.message || "Weather lookup failed";
      }
      this.render();
    });
    this.querySelector("#flight-form")?.addEventListener("submit", (event) => this.addFlight(event));
    this.querySelector("#team-form")?.addEventListener("submit", (event) => this.addTeam(event));
    this.querySelector("#rocket-form")?.addEventListener("submit", (event) => this.addRocket(event));
    this.querySelector("#csv-import")?.addEventListener("change", (event) => this.importCsv(event.target.files?.[0]));
  }

  getStats(flights) {
    const average = flights.length ? flights.reduce((sum, flight) => sum + flight.measuredAltitudeFt, 0) / flights.length : 0;
    const best = flights.reduce((current, flight) => {
      const currentDiff = current ? Math.abs(current.measuredAltitudeFt - this.state.targetAltitudeFt) : Infinity;
      const nextDiff = Math.abs(flight.measuredAltitudeFt - this.state.targetAltitudeFt);
      return nextDiff < currentDiff ? flight : current;
    }, null);
    const spread = flights.length ? Math.max(...flights.map((flight) => flight.measuredAltitudeFt)) - Math.min(...flights.map((flight) => flight.measuredAltitudeFt)) : 0;
    return { average, best, spread };
  }

  addFlight(event) {
    event.preventDefault();
    const form = new FormData(event.target);
    const rocket = this.state.rockets.find((item) => item.id === form.get("rocketId")) || this.state.rockets[0];
    const weather = {
      temperatureF: Number(form.get("temperatureF")) || this.weatherDraft.temperatureF,
      windMph: Number(form.get("windMph")) || this.weatherDraft.windMph,
      humidityPercent: Number(form.get("humidityPercent")) || this.weatherDraft.humidityPercent,
      location: this.weatherDraft.location
    };
    this.weatherDraft = { ...weather };
    const flight = {
      id: crypto.randomUUID(),
      rocketId: rocket.id,
      teamId: rocket.teamId,
      flownAt: new Date().toISOString(),
      motorType: form.get("motorType") || "F",
      rocketMassGrams: Number(form.get("rocketMassGrams")) || rocket.dryMassGrams,
      weather,
      measuredAltitudeFt: Number(form.get("measuredAltitudeFt")) || this.state.targetAltitudeFt,
      parachuteSizeIn: Number(form.get("parachuteSizeIn")) || 18,
      descentSystem: form.get("descentSystem") || "standard chute",
      notes: form.get("notes") || "",
      round: this.state.nationalsMode ? "Nationals" : ""
    };
    this.save({ ...this.state, flights: [flight, ...this.state.flights] });
  }

  addTeam(event) {
    event.preventDefault();
    const form = new FormData(event.target);
    const team = { id: crypto.randomUUID(), name: form.get("teamName") || "New Team", school: form.get("school") || "" };
    this.save({ ...this.state, teams: [...this.state.teams, team] });
  }

  addRocket(event) {
    event.preventDefault();
    const form = new FormData(event.target);
    const rocket = {
      id: crypto.randomUUID(),
      teamId: form.get("teamId"),
      name: form.get("rocketName") || "New Rocket",
      dryMassGrams: Number(form.get("dryMassGrams")) || 650,
      diameterMm: Number(form.get("diameterMm")) || 66,
      lockedForNationals: this.state.nationalsMode
    };
    this.save({ ...this.state, rockets: [...this.state.rockets, rocket] });
  }

  importCsv(file) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const rows = String(reader.result).split(/\r?\n/).slice(1).filter(Boolean);
      const imported = rows.map((row) => {
        const cells = row.match(/("([^"]|"")*"|[^,]+)/g)?.map((cell) => cell.replace(/^"|"$/g, "").replaceAll('""', '"')) || [];
        const rocket = this.state.rockets.find((item) => item.id === cells[1]) || this.state.rockets[0];
        return {
          id: crypto.randomUUID(),
          flownAt: cells[0] || new Date().toISOString(),
          rocketId: rocket.id,
          teamId: rocket.teamId,
          motorType: cells[3] || "F",
          rocketMassGrams: Number(cells[4]) || rocket.dryMassGrams,
          weather: { temperatureF: Number(cells[5]) || 72, windMph: Number(cells[6]) || 5, humidityPercent: Number(cells[7]) || 45 },
          measuredAltitudeFt: Number(cells[8]) || 0,
          parachuteSizeIn: Number(cells[9]) || 18,
          descentSystem: cells[10] || "standard chute",
          notes: cells[11] || "Imported from CSV"
        };
      });
      this.save({ ...this.state, flights: [...imported, ...this.state.flights] });
    };
    reader.readAsText(file);
  }
}

customElements.define("arc-flight-app", ArcFlightApp);

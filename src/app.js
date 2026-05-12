const STORAGE_KEY = "arc-flight-optimizer-state-v2";
const LEGACY_STORAGE_KEY = "arc-flight-optimizer-state-v1";

if (typeof history !== "undefined" && "scrollRestoration" in history) {
  history.scrollRestoration = "manual";
}

const motors = ["A", "B", "C", "D", "E", "F", "G", "H", "Other"];
const motorImpulseScore = { A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, Other: 5 };
const modeDetails = {
  hobby: "Casual testing, experiments, and max-altitude practice.",
  competition: "ARC practice with scoring, target altitude, flight time, and repeatability.",
  nationals: "Unlocked for finalist teams. Tune multiple target altitudes and launch-window flow."
};
const defaultChecklist = [
  "Confirm launch site weather",
  "Verify motor and delay",
  "Check recovery system",
  "Power on altimeter",
  "Record loaded mass"
];

const defaultState = {
  setupComplete: false,
  flightMode: "hobby",
  targetAltitudeFt: 800,
  teams: [],
  rockets: [],
  flights: [],
  profile: {
    displayName: "",
    email: "",
    school: "",
    teamNumber: "",
    nationalsStatus: "unknown",
    syncEnabled: false,
    syncKey: ""
  },
  deletedFlightIds: [],
  deletedRocketIds: [],
  updatedAt: new Date().toISOString(),
  launchWindowSeconds: 45 * 60,
  launchWindowEndsAt: null,
  launchTimerState: "stopped",
  checklist: defaultChecklist.map((title) => ({ id: uid(), title, done: false }))
};

function uid() {
  return crypto.randomUUID?.() || `id-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function numberOrNull(value) {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function finiteNumber(value, fallback = 0) {
  if (value === null || value === undefined || String(value).trim() === "") return fallback;
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function rounded(value, digits = 0) {
  if (!Number.isFinite(value)) return "--";
  return digits === 0 ? String(Math.round(value)) : value.toFixed(digits);
}

function grams(value) {
  return Number.isFinite(value) ? `${Math.round(value)}g` : "--";
}

function modeLabel(mode) {
  if (mode === "competition") return "Competition";
  if (mode === "nationals") return "Nationals";
  return "Hobby";
}

function isNationalsUnlocked(state) {
  return state.profile?.nationalsStatus === "qualified";
}

function migrateState(raw) {
  const state = { ...defaultState, ...raw };
  state.profile = { ...defaultState.profile, ...(raw?.profile || {}) };
  state.deletedFlightIds = Array.isArray(raw?.deletedFlightIds) ? raw.deletedFlightIds : [];
  state.deletedRocketIds = Array.isArray(raw?.deletedRocketIds) ? raw.deletedRocketIds : [];
  state.updatedAt = raw?.updatedAt || new Date().toISOString();
  state.flightMode = raw?.flightMode || (raw?.nationalsMode ? "nationals" : "hobby");
  state.setupComplete = Boolean(raw?.setupComplete || state.teams?.length || state.rockets?.length);
  state.teams = Array.isArray(raw?.teams) ? raw.teams : [];
  state.rockets = Array.isArray(raw?.rockets) ? raw.rockets : [];
  state.flights = Array.isArray(raw?.flights) ? raw.flights.map(normalizeFlight).filter(Boolean) : [];
  state.checklist = Array.isArray(raw?.checklist) && raw.checklist.length
    ? raw.checklist
    : defaultChecklist.map((title) => ({ id: uid(), title, done: false }));
  if (state.flightMode === "nationals" && !isNationalsUnlocked(state)) {
    state.flightMode = "competition";
  }
  return state;
}

function normalizeFlight(flight) {
  if (!flight) return null;
  return {
    id: flight.id || uid(),
    rocketId: flight.rocketId,
    teamId: flight.teamId,
    flownAt: flight.flownAt || new Date().toISOString(),
    motorType: flight.motorType || "F",
    rocketMassGrams: finiteNumber(flight.rocketMassGrams, 0),
    measuredAltitudeFt: finiteNumber(flight.measuredAltitudeFt, 0),
    targetAltitudeFt: numberOrNull(flight.targetAltitudeFt),
    flightTimeSeconds: numberOrNull(flight.flightTimeSeconds),
    parachuteSizeIn: finiteNumber(flight.parachuteSizeIn, 18),
    reefedCm: numberOrNull(flight.reefedCm ?? flight.parachuteReefedCentimeters),
    descentSystem: flight.descentSystem || "Reefed chute",
    eggStatus: flight.eggStatus || "Unknown",
    notes: flight.notes || "",
    round: flight.round || "",
    weather: {
      temperatureF: finiteNumber(flight.weather?.temperatureF, 72),
      windMph: finiteNumber(flight.weather?.windMph ?? flight.weather?.windMPH, 0),
      humidityPercent: finiteNumber(flight.weather?.humidityPercent, 0),
      location: flight.weather?.location || ""
    }
  };
}

function loadState() {
  for (const key of [STORAGE_KEY, LEGACY_STORAGE_KEY]) {
    try {
      const value = localStorage.getItem(key);
      if (value) return migrateState(JSON.parse(value));
    } catch {
      // Fall through to the clean default.
    }
  }
  return migrateState(defaultState);
}

function newerThan(left, right) {
  return new Date(left || 0).getTime() > new Date(right || 0).getTime();
}

function mergeById(localItems, remoteItems, deletedIds, remoteIsNewer) {
  const deleted = new Set(deletedIds || []);
  const merged = new Map();
  for (const item of localItems || []) {
    if (item?.id && !deleted.has(item.id)) merged.set(item.id, item);
  }
  for (const item of remoteItems || []) {
    if (!item?.id || deleted.has(item.id)) continue;
    if (!merged.has(item.id) || remoteIsNewer) merged.set(item.id, item);
  }
  return [...merged.values()];
}

function mergeSyncedState(localState, remoteState) {
  const local = migrateState(localState);
  const remote = migrateState(remoteState);
  const remoteIsNewer = newerThan(remote.updatedAt, local.updatedAt);
  const deletedFlightIds = [...new Set([...(local.deletedFlightIds || []), ...(remote.deletedFlightIds || [])])];
  const deletedRocketIds = [...new Set([...(local.deletedRocketIds || []), ...(remote.deletedRocketIds || [])])];
  const profile = {
    ...(remoteIsNewer ? local.profile : remote.profile),
    ...(remoteIsNewer ? remote.profile : local.profile),
    syncEnabled: local.profile.syncEnabled,
    syncKey: local.profile.syncKey || remote.profile.syncKey
  };
  return migrateState({
    ...(remoteIsNewer ? local : remote),
    ...(remoteIsNewer ? remote : local),
    profile,
    teams: mergeById(local.teams, remote.teams, [], remoteIsNewer),
    rockets: mergeById(local.rockets, remote.rockets, deletedRocketIds, remoteIsNewer),
    flights: mergeById(local.flights, remote.flights, deletedFlightIds, remoteIsNewer),
    checklist: mergeById(local.checklist, remote.checklist, [], remoteIsNewer),
    deletedFlightIds,
    deletedRocketIds,
    updatedAt: remoteIsNewer ? remote.updatedAt : local.updatedAt
  });
}

function featureVector(input) {
  return [
    1,
    input.rocketMassGrams,
    motorImpulseScore[input.motorType] || 5,
    input.temperatureF,
    input.windMph,
    input.humidityPercent
  ];
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

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function sameMotorOrAll(flights, motorType) {
  const sameMotor = flights.filter((flight) => flight.motorType === motorType);
  return sameMotor.length ? sameMotor : flights;
}

function nearestByMass(flights, input) {
  return sameMotorOrAll(flights, input.motorType)
    .sort((a, b) => Math.abs(a.rocketMassGrams - input.rocketMassGrams) - Math.abs(b.rocketMassGrams - input.rocketMassGrams))[0];
}

function nearestByTarget(flights, input, targetAltitudeFt) {
  return sameMotorOrAll(flights, input.motorType)
    .sort((a, b) => Math.abs(a.measuredAltitudeFt - targetAltitudeFt) - Math.abs(b.measuredAltitudeFt - targetAltitudeFt))[0];
}

function massAltitudeSlope(flights, motorType) {
  const pool = sameMotorOrAll(flights, motorType);
  const slopes = [];
  for (let i = 0; i < pool.length; i += 1) {
    for (let j = i + 1; j < pool.length; j += 1) {
      const massDelta = pool[j].rocketMassGrams - pool[i].rocketMassGrams;
      if (Math.abs(massDelta) < 8) continue;
      const slope = (pool[j].measuredAltitudeFt - pool[i].measuredAltitudeFt) / massDelta;
      if (slope < -0.15 && slope > -8) slopes.push(slope);
    }
  }
  return slopes.length ? median(slopes) : -2.8;
}

function sparsePredict(usable, input) {
  if (!usable.length) {
    return { altitudeFt: 750, confidence: 0, method: "starter baseline" };
  }
  const anchor = nearestByMass(usable, input);
  const slope = massAltitudeSlope(usable, input.motorType);
  const motorAdjustment = ((motorImpulseScore[input.motorType] || 5) - (motorImpulseScore[anchor.motorType] || 5)) * 55;
  const weatherAdjustment =
    (input.temperatureF - anchor.weather.temperatureF) * 0.35 -
    (input.windMph - anchor.weather.windMph) * 1.2 -
    (input.humidityPercent - anchor.weather.humidityPercent) * 0.08;
  const altitudeFt = anchor.measuredAltitudeFt + (input.rocketMassGrams - anchor.rocketMassGrams) * slope + motorAdjustment + weatherAdjustment;
  return {
    altitudeFt: Math.round(altitudeFt),
    confidence: Math.min(0.62, 0.18 + usable.length * 0.11),
    method: usable.length > 1 ? "nearest trend" : "proven setup adjustment"
  };
}

function trainAndPredict(flights, input) {
  const usable = flights.filter((flight) =>
    Number.isFinite(flight.measuredAltitudeFt) &&
    flight.measuredAltitudeFt > 20 &&
    Number.isFinite(flight.rocketMassGrams)
  );
  if (usable.length < 4) {
    return sparsePredict(usable, input);
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

  // Ridge regression keeps the field model stable when a team has only a few launches.
  for (let row = 0; row < features.length; row += 1) {
    for (let i = 0; i < width; i += 1) {
      xty[i] += features[row][i] * target[row];
      for (let j = 0; j < width; j += 1) xtx[i][j] += features[row][i] * features[row][j];
    }
  }
  for (let i = 1; i < width; i += 1) xtx[i][i] += 0.002;

  const weights = solveLinearSystem(xtx, xty);
  const altitudeFt = featureVector(input).reduce((sum, value, index) => sum + value * weights[index], 0);
  const meanError = usable.reduce((sum, flight, index) => {
    const predicted = features[index].reduce((total, value, featureIndex) => total + value * weights[featureIndex], 0);
    return sum + Math.abs(predicted - flight.measuredAltitudeFt);
  }, 0) / usable.length;

  return {
    altitudeFt: Math.round(altitudeFt),
    confidence: Math.max(0.35, Math.min(0.94, 1 - meanError / 190 + usable.length * 0.012)),
    method: "team regression"
  };
}

function optimizeMass(flights, input, targetAltitudeFt) {
  const usable = flights.filter((flight) => flight.measuredAltitudeFt > 20 && flight.rocketMassGrams > 0);
  const nearMatch = usable
    .filter((flight) => Math.abs(flight.measuredAltitudeFt - targetAltitudeFt) <= 6 && flight.motorType === input.motorType)
    .sort((a, b) => Math.abs(a.measuredAltitudeFt - targetAltitudeFt) - Math.abs(b.measuredAltitudeFt - targetAltitudeFt))[0];
  if (nearMatch) {
    return {
      mass: nearMatch.rocketMassGrams,
      altitude: nearMatch.measuredAltitudeFt,
      confidence: 0.9,
      method: "proven repeat"
    };
  }

  const loggedMasses = usable.map((flight) => flight.rocketMassGrams);
  const minMass = Math.max(50, Math.min(input.rocketMassGrams, ...loggedMasses, 550) - 250);
  const maxMass = Math.min(2200, Math.max(input.rocketMassGrams, ...loggedMasses, 750) + 250);
  if (usable.length && usable.length < 4) {
    const anchor = nearestByTarget(usable, input, targetAltitudeFt);
    const slope = massAltitudeSlope(usable, input.motorType);
    const mass = Math.round(Math.max(50, Math.min(2200, anchor.rocketMassGrams + (targetAltitudeFt - anchor.measuredAltitudeFt) / slope)));
    const predicted = trainAndPredict(flights, { ...input, rocketMassGrams: mass });
    return { mass, altitude: predicted.altitudeFt, confidence: predicted.confidence, method: predicted.method };
  }
  const initialPrediction = trainAndPredict(flights, input);
  let best = {
    mass: input.rocketMassGrams,
    altitude: initialPrediction.altitudeFt,
    error: Math.abs(initialPrediction.altitudeFt - targetAltitudeFt)
  };
  for (let mass = minMass; mass <= maxMass; mass += 1) {
    const predicted = trainAndPredict(flights, { ...input, rocketMassGrams: mass });
    const error = Math.abs(predicted.altitudeFt - targetAltitudeFt);
    if (error + 0.001 < best.error) best = { mass, altitude: predicted.altitudeFt, error };
  }
  const confidence = trainAndPredict(flights, { ...input, rocketMassGrams: best.mass }).confidence;
  return { mass: best.mass, altitude: best.altitude, confidence, method: "model search" };
}

function reefingSuggestion(flights, targetRange = [41, 44]) {
  const usable = flights.filter((flight) =>
    Number.isFinite(flight.flightTimeSeconds) &&
    Number.isFinite(flight.reefedCm)
  );
  if (usable.length < 2) {
    return {
      text: "Log at least two flights with flight time and reefed centimeters to calculate reefing.",
      value: null
    };
  }
  const targetTime = (targetRange[0] + targetRange[1]) / 2;
  const n = usable.length;
  const sumX = usable.reduce((sum, flight) => sum + flight.flightTimeSeconds, 0);
  const sumY = usable.reduce((sum, flight) => sum + flight.reefedCm, 0);
  const sumXY = usable.reduce((sum, flight) => sum + flight.flightTimeSeconds * flight.reefedCm, 0);
  const sumXX = usable.reduce((sum, flight) => sum + flight.flightTimeSeconds ** 2, 0);
  const denominator = n * sumXX - sumX ** 2;
  const averageReef = sumY / n;
  if (Math.abs(denominator) < 0.001) {
    return { text: `Try reefing near your logged average of ${rounded(averageReef, 1)} cm.`, value: averageReef };
  }
  const slope = (n * sumXY - sumX * sumY) / denominator;
  const intercept = (sumY - slope * sumX) / n;
  const suggested = Math.max(0, Math.min(500, slope * targetTime + intercept));
  return { text: `Try about ${rounded(suggested, 1)} cm reefed for the ${targetRange[0]}-${targetRange[1]} s window.`, value: suggested };
}

function makeRecommendations(flights, input, targetAltitudeFt, mode) {
  const prediction = trainAndPredict(flights, input);
  const optimized = optimizeMass(flights, input, targetAltitudeFt);
  const delta = targetAltitudeFt - prediction.altitudeFt;
  const reef = mode === "hobby" ? null : reefingSuggestion(flights);
  const recommendations = [
    {
      title: "Loaded weight target",
      detail: `Aim for about ${grams(optimized.mass)} loaded mass. The model predicts ${rounded(optimized.altitude)} ft using ${optimized.method}.`,
      priority: Math.abs(optimized.altitude - targetAltitudeFt) <= 10 ? "low" : "medium"
    },
    {
      title: delta > 0 ? "Altitude is low" : "Altitude is high",
      detail: delta > 0
        ? "If your next result is still low, reduce trim mass or use a stronger proven motor setup."
        : "If your next result is still high, add trim mass in small repeatable steps.",
      priority: Math.abs(delta) > 35 ? "high" : "medium"
    }
  ];
  if (reef) {
    recommendations.push({
      title: "Try reefing for time",
      detail: reef.text,
      priority: reef.value === null ? "low" : "medium"
    });
  }
  return recommendations;
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
  const headers = ["flownAt", "rocketId", "teamId", "motorType", "rocketMassGrams", "targetAltitudeFt", "flightTimeSeconds", "temperatureF", "windMph", "humidityPercent", "measuredAltitudeFt", "parachuteSizeIn", "reefedCm", "eggStatus", "descentSystem", "notes"];
  const rows = flights.map((flight) => [
    flight.flownAt,
    flight.rocketId,
    flight.teamId,
    flight.motorType,
    flight.rocketMassGrams,
    flight.targetAltitudeFt ?? "",
    flight.flightTimeSeconds ?? "",
    flight.weather.temperatureF,
    flight.weather.windMph,
    flight.weather.humidityPercent,
    flight.measuredAltitudeFt,
    flight.parachuteSizeIn,
    flight.reefedCm ?? "",
    flight.eggStatus,
    flight.descentSystem,
    flight.notes || ""
  ].map((value) => `"${String(value).replaceAll('"', '""')}"`).join(","));
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

function drawPlannerChart(canvas, flights, targetAltitudeFt) {
  if (!canvas) return;
  const context = canvas.getContext("2d");
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, rect.width * dpr);
  canvas.height = Math.max(1, rect.height * dpr);
  context.scale(dpr, dpr);
  context.clearRect(0, 0, rect.width, rect.height);
  context.strokeStyle = "rgba(183, 209, 232, 0.16)";
  context.lineWidth = 1;
  for (let index = 0; index < 5; index += 1) {
    const y = 28 + index * ((rect.height - 64) / 4);
    context.beginPath();
    context.moveTo(52, y);
    context.lineTo(rect.width - 24, y);
    context.stroke();
  }
  const usable = flights.filter((flight) => flight.measuredAltitudeFt > 20 && flight.rocketMassGrams > 0);
  if (!usable.length) return;
  const masses = usable.map((flight) => flight.rocketMassGrams);
  const altitudes = usable.map((flight) => flight.measuredAltitudeFt);
  const minMass = Math.min(...masses) - 28;
  const maxMass = Math.max(...masses) + 28;
  const minAlt = Math.min(targetAltitudeFt - 110, ...altitudes) - 20;
  const maxAlt = Math.max(targetAltitudeFt + 110, ...altitudes) + 20;

  const mapValue = (value, inMin, inMax, outMin, outMax) => outMin + ((value - inMin) / (inMax - inMin || 1)) * (outMax - outMin);
  const yTarget = mapValue(targetAltitudeFt, minAlt, maxAlt, rect.height - 36, 24);
  context.strokeStyle = "rgba(255, 207, 92, 0.9)";
  context.setLineDash([8, 8]);
  context.beginPath();
  context.moveTo(52, yTarget);
  context.lineTo(rect.width - 24, yTarget);
  context.stroke();
  context.setLineDash([]);

  if (usable.length >= 2) {
    const n = usable.length;
    const sumX = usable.reduce((sum, flight) => sum + flight.rocketMassGrams, 0);
    const sumY = usable.reduce((sum, flight) => sum + flight.measuredAltitudeFt, 0);
    const sumXY = usable.reduce((sum, flight) => sum + flight.rocketMassGrams * flight.measuredAltitudeFt, 0);
    const sumXX = usable.reduce((sum, flight) => sum + flight.rocketMassGrams ** 2, 0);
    const slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX ** 2 || 1);
    const intercept = (sumY - slope * sumX) / n;
    context.strokeStyle = "#7cf4c8";
    context.lineWidth = 3;
    context.beginPath();
    [minMass, maxMass].forEach((mass, index) => {
      const point = {
        x: mapValue(mass, minMass, maxMass, 52, rect.width - 24),
        y: mapValue(slope * mass + intercept, minAlt, maxAlt, rect.height - 36, 24)
      };
      if (index === 0) context.moveTo(point.x, point.y);
      else context.lineTo(point.x, point.y);
    });
    context.stroke();
  }

  usable.forEach((flight) => {
    context.fillStyle = "#ffcf5c";
    context.beginPath();
    context.arc(
      mapValue(flight.rocketMassGrams, minMass, maxMass, 52, rect.width - 24),
      mapValue(flight.measuredAltitudeFt, minAlt, maxAlt, rect.height - 36, 24),
      5,
      0,
      Math.PI * 2
    );
    context.fill();
  });
}

class ArcFlightApp extends HTMLElement {
  constructor() {
    super();
    this.state = loadState();
    this.activeTab = this.state.setupComplete ? "dashboard" : "setup";
    this.setupStep = 0;
    this.setupDraft = {
      flightMode: this.state.flightMode || "hobby",
      teamName: "",
      school: "",
      rocketName: "",
      dryMassGrams: "",
      diameterMm: "66",
      material: "Cardboard",
      parachuteSizeIn: "18",
      defaultMotor: "F",
      heightMm: "700",
      widthMm: "66"
    };
    this.selectedRocketId = "all";
    this.editFlightId = null;
    this.editRocketId = null;
    this.weatherLocation = "Manassas, VA";
    this.weatherDraft = { temperatureF: 72, windMph: 6, humidityPercent: 45, location: "Manual" };
    this.weatherStatus = "Manual values work offline.";
    this.installPrompt = null;
    this.installStatus = "Install from this same link on computer or phone.";
    this.syncStatus = this.syncCredentials() ? "Sync ready." : "Register account and enable sync to share data.";
    this.syncTimer = null;
    this.syncInFlight = false;
  }

  connectedCallback() {
    this.beforeInstallPromptHandler = (event) => {
      event.preventDefault();
      this.installPrompt = event;
      this.installStatus = "Ready to install on this device.";
      this.render();
    };
    window.addEventListener("beforeinstallprompt", this.beforeInstallPromptHandler);
    window.addEventListener("resize", this.resizeHandler = () => this.drawCharts());
    this.render();
    window.scrollTo({ top: 0, left: 0 });
    this.timer = setInterval(() => this.tickTimer(), 1000);
  }

  disconnectedCallback() {
    clearInterval(this.timer);
    clearTimeout(this.syncTimer);
    window.removeEventListener("beforeinstallprompt", this.beforeInstallPromptHandler);
    window.removeEventListener("resize", this.resizeHandler);
  }

  save(nextState = this.state, shouldRender = true, options = {}) {
    const state = migrateState(nextState);
    if (!options.preserveUpdatedAt) state.updatedAt = new Date().toISOString();
    this.state = state;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(this.state));
    if (shouldRender) this.render();
    if (!options.skipSync) this.scheduleSyncPush();
  }

  syncCredentials() {
    const email = String(this.state.profile.email || "").trim().toLowerCase();
    const syncKey = String(this.state.profile.syncKey || "").trim();
    if (!this.state.profile.syncEnabled || !email || syncKey.length < 8) return null;
    return { email, syncKey };
  }

  scheduleSyncPush() {
    const credentials = this.syncCredentials();
    if (!credentials) return;
    clearTimeout(this.syncTimer);
    this.syncTimer = setTimeout(() => this.pushSync(), 900);
  }

  async pushSync() {
    const credentials = this.syncCredentials();
    if (!credentials || this.syncInFlight) return;
    this.syncInFlight = true;
    try {
      const response = await fetch("/api/sync/push", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...credentials, state: this.state })
      });
      if (!response.ok) throw new Error("Sync server unavailable");
      const result = await response.json();
      this.syncStatus = `Synced ${new Date(result.updatedAt || Date.now()).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}.`;
    } catch {
      this.syncStatus = "Sync server unavailable. GitHub Pages cannot store account data by itself.";
    } finally {
      this.syncInFlight = false;
      if (this.activeTab === "account") this.render();
    }
  }

  async pullSync() {
    const credentials = this.syncCredentials();
    if (!credentials) {
      this.syncStatus = "Register account, enable sync, and keep the same sync key on each device.";
      this.render();
      return;
    }
    this.syncStatus = "Checking cloud data...";
    this.render();
    try {
      const response = await fetch("/api/sync/pull", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(credentials)
      });
      if (!response.ok) throw new Error("Sync server unavailable");
      const result = await response.json();
      if (!result.state) {
        this.syncStatus = "No cloud copy yet. Saving this device now.";
        this.render();
        await this.pushSync();
        return;
      }
      const merged = mergeSyncedState(this.state, result.state);
      this.save(merged, false, { skipSync: true, preserveUpdatedAt: true });
      this.syncStatus = "Pulled and merged cloud data.";
      this.render();
      this.scheduleSyncPush();
    } catch {
      this.syncStatus = "Sync server unavailable. Use backup export here, or iCloud sync in the iPhone app.";
      this.render();
    }
  }

  activeFlights() {
    const flights = this.selectedRocketId === "all"
      ? this.state.flights
      : this.state.flights.filter((flight) => flight.rocketId === this.selectedRocketId);
    return [...flights].sort((a, b) => new Date(b.flownAt) - new Date(a.flownAt));
  }

  selectedModelFlights() {
    const filtered = this.activeFlights();
    return filtered.length ? filtered : this.state.flights;
  }

  selectedRocket() {
    return this.state.rockets.find((rocket) => rocket.id === this.selectedRocketId) || this.state.rockets[0] || null;
  }

  predictionInput() {
    const rocket = this.selectedRocket();
    const latest = this.selectedModelFlights()[0];
    return {
      motorType: latest?.motorType || rocket?.defaultMotor || "F",
      rocketMassGrams: latest?.rocketMassGrams || (rocket ? rocket.dryMassGrams + 90 : 700),
      temperatureF: latest?.weather.temperatureF || this.weatherDraft.temperatureF,
      windMph: latest?.weather.windMph || this.weatherDraft.windMph,
      humidityPercent: latest?.weather.humidityPercent || this.weatherDraft.humidityPercent
    };
  }

  stats(flights = this.activeFlights()) {
    const altitudes = flights.map((flight) => flight.measuredAltitudeFt).filter(Number.isFinite);
    const average = altitudes.length ? altitudes.reduce((sum, value) => sum + value, 0) / altitudes.length : 0;
    const best = flights.reduce((current, flight) => {
      const target = flight.targetAltitudeFt || this.state.targetAltitudeFt;
      const currentDiff = current ? Math.abs(current.measuredAltitudeFt - (current.targetAltitudeFt || this.state.targetAltitudeFt)) : Infinity;
      const nextDiff = Math.abs(flight.measuredAltitudeFt - target);
      return nextDiff < currentDiff ? flight : current;
    }, null);
    const spread = altitudes.length ? Math.max(...altitudes) - Math.min(...altitudes) : 0;
    return { average, best, spread };
  }

  tickTimer() {
    if (this.state.launchTimerState !== "running" || !this.state.launchWindowEndsAt) return;
    const remaining = Math.max(0, Math.ceil((new Date(this.state.launchWindowEndsAt).getTime() - Date.now()) / 1000));
    const timerNode = this.querySelector("[data-timer-display]");
    if (timerNode) timerNode.textContent = this.formatTime(remaining);
    if (remaining === 0) {
      this.save({ ...this.state, launchTimerState: "stopped", launchWindowEndsAt: null, launchWindowSeconds: 0 });
    }
  }

  remainingSeconds() {
    if (this.state.launchTimerState === "running" && this.state.launchWindowEndsAt) {
      return Math.max(0, Math.ceil((new Date(this.state.launchWindowEndsAt).getTime() - Date.now()) / 1000));
    }
    return this.state.launchWindowSeconds;
  }

  formatTime(seconds) {
    const minutes = String(Math.floor(seconds / 60)).padStart(2, "0");
    const rest = String(seconds % 60).padStart(2, "0");
    return `${minutes}:${rest}`;
  }

  render() {
    this.innerHTML = this.state.setupComplete ? this.appMarkup() : this.setupMarkup();
    this.bindEvents();
    this.drawCharts();
  }

  setupMarkup() {
    const stepTitles = ["Choose mode", "Account and team", "First rocket"];
    return `
      <main class="setup-shell">
        <section class="setup-card glass">
          <div class="setup-hero">
            <p class="eyebrow">RocketTune Web</p>
            <h1>Set up your launch workspace</h1>
            <p>The computer version now follows the phone app: required setup, clean tabs, no demo data, and a logbook that starts empty.</p>
          </div>
          <div class="progress-row">
            ${stepTitles.map((title, index) => `<span class="${index === this.setupStep ? "active" : ""}">${index + 1}. ${title}</span>`).join("")}
          </div>
          ${this.setupStep === 0 ? this.setupModeMarkup() : ""}
          ${this.setupStep === 1 ? this.setupTeamMarkup() : ""}
          ${this.setupStep === 2 ? this.setupRocketMarkup() : ""}
          <div class="button-row">
            <button class="ghost-button" data-action="setup-back" ${this.setupStep === 0 ? "disabled" : ""}>Back</button>
            <button data-action="${this.setupStep === 2 ? "setup-finish" : "setup-next"}">${this.setupStep === 2 ? "Enter App" : "Next"}</button>
          </div>
        </section>
      </main>
    `;
  }

  setupModeMarkup() {
    return `
      <div class="mode-grid">
        ${["hobby", "competition", "nationals"].map((mode) => `
          <button class="mode-card ${this.setupDraft.flightMode === mode ? "selected" : ""}" data-setup-mode="${mode}" ${mode === "nationals" && !isNationalsUnlocked(this.state) ? "data-locked=\"true\"" : ""}>
            <strong>${modeLabel(mode)}</strong>
            <span>${escapeHTML(modeDetails[mode])}</span>
            ${mode === "nationals" && !isNationalsUnlocked(this.state) ? "<small>Unlock from Account after your team qualifies.</small>" : ""}
          </button>
        `).join("")}
      </div>
    `;
  }

  setupTeamMarkup() {
    return `
      <form class="form-grid two" id="setup-team-form">
        <label>Team name<input name="teamName" required value="${escapeHTML(this.setupDraft.teamName)}" placeholder="Team Apogee"></label>
        <label>School / organization<input name="school" required value="${escapeHTML(this.setupDraft.school)}" placeholder="Your school"></label>
        <label>Your name<input name="displayName" value="${escapeHTML(this.state.profile.displayName)}" placeholder="Name"></label>
        <label>Email<input name="email" type="email" value="${escapeHTML(this.state.profile.email)}" placeholder="you@example.com"></label>
      </form>
    `;
  }

  setupRocketMarkup() {
    return `
      <form class="form-grid three" id="setup-rocket-form">
        <label>Rocket name<input name="rocketName" required value="${escapeHTML(this.setupDraft.rocketName)}" placeholder="Sparrow Mk II"></label>
        <label>Dry mass (g)<input name="dryMassGrams" required type="number" value="${escapeHTML(this.setupDraft.dryMassGrams)}" placeholder="612"></label>
        <label>Diameter (mm)<input name="diameterMm" required type="number" value="${escapeHTML(this.setupDraft.diameterMm)}"></label>
        <label>Material<input name="material" value="${escapeHTML(this.setupDraft.material)}"></label>
        <label>Parachute (in)<input name="parachuteSizeIn" type="number" value="${escapeHTML(this.setupDraft.parachuteSizeIn)}"></label>
        <label>Default motor<select name="defaultMotor">${motors.map((motor) => `<option ${motor === this.setupDraft.defaultMotor ? "selected" : ""}>${motor}</option>`).join("")}</select></label>
        <label>Height (mm)<input name="heightMm" type="number" value="${escapeHTML(this.setupDraft.heightMm)}"></label>
        <label>Width (mm)<input name="widthMm" type="number" value="${escapeHTML(this.setupDraft.widthMm)}"></label>
      </form>
    `;
  }

  appMarkup() {
    const mode = this.state.flightMode;
    return `
      <main class="app-shell">
        <aside class="sidebar glass">
          <div class="brand-block">
            <span class="brand-mark">ARC</span>
            <div>
              <strong>RocketTune</strong>
              <small>${modeLabel(mode)} Mode</small>
            </div>
          </div>
          <nav class="tab-nav">
            ${[
              ["dashboard", "Dashboard"],
              ["log", "Log"],
              ["insights", "Insights"],
              ["rockets", "Rockets"],
              ["account", "Account"]
            ].map(([tab, label]) => `<button class="${this.activeTab === tab ? "active" : ""}" data-tab="${tab}">${label}</button>`).join("")}
          </nav>
          <div class="sidebar-card">
            <span>Target altitude</span>
            <label class="compact-input"><input id="target-altitude" type="number" value="${this.state.targetAltitudeFt}"><b>ft</b></label>
          </div>
          <button class="ghost-button full" data-action="install-app">Install App</button>
          <small>${escapeHTML(this.installStatus)}</small>
        </aside>
        <section class="screen">
          ${this.topBarMarkup()}
          ${this.activeTab === "dashboard" ? this.dashboardMarkup() : ""}
          ${this.activeTab === "log" ? this.logMarkup() : ""}
          ${this.activeTab === "insights" ? this.insightsMarkup() : ""}
          ${this.activeTab === "rockets" ? this.rocketsMarkup() : ""}
          ${this.activeTab === "account" ? this.accountMarkup() : ""}
        </section>
      </main>
    `;
  }

  topBarMarkup() {
    return `
      <header class="topbar glass">
        <div>
          <p class="eyebrow">${modeLabel(this.state.flightMode)}</p>
          <h2>${this.activeTab[0].toUpperCase()}${this.activeTab.slice(1)}</h2>
        </div>
        <div class="mode-pills">
          ${["hobby", "competition", "nationals"].map((mode) => `
            <button data-mode="${mode}" class="${this.state.flightMode === mode ? "active" : ""}" ${mode === "nationals" && !isNationalsUnlocked(this.state) ? "disabled" : ""}>${modeLabel(mode)}</button>
          `).join("")}
        </div>
      </header>
    `;
  }

  dashboardMarkup() {
    const flights = this.activeFlights();
    const stats = this.stats(flights);
    const bestTwo = [...this.state.flights]
      .sort((a, b) => Math.abs(a.measuredAltitudeFt - (a.targetAltitudeFt || this.state.targetAltitudeFt)) - Math.abs(b.measuredAltitudeFt - (b.targetAltitudeFt || this.state.targetAltitudeFt)))
      .slice(0, 2);
    return `
      <section class="grid stats-grid">
        ${this.statCard("Average altitude", `${rounded(stats.average)} ft`, `${flights.length} flights`)}
        ${this.statCard("Best match", stats.best ? `${rounded(stats.best.measuredAltitudeFt)} ft` : "--", stats.best ? `${rounded(Math.abs(stats.best.measuredAltitudeFt - (stats.best.targetAltitudeFt || this.state.targetAltitudeFt)))} ft off` : "No flights yet")}
        ${this.statCard("Consistency", `${rounded(stats.spread)} ft`, "Altitude spread")}
        ${this.statCard("Model", this.modelReadinessLabel(), `${this.selectedModelFlights().length} logs used`)}
      </section>
      <section class="dashboard-grid">
        <article class="panel glass">
          <div class="panel-heading"><h3>Launch Timer</h3><span data-timer-display>${this.formatTime(this.remainingSeconds())}</span></div>
          <p>Works from a saved end time, so refreshing the page keeps the timer honest.</p>
          <div class="button-row compact">
            <button data-action="timer-start">Start</button>
            <button class="ghost-button" data-action="timer-pause">Pause</button>
            <button class="ghost-button" data-action="timer-reset">Restart</button>
          </div>
        </article>
        <article class="panel glass">
          <div class="panel-heading"><h3>Checklist</h3><button class="ghost-button small" data-action="checklist-add">Add</button></div>
          <div class="checklist">
            ${this.state.checklist.map((item) => `
              <label class="check-row">
                <input type="checkbox" data-check="${item.id}" ${item.done ? "checked" : ""}>
                <span>${escapeHTML(item.title)}</span>
                <button type="button" data-delete-check="${item.id}">Remove</button>
              </label>
            `).join("")}
          </div>
        </article>
        <article class="panel glass full-span">
          <div class="panel-heading"><h3>Best Flights</h3><span>${bestTwo.length} selected</span></div>
          <div class="flight-list compact-list">
            ${bestTwo.length ? bestTwo.map((flight) => this.flightRowMarkup(flight, false)).join("") : "<p>No flights logged yet.</p>"}
          </div>
        </article>
      </section>
    `;
  }

  statCard(label, value, detail) {
    return `<article class="stat-card glass"><span>${label}</span><strong>${value}</strong><small>${detail}</small></article>`;
  }

  weatherCardMarkup() {
    const weather = this.weatherDraft;
    return `
      <article class="panel glass weather-card">
        <div class="panel-heading"><h3>Live Weather</h3><span>${escapeHTML(weather.location || "Manual")}</span></div>
        <div class="weather-grid">
          <label class="weather-location">Launch site<input id="weather-location" value="${escapeHTML(this.weatherLocation)}" placeholder="The Plains, VA"></label>
          <div class="weather-stat"><span>Temp</span><strong>${rounded(weather.temperatureF)} F</strong></div>
          <div class="weather-stat"><span>Wind</span><strong>${rounded(weather.windMph)} mph</strong></div>
          <div class="weather-stat"><span>Humidity</span><strong>${rounded(weather.humidityPercent)}%</strong></div>
          <button type="button" data-action="pull-weather">Pull Weather</button>
        </div>
        <p>${escapeHTML(this.weatherStatus)}</p>
      </article>
    `;
  }

  logMarkup() {
    const flights = this.activeFlights();
    return `
      ${this.weatherCardMarkup()}
      <section class="split-grid">
        <article class="panel glass">
          <div class="panel-heading"><h3>${this.editFlightId ? "Edit Flight" : "Quick Log"}</h3><span>${modeLabel(this.state.flightMode)}</span></div>
          ${this.flightFormMarkup(this.state.flights.find((flight) => flight.id === this.editFlightId))}
        </article>
        <article class="panel glass">
          <div class="panel-heading"><h3>Flights</h3><span>${flights.length}</span></div>
          <div class="flight-list">
            ${flights.length ? flights.map((flight) => this.flightRowMarkup(flight, true)).join("") : "<p>Your logbook is empty. Add the first flight on the left.</p>"}
          </div>
        </article>
      </section>
    `;
  }

  flightFormMarkup(flight = null) {
    const rocket = this.state.rockets.find((item) => item.id === flight?.rocketId) || this.state.rockets[0];
    const target = flight?.targetAltitudeFt ?? this.state.targetAltitudeFt;
    return `
      <form id="flight-form" class="form-grid two">
        <label>Rocket<select name="rocketId">${this.state.rockets.map((item) => `<option value="${item.id}" ${item.id === rocket?.id ? "selected" : ""}>${escapeHTML(item.name)}</option>`).join("")}</select></label>
        <label>Motor<select name="motorType">${motors.map((motor) => `<option ${motor === (flight?.motorType || rocket?.defaultMotor || "F") ? "selected" : ""}>${motor}</option>`).join("")}</select></label>
        <label>Wanted altitude (ft)<input name="targetAltitudeFt" type="number" value="${escapeHTML(target)}"></label>
        <label>Measured altitude (ft)<input name="measuredAltitudeFt" type="number" value="${escapeHTML(flight?.measuredAltitudeFt ?? "")}" placeholder="758"></label>
        <label>Loaded mass (g)<input name="rocketMassGrams" type="number" value="${escapeHTML(flight?.rocketMassGrams ?? "")}" placeholder="607"></label>
        <label>Flight time (s)<input name="flightTimeSeconds" type="number" step="0.1" value="${escapeHTML(flight?.flightTimeSeconds ?? "")}" placeholder="42.5"></label>
        <label>Temperature (F)<input name="temperatureF" type="number" value="${escapeHTML(flight?.weather.temperatureF ?? this.weatherDraft.temperatureF)}"></label>
        <label>Wind (mph)<input name="windMph" type="number" value="${escapeHTML(flight?.weather.windMph ?? this.weatherDraft.windMph)}"></label>
        <label>Humidity (%)<input name="humidityPercent" type="number" value="${escapeHTML(flight?.weather.humidityPercent ?? this.weatherDraft.humidityPercent)}"></label>
        <label>Parachute (in)<input name="parachuteSizeIn" type="number" value="${escapeHTML(flight?.parachuteSizeIn ?? rocket?.parachuteSizeIn ?? 18)}"></label>
        <label>Reefed (cm)<input name="reefedCm" type="number" step="0.1" value="${escapeHTML(flight?.reefedCm ?? "")}" placeholder="Optional"></label>
        <label>Egg status<select name="eggStatus">${["Unknown", "Intact", "Cracked", "Broken", "Not carried"].map((status) => `<option ${status === (flight?.eggStatus || "Unknown") ? "selected" : ""}>${status}</option>`).join("")}</select></label>
        <label class="wide">Descent system<input name="descentSystem" value="${escapeHTML(flight?.descentSystem ?? "Reefed chute")}"></label>
        <label class="wide">Notes<input name="notes" value="${escapeHTML(flight?.notes ?? "")}" placeholder="Delay, rail angle, recovery, video notes"></label>
        <div class="button-row wide">
          <button type="submit">${flight ? "Update Flight" : "Save Flight"}</button>
          ${flight ? "<button class=\"ghost-button\" type=\"button\" data-action=\"cancel-flight-edit\">Cancel</button>" : ""}
        </div>
      </form>
    `;
  }

  flightRowMarkup(flight, actions) {
    const rocket = this.state.rockets.find((item) => item.id === flight.rocketId);
    const target = flight.targetAltitudeFt || this.state.targetAltitudeFt;
    const deviation = Math.abs(flight.measuredAltitudeFt - target);
    return `
      <div class="flight-row">
        <div>
          <strong>${escapeHTML(rocket?.name || "Unknown Rocket")}</strong>
          <span>${rounded(flight.measuredAltitudeFt)} ft • ${grams(flight.rocketMassGrams)} • ${escapeHTML(flight.motorType)} motor</span>
          <small>Target ${rounded(target)} ft • ${rounded(deviation)} ft off${flight.flightTimeSeconds ? ` • ${rounded(flight.flightTimeSeconds, 1)} s` : ""}${Number.isFinite(flight.reefedCm) ? ` • reefed ${rounded(flight.reefedCm, 1)} cm` : ""}</small>
        </div>
        ${actions ? `<div class="row-actions"><button class="ghost-button small" data-edit-flight="${flight.id}">Edit</button><button class="ghost-button small danger" data-delete-flight="${flight.id}">Delete</button></div>` : ""}
      </div>
    `;
  }

  insightsMarkup() {
    const flights = this.selectedModelFlights();
    const input = this.predictionInput();
    const prediction = trainAndPredict(flights, input);
    const optimized = optimizeMass(flights, input, this.state.targetAltitudeFt);
    const recommendations = makeRecommendations(flights, input, this.state.targetAltitudeFt, this.state.flightMode);
    const reef = reefingSuggestion(flights);
    return `
      <section class="insights-grid">
        <article class="prediction-card glass">
          <span>Current prediction</span>
          <strong>${grams(optimized.mass)}</strong>
          <p>Suggested loaded weight for ${rounded(this.state.targetAltitudeFt)} ft. Predicted apogee: ${rounded(optimized.altitude)} ft.</p>
          <div class="confidence"><span style="width:${Math.round(optimized.confidence * 100)}%"></span></div>
          <small>${Math.round(optimized.confidence * 100)}% confidence • ${escapeHTML(optimized.method)}</small>
        </article>
        <article class="panel glass">
          <div class="panel-heading"><h3>Data Summary</h3><span>${flights.length} logs</span></div>
          <p>${this.summaryText(flights, prediction)}</p>
          <p>${reef.text}</p>
        </article>
        <article class="panel glass full-span">
          <div class="panel-heading"><h3>Height vs Weight Planner</h3><span>Best-fit line</span></div>
          <div class="chart-frame"><canvas id="planner-chart"></canvas></div>
        </article>
        <article class="panel glass full-span">
          <div class="recommendation-list">
            ${recommendations.map((item) => `<article class="recommendation ${item.priority}"><strong>${escapeHTML(item.title)}</strong><p>${escapeHTML(item.detail)}</p></article>`).join("")}
          </div>
        </article>
      </section>
    `;
  }

  summaryText(flights, prediction) {
    if (!flights.length) return "No flight data yet. Add logs or import a flight sheet so the model can learn from your team.";
    const stats = this.stats(flights);
    return `${flights.length} flights, average ${rounded(stats.average)} ft, spread ${rounded(stats.spread)} ft. The model currently predicts ${rounded(prediction.altitudeFt)} ft from your latest setup.`;
  }

  rocketsMarkup() {
    return `
      <section class="split-grid">
        <article class="panel glass">
          <div class="panel-heading"><h3>${this.editRocketId ? "Edit Rocket" : "Add Rocket"}</h3><span>${this.state.rockets.length} total</span></div>
          ${this.rocketFormMarkup(this.state.rockets.find((rocket) => rocket.id === this.editRocketId))}
        </article>
        <article class="panel glass">
          <div class="rocket-list">
            ${this.state.rockets.map((rocket) => this.rocketRowMarkup(rocket)).join("")}
          </div>
        </article>
      </section>
    `;
  }

  rocketFormMarkup(rocket = null) {
    return `
      <form id="rocket-form" class="form-grid two">
        <label>Team<select name="teamId">${this.state.teams.map((team) => `<option value="${team.id}" ${team.id === (rocket?.teamId || this.state.teams[0]?.id) ? "selected" : ""}>${escapeHTML(team.name)}</option>`).join("")}</select></label>
        <label>Name<input name="rocketName" required value="${escapeHTML(rocket?.name ?? "")}" placeholder="Rocket name"></label>
        <label>Dry mass (g)<input name="dryMassGrams" required type="number" value="${escapeHTML(rocket?.dryMassGrams ?? "")}"></label>
        <label>Diameter (mm)<input name="diameterMm" required type="number" value="${escapeHTML(rocket?.diameterMm ?? 66)}"></label>
        <label>Material<input name="material" value="${escapeHTML(rocket?.material ?? "Cardboard")}"></label>
        <label>Parachute (in)<input name="parachuteSizeIn" type="number" value="${escapeHTML(rocket?.parachuteSizeIn ?? 18)}"></label>
        <label>Default motor<select name="defaultMotor">${motors.map((motor) => `<option ${motor === (rocket?.defaultMotor || "F") ? "selected" : ""}>${motor}</option>`).join("")}</select></label>
        <label>Height (mm)<input name="heightMm" type="number" value="${escapeHTML(rocket?.heightMm ?? 700)}"></label>
        <label>Width (mm)<input name="widthMm" type="number" value="${escapeHTML(rocket?.widthMm ?? rocket?.diameterMm ?? 66)}"></label>
        <div class="button-row wide">
          <button type="submit">${rocket ? "Update Rocket" : "Add Rocket"}</button>
          ${rocket ? "<button class=\"ghost-button\" type=\"button\" data-action=\"cancel-rocket-edit\">Cancel</button>" : ""}
        </div>
      </form>
    `;
  }

  rocketRowMarkup(rocket) {
    return `
      <div class="rocket-row">
        <div>
          <strong>${escapeHTML(rocket.name)}</strong>
          <span>${grams(rocket.dryMassGrams)} dry • ${rounded(rocket.diameterMm)} mm • ${escapeHTML(rocket.defaultMotor || "F")} motor</span>
          <small>${escapeHTML(rocket.material || "Material not set")} • ${rounded(rocket.parachuteSizeIn || 18)} in chute</small>
        </div>
        <div class="row-actions"><button class="ghost-button small" data-edit-rocket="${rocket.id}">Edit</button><button class="ghost-button small danger" data-delete-rocket="${rocket.id}">Delete</button></div>
      </div>
    `;
  }

  accountMarkup() {
    const syncKey = this.state.profile.syncKey || "";
    return `
      <section class="split-grid">
        <article class="panel glass">
          <div class="panel-heading"><h3>Personal Account</h3><span>${this.state.profile.syncEnabled ? "Sync on" : "Local-first"}</span></div>
          <form id="account-form" class="form-grid two">
            <label>Name<input name="displayName" value="${escapeHTML(this.state.profile.displayName)}"></label>
            <label>Email<input name="email" type="email" value="${escapeHTML(this.state.profile.email)}"></label>
            <label>School / organization<input name="school" value="${escapeHTML(this.state.profile.school)}"></label>
            <label>Team number<input name="teamNumber" value="${escapeHTML(this.state.profile.teamNumber)}"></label>
            <label>Nationals status<select name="nationalsStatus"><option value="unknown">Unknown</option><option value="qualified" ${this.state.profile.nationalsStatus === "qualified" ? "selected" : ""}>Made Nationals</option><option value="not-qualified" ${this.state.profile.nationalsStatus === "not-qualified" ? "selected" : ""}>Not qualified</option></select></label>
            <label class="check-row sync-toggle"><input name="syncEnabled" type="checkbox" ${this.state.profile.syncEnabled ? "checked" : ""}><span>Sync when signed in</span></label>
            <label class="wide">Sync key<input name="syncKey" value="${escapeHTML(syncKey)}" placeholder="Auto-generated when sync is enabled"></label>
            <div class="button-row wide"><button>Save Account</button></div>
          </form>
          <div class="button-row account-sync-actions">
            <button class="ghost-button" data-action="generate-sync-key">Generate Sync Key</button>
            <button class="ghost-button" data-action="pull-sync">Pull Cloud Data</button>
            <button data-action="push-sync">Sync Now</button>
          </div>
          <p>${escapeHTML(this.syncStatus)}</p>
          <p class="muted">Use the same email and sync key on another device. The iPhone app syncs through iCloud; the web version needs the Node server because GitHub Pages is static.</p>
        </article>
        <article class="panel glass">
          <div class="panel-heading"><h3>Team Backup</h3><span>${this.state.teams.length} teams</span></div>
          <div class="button-stack">
            <button data-action="export-csv">Export Flight Report</button>
            <button class="ghost-button" data-action="backup-json">Download Backup</button>
            <label class="ghost-button file-button">Import CSV<input id="csv-import" type="file" accept=".csv"></label>
          </div>
          <p>The web version stores data in this browser. Use backup/export before switching devices.</p>
        </article>
      </section>
    `;
  }

  modelReadinessLabel() {
    const count = this.selectedModelFlights().length;
    if (count >= 8) return "Ready";
    if (count >= 4) return "Learning";
    return "Needs data";
  }

  drawCharts() {
    if (this.activeTab !== "insights") return;
    requestAnimationFrame(() => drawPlannerChart(this.querySelector("#planner-chart"), this.selectedModelFlights(), this.state.targetAltitudeFt));
  }

  bindEvents() {
    this.querySelectorAll("[data-tab]").forEach((button) => {
      button.addEventListener("click", () => {
        this.activeTab = button.dataset.tab;
        this.editFlightId = null;
        this.editRocketId = null;
        this.render();
        window.scrollTo({ top: 0, left: 0 });
      });
    });
    this.querySelectorAll("[data-mode]").forEach((button) => {
      button.addEventListener("click", () => this.setMode(button.dataset.mode));
    });
    this.querySelectorAll("[data-setup-mode]").forEach((button) => {
      button.addEventListener("click", () => {
        if (button.dataset.locked === "true") return;
        this.setupDraft.flightMode = button.dataset.setupMode;
        this.render();
      });
    });
    this.querySelector('[data-action="setup-back"]')?.addEventListener("click", () => {
      this.captureSetupForms();
      this.setupStep = Math.max(0, this.setupStep - 1);
      this.render();
    });
    this.querySelector('[data-action="setup-next"]')?.addEventListener("click", () => {
      this.captureSetupForms();
      if (!this.validateSetupStep()) return;
      this.setupStep = Math.min(2, this.setupStep + 1);
      this.render();
    });
    this.querySelector('[data-action="setup-finish"]')?.addEventListener("click", () => this.finishSetup());
    this.querySelector("#target-altitude")?.addEventListener("change", (event) => this.save({ ...this.state, targetAltitudeFt: finiteNumber(event.target.value, 800) }));
    this.querySelector('[data-action="install-app"]')?.addEventListener("click", () => this.installApp());
    this.querySelector("#weather-location")?.addEventListener("input", (event) => {
      this.weatherLocation = event.target.value;
    });
    this.querySelector('[data-action="pull-weather"]')?.addEventListener("click", () => this.pullWeather());
    this.querySelector('[data-action="timer-start"]')?.addEventListener("click", () => this.startTimer());
    this.querySelector('[data-action="timer-pause"]')?.addEventListener("click", () => this.pauseTimer());
    this.querySelector('[data-action="timer-reset"]')?.addEventListener("click", () => this.resetTimer());
    this.querySelector('[data-action="checklist-add"]')?.addEventListener("click", () => this.addChecklistItem());
    this.querySelectorAll("[data-check]").forEach((checkbox) => checkbox.addEventListener("change", () => this.toggleChecklist(checkbox.dataset.check)));
    this.querySelectorAll("[data-delete-check]").forEach((button) => button.addEventListener("click", () => this.deleteChecklist(button.dataset.deleteCheck)));
    this.querySelector("#flight-form")?.addEventListener("submit", (event) => this.saveFlight(event));
    this.querySelector('[data-action="cancel-flight-edit"]')?.addEventListener("click", () => {
      this.editFlightId = null;
      this.render();
    });
    this.querySelectorAll("[data-edit-flight]").forEach((button) => button.addEventListener("click", () => {
      this.editFlightId = button.dataset.editFlight;
      this.render();
    }));
    this.querySelectorAll("[data-delete-flight]").forEach((button) => button.addEventListener("click", () => this.deleteFlight(button.dataset.deleteFlight)));
    this.querySelector("#rocket-form")?.addEventListener("submit", (event) => this.saveRocket(event));
    this.querySelector('[data-action="cancel-rocket-edit"]')?.addEventListener("click", () => {
      this.editRocketId = null;
      this.render();
    });
    this.querySelectorAll("[data-edit-rocket]").forEach((button) => button.addEventListener("click", () => {
      this.editRocketId = button.dataset.editRocket;
      this.render();
    }));
    this.querySelectorAll("[data-delete-rocket]").forEach((button) => {
      button.addEventListener("click", () => this.deleteRocket(button.dataset.deleteRocket));
    });
    this.querySelector("#account-form")?.addEventListener("submit", (event) => this.saveAccount(event));
    this.querySelector('[data-action="generate-sync-key"]')?.addEventListener("click", () => this.generateSyncKey());
    this.querySelector('[data-action="pull-sync"]')?.addEventListener("click", () => this.pullSync());
    this.querySelector('[data-action="push-sync"]')?.addEventListener("click", () => this.pushSync());
    this.querySelector('[data-action="export-csv"]')?.addEventListener("click", () => downloadFile("arc-flight-report.csv", flightsToCsv(this.state.flights), "text/csv"));
    this.querySelector('[data-action="backup-json"]')?.addEventListener("click", () => downloadFile("arc-flight-optimizer-backup.json", JSON.stringify(this.state, null, 2), "application/json"));
    this.querySelector("#csv-import")?.addEventListener("change", (event) => this.importCsv(event.target.files?.[0]));
  }

  captureSetupForms() {
    const teamForm = this.querySelector("#setup-team-form");
    if (teamForm) {
      const form = new FormData(teamForm);
      this.setupDraft.teamName = form.get("teamName") || "";
      this.setupDraft.school = form.get("school") || "";
      this.state.profile.displayName = form.get("displayName") || "";
      this.state.profile.email = form.get("email") || "";
    }
    const rocketForm = this.querySelector("#setup-rocket-form");
    if (rocketForm) {
      const form = new FormData(rocketForm);
      Object.assign(this.setupDraft, {
        rocketName: form.get("rocketName") || "",
        dryMassGrams: form.get("dryMassGrams") || "",
        diameterMm: form.get("diameterMm") || "",
        material: form.get("material") || "",
        parachuteSizeIn: form.get("parachuteSizeIn") || "",
        defaultMotor: form.get("defaultMotor") || "F",
        heightMm: form.get("heightMm") || "",
        widthMm: form.get("widthMm") || ""
      });
    }
  }

  validateSetupStep() {
    if (this.setupStep === 1) return this.setupDraft.teamName.trim() && this.setupDraft.school.trim();
    if (this.setupStep === 2) return this.setupDraft.rocketName.trim() && finiteNumber(this.setupDraft.dryMassGrams) > 0;
    return true;
  }

  finishSetup() {
    this.captureSetupForms();
    if (!this.validateSetupStep()) return;
    const team = {
      id: uid(),
      name: this.setupDraft.teamName.trim(),
      school: this.setupDraft.school.trim()
    };
    const rocket = {
      id: uid(),
      teamId: team.id,
      name: this.setupDraft.rocketName.trim(),
      dryMassGrams: finiteNumber(this.setupDraft.dryMassGrams, 650),
      diameterMm: finiteNumber(this.setupDraft.diameterMm, 66),
      material: this.setupDraft.material || "Cardboard",
      parachuteSizeIn: finiteNumber(this.setupDraft.parachuteSizeIn, 18),
      defaultMotor: this.setupDraft.defaultMotor || "F",
      heightMm: finiteNumber(this.setupDraft.heightMm, 700),
      widthMm: finiteNumber(this.setupDraft.widthMm, 66),
      lockedForNationals: this.setupDraft.flightMode === "nationals"
    };
    this.activeTab = "account";
    this.save({
      ...this.state,
      setupComplete: true,
      flightMode: this.setupDraft.flightMode === "nationals" && !isNationalsUnlocked(this.state) ? "competition" : this.setupDraft.flightMode,
      teams: [team],
      rockets: [rocket],
      flights: [],
      targetAltitudeFt: this.setupDraft.flightMode === "hobby" ? 800 : 790
    });
  }

  setMode(mode) {
    if (mode === "nationals" && !isNationalsUnlocked(this.state)) return;
    this.save({
      ...this.state,
      flightMode: mode,
      targetAltitudeFt: mode === "hobby" ? this.state.targetAltitudeFt : 790
    });
  }

  async installApp() {
    if (this.installPrompt) {
      const prompt = this.installPrompt;
      this.installPrompt = null;
      prompt.prompt();
      const choice = await prompt.userChoice;
      this.installStatus = choice.outcome === "accepted" ? "Installing on this device." : "Install skipped.";
      this.render();
      return;
    }
    this.installStatus = "On iPhone: Share -> Add to Home Screen. On desktop: use the browser install icon.";
    this.render();
  }

  startTimer() {
    const remaining = this.remainingSeconds() || 45 * 60;
    this.save({ ...this.state, launchTimerState: "running", launchWindowSeconds: remaining, launchWindowEndsAt: new Date(Date.now() + remaining * 1000).toISOString() });
  }

  pauseTimer() {
    this.save({ ...this.state, launchTimerState: "paused", launchWindowSeconds: this.remainingSeconds(), launchWindowEndsAt: null });
  }

  resetTimer() {
    this.save({ ...this.state, launchTimerState: "stopped", launchWindowSeconds: 45 * 60, launchWindowEndsAt: null });
  }

  async pullWeather() {
    const location = this.querySelector("#weather-location")?.value.trim() || this.weatherLocation.trim();
    if (!location) {
      this.weatherStatus = "Enter a launch site first.";
      this.render();
      return;
    }
    this.weatherLocation = location;
    this.weatherStatus = "Pulling live weather...";
    this.render();
    try {
      this.weatherDraft = await lookupWeather(location);
      this.weatherStatus = `Updated from live weather for ${this.weatherDraft.location}.`;
    } catch (error) {
      this.weatherStatus = "Weather lookup failed. Manual weather fields still work offline.";
    }
    this.render();
  }

  addChecklistItem() {
    const title = prompt("Checklist item");
    if (!title?.trim()) return;
    this.save({ ...this.state, checklist: [...this.state.checklist, { id: uid(), title: title.trim(), done: false }] });
  }

  toggleChecklist(id) {
    this.save({ ...this.state, checklist: this.state.checklist.map((item) => item.id === id ? { ...item, done: !item.done } : item) });
  }

  deleteChecklist(id) {
    this.save({ ...this.state, checklist: this.state.checklist.filter((item) => item.id !== id) });
  }

  saveFlight(event) {
    event.preventDefault();
    const form = new FormData(event.target);
    const rocket = this.state.rockets.find((item) => item.id === form.get("rocketId")) || this.state.rockets[0];
    if (!rocket) return;
    const flight = normalizeFlight({
      id: this.editFlightId || uid(),
      rocketId: rocket.id,
      teamId: rocket.teamId,
      flownAt: this.editFlightId ? this.state.flights.find((item) => item.id === this.editFlightId)?.flownAt : new Date().toISOString(),
      motorType: form.get("motorType") || rocket.defaultMotor || "F",
      rocketMassGrams: finiteNumber(form.get("rocketMassGrams"), rocket.dryMassGrams),
      measuredAltitudeFt: finiteNumber(form.get("measuredAltitudeFt"), 0),
      targetAltitudeFt: numberOrNull(form.get("targetAltitudeFt")),
      flightTimeSeconds: numberOrNull(form.get("flightTimeSeconds")),
      parachuteSizeIn: finiteNumber(form.get("parachuteSizeIn"), rocket.parachuteSizeIn || 18),
      reefedCm: numberOrNull(form.get("reefedCm")),
      descentSystem: form.get("descentSystem") || "Reefed chute",
      eggStatus: form.get("eggStatus") || "Unknown",
      notes: form.get("notes") || "",
      round: modeLabel(this.state.flightMode),
      weather: {
        temperatureF: finiteNumber(form.get("temperatureF"), 72),
        windMph: finiteNumber(form.get("windMph"), 0),
        humidityPercent: finiteNumber(form.get("humidityPercent"), 0),
        location: this.weatherDraft.location
      }
    });
    const flights = this.editFlightId
      ? this.state.flights.map((item) => item.id === this.editFlightId ? flight : item)
      : [flight, ...this.state.flights];
    this.editFlightId = null;
    this.save({ ...this.state, flights });
  }

  deleteFlight(id) {
    this.editFlightId = this.editFlightId === id ? null : this.editFlightId;
    const deletedFlightIds = [...new Set([...(this.state.deletedFlightIds || []), id])];
    this.save({ ...this.state, flights: this.state.flights.filter((flight) => flight.id !== id), deletedFlightIds });
  }

  saveRocket(event) {
    event.preventDefault();
    const form = new FormData(event.target);
    const rocket = {
      id: this.editRocketId || uid(),
      teamId: form.get("teamId") || this.state.teams[0]?.id,
      name: form.get("rocketName") || "New Rocket",
      dryMassGrams: finiteNumber(form.get("dryMassGrams"), 650),
      diameterMm: finiteNumber(form.get("diameterMm"), 66),
      material: form.get("material") || "Cardboard",
      parachuteSizeIn: finiteNumber(form.get("parachuteSizeIn"), 18),
      defaultMotor: form.get("defaultMotor") || "F",
      heightMm: finiteNumber(form.get("heightMm"), 700),
      widthMm: finiteNumber(form.get("widthMm"), finiteNumber(form.get("diameterMm"), 66)),
      lockedForNationals: this.state.flightMode === "nationals"
    };
    const rockets = this.editRocketId
      ? this.state.rockets.map((item) => item.id === this.editRocketId ? rocket : item)
      : [...this.state.rockets, rocket];
    this.editRocketId = null;
    this.save({ ...this.state, rockets });
  }

  deleteRocket(id) {
    this.editRocketId = this.editRocketId === id ? null : this.editRocketId;
    const rockets = this.state.rockets.filter((rocket) => rocket.id !== id);
    const flights = this.state.flights.filter((flight) => flight.rocketId !== id);
    const deletedRocketIds = [...new Set([...(this.state.deletedRocketIds || []), id])];
    const deletedFlightIds = [
      ...new Set([
        ...(this.state.deletedFlightIds || []),
        ...this.state.flights.filter((flight) => flight.rocketId === id).map((flight) => flight.id)
      ])
    ];
    this.save({ ...this.state, rockets, flights, deletedRocketIds, deletedFlightIds });
  }

  generateSyncKey() {
    const syncKey = crypto.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    this.syncStatus = "New sync key generated. Use this same key on your other device.";
    this.save({ ...this.state, profile: { ...this.state.profile, syncKey, syncEnabled: true } });
  }

  saveAccount(event) {
    event.preventDefault();
    const form = new FormData(event.target);
    const syncEnabled = form.get("syncEnabled") === "on";
    const existingSyncKey = this.state.profile.syncKey || "";
    const nextSyncKey = String(form.get("syncKey") || "").trim() || (syncEnabled ? existingSyncKey || crypto.randomUUID?.() || uid() : "");
    const profile = {
      displayName: form.get("displayName") || "",
      email: form.get("email") || "",
      school: form.get("school") || "",
      teamNumber: form.get("teamNumber") || "",
      nationalsStatus: form.get("nationalsStatus") || "unknown",
      syncEnabled,
      syncKey: nextSyncKey
    };
    const flightMode = profile.nationalsStatus === "qualified" ? this.state.flightMode : (this.state.flightMode === "nationals" ? "competition" : this.state.flightMode);
    this.syncStatus = syncEnabled ? "Account saved. Sync will run automatically." : "Account saved locally.";
    this.save({ ...this.state, profile, flightMode });
    if (syncEnabled) this.pullSync();
  }

  importCsv(file) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const rows = String(reader.result).split(/\r?\n/).slice(1).filter(Boolean);
      const imported = rows.map((row) => {
        const cells = row.match(/("([^"]|"")*"|[^,]+)/g)?.map((cell) => cell.replace(/^"|"$/g, "").replaceAll('""', '"')) || [];
        const rocket = this.state.rockets.find((item) => item.id === cells[1]) || this.state.rockets[0];
        if (!rocket) return null;
        return normalizeFlight({
          id: uid(),
          flownAt: cells[0] || new Date().toISOString(),
          rocketId: rocket.id,
          teamId: rocket.teamId,
          motorType: cells[3] || "F",
          rocketMassGrams: finiteNumber(cells[4], rocket.dryMassGrams),
          targetAltitudeFt: numberOrNull(cells[5]),
          flightTimeSeconds: numberOrNull(cells[6]),
          weather: { temperatureF: finiteNumber(cells[7], 72), windMph: finiteNumber(cells[8], 0), humidityPercent: finiteNumber(cells[9], 0) },
          measuredAltitudeFt: finiteNumber(cells[10], 0),
          parachuteSizeIn: finiteNumber(cells[11], 18),
          reefedCm: numberOrNull(cells[12]),
          eggStatus: cells[13] || "Unknown",
          descentSystem: cells[14] || "Reefed chute",
          notes: cells[15] || "Imported from CSV"
        });
      }).filter(Boolean);
      this.save({ ...this.state, flights: [...imported, ...this.state.flights] });
    };
    reader.readAsText(file);
  }
}

customElements.define("arc-flight-app", ArcFlightApp);

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register(new URL("../sw.js", import.meta.url)).catch(() => {
      // The app still works without offline caching, such as in private browsing.
    });
  });
}

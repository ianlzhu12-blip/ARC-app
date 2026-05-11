import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { readFile } from "node:fs/promises";

const root = process.cwd();
const port = Number(process.env.PORT || 5173);
const openAIModel = process.env.OPENAI_MODEL || "gpt-5";
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon"
};

function sendJSON(response, status, payload) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
}

async function readJSONBody(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? JSON.parse(text) : {};
}

function parseDelimitedLine(line, delimiter) {
  const output = [];
  let current = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === "\"") {
      if (quoted && line[index + 1] === "\"") {
        current += "\"";
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === delimiter && !quoted) {
      output.push(current.trim());
      current = "";
    } else {
      current += character;
    }
  }
  output.push(current.trim());
  return output;
}

function detectedDelimiter(lines) {
  const delimiters = ["\t", ",", ";"];
  return delimiters
    .map((delimiter) => ({
      delimiter,
      score: lines.slice(0, 12).reduce((total, line) => total + parseDelimitedLine(line, delimiter).length, 0)
    }))
    .sort((left, right) => right.score - left.score)[0]?.delimiter || "\t";
}

function normalizeHeader(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[()/_\-.]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const importKeys = {
  altitude: ["altitude", "alt", "alt ft", "alt feet", "measured altitude", "measured alt", "altitude ft", "flight altitude", "flight altitude ft", "actual altitude", "actual altitude ft", "apogee", "apogee ft", "flight height", "flight height ft", "measured height", "max altitude", "peak altitude"],
  targetAltitude: ["target altitude", "target alt", "target alt ft", "target altitude ft", "wanted altitude", "wanted alt", "wanted altitude ft", "goal altitude", "goal alt", "goal altitude ft", "planned altitude", "planned alt", "planned altitude ft"],
  rocket: ["rocket", "rocket name", "vehicle", "airframe"],
  motor: ["motor", "motor designation", "engine", "engine designation", "motor type"],
  mass: ["mass", "mass g", "rocket mass", "loaded mass", "loaded mass g", "weight", "weight g", "wt", "wt g", "liftoff mass", "lift off mass"],
  time: ["flight time", "flight time s", "flight time sec", "time", "duration", "total time"],
  temperature: ["temperature", "temperature f", "temp", "temp f", "air temp"],
  wind: ["wind", "wind mph", "wind speed", "wind speed mph"],
  humidity: ["humidity", "humidity %", "relative humidity", "rh"],
  parachute: ["parachute", "parachute in", "parachute size", "chute", "chute in"],
  reefedCentimeters: ["reef", "reefed", "reefed cm", "reef cm", "reefing", "reefing cm", "reef length", "reef length cm", "reefed length", "reefed length cm", "centimeters reefed", "cm reefed", "chute reef", "parachute reef"],
  notes: ["notes", "comments", "comment", "observations"],
  date: ["date", "flight date", "date time", "datetime", "timestamp", "launch date"],
  egg: ["egg", "egg status", "payload", "payload status", "egg condition"],
  attachments: ["attachments", "attachment", "files", "file"]
};

function valueFor(columns, indexByHeader, keys) {
  for (const rawKey of keys) {
    const key = normalizeHeader(rawKey);
    const index = indexByHeader.get(key);
    if (index !== undefined && columns[index]) {
      return columns[index];
    }
  }
  for (const rawKey of keys) {
    const key = normalizeHeader(rawKey);
    const keyTokens = new Set(key.split(" ").filter(Boolean));
    for (const [header, index] of indexByHeader.entries()) {
      if (key === "altitude" && ["target", "wanted", "goal", "planned"].some((token) => header.includes(token))) {
        continue;
      }
      const headerTokens = new Set(header.split(" ").filter(Boolean));
      const overlap = [...keyTokens].filter((token) => headerTokens.has(token)).length;
      if ((header.includes(key) || key.includes(header) || overlap >= Math.min(2, keyTokens.size)) && columns[index]) {
        return columns[index];
      }
    }
  }
  return "";
}

function inferredUnit(value, header = "") {
  const combined = `${normalizeHeader(header)} ${normalizeHeader(value)}`;
  if (combined.includes("kg") || combined.includes("kilogram")) return "kilograms";
  if (combined.includes("oz") || combined.includes("ounce")) return "ounces";
  if (combined.includes("lb") || combined.includes("pound")) return "pounds";
  if (combined.includes("gram") || combined.includes(" g")) return "grams";
  if (combined.includes("meter") || combined.includes(" m ")) return "meters";
  if (combined.includes("feet") || combined.includes("foot") || combined.includes(" ft")) return "feet";
  if (combined.includes("cm") || combined.includes("centimeter")) return "centimeters";
  if (combined.includes("mm") || combined.includes("millimeter")) return "millimeters";
  if (combined.includes("inch") || combined.includes(" in")) return "inches";
  if (combined.includes("celsius") || combined.includes(" deg c") || combined.includes(" c")) return "celsius";
  if (combined.includes("fahrenheit") || combined.includes(" deg f") || combined.includes(" f")) return "fahrenheit";
  if (combined.includes("m s") || combined.includes("m/s")) return "metersPerSecond";
  if (combined.includes("km h") || combined.includes("km/h") || combined.includes("kph")) return "kilometersPerHour";
  if (combined.includes("mph")) return "mph";
  return null;
}

function convertedNumber(number, role, unit) {
  if ((role === "altitude" || role === "targetAltitude") && unit === "meters") return number * 3.28084;
  if (role === "mass" && unit === "kilograms") return number * 1000;
  if (role === "mass" && unit === "ounces") return number * 28.3495;
  if (role === "mass" && unit === "pounds") return number * 453.592;
  if (role === "temperature" && unit === "celsius") return number * 9 / 5 + 32;
  if (role === "wind" && unit === "metersPerSecond") return number * 2.23694;
  if (role === "wind" && unit === "kilometersPerHour") return number * 0.621371;
  if (role === "parachute" && unit === "centimeters") return number / 2.54;
  if (role === "parachute" && unit === "millimeters") return number / 25.4;
  if (role === "reefedCentimeters" && unit === "inches") return number * 2.54;
  if (role === "reefedCentimeters" && unit === "millimeters") return number / 10;
  if (role === "reefedCentimeters" && unit === "meters") return number * 100;
  return number;
}

function numberFrom(value, role = "", header = "") {
  const match = String(value || "").replace(/,/g, "").match(/-?\d+(?:\.\d+)?/);
  if (!match) return null;
  const number = convertedNumber(Number(match[0]), role, inferredUnit(value, header));
  if (!Number.isFinite(number)) return null;
  if ((role === "altitude" || role === "targetAltitude") && (number < 20 || number > 5000)) return null;
  if (role === "mass" && (number < 1 || number > 5000)) return null;
  if (role === "time" && (number < 0 || number > 300)) return null;
  if (role === "temperature" && (number < -40 || number > 140)) return null;
  if (role === "wind" && (number < 0 || number > 120)) return null;
  if (role === "humidity" && (number < 0 || number > 100)) return null;
  if (role === "parachute" && (number < 1 || number > 160)) return null;
  if (role === "reefedCentimeters" && (number < 0 || number > 500)) return null;
  return number;
}

function rolePenalty(header, role) {
  if (role === "altitude") {
    return ["target", "wanted", "goal", "desired", "planned", "rocket height", "rocket length", "body length", "length", "diameter", "width", "span", "size"].some((token) => header.includes(token)) ? 7 : 0;
  }
  if (role === "targetAltitude") {
    return ["measured", "actual", "observed", "recorded", "apogee", "max", "peak", "rocket height", "rocket length", "body length", "length", "diameter", "width"].some((token) => header.includes(token)) ? 5 : 0;
  }
  if (role === "time" && (header.includes("date") || header.includes("timestamp"))) return 5;
  if (role === "mass" && (header.includes("motor mass") || header.includes("propellant"))) return 4;
  if (role === "parachute" && header.includes("reef")) return 5;
  if (role === "reefedCentimeters" && (header.includes("diameter") || header.includes("size"))) return 4;
  if (role === "wind" && header.includes("direction")) return 4;
  return 0;
}

function unitScore(header, role) {
  const tokens = new Set(header.split(" ").filter(Boolean));
  if (role === "altitude" || role === "targetAltitude") return header.includes("ft") || header.includes("feet") || header.includes("meter") ? 1.2 : 0;
  if (role === "mass") return tokens.has("g") || header.includes("gram") || header.includes("kg") || header.includes("oz") || header.includes("lb") ? 1.2 : 0;
  if (role === "time") return tokens.has("s") || header.includes("sec") || header.includes("second") ? 0.8 : 0;
  if (role === "temperature") return header.includes("temp") || tokens.has("f") || tokens.has("c") ? 0.8 : 0;
  if (role === "wind") return header.includes("mph") || header.includes("m s") || header.includes("km h") ? 0.8 : 0;
  if (role === "humidity") return header.includes("%") || header.includes("percent") ? 0.8 : 0;
  if (role === "parachute") return tokens.has("in") || header.includes("inch") || header.includes("cm") ? 0.8 : 0;
  if (role === "reefedCentimeters") return header.includes("cm") || header.includes("centimeter") || header.includes("reef") ? 1.2 : 0;
  return 0;
}

function columnScore(header, role) {
  const normalized = normalizeHeader(header);
  if (!normalized) return 0;
  const tokens = new Set(normalized.split(" ").filter(Boolean));
  return Math.max(...(importKeys[role] || []).map((key) => {
    const normalizedKey = normalizeHeader(key);
    const keyTokens = new Set(normalizedKey.split(" ").filter(Boolean));
    let score = 0;
    if (normalized === normalizedKey) score += 8;
    else if (normalized.includes(normalizedKey) || normalizedKey.includes(normalized)) score += 5;
    score += [...tokens].filter((token) => keyTokens.has(token)).length * 2.2;
    score += unitScore(normalized, role);
    score -= rolePenalty(normalized, role);
    return score;
  }), 0);
}

function inferredColumnMap(headers) {
  const roles = Object.keys(importKeys);
  const minimumScore = (role) => ["altitude", "targetAltitude", "mass"].includes(role) ? 5.5 : 4.5;
  const candidates = roles.flatMap((role) => headers.map((header, index) => ({
    role,
    index,
    score: columnScore(header, role)
  }))).filter((candidate) => candidate.score >= minimumScore(candidate.role))
    .sort((left, right) => right.score - left.score || left.index - right.index);
  const output = new Map();
  const used = new Set();
  for (const candidate of candidates) {
    if (!output.has(candidate.role) && !used.has(candidate.index)) {
      output.set(candidate.role, candidate.index);
      used.add(candidate.index);
    }
  }
  return output;
}

function mappedValue(columns, columnMap, role) {
  const index = columnMap.get(role);
  if (index === undefined || !columns[index]) return "";
  return columns[index];
}

function mappedHeader(headers, columnMap, role) {
  const index = columnMap.get(role);
  return index === undefined ? "" : String(headers[index] || "");
}

async function openAIClient() {
  if (!process.env.OPENAI_API_KEY) return null;
  const { default: OpenAI } = await import("openai");
  return new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
}

function safeJSONFromText(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}|\[[\s\S]*\]/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

const nullableString = { anyOf: [{ type: "string" }, { type: "null" }] };
const nullableNumber = { anyOf: [{ type: "number" }, { type: "null" }] };
const flightRowSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "rocketName",
    "motorDesignation",
    "massGrams",
    "targetAltitudeFeet",
    "altitudeFeet",
    "flightTimeSeconds",
    "temperatureF",
    "windMPH",
    "humidityPercent",
    "parachuteSizeInches",
    "parachuteReefedCentimeters",
    "notes",
    "flownAtText",
    "eggStatus",
    "attachments"
  ],
  properties: {
    rocketName: nullableString,
    motorDesignation: nullableString,
    massGrams: nullableNumber,
    targetAltitudeFeet: nullableNumber,
    altitudeFeet: nullableNumber,
    flightTimeSeconds: nullableNumber,
    temperatureF: nullableNumber,
    windMPH: nullableNumber,
    humidityPercent: nullableNumber,
    parachuteSizeInches: nullableNumber,
    parachuteReefedCentimeters: nullableNumber,
    notes: nullableString,
    flownAtText: nullableString,
    eggStatus: nullableString,
    attachments: nullableString
  }
};

const flightSheetImportSchema = {
  type: "object",
  additionalProperties: false,
  required: ["rows"],
  properties: {
    rows: {
      type: "array",
      items: flightRowSchema
    }
  }
};

const rocketRecommendationSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "suggestedMassGrams",
    "predictedAltitudeFeet",
    "confidence",
    "reasoning",
    "notes"
  ],
  properties: {
    suggestedMassGrams: nullableNumber,
    predictedAltitudeFeet: nullableNumber,
    confidence: nullableNumber,
    reasoning: { type: "string" },
    notes: {
      type: "array",
      items: { type: "string" }
    }
  }
};

function finiteOrNull(value, role) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return numberFrom(String(number), role);
}

function cleanStringOrNull(value) {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text ? text : null;
}

function sanitizeOpenAIRows(rows) {
  return (Array.isArray(rows) ? rows : []).map((row) => ({
    rocketName: cleanStringOrNull(row.rocketName),
    motorDesignation: cleanStringOrNull(row.motorDesignation),
    massGrams: finiteOrNull(row.massGrams, "mass"),
    targetAltitudeFeet: finiteOrNull(row.targetAltitudeFeet, "targetAltitude"),
    altitudeFeet: finiteOrNull(row.altitudeFeet, "altitude"),
    flightTimeSeconds: finiteOrNull(row.flightTimeSeconds, "time"),
    temperatureF: finiteOrNull(row.temperatureF, "temperature"),
    windMPH: finiteOrNull(row.windMPH, "wind"),
    humidityPercent: finiteOrNull(row.humidityPercent, "humidity"),
    parachuteSizeInches: finiteOrNull(row.parachuteSizeInches, "parachute"),
    parachuteReefedCentimeters: finiteOrNull(row.parachuteReefedCentimeters, "reefedCentimeters"),
    notes: cleanStringOrNull(row.notes),
    flownAtText: cleanStringOrNull(row.flownAtText),
    eggStatus: cleanStringOrNull(row.eggStatus),
    attachments: cleanStringOrNull(row.attachments)
  })).filter((row) => row.altitudeFeet !== null);
}

function mergeFlightRows(primaryRows, backupRows) {
  const primary = Array.isArray(primaryRows) ? primaryRows : [];
  const backup = Array.isArray(backupRows) ? backupRows : [];
  if (!backup.length) return primary;
  if (!primary.length) return backup;

  const merged = primary.map((row, index) => {
    const backupRow = backup[index] || {};
    return Object.fromEntries(Object.keys(flightRowSchema.properties).map((key) => [
      key,
      row[key] ?? backupRow[key] ?? null
    ]));
  });

  if (primary.length < Math.ceil(backup.length * 0.7)) {
    return mergeFlightRows(backup, primary);
  }

  return merged;
}

async function parseFlightSheetWithOpenAI({ text, fileName, parserRows = [] }) {
  const client = await openAIClient();
  if (!client) return [];

  const response = await client.responses.create({
    model: openAIModel,
    reasoning: { effort: "low" },
    text: {
      format: {
        type: "json_schema",
        name: "arc_flight_sheet_import",
        strict: true,
        schema: flightSheetImportSchema
      }
    },
    instructions: [
      "You convert American Rocketry Challenge model rocket flight spreadsheet text into schema-valid JSON.",
      "Each output row must represent one actual flight log, not a rocket specification row, summary row, blank row, average row, or notes-only row.",
      "Use null for missing values. Never invent altitudes, masses, motors, dates, weather, or times.",
      "Only set altitudeFeet from measured flight-result columns such as measured altitude, actual altitude, apogee, peak altitude, or max altitude.",
      "Do not use target/wanted altitude, rocket body height, rocket length, width, diameter, material, parachute size, or motor dimensions as altitudeFeet.",
      "Convert units when obvious: meters to feet for altitude, ounces/pounds/kilograms to grams for mass, Celsius to Fahrenheit, and inches to centimeters for reefed length.",
      "Put parachute diameter/size in parachuteSizeInches and reefed/reefing length in parachuteReefedCentimeters.",
      "Preserve date/time text in flownAtText instead of guessing a new date.",
      "If the sheet includes egg/payload condition, map it into eggStatus as intact, cracked, broken, not carried, or unknown.",
      "Use the parser draft only as a hint. Correct it when spreadsheet context shows a better column mapping, but keep the same actual flight rows whenever possible."
    ].join(" "),
    input: [
      {
        role: "user",
        content: [
          `File name: ${fileName}`,
          "",
          `Parser draft rows for comparison:\n${JSON.stringify(parserRows).slice(0, 20000)}`,
          "",
          `Spreadsheet text:\n${String(text || "").slice(0, 60000)}`
        ].join("\n")
      }
    ]
  });

  const parsed = safeJSONFromText(response.output_text);
  return mergeFlightRows(sanitizeOpenAIRows(parsed?.rows), parserRows);
}

async function rocketRecommendationWithOpenAI(body) {
  const client = await openAIClient();
  if (!client) return null;

  const response = await client.responses.create({
    model: openAIModel,
    reasoning: { effort: "medium" },
    text: {
      format: {
        type: "json_schema",
        name: "arc_rocket_recommendation",
        strict: true,
        schema: rocketRecommendationSchema
      }
    },
    instructions: [
      "You are helping tune American Rocketry Challenge model rocket practice data for altitude and time targeting.",
      "Use only the supplied log data, rocket specs, weather, OpenRocket summary, and model prediction. Never invent extra flights.",
      "Prefer repeatable data patterns over single outlier flights. If data is weak, keep confidence low and explain the missing calibration.",
      "Suggested mass must be loaded mass in grams. Predicted altitude must be apogee in feet.",
      "If parachute reefing, flight-time, delay-drill, or weather effects appear in supplied data, mention them briefly in notes.",
      "Keep reasoning practical for a launch field: one or two short sentences."
    ].join(" "),
    input: JSON.stringify(body).slice(0, 20000)
  });

  const parsed = safeJSONFromText(response.output_text);
  if (!parsed) return null;
  return {
    suggestedMassGrams: finiteOrNull(parsed.suggestedMassGrams, "mass"),
    predictedAltitudeFeet: finiteOrNull(parsed.predictedAltitudeFeet, "altitude"),
    confidence: Math.max(0, Math.min(1, Number(parsed.confidence) || 0)),
    reasoning: cleanStringOrNull(parsed.reasoning) || "AI recommendation used the supplied flight data.",
    notes: Array.isArray(parsed.notes) ? parsed.notes.map(cleanStringOrNull).filter(Boolean).slice(0, 5) : []
  };
}

function parseFlightSheetText(text) {
  const lines = String(text || "").split(/\r?\n/).filter((line) => line.trim());
  if (!lines.length) return [];
  const delimiter = detectedDelimiter(lines);
  const rows = lines.map((line) => parseDelimitedLine(line, delimiter));
  const headerIndex = rows.slice(0, 12).map((row, index) => {
    const cells = row.map(normalizeHeader);
    const score = Object.values(importKeys).reduce((total, keys) => {
      const matched = cells.some((cell) => keys.some((key) => {
        const normalizedKey = normalizeHeader(key);
        return cell === normalizedKey || cell.includes(normalizedKey) || normalizedKey.includes(cell);
      }));
      return total + (matched ? 1 : 0);
    }, 0);
    return { index, score };
  }).sort((left, right) => right.score - left.score)[0];

  if (!headerIndex || headerIndex.score < 2) return [];
  const headers = rows[headerIndex.index];
  const indexByHeader = new Map(headers.map((header, index) => [normalizeHeader(header), index]));
  const columnMap = inferredColumnMap(headers);

  return rows.slice(headerIndex.index + 1).map((columns) => {
    const altitude = numberFrom(mappedValue(columns, columnMap, "altitude"), "altitude", mappedHeader(headers, columnMap, "altitude"));
    if (altitude === null) return null;
    return {
      rocketName: mappedValue(columns, columnMap, "rocket") || valueFor(columns, indexByHeader, importKeys.rocket),
      motorDesignation: mappedValue(columns, columnMap, "motor") || valueFor(columns, indexByHeader, importKeys.motor),
      massGrams: numberFrom(mappedValue(columns, columnMap, "mass") || valueFor(columns, indexByHeader, importKeys.mass), "mass", mappedHeader(headers, columnMap, "mass")),
      targetAltitudeFeet: numberFrom(mappedValue(columns, columnMap, "targetAltitude") || valueFor(columns, indexByHeader, importKeys.targetAltitude), "targetAltitude", mappedHeader(headers, columnMap, "targetAltitude")),
      altitudeFeet: altitude,
      flightTimeSeconds: numberFrom(mappedValue(columns, columnMap, "time") || valueFor(columns, indexByHeader, importKeys.time), "time", mappedHeader(headers, columnMap, "time")),
      temperatureF: numberFrom(mappedValue(columns, columnMap, "temperature") || valueFor(columns, indexByHeader, importKeys.temperature), "temperature", mappedHeader(headers, columnMap, "temperature")),
      windMPH: numberFrom(mappedValue(columns, columnMap, "wind") || valueFor(columns, indexByHeader, importKeys.wind), "wind", mappedHeader(headers, columnMap, "wind")),
      humidityPercent: numberFrom(mappedValue(columns, columnMap, "humidity") || valueFor(columns, indexByHeader, importKeys.humidity), "humidity", mappedHeader(headers, columnMap, "humidity")),
      parachuteSizeInches: numberFrom(mappedValue(columns, columnMap, "parachute") || valueFor(columns, indexByHeader, importKeys.parachute), "parachute", mappedHeader(headers, columnMap, "parachute")),
      parachuteReefedCentimeters: numberFrom(mappedValue(columns, columnMap, "reefedCentimeters") || valueFor(columns, indexByHeader, importKeys.reefedCentimeters), "reefedCentimeters", mappedHeader(headers, columnMap, "reefedCentimeters")),
      notes: mappedValue(columns, columnMap, "notes") || valueFor(columns, indexByHeader, importKeys.notes),
      flownAtText: mappedValue(columns, columnMap, "date") || valueFor(columns, indexByHeader, importKeys.date),
      eggStatus: mappedValue(columns, columnMap, "egg") || valueFor(columns, indexByHeader, importKeys.egg),
      attachments: mappedValue(columns, columnMap, "attachments") || valueFor(columns, indexByHeader, importKeys.attachments)
    };
  }).filter(Boolean);
}

createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://${request.headers.host}`);
    if (request.method === "POST" && url.pathname === "/api/import-flight-sheet") {
      const body = await readJSONBody(request);
      const parserRows = parseFlightSheetText(body.text || "");
      let rows = [];
      let source = "server-parser";
      if (process.env.OPENAI_API_KEY) {
        try {
          rows = await parseFlightSheetWithOpenAI({
            text: body.text || "",
            fileName: body.fileName || "flight-sheet",
            parserRows
          });
          source = "openai-structured";
        } catch (error) {
          console.error("OpenAI flight sheet import failed:", error);
          source = "server-parser-openai-fallback";
        }
      }
      if (rows.length === 0) {
        rows = parserRows;
        if (source === "openai-structured") {
          source = "server-parser-openai-empty";
        }
      }
      sendJSON(response, 200, {
        rows,
        source,
        message: `${source.startsWith("openai") ? "GPT converted" : "Server parsed"} ${rows.length} editable flight log${rows.length === 1 ? "" : "s"}.`
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/rocket-ai") {
      const body = await readJSONBody(request);
      const openAIResult = await rocketRecommendationWithOpenAI(body);
      if (openAIResult) {
        sendJSON(response, 200, {
          ...openAIResult,
          source: "openai"
        });
        return;
      }
      sendJSON(response, 200, {
        suggestedMassGrams: body.suggestedMassGrams ?? null,
        predictedAltitudeFeet: body.predictedAltitudeFeet ?? null,
        confidence: body.confidence ?? 0,
        reasoning: "Server endpoint is connected. Add OPENAI_API_KEY on the server to enable OpenAI-powered recommendations.",
        source: "local-placeholder"
      });
      return;
    }

    const requested = url.pathname === "/" ? "/index.html" : url.pathname;
    const safePath = normalize(requested).replace(/^(\.\.[/\\])+/, "");
    const filePath = join(root, safePath);
    const body = await readFile(filePath);
    response.writeHead(200, { "content-type": types[extname(filePath)] || "application/octet-stream" });
    response.end(body);
  } catch {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("Not found");
  }
}).listen(port, () => {
  console.log(`ARC Flight Optimizer running at http://localhost:${port}`);
});

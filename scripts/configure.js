#!/usr/bin/env node
// ============================================================
// configure.js — Converts environment variables to OpenClaw
// gateway JSON configuration at /data/.openclaw/config.json
// ============================================================

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const CONFIG_DIR = "/data/.openclaw";
const CONFIG_PATH = path.join(CONFIG_DIR, "config.json");

// Ensure config directory exists
fs.mkdirSync(CONFIG_DIR, { recursive: true });

// Load existing config if present
let config = {};
if (fs.existsSync(CONFIG_PATH)) {
  try {
    config = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8"));
  } catch {
    config = {};
  }
}

// --------------- AI Provider Keys ---------------

const providers = [];

if (process.env.ANTHROPIC_API_KEY) {
  providers.push({
    id: "anthropic",
    name: "Anthropic",
    type: "anthropic",
    apiKey: process.env.ANTHROPIC_API_KEY,
  });
}

if (process.env.OPENAI_API_KEY) {
  providers.push({
    id: "openai",
    name: "OpenAI",
    type: "openai",
    apiKey: process.env.OPENAI_API_KEY,
  });
}

if (process.env.OPENROUTER_API_KEY) {
  providers.push({
    id: "openrouter",
    name: "OpenRouter",
    type: "openrouter",
    apiKey: process.env.OPENROUTER_API_KEY,
  });
}

if (process.env.GEMINI_API_KEY) {
  providers.push({
    id: "gemini",
    name: "Google Gemini",
    type: "gemini",
    apiKey: process.env.GEMINI_API_KEY,
  });
}

if (process.env.XAI_API_KEY) {
  providers.push({
    id: "xai",
    name: "xAI",
    type: "xai",
    apiKey: process.env.XAI_API_KEY,
  });
}

if (process.env.GROQ_API_KEY) {
  providers.push({
    id: "groq",
    name: "Groq",
    type: "groq",
    apiKey: process.env.GROQ_API_KEY,
  });
}

if (process.env.MISTRAL_API_KEY) {
  providers.push({
    id: "mistral",
    name: "Mistral",
    type: "mistral",
    apiKey: process.env.MISTRAL_API_KEY,
  });
}

if (process.env.OLLAMA_BASE_URL) {
  providers.push({
    id: "ollama",
    name: "Ollama",
    type: "ollama",
    baseUrl: process.env.OLLAMA_BASE_URL,
  });
}

if (providers.length > 0) {
  config.providers = providers;
}

// --------------- Gateway Token ---------------

const gatewayToken =
  process.env.OPENCLAW_GATEWAY_TOKEN ||
  config.gatewayToken ||
  crypto.randomBytes(32).toString("hex");

config.gatewayToken = gatewayToken;

// --------------- Primary Model Override ---------------

if (process.env.OPENCLAW_PRIMARY_MODEL) {
  config.primaryModel = process.env.OPENCLAW_PRIMARY_MODEL;
}

// --------------- Gateway Settings ---------------

config.host = "0.0.0.0";
config.port = 18789;
config.dataDir = "/data/.openclaw";
config.workspaceDir = "/data/workspace";

// --------------- Messaging Channels ---------------

if (process.env.TELEGRAM_BOT_TOKEN) {
  config.telegram = {
    botToken: process.env.TELEGRAM_BOT_TOKEN,
    dmPolicy: process.env.TELEGRAM_DM_POLICY || "pairing",
  };
}

if (process.env.DISCORD_BOT_TOKEN) {
  config.discord = {
    botToken: process.env.DISCORD_BOT_TOKEN,
  };
}

// --------------- Write Config ---------------

fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2) + "\n");

console.log("[configure.js] Config written to", CONFIG_PATH);
console.log(
  "[configure.js] Providers configured:",
  providers.map((p) => p.id).join(", ") || "(none from env)"
);
console.log("[configure.js] Gateway token:", gatewayToken.slice(0, 8) + "...");

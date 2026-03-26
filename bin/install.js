#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const https = require("https");

const SKILLS = ["perf-setup", "perf-query", "perf-dashboard", "perf-fix"];
const TARGET = path.join(process.cwd(), ".claude", "skills");

// ─── Preflight ──────────────────────────────────────────────────────
if (!fs.existsSync(path.join(process.cwd(), ".git"))) {
  console.error(
    "Error: Run this from the root of your project (no .git directory found)."
  );
  process.exit(1);
}

// ─── Anonymous install counter ──────────────────────────────────────
// Pings a public counter so the maintainer knows how many people use
// Unjank. Sends NO personal data — just increments a number.
// Opt out: UNJANK_NO_ANALYTICS=1 npx unjank-perf
if (!process.env.UNJANK_NO_ANALYTICS) {
  https
    .get("https://hits.sh/github.com/no-hup/unjank/install.svg", () => {})
    .on("error", () => {});
}

// ─── Resolve source skills directory ────────────────────────────────
// When run via npx, __dirname is inside the downloaded package
const sourceDir = path.join(__dirname, "..", "skills");

if (!fs.existsSync(sourceDir)) {
  console.error("Error: Could not find skills directory in package.");
  process.exit(1);
}

// ─── Copy skills ────────────────────────────────────────────────────
function copyDirSync(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

console.log("Installing Unjank skills...\n");
fs.mkdirSync(TARGET, { recursive: true });

for (const skill of SKILLS) {
  const src = path.join(sourceDir, skill);
  const dest = path.join(TARGET, skill);

  if (fs.existsSync(dest)) {
    console.log(`  Updating ${skill}...`);
    fs.rmSync(dest, { recursive: true, force: true });
  } else {
    console.log(`  Installing ${skill}...`);
  }
  copyDirSync(src, dest);
}

console.log(`
Unjank installed to .claude/skills/

Next steps:
  1. gcloud auth login && gcloud auth application-default login
  2. Open Claude Code and run: /perf-setup

Full docs: https://github.com/no-hup/unjank
`);

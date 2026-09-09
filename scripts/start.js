#!/usr/bin/env node

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SERVICES_FILE = path.join(__dirname, '..', 'services.json');
const ECOSYSTEM_FILE = path.join(__dirname, '..', 'ecosystem.config.js');
const LOGS_DIR = path.join(__dirname, '..', 'logs');

// Ensure logs directory exists
if (!fs.existsSync(LOGS_DIR)) {
  fs.mkdirSync(LOGS_DIR, { recursive: true });
}

// Load services config. Paths use $HOME so one repo works on every machine.
const expand = p => p.replace(/^~(?=\/|$)/, process.env.HOME).replace(/\$HOME/g, process.env.HOME);
const services = JSON.parse(fs.readFileSync(SERVICES_FILE, 'utf8'))
  .map(s => ({ ...s, cwd: expand(s.cwd), command: expand(s.command) }));

// Generate ecosystem.config.js
const ecosystem = {
  apps: services.map(service => {
    const parts = service.command.split(' ');
    return {
      name: service.name,
      script: parts[0],
      args: parts.slice(1).join(' '),
      cwd: service.cwd,
      interpreter: service.command.endsWith('.sh') ? '/bin/bash' : 'none',
      autorestart: true,
      watch: false,
      max_restarts: 10,
      restart_delay: 5000,
      error_file: path.join(LOGS_DIR, `${service.name}-error.log`),
      out_file: path.join(LOGS_DIR, `${service.name}-out.log`),
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
    };
  })
};

// Write ecosystem config
fs.writeFileSync(ECOSYSTEM_FILE, `module.exports = ${JSON.stringify(ecosystem, null, 2)};\n`);

// Get currently running pm2 processes
let runningProcesses = new Set();
try {
  const pm2List = JSON.parse(execSync('npx pm2 jlist', { encoding: 'utf8' }));
  runningProcesses = new Set(pm2List.filter(p => p.pm2_env.status === 'online').map(p => p.name));
} catch (e) {
  // pm2 not running or no processes
}

console.log('\n🚀 Stack Service Manager\n');

let started = 0;
let skipped = 0;

for (const service of services) {
  const isRunning = runningProcesses.has(service.name);

  if (isRunning) {
    console.log(`⏭️  ${service.name} — already running`);
    skipped++;
  } else {
    try {
      execSync('npx pm2 start ecosystem.config.js --only ' + service.name, {
        stdio: 'pipe',
        cwd: path.join(__dirname, '..')
      });
      console.log(`✅ ${service.name} — started`);
      started++;
    } catch (e) {
      console.log(`❌ ${service.name} — failed: ${e.message.split('\n')[0]}`);
    }
  }
}

// Show status
console.log('\n📊 Status:\n');
execSync('npx pm2 status', { stdio: 'inherit' });

console.log(`\n✨ Done: ${started} started, ${skipped} already running\n`);

#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SERVICES_FILE = path.join(__dirname, '..', 'services.json');

const name = process.argv[2];

if (!name) {
  console.log('\n🗑️  Remove Service\n');
  console.log('Usage: node scripts/remove.js <name>\n');
  console.log('Example: node scripts/remove.js 9router\n');
  process.exit(1);
}

// Load existing services
let services = [];
try {
  services = JSON.parse(fs.readFileSync(SERVICES_FILE, 'utf8'));
} catch (e) {
  console.log('❌ No services.json found');
  process.exit(1);
}

// Find and remove
const index = services.findIndex(s => s.name === name);
if (index === -1) {
  console.log(`\n❌ Service "${name}" not found`);
  process.exit(1);
}

services.splice(index, 1);
fs.writeFileSync(SERVICES_FILE, JSON.stringify(services, null, 2) + '\n');

// Stop pm2 process if running
try {
  execSync(`npx pm2 delete "${name}"`, { stdio: 'pipe' });
} catch (e) {
  // Process wasn't running
}

console.log(`\n✅ Removed "${name}"\n`);

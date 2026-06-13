#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const SERVICES_FILE = path.join(__dirname, '..', 'services.json');

// Get command line arguments
const args = process.argv.slice(2);

if (args.length < 2) {
  console.log('\n➕ Add New Service\n');
  console.log('Usage: node scripts/add.js <name> <command> [cwd]\n');
  console.log('Examples:');
  console.log('  node scripts/add.js 9router "9router --port 3000"');
  console.log('  node scripts/add.js myapp "node server.js" ~/myapp');
  console.log('  node scripts/add.js api "cd ~/api && npm start"\n');
  process.exit(1);
}

const name = args[0];
const command = args[1];
const cwd = args[2] || process.env.HOME + '/stack';

const service = { name, command, cwd };

// Load existing services
let services = [];
try {
  services = JSON.parse(fs.readFileSync(SERVICES_FILE, 'utf8'));
} catch (e) {
  // File doesn't exist or is empty
}

// Check for duplicate
if (services.find(s => s.name === name)) {
  console.log(`\n❌ Service "${name}" already exists`);
  process.exit(1);
}

// Add and save
services.push(service);
fs.writeFileSync(SERVICES_FILE, JSON.stringify(services, null, 2) + '\n');

console.log(`\n✅ Added "${name}"`);
console.log(`   Command: ${command}`);
console.log(`   CWD: ${cwd}`);
console.log(`\nRun "pnpm start" to launch all services\n`);

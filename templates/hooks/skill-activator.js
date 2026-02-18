#!/usr/bin/env node
/**
 * Skill Auto-Activator Hook
 *
 * Runs on UserPromptSubmit to detect relevant skills
 * and inject activation reminders into Claude's context.
 *
 * Usage: node skill-activator.js "<user-prompt>"
 */

const fs = require('fs');
const path = require('path');

function loadRules() {
  const rulesPath = path.join(process.cwd(), 'skill-rules.json');
  if (!fs.existsSync(rulesPath)) return {};

  try {
    const rules = JSON.parse(fs.readFileSync(rulesPath, 'utf-8'));
    // Remove _meta key
    delete rules._meta;
    return rules;
  } catch (e) {
    return {};
  }
}

function checkKeywords(prompt, keywords) {
  const lowerPrompt = prompt.toLowerCase();
  return keywords.some(kw => lowerPrompt.includes(kw.toLowerCase()));
}

function checkPatterns(prompt, patterns) {
  return patterns.some(pattern => {
    try {
      return new RegExp(pattern, 'i').test(prompt);
    } catch {
      return false;
    }
  });
}

function findMatchingSkills(prompt, rules) {
  const matches = [];

  for (const [skillName, rule] of Object.entries(rules)) {
    if (!rule.promptTriggers) continue;

    const hasKeyword = checkKeywords(prompt, rule.promptTriggers.keywords || []);
    const hasPattern = checkPatterns(prompt, rule.promptTriggers.intentPatterns || []);

    if (hasKeyword || hasPattern) {
      matches.push({
        name: skillName,
        priority: rule.priority || 'normal',
        enforcement: rule.enforcement || 'suggest'
      });
    }
  }

  // Sort by priority
  const priorityOrder = { critical: 0, high: 1, normal: 2, low: 3 };
  matches.sort((a, b) => (priorityOrder[a.priority] || 2) - (priorityOrder[b.priority] || 2));

  return matches;
}

function main() {
  const prompt = process.argv[2] || '';
  if (!prompt) process.exit(0);

  const rules = loadRules();
  if (Object.keys(rules).length === 0) process.exit(0);

  const matches = findMatchingSkills(prompt, rules);
  if (matches.length === 0) process.exit(0);

  // Output activation message (will be captured by hook)
  const skillList = matches
    .map(m => `  - ${m.name} (${m.enforcement}, ${m.priority})`)
    .join('\n');

  console.log(`[Skill Activation] Relevant skills detected:`);
  console.log(skillList);
  console.log(`Load and follow these skill guidelines.`);
}

main();

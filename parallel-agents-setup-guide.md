# Parallel AI Coding Agents — Setup Guide

**Version:** 1.0  
**Last Updated:** May 2026  
**Stack:** Ubuntu 24.04 · Proxmox · N8N · Cursor CLI · GitHub · Discord

---

## What This Guide Covers

This guide walks through setting up a fleet of parallel AI coding agents for any software project. Each agent is an Ubuntu VM running Cursor CLI headlessly, orchestrated by N8N via SSH, with Discord notifications for live updates and blocker alerts.

```
You (Cursor — Orchestrator machine)
    └── /dispatch command
         └── N8N (your-n8n-ip:5678)
              └── SSH → Each Agent VM
                   └── Cursor CLI (agent --print --yolo --trust)
                        └── Edits code → commits → pushes → Discord
```

---

## Variable Reference

Define these for your project before starting. They are referenced throughout the guide.

| Variable | Description | Example |
|----------|-------------|---------|
| `AGENT_USER` | Linux username on all agent VMs | `devuser` |
| `ORCHESTRATOR_NAME` | Name for the orchestrator machine | `sc-karl` |
| `ORCHESTRATOR_IP` | IP of your main Cursor/dev machine | `10.0.0.5` |
| `N8N_IP` | IP of the N8N server VM | `10.0.0.10` |
| `N8N_PORT` | N8N port (HTTP, not exposed to internet) | `5678` |
| `GITHUB_REPO` | SSH URL of your GitHub repo | `git@github.com:org/repo.git` |
| `REPO_NAME` | Folder name of the cloned repo | `my-project` |
| `AGENT_COUNT` | Number of agent VMs | `3`, `5`, `8` |

### Agent Naming Convention

Name agents sequentially. Each gets a unique IP, branch, and Discord channel:

| Agent | IP | Branch | Model | Role |
|-------|----|--------|-------|------|
| `agent-01` | `10.0.0.11` | `agent-agent-01` | `composer-2-fast` | Assign as needed |
| `agent-02` | `10.0.0.12` | `agent-agent-02` | `composer-2-fast` | Assign as needed |
| `agent-03` | `10.0.0.13` | `agent-agent-03` | `composer-2` | Tests / DevOps |
| `agent-N` | `10.0.0.1N` | `agent-agent-N` | `composer-2-fast` | General purpose |

> Agents 01 and 02 typically use `composer-2-fast` for speed. Assign `composer-2` to whichever agent handles testing, migrations, or complex reasoning tasks.

---

## Part 1 — Infrastructure Planning

### 1.1 VM Specifications

Create one VM per agent plus one for N8N.

**Agent VMs:**

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 vCPU | 8 vCPU |
| RAM | 4 GB | 16 GB |
| Disk | 60 GB | 96 GB |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| Network | Internal LAN | Internal LAN |

> **Why these specs?** Cursor CLI runs headlessly and offloads all AI inference to Cursor's cloud. The VM only runs git, bash, and the CLI wrapper — it uses ~400–600 MB RAM during a task. The disk requirement is driven by your repo size, not the agent software.

**N8N VM:**

| Resource | Value |
|----------|-------|
| CPU | 4 vCPU |
| RAM | 8 GB |
| Disk | 40 GB |
| OS | Ubuntu 24.04 LTS |

### 1.2 Networking

- All agent VMs and the N8N VM must be on the same internal network
- The orchestrator machine (your dev/Cursor machine) must be able to reach N8N's IP and port
- N8N does **not** need to be exposed to the internet — only your internal network
- Agent VMs need outbound internet access to reach GitHub and Cursor's API

### 1.3 Proxmox Setup (if applicable)

In Proxmox UI:
1. **Create VM** for each agent and N8N
2. Set hostname matching your agent naming convention
3. Use Ubuntu 24.04 ISO
4. Assign a static IP (via DHCP reservation or set in-VM after install)
5. Set resources per table above

---

## Part 2 — N8N Server Setup

### 2.1 Install N8N

SSH into the N8N VM as root or a sudo user:

```bash
# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs

# Install N8N and PM2 globally
npm install -g n8n pm2

# Start N8N with PM2 (persists across reboots)
pm2 start n8n --name n8n
pm2 save
pm2 startup
```

N8N will be available at `http://YOUR_N8N_IP:5678`

> **Note:** This guide uses HTTP only. N8N is not exposed to the internet — it is accessed only from within your internal network or through a VPN/tunnel from your orchestrator machine.

### 2.2 Generate the N8N SSH Key

This key allows N8N to SSH into every agent VM without a password:

```bash
# Run on the N8N machine
ssh-keygen -t ed25519 -C "n8n-orchestrator" -f ~/.ssh/n8n_agents -N ""

# View the public key — save this for Phase 3
cat ~/.ssh/n8n_agents.pub
```

---

## Part 3 — Agent VM Bootstrap

### 3.1 Edit the Bootstrap Script

Open `bootstrap-agent.sh` and fill in the variables at the top:

```bash
AGENT_USER="youruser"           # Linux username on this VM
AGENT_NAME="agent-01"           # Unique agent name
AGENT_ROLE="coder"              # coder or monitor
AGENT_BRANCH="agent-agent-01"  # Git branch for this agent
AGENT_IP="10.0.0.11"           # This VM's IP

N8N_IP="10.0.0.10"             # N8N server IP
N8N_PORT="5678"

REPO_URL="git@github.com:org/repo.git"
REPO_NAME="your-repo"
MODEL="composer-2-fast"
REPORT_TO="orchestrator"
DISCORD_WEBHOOK=""              # Fill in after Part 4
DISCORD_BLOCKED_WEBHOOK=""      # Fill in after Part 4
```

### 3.2 Run the Bootstrap Script

After a fresh Ubuntu 24.04 install on the agent VM:

```bash
# Copy the script to the agent VM
scp bootstrap-agent.sh AGENT_USER@AGENT_IP:~/

# SSH in and run it
ssh AGENT_USER@AGENT_IP
bash bootstrap-agent.sh
```

The script will pause **twice** for manual actions:
1. **Cursor CLI authentication** — open the printed URL in your browser and approve
2. **GitHub SSH key** — copy the printed public key and add it to GitHub → Settings → SSH keys

### 3.3 What the Bootstrap Script Does

| Phase | Action |
|-------|--------|
| 1 | System updates + install git, curl, python3, openssh |
| 2 | Configure passwordless sudo for AGENT_USER |
| 3 | Add `~/.local/bin` and system paths to PATH permanently |
| 4 | Configure persistent DNS (8.8.8.8, 8.8.4.4, 1.1.1.1) via systemd-resolved |
| 5 | Install Cursor CLI + authenticate with your Cursor account |
| 6 | Generate GitHub SSH key + configure `~/.ssh/config` |
| 7 | Configure git (name, email, merge strategy) |
| 8 | Clone repo + create and push agent branch |
| 9 | Configure `.gitattributes` (prevents cursor rules and docs conflicts) |
| 10 | Update `.gitignore` (excludes `.agent-identity` and `.venv`) |
| 11 | Create `.agent-identity` file (not tracked by git) |
| 12 | Deploy `run-agent-task.sh` (called by N8N on every dispatch) |
| 13 | Verify all components |

### 3.4 Copy N8N SSH Key to the Agent

After bootstrap completes, on the **N8N machine**:

```bash
ssh-copy-id -i ~/.ssh/n8n_agents.pub AGENT_USER@AGENT_IP
```

Verify keyless auth:

```bash
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "echo reachable"
```

### 3.5 The .agent-identity File

This file tells the agent who it is. It is excluded from git via `.gitignore` and must be created manually on each VM — it is never committed or pulled.

```
AGENT_NAME=agent-01
AGENT_ROLE=coder
AGENT_BRANCH=agent-agent-01
PROJECT_ROOT=/home/AGENT_USER/REPO_NAME
REPORT_TO=orchestrator
MODEL=composer-2-fast
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
```

> **Important:** If you ever run `git rm --cached .agent-identity`, git will also delete the file from disk. Always recreate it immediately on that machine.

---

## Part 4 — Discord Setup

### 4.1 Create Discord Channels

Create one channel per agent plus shared channels:

| Channel | Purpose |
|---------|---------|
| `#project-orchestration` | N8N final dispatch summary after all agents complete |
| `#project-agent-01` | agent-01 live task start/complete updates |
| `#project-agent-02` | agent-02 live task start/complete updates |
| `#project-agent-N` | agent-N live task start/complete updates |
| `#project-deploy-monitor` | Server/deployment log alerts |
| `#project-blocked` | Any agent error — @here ping |

### 4.2 Create Webhooks

For each channel:
1. Right-click the channel → **Edit Channel**
2. **Integrations** → **Webhooks** → **New Webhook**
3. Name it (e.g. `Agent-01`)
4. **Copy Webhook URL**

Webhook URL format:
```
https://discord.com/api/webhooks/WEBHOOK_ID/WEBHOOK_TOKEN
```

### 4.3 Add Webhooks to .agent-identity

Once you have the URLs, add them to each agent's `.agent-identity` file:

```bash
# On the agent VM
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_AGENT_WEBHOOK"
```

And update the blocked webhook in `run-agent-task.sh`:

```bash
DISCORD_BLOCKED_WEBHOOK="https://discord.com/api/webhooks/YOUR_BLOCKED_WEBHOOK"
```

### 4.4 Test Webhook Connectivity

From the N8N machine, test that each agent can reach Discord:

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_3; do
  echo "=== $host ==="
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host \
    "curl -s -o /dev/null -w '%{http_code}' -X POST 'YOUR_ORCHESTRATION_WEBHOOK' \
     -H 'Content-Type: application/json' \
     -d '{\"content\": \"connectivity test from \$(hostname)\"}'"
  echo ""
done
```

Expected: `204` from all agents (Discord's success response).

---

## Part 5 — N8N Workflow Setup

### 5.1 Create SSH Credentials

In N8N: **Settings → Credentials → Add Credential → SSH**

Create one credential per agent:

| Field | Value |
|-------|-------|
| Name | `Project SSH — agent-01` |
| Host | `AGENT_IP` |
| Port | `22` |
| Username | `AGENT_USER` |
| Authentication | `Private Key` |
| Private Key | Contents of `~/.ssh/n8n_agents` on the N8N machine |
| Passphrase | (leave blank) |

To get the private key:
```bash
cat ~/.ssh/n8n_agents
# Copy everything including -----BEGIN and -----END lines
```

### 5.2 Workflow Architecture

```
Webhook (POST /webhook/dispatch-task)
    └── Parse Body
         └── Switch (routes by agent name)
              ├── SSH → agent-01 ──┐
              ├── SSH → agent-02  ─┤
              ├── SSH → agent-03  ─┤→ Collect Results
              └── SSH → agent-N  ──┘
```

**Critical wiring rules:**
- Parse Body connects only to Switch — never directly to SSH nodes
- Switch output 0 → SSH → agent-01, output 1 → SSH → agent-02, etc.
- All SSH nodes connect their output to the single Collect Results node
- No SSH node should have more than one input source

### 5.3 Parse Body Node

Mode: `Run Once for All Items` | Language: `JavaScript`

```javascript
const input = $input.first().json;
const body = input.body || input;  // handles N8N body nesting

return [
  { json: { agent: 'agent-01', branch: 'agent-agent-01', task: body.task_01 || 'n/a', files: body.files_01 || 'n/a' } },
  { json: { agent: 'agent-02', branch: 'agent-agent-02', task: body.task_02 || 'n/a', files: body.files_02 || 'n/a' } },
  { json: { agent: 'agent-03', branch: 'agent-agent-03', task: body.task_03 || 'n/a', files: body.files_03 || 'n/a' } },
  // Add one line per agent
];
```

> **Why `input.body || input`?** N8N wraps the webhook POST body under a `body` key. This pattern handles both cases so tasks are never `undefined`.

### 5.4 Switch Node

Mode: **Rules**

Add one rule per agent:

| Rule | Left value | Operator | Right value | Output |
|------|------------|----------|-------------|--------|
| 1 | `{{ $json.agent }}` | equals | `agent-01` | 0 → SSH agent-01 |
| 2 | `{{ $json.agent }}` | equals | `agent-02` | 1 → SSH agent-02 |
| N | `{{ $json.agent }}` | equals | `agent-N` | N-1 → SSH agent-N |

### 5.5 SSH Node Command Field

For every SSH node, the Command field must be in **Expression mode**:

1. Click the Command field
2. Find the `{}` pill on the right edge of the field
3. Click it until it turns **blue** (expression mode active)
4. The `{{ }}` text will appear highlighted in amber/orange when active

Enter this command (identical for all SSH nodes):

```
/home/AGENT_USER/run-agent-task.sh "{{ $json.task }}" "{{ $json.files }}" "{{ $json.branch }}"
```

> **Common mistake:** If the `{}` toggle is grey (Fixed mode), N8N treats `{{ $json.task }}` as literal text and agents receive `undefined`. Always verify the toggle is blue before publishing.

### 5.6 Collect Results Node

```javascript
const results = $input.all();
const ts = new Date().toISOString();

// Replace with your actual webhook URLs
const WEBHOOKS = {
  'agent-01': 'YOUR_AGENT_01_WEBHOOK',
  'agent-02': 'YOUR_AGENT_02_WEBHOOK',
  'agent-03': 'YOUR_AGENT_03_WEBHOOK',
  orchestration: 'YOUR_ORCHESTRATION_WEBHOOK',
  blocked: 'YOUR_BLOCKED_WEBHOOK'
};

async function discordPost(url, content) {
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content })
    });
  } catch(e) {
    console.log('Discord post failed:', e.message);
  }
}

const report = [];
const summaryLines = [`📋 **Dispatch Complete** — ${ts}`];

for (const r of results) {
  const out = r.json.stdout || '';
  const err = r.json.stderr || '';
  const lines = out.split('\n');

  const isComplete = lines.some(l => l.includes('TASK COMPLETE'));
  const isBlocked  = lines.some(l => l.includes('BLOCKED'));
  const agentLine  = lines.find(l => l.startsWith('Agent:')) || '';
  const branchLine = lines.find(l => l.startsWith('Branch:')) || '';
  const summaryLine = lines.find(l => l.startsWith('DISCORD_SUMMARY:')) || '';
  const agentName  = agentLine.replace('Agent:', '').trim();
  const status = isComplete ? 'COMPLETE' : isBlocked ? 'BLOCKED' : 'CHECK_NEEDED';

  report.push({ status, agent: agentLine, branch: branchLine, errors: err.substring(0, 300) });

  const emoji = status === 'COMPLETE' ? '✅' : status === 'BLOCKED' ? '⛔' : '⚠️';
  summaryLines.push(`${emoji} **${agentName}** — ${branchLine.replace('Branch: ', '')} — ${status}`);

  const agentWebhook = WEBHOOKS[agentName];

  if (agentWebhook && status === 'COMPLETE') {
    const summary = summaryLine.replace('DISCORD_SUMMARY:', '').trim().substring(0, 600);
    if (summary) {
      await discordPost(agentWebhook,
        `📊 **${agentName} — N8N confirmed complete**\n\`\`\`${summary}\`\`\``);
    }
  }

  if (isBlocked) {
    await discordPost(WEBHOOKS.blocked,
      `⛔ **${agentName} BLOCKED**\n\`\`\`${err.substring(0, 500)}\`\`\`\n@here`);
  }
}

await discordPost(WEBHOOKS.orchestration, summaryLines.join('\n'));
return [{ json: { report, timestamp: ts } }];
```

### 5.7 Publish the Workflow

After wiring all nodes:
1. Verify no SSH node has a direct connection from Parse Body (only from Switch)
2. Verify all SSH nodes connect their output to Collect Results
3. Click **Publish**
4. The webhook URL becomes active: `http://YOUR_N8N_IP:5678/webhook/dispatch-task`

---

## Part 6 — Orchestrator Setup (Cursor)

### 6.1 Cursor Rules

Place these `.mdc` files in `.cursor/rules/` in your repo on the orchestrator machine:

| File | Purpose |
|------|---------|
| `agent-network.mdc` | Agent roster, topology, roles, responsibilities |
| `dispatch-agents.mdc` | `/dispatch` command behavior and payload format |
| `git-rules.mdc` | Git discipline enforced on all agents |
| `orchestration.mdc` | Delegation, review, and merge protocols |
| `coding-standards.mdc` | Code quality rules for all agents |

### 6.2 Dispatching Tasks

From the orchestrator's Cursor terminal, type `/dispatch` followed by your task description. Cursor formats and sends the payload automatically per the `dispatch-agents.mdc` rule.

The PowerShell payload format:

```powershell
$body = @{
    task_01  = "You are agent-01 working on branch agent-agent-01 of PROJECT_NAME. <full self-contained task>. Commit with message '<type>: <description>'."
    files_01 = "path/to/file1.py path/to/file2.py"
    task_02  = "n/a"
    files_02 = "n/a"
    task_03  = "n/a"
    files_03 = "n/a"
    # ... one pair per agent, always include all keys
} | ConvertTo-Json -Compress

Invoke-RestMethod `
    -Uri "http://YOUR_N8N_IP:5678/webhook/dispatch-task" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec 600
```

**Payload rules:**
- Always include ALL key pairs (one `task_N` + `files_N` per agent)
- Unused agents always get `"n/a"` for both task and files — never omit keys
- Use `ConvertTo-Json -Compress` directly — never pipe through `ConvertFrom-Json`
- `-TimeoutSec 600` prevents the orchestrator from timing out on long tasks
- Task descriptions must be fully self-contained — agents have no prior context

**Good task example:**
```
"You are agent-01 working on branch agent-agent-01 of PROJECT_NAME.
Add a LoginForm component at web/src/components/LoginForm.jsx with email
and password fields, validation (no empty fields), and a submit button.
Follow the pattern used in web/src/components/RegisterForm.jsx. Export as
default. Done when the component renders without errors and accepts onSubmit
as a prop. Commit with message 'feat: add LoginForm component'."
```

### 6.3 What Happens After Dispatch

```
1. N8N receives the POST
2. Parse Body splits into N items (one per agent)
3. Switch routes each item to the correct SSH node
4. Each active agent:
   a. Posts 🔄 "starting task" to its Discord channel
   b. Runs git startup checklist (checkout → pull → merge origin/dev)
   c. Runs Cursor CLI with the task
   d. Posts ✅ "task complete" with summary to its Discord channel
5. N8N Collect Results posts 📋 summary to #project-orchestration
6. Any blocked agent posts ⛔ to #project-blocked with @here
```

### 6.4 Slice Discipline

Every agent must touch **only** the files declared in its `files_N` key. This is enforced at two levels:

**At the script level** — `run-agent-task.sh` appends a slice discipline block to every task prompt automatically and runs a post-task file scope check. If undeclared files were changed, the agent posts a `⚠️` warning to its Discord channel.

**At the task level** — every task string sent by the orchestrator must end with:

```
SLICE DISCIPLINE — STRICTLY ENFORCED:
- Work ONLY on these files: <files_N value>
- Do NOT modify any file outside this list under any circumstances
- Do NOT make drive-by fixes, formatting changes, or improvements to unrelated files
- Do NOT merge, cherry-pick, or carry over any unrelated local work
- If a change seems needed outside your assigned files, note it in your report — do NOT make it
- Commit ONLY the changes to your assigned files
- Commit message format: '<type>: <description>'
```

**At the review level** — before merging any agent branch to dev, always run:

```bash
git diff --name-only dev...agent-BRANCH-NAME
```

If any file appears that was not in `files_N` for that agent — cherry-pick only the assigned-file commits. Never merge an agent branch wholesale.

If any file appears that was not in `files_N` for that agent — cherry-pick only the assigned-file commits. Never merge an agent branch wholesale.

---

## Part 7 — Sample Cursor Rules Files

Place these `.mdc` files in `.cursor/rules/` in your repo on the orchestrator machine. Customize the placeholder values (`YOUR_IP`, `YOUR_N8N_IP`, `agent-01`, `your-domain.com`, etc.) for your project.

---

### `git-rules.mdc`

```markdown
---
description: Git rules for all agents — commit, push, identity discipline
globs:
alwaysApply: true
---

# Git Rules — All Agents (Strictly Enforced)

These rules apply to every agent on every machine. No exceptions.

## Branch Assignments

| Agent        | Branch           |
|--------------|------------------|
| orchestrator | dev (review/merge only) |
| agent-01     | agent-agent-01   |
| agent-02     | agent-agent-02   |
| agent-N      | agent-agent-N    |

## Rule 1 — Always Start Clean from origin/dev

Before any file is read, edited, or created:

  git fetch origin
  git checkout <your-branch>
  git reset --hard origin/dev

This guarantees no stale local commits carry into the new task.

## Rule 2 — Commit Only Your Assigned Files

Never use git add . for real tasks. Always stage explicitly:

  git add path/to/assigned/file1 path/to/assigned/file2
  git commit -m "<type>: <short description>"

Commit types: feat / fix / refactor / test / config / docs / chore
Never use vague messages: fix, update, changes, WIP, misc.

## Rule 3 — Push Regularly

Push at minimum every 30 minutes even if a task is not complete.

## Rule 4 — Never Push to main or dev Directly

Only the orchestrator merges into dev. Only the user approves merges into main.

## Rule 5 — Start of Task Checklist

  1. cd /path/to/repo
  2. git fetch origin
  3. git checkout <your-branch>
  4. git reset --hard origin/dev
  5. git status  ← must be clean before starting

## Rule 6 — End of Task Checklist

  1. git add path/to/assigned/files (explicit only)
  2. git diff --staged
  3. git commit -m "type: description"
  4. git push origin <your-branch>
  5. Report completion to orchestrator

## Rule 7 — Conflict Resolution

If you see CONFLICT during any git operation — STOP immediately.
Do not touch the file. Report to the orchestrator.

## Rule 8 — Do Not Commit These Files

node_modules/ .env .env.* .agent-identity *.log dist/ build/
.DS_Store Thumbs.db *.sqlite *.key *.pem .venv/ __pycache__/

## Rule 9 — .agent-identity Is Local

Never commit .agent-identity. It is gitignored and machine-local.

## Rule 10 — Force-Push Policy

Permitted on agent branches only:
- Pre-task reset (automatic): git push --force-with-lease origin <branch>
- Orchestrator-requested cleanup: git push --force-with-lease origin <branch>
- Any other reason: NOT permitted

Never --force to dev or main.

## Rule 11 — Git Identity

  git config --global user.name "agent-01"
  git config --global user.email "agent-01@your-domain.com"

Remove local repo overrides if present:
  git config --local --unset user.name
  git config --local --unset user.email

## Quick Reference Card

| Situation             | Command                                                              |
|-----------------------|----------------------------------------------------------------------|
| Start of task         | git fetch origin && git checkout <branch> && git reset --hard origin/dev |
| Stage assigned files  | git add path/to/file1 path/to/file2                                  |
| Review staged         | git diff --staged                                                    |
| Commit                | git commit -m "type: description"                                    |
| Push                  | git push origin <branch>                                             |
| Force-push after reset| git push --force-with-lease origin <branch>                          |
| Conflict detected     | STOP — report to orchestrator                                        |
| Verify git identity   | git config user.name && git config user.email                        |
```

---

### `agent-network.mdc`

```markdown
---
description: Agent network topology, roles, and communication rules
globs:
alwaysApply: true
---

# Agent Network

## Network Topology

User
 └── orchestrator (main Cursor machine — YOUR_ORCH_IP)
      ├── agent-01 (Ubuntu 24.04 — YOUR_IP_01)
      ├── agent-02 (Ubuntu 24.04 — YOUR_IP_02)
      ├── agent-03 (Ubuntu 24.04 — YOUR_IP_03)
      └── agent-N  (Ubuntu 24.04 — YOUR_IP_N)

N8N: YOUR_N8N_IP:5678

All instructions flow DOWN from the user through the orchestrator.
All reports flow UP back to the orchestrator and then to the user.
No agent communicates directly with another agent.

## Agent Roster

| Agent        | IP           | Branch          | Model           | Default Role      |
|--------------|--------------|-----------------|-----------------|-------------------|
| orchestrator | YOUR_ORCH_IP | dev             | —               | Delegate & review |
| agent-01     | YOUR_IP_01   | agent-agent-01  | composer-2-fast | Frontend (web/)   |
| agent-02     | YOUR_IP_02   | agent-agent-02  | composer-2-fast | Backend (server/) |
| agent-03     | YOUR_IP_03   | agent-agent-03  | composer-2      | Tests / DevOps    |
| agent-N      | YOUR_IP_N    | agent-agent-N   | composer-2-fast | General purpose   |

## Orchestrator Responsibilities

- Receives all tasks from the user
- Breaks tasks into subtasks before any work begins
- Delegates via /dispatch → N8N → Cursor CLI on each agent
- Never writes code unless trivial or explicitly asked
- Reviews all work before merging to dev
- Only agent allowed to merge branches into dev
- Monitors Discord channels for completion and blocker reports

## Coder Agent Responsibilities

- Receives tasks only from the orchestrator
- Works exclusively on their assigned branch
- Resets to origin/dev before every task
- Commits only assigned files
- Pushes every 30 minutes minimum
- Reports TASK COMPLETE or BLOCKED to orchestrator
- Never pushes to dev or main

## Default Task Assignments

| Work Type                        | Default Agent |
|----------------------------------|---------------|
| UI components, pages, CSS        | agent-01      |
| API routes, auth, middleware     | agent-02      |
| Tests, migrations, CI config     | agent-03      |
| Overflow / parallel / large work | agent-N       |
| Code review, merging             | orchestrator  |

## Communication Formats

Delegation:
  DELEGATE TO: <agent>
  BRANCH: <branch>
  TASK: <description>
  FILES: <paths>
  DEPENDS ON: <other agent or none>
  COMPLETE WHEN: <definition of done>

Completion:
  TASK COMPLETE
  Agent: <name>
  Branch: <branch>
  Completed: <what was done>
  Files Modified: <list>
  Commits: <messages>
  Pushed: Yes / No
  Issues: <any problems>

Blocker:
  BLOCKED
  Agent: <name>
  Task: <what was being worked on>
  Blocker: <what is preventing progress>
  Awaiting instruction from: orchestrator

## Parallel Work Rules

- Verify zero file overlap before dispatching parallel tasks
- If two agents need the same file — serialize, never parallelize
- Shared hotspot files always serialize

## Escalation Rules

| Situation                       | Action                           |
|---------------------------------|----------------------------------|
| Merge conflict                  | Stop, report to orchestrator     |
| Blocked > 10 minutes            | Report blocker immediately       |
| Task scope grows unexpectedly   | Report before continuing         |
| Uncertainty about file ownership| Ask orchestrator before touching |
```

---

### `dispatch-agents.mdc`

```markdown
---
description: Orchestrator dispatch rule — formats and sends parallel agent tasks via N8N
globs:
alwaysApply: true
---

# Dispatch Rule — Orchestrator → N8N Parallel Agents

Activates whenever the user types /dispatch in Cursor chat.

## Infrastructure Reference

| Agent    | IP          | Model           | Default Role |
|----------|-------------|-----------------|--------------|
| agent-01 | YOUR_IP_01  | composer-2-fast | Frontend     |
| agent-02 | YOUR_IP_02  | composer-2-fast | Backend      |
| agent-03 | YOUR_IP_03  | composer-2      | Tests/DevOps |
| agent-N  | YOUR_IP_N   | composer-2-fast | General      |

N8N webhook: http://YOUR_N8N_IP:5678/webhook/dispatch-task

## Step 1 — Task Breakdown

Read project planning docs before every dispatch. Break the feature into
one subtask per agent. List every file each agent will touch before Step 2.

## Step 2 — Overlap Check (MANDATORY — Hard Block)

Verify zero file overlap across all assigned agents.

If overlap detected:
  ⛔ DISPATCH BLOCKED — FILE OVERLAP DETECTED
  Resolve before dispatch proceeds.

Known hotspot files: shared schemas, models, package.json, lockfiles.

## Step 3 — Dispatch Summary + Payload

Show human-readable summary first. Then show and run the PowerShell payload:

  $body = @{
      task_01  = "<self-contained task for agent-01, or 'n/a'>"
      files_01 = "<repo-relative paths, or 'n/a'>"
      task_02  = "<task for agent-02, or 'n/a'>"
      files_02 = "<paths, or 'n/a'>"
      task_N   = "<task for agent-N, or 'n/a'>"
      files_N  = "<paths, or 'n/a'>"
  } | ConvertTo-Json -Compress

  Invoke-RestMethod `
      -Uri "http://YOUR_N8N_IP:5678/webhook/dispatch-task" `
      -Method POST `
      -ContentType "application/json" `
      -Body $body `
      -TimeoutSec 600

Critical rules:
- Always include ALL key pairs — never omit any
- Unused agents get "n/a" for both task and files
- Use ConvertTo-Json -Compress directly

## Step 4 — Auto-Run

Run PowerShell immediately after showing summary. No second confirmation.

## Step 5 — Update Planning Docs

Mark dispatched tasks as IN PROGRESS in project planning docs. Push to dev.

## Task Description Quality Standard

Every task MUST include:
1. Who — "You are agent-01 working on branch agent-agent-01 of PROJECT"
2. What — specific feature or fix
3. Where — exact repo-relative file paths
4. How — patterns to follow
5. Done when — clear definition of done
6. Dependencies — if dependent on another agent finishing first

Always end every task string with:

  SLICE DISCIPLINE — STRICTLY ENFORCED:
  - Work ONLY on these files: <files_N value>
  - Do NOT modify any file outside this list
  - Do NOT make drive-by fixes to unrelated files
  - Note anything outside scope in your report — do not change it
  - Commit ONLY the changes to your assigned files

## Slice Discipline Review

Before merging any agent branch to dev:
  git diff --name-only dev...agent-BRANCH-NAME

If files appear outside files_N — cherry-pick only assigned-file commits.
Never merge agent branches wholesale.

## Rules Orchestrator MUST Follow

- Never dispatch with overlap — hard block, resolve first
- Always show summary before running
- Always include all key pairs — unused agents get "n/a"
- Always append slice discipline block to every real task
- Always review diff before merging — never merge wholesale
- File paths relative to repo root
- Never touch dev or main directly from agent machines
```

---

### `orchestration.mdc`

```markdown
---
description: Orchestration protocol — delegation, review, merge, and escalation
globs:
alwaysApply: true
---

# Orchestration Protocol

## Role of the Orchestrator

The orchestrator is the ONLY entry point for tasks. It delegates, reviews,
and merges — it does not write production code for complex tasks.

## Delegation Protocol

Step 1 — Read planning docs (architecture, todo, backlog)
Step 2 — Overlap check (hard block if any two agents share a file)
Step 3 — Generate dispatch summary + payload
Step 4 — Auto-run /dispatch
Step 5 — Monitor Discord for 🔄 start and ✅ complete posts
Step 6 — Review: git diff --name-only dev...agent-BRANCH for each agent
Step 7 — Cherry-pick clean slice commits to dev
Step 8 — Update planning docs, push to dev

## Review Protocol

Before merging any agent work:

1. Check scope:
   git diff --name-only dev...agent-BRANCH-NAME
   Must match files_N exactly. If extras found, cherry-pick only.

2. Check attribution:
   git log --oneline dev..agent-BRANCH-NAME
   Each commit must have a clear Author (agent-name@domain).

3. Run tests.

4. Cherry-pick or merge:
   git cherry-pick SHA   ← preferred for clean single-file slices
   git merge agent-BRANCH ← only if branch is provably clean

5. git push origin dev

## Merge Policy

| Branch type    | Who merges   | How                       |
|----------------|--------------|---------------------------|
| agent-* → dev  | Orchestrator | Cherry-pick slice commits |
| dev → main     | User only    | PR / manual approval      |

Never merge agent branches wholesale unless every commit contains only
the declared files_N paths.

## Sequenced Dispatch

When task B depends on task A:
1. Dispatch Round 1 (independent agents only)
2. Wait for ✅ Discord posts from Round 1 agents
3. Dispatch Round 2 for dependent agents

Announce before dispatching:
  ⚠️ SEQUENCED DISPATCH
  Round 1 → agent-01, agent-02 (parallel)
  Round 2 → agent-03 (after agent-02 posts ✅)

## Escalation Rules

| Situation                        | Action                             |
|----------------------------------|------------------------------------|
| Merge conflict on agent branch   | Agent stops, orchestrator resolves |
| Agent blocked > 10 minutes       | Agent reports, orchestrator acts   |
| Task scope grows unexpectedly    | Agent reports before continuing    |
| Two agents need the same file    | Orchestrator serializes            |
| ⚠️ Discord out-of-scope warning | Cherry-pick only, do not merge     |

## Discord Channel Protocol

| Channel                 | Purpose                                     |
|-------------------------|---------------------------------------------|
| #project-orchestration  | Dispatch summaries, merge announcements     |
| #project-agent-N        | Live start/complete updates per agent       |
| #project-blocked        | @here alerts — requires immediate response  |
| #project-deploy-monitor | Server/deployment log alerts                |

Watch all channels after every dispatch.
Blocked channel requires immediate response.
```

---

## Part 8 — Verification

Run from the N8N machine after all agents are bootstrapped:

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_3; do
  echo "=== $host ==="
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    cd ~/REPO_NAME
    echo 'Agent  :' \$(grep AGENT_NAME .agent-identity | cut -d'=' -f2)
    echo 'Branch :' \$(git branch --show-current)
    echo 'Clean  :' \$(git status --short | wc -l) uncommitted files
    echo 'DNS    :' \$(curl -s -o /dev/null -w '%{http_code}' https://cursor.com)
    sudo echo 'Sudo   : OK'
  "
done
```

Expected output per agent:
```
Agent  : agent-01
Branch : agent-agent-01
Clean  : 0 uncommitted files
DNS    : 200
Sudo   : OK
```

### 11.2 Identity Test (no code changes)

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_3; do
  echo "=== Testing $host ==="
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host \
    "~/run-agent-task.sh 'echo identity test' 'n/a' \
    \$(grep AGENT_BRANCH ~/REPO_NAME/.agent-identity | cut -d'=' -f2)"
done
```

### 11.3 Full N8N Dispatch Test

Send a sync verification from the orchestrator:

```powershell
$body = @{
    task_01  = "You are agent-01. Sync verification only — do not change source files. Run: git fetch origin && git pull origin agent-agent-01 && git rev-parse HEAD. Report TASK COMPLETE with hostname and SHA."
    files_01 = "n/a"
    task_02  = "You are agent-02. Sync verification only — do not change source files. Run: git fetch origin && git pull origin agent-agent-02 && git rev-parse HEAD. Report TASK COMPLETE with hostname and SHA."
    files_02 = "n/a"
    # repeat for all agents with n/a files
} | ConvertTo-Json -Compress

Invoke-RestMethod `
    -Uri "http://YOUR_N8N_IP:5678/webhook/dispatch-task" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec 600
```

Watch N8N → Executions and your Discord `#project-orchestration` channel. You should see all agents report COMPLETE and a summary post in Discord.

---

## Part 9 — Adding a New Agent

When adding agent-N+1 to the fleet:

**Step 1 — Create and bootstrap the VM**
Edit `bootstrap-agent.sh` variables for the new agent and run it.

**Step 2 — Copy N8N SSH key**
```bash
ssh-copy-id -i ~/.ssh/n8n_agents.pub AGENT_USER@NEW_AGENT_IP
```

**Step 3 — Create Discord channel + webhook**
Create `#project-agent-N` and get the webhook URL.

**Step 4 — In N8N:**
- Add SSH credential for the new agent
- Add new SSH node using that credential
- Add new routing rule to the Switch node
- Connect new SSH node output to Collect Results
- Add the new agent to Parse Body code
- Add the new agent webhook to Collect Results webhook map
- Publish

**Step 5 — Update Cursor rules on orchestrator**
- Add agent to `agent-network.mdc` roster table
- Add `task_N`/`files_N` keys to `dispatch-agents.mdc` payload template

---

## Part 10 — Troubleshooting

### 11.1 Merge Conflicts on Agent Branches

Agents occasionally conflict with dev when pulling updates. Fix any conflicted agent:

```bash
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "
  cd ~/REPO_NAME
  git merge --abort 2>/dev/null || true
  git fetch origin dev
  git merge -X theirs origin/dev --no-edit
  git push origin \$(grep AGENT_BRANCH .agent-identity | cut -d'=' -f2)
  git status
"
```

To fix all agents at once:

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_N; do
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    cd ~/REPO_NAME
    BRANCH=\$(grep AGENT_BRANCH .agent-identity | cut -d'=' -f2)
    git merge --abort 2>/dev/null || true
    git fetch origin dev
    git merge -X theirs origin/dev --no-edit
    git push origin \$BRANCH
    echo \$(grep AGENT_NAME .agent-identity | cut -d'=' -f2): clean
  "
done
```

> **Why `-X theirs`?** On agent branches, dev is always the source of truth for shared files. Agents should never block on conflicts in files they don't own.

### 11.2 Preventing Future Conflicts — .gitattributes

The bootstrap script configures `.gitattributes` to prevent conflicts in cursor rules and docs. If agents are still conflicting on specific files, add them:

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_N; do
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    cd ~/REPO_NAME
    echo 'path/to/shared/file merge=ours' >> .gitattributes
    git add .gitattributes
    git diff --staged --quiet || git commit -m 'chore: add conflict-prone file to merge=ours strategy'
    git push origin \$(grep AGENT_BRANCH .agent-identity | cut -d'=' -f2)
  "
done
```

### 11.3 DNS Resolution Failures

**Symptom:** `getaddrinfo EAI_AGAIN api2.cursor.sh` or DNS failures to GitHub

**Permanent fix on all agents:**

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_N; do
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null << 'DNSEOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1
FallbackDNS=9.9.9.9
DNSEOF
    sudo systemctl restart systemd-resolved
    curl -s -o /dev/null -w '%{http_code}' https://cursor.com && echo ' OK'
  "
done
```

### 11.4 .agent-identity Missing

The file is gitignored and must be manually recreated if deleted:

```bash
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "cat > ~/REPO_NAME/.agent-identity << 'EOF'
AGENT_NAME=agent-01
AGENT_ROLE=coder
AGENT_BRANCH=agent-agent-01
PROJECT_ROOT=/home/AGENT_USER/REPO_NAME
REPORT_TO=orchestrator
MODEL=composer-2-fast
DISCORD_WEBHOOK=YOUR_WEBHOOK_URL
EOF"
```

### 11.5 N8N SSH Node Shows "undefined" for Task/Files

**Cause:** Command field is in Fixed mode instead of Expression mode.

**Fix:**
1. Click the SSH node
2. Find the `{}` pill on the right edge of the Command field
3. Click it until it turns **blue** (expression mode)
4. `{{ $json.task }}` should turn amber/orange
5. Publish

### 11.6 N8N "executeCommand" Node Error on Import

Newer N8N versions removed the `executeCommand` node. Use SSH nodes with agent credentials instead — the SSH node connects directly to each agent VM.

### 11.7 sudo: command not found

```bash
# Fix PATH to include sudo location
echo 'export PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin' >> ~/.bashrc
source ~/.bashrc
```

If sudo itself is missing, install via the Proxmox console as root:

```bash
apt-get install -y sudo
echo 'AGENT_USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/AGENT_USER
chmod 440 /etc/sudoers.d/AGENT_USER
```

### 11.8 Virtual Environment (.venv) Accidentally Committed

```bash
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "
  cd ~/REPO_NAME
  git rm -r --cached .venv
  grep -q '.venv/' .gitignore || echo '.venv/' >> .gitignore
  git add .gitignore
  git commit -m 'chore: remove .venv from tracking, add to .gitignore'
  git push origin \$(grep AGENT_BRANCH .agent-identity | cut -d'=' -f2)
"
```

> **Warning:** `git rm --cached .venv` also removes the `.venv` directory from disk. Recreate it with `python3 -m venv .venv` if needed. Always check `.gitignore` covers `.venv/` before running `git add .`.

### 11.9 Orchestrator Times Out Waiting for Dispatch Response

**Cause:** Tasks take longer than the default PowerShell timeout.

**Fix:** Add `-TimeoutSec 600` to `Invoke-RestMethod`:

```powershell
Invoke-RestMethod `
    -Uri "http://YOUR_N8N_IP:5678/webhook/dispatch-task" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec 600
```

### 11.10 Cursor CLI Authentication Failure

```bash
# Re-authenticate on the affected agent
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP
~/.local/bin/agent login
# Open the printed URL in your browser and approve
exit

# Verify
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "~/.local/bin/agent status"
```

### 11.11 Agent Branches Accumulating Stale Commits

**Symptom:** Orchestrator reports empty cherry-picks or "content already on dev"

**Cause:** Agent branch was not reset to `origin/dev` before the slice, or work was stacked across rounds without squashing. The pre-flight reset in `run-agent-task.sh` handles this automatically for N8N dispatches — this issue only appears in manual sessions or when the script isn't running.

**Immediate fix** — reset the agent branch cleanly:

```bash
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "
  cd ~/REPO_NAME
  BRANCH=\$(grep AGENT_BRANCH .agent-identity | cut -d'=' -f2)
  git fetch origin
  git reset --hard origin/dev
  git push --force-with-lease origin \$BRANCH
"
```

**Prevention — one clean commit per slice:**

Before pushing any slice, agents should verify and squash:

```bash
# Check what you have vs dev
git log origin/dev..HEAD --oneline
# If commits already on dev appear → squash them:
git rebase -i origin/dev
# Mark already-merged commits as 'drop'

# Verify final diff matches only assigned files
git diff --name-only origin/dev HEAD

# Only push if there is new content
git log origin/dev..HEAD --oneline | wc -l
# If 0 → nothing to push, skip
```

The `run-agent-task.sh` script automatically skips the push if there are no new commits vs dev, and posts an informational Discord message instead.

### 11.12 N8N Parse Body Returns All Agents as "n/a"

**Cause:** The webhook body is nested under a `body` key in N8N but the Parse Body code accesses it at the wrong level.

**Fix:** Ensure Parse Body code uses:

```javascript
const input = $input.first().json;
const body = input.body || input;  // handles the nesting
```

Without `input.body || input`, all `body.task_01` lookups return `undefined`.

### 11.13 Agents Touching Files Outside Their Assigned Scope

**Symptom:** Orchestrator reports drive-by fixes, empty cherry-picks, or files outside `files_N` appearing in the agent branch diff.

**Cause:** Agent made changes outside declared scope.

**Immediate fix** — cherry-pick only the slice commits onto dev:

```bash
git log --oneline dev..agent-BRANCH-NAME -- path/to/assigned/file
git checkout dev
git cherry-pick SHA1 SHA2
git push origin dev
```

**Permanent fix** — three layers enforced in the latest `run-agent-task.sh`:

1. **Pre-flight reset** — `git reset --hard origin/dev` before every task eliminates stale history
2. **Slice discipline prompt** — appended automatically to every real task prompt
3. **Hard scope enforcement** — out-of-scope files are restored to `origin/dev` state before committing; only declared `files_N` can land on the branch

### 11.14 Force-Push Warnings on Agent Branches

**Symptom:** `git fetch` reports forced updates on agent branches.

**Cause:** The pre-flight `git reset --hard origin/dev` followed by `git push --force-with-lease` is expected and intentional — it resets the agent branch to a clean state before every task.

**Policy:** Always use `--force-with-lease` never `--force`. Never force-push to `dev` or `main`. See `git-rules.mdc` Rule 10 for the full force-push policy.

### 11.15 Commits Missing Author Attribution

**Symptom:** Cherry-picked commits show no Author line or blank git identity.

**Cause:** `git config user.name` or `user.email` not set on that agent VM, or a local repo config is overriding the global setting.

**Fix:**
```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_N; do
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    AGENT=\$(grep AGENT_NAME ~/REPO_NAME/.agent-identity | cut -d'=' -f2)
    git config --global user.name \"\$AGENT\"
    git config --global user.email \"\$AGENT@your-domain.com\"
    git config --local --unset user.name 2>/dev/null || true
    git config --local --unset user.email 2>/dev/null || true
    echo Fixed: \$(git config user.name) / \$(git config user.email)
  "
done
```

### 11.16 Empty Push — Slice Already on dev

**Symptom:** Agent pushes but orchestrator reports the cherry-pick is empty — content already on dev.

**Cause:** The agent's slice commit duplicated content already integrated in a previous round.

**Prevention:** The `run-agent-task.sh` script checks `git log origin/dev..HEAD --oneline` before pushing. If there are zero new commits vs dev, it skips the push and posts an informational Discord message instead of pushing a no-op commit.

**Manual check before any push:**
```bash
git log origin/dev..HEAD --oneline
# 0 lines = nothing new = do not push
git diff --name-only origin/dev HEAD
# Must match files_N — if empty, slice was already on dev
```

### 11.17 Agent Pushes Files Outside Declared Scope (Scope Violation)

**Symptom:** Orchestrator's `git diff --name-only` shows files beyond `files_N` on the agent branch tip.

**Cause:** Agent made changes outside the declared slice — either the AI model edited unrelated files or stale history carried them forward.

**Immediate fix:**
```bash
# Reset the violating agent branch to dev
ssh -i ~/.ssh/n8n_agents AGENT_USER@AGENT_IP "
  cd ~/REPO_NAME
  git fetch origin
  git reset --hard origin/dev
  git push --force-with-lease origin AGENT_BRANCH
"
```

**Permanent fix:** The latest `run-agent-task.sh` runs a pre-push scope check:
```bash
git diff --name-only origin/dev HEAD
```
If any file outside `files_N` appears, the script posts `⛔ SCOPE VIOLATION` to `#project-blocked` and exits without pushing. The branch is left clean for a corrected redispatch.

### 11.18 Symbols (§) or Non-ASCII Characters in Commit Subjects

**Symptom:** Commits contain `§`, `→`, or other non-ASCII symbols in the subject line, which can break some git tooling and CI log parsers.

**Cause:** Cursor CLI model used documentation symbols in commit messages.

**Prevention:** The slice discipline block appended to every task prompt now includes commit subject style rules. Agents are instructed to use only ASCII in commit subjects.

**Fix existing commits** (if already pushed):
```bash
# Amend the last commit subject on the agent branch
git commit --amend -m "docs: corrected commit subject without symbols"
git push --force-with-lease origin AGENT_BRANCH
```

**Fix:** Ensure Parse Body code uses:

```javascript
const input = $input.first().json;
const body = input.body || input;  // handles the nesting
```

Without `input.body || input`, all `body.task_01` lookups return `undefined`.

### 11.13 Agents Touching Files Outside Their Assigned Scope

**Symptom:** Orchestrator reports drive-by fixes, empty cherry-picks, or files outside `files_N` appearing in the agent branch diff.

**Cause:** Agent made changes outside declared scope.

**Immediate fix** — cherry-pick only the slice commits onto dev:

```bash
git log --oneline dev..agent-BRANCH-NAME -- path/to/assigned/file
git checkout dev
git cherry-pick SHA1 SHA2
git push origin dev
```

**Permanent fix** — three layers enforced in the latest `run-agent-task.sh`:

1. **Pre-flight reset** — `git reset --hard origin/dev` before every task eliminates stale history
2. **Slice discipline prompt** — appended automatically to every real task prompt
3. **Hard scope enforcement** — out-of-scope files are restored to `origin/dev` state before committing; only declared `files_N` can land on the branch

### 11.14 Force-Push Warnings on Agent Branches

**Symptom:** `git fetch` reports forced updates on agent branches.

**Cause:** The pre-flight `git reset --hard origin/dev` followed by `git push --force-with-lease` is expected and intentional — it resets the agent branch to a clean state before every task.

**Force-push policy:**

| Situation | Command |
|-----------|---------|
| Pre-task reset (automatic in script) | `git push --force-with-lease origin BRANCH` |
| Manual branch cleanup by orchestrator | `git push --force-with-lease origin BRANCH` |
| Any other reason | **NOT permitted** — report to orchestrator first |

Always use `--force-with-lease` not `--force`. Never force-push to `dev` or `main`.

When manually force-pushing, post in your orchestration Discord channel:
```
🔄 Force-push on agent-BRANCH — branch reset to origin/dev for clean dispatch
```

### 11.15 Commits Missing Author Attribution

**Symptom:** Cherry-picked commits show no Author line or blank git identity.

**Cause:** `git config user.name` or `user.email` not set on that agent VM.

**Check all agents:**

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_N; do
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    AGENT=\$(grep AGENT_NAME ~/REPO_NAME/.agent-identity | cut -d'=' -f2)
    echo \$AGENT: \$(git config user.name) / \$(git config user.email)
  "
done
```

**Fix any agent with blank identity:**

```bash
for host in AGENT_IP_1 AGENT_IP_2 AGENT_IP_N; do
  ssh -i ~/.ssh/n8n_agents AGENT_USER@$host "
    AGENT=\$(grep AGENT_NAME ~/REPO_NAME/.agent-identity | cut -d'=' -f2)
    git config --global user.name \"\$AGENT\"
    git config --global user.email \"\$AGENT@your-project\"
    echo Fixed: \$(git config user.name) / \$(git config user.email)
  "
done
```

> The bootstrap script now sets `user.name` to `AGENT_NAME` (e.g. `agent-01`) so every commit is clearly attributable to the agent that made it.

### How run-agent-task.sh Works

```
Arguments: TASK, FILES, BRANCH
    ↓
Read .agent-identity (agent name, model, discord webhook)
    ↓
Post 🔄 "starting" to Discord (if real task)
    ↓
Pre-flight reset:
  git fetch origin
  git checkout BRANCH
  git reset --hard origin/dev  ← always start clean from dev
    ↓
Task routing:
  TASK = "n/a"     → skip silently
  FILES = "n/a"    → run agent CLI as open-ended prompt
  FILES = paths    → run agent CLI with file scope
                     + slice discipline block appended to prompt
    ↓
Post-task file scope check:
  Restore any out-of-scope files to origin/dev state (hard reset)
  git add only declared FILES
  Any auto-reset files → post ⚠️ warning to agent Discord channel
    ↓
On error (exit code ≠ 0):
  Post ⛔ BLOCKED to #project-blocked with @here
  Exit 1 (N8N marks as failed)
    ↓
On success:
  git add . && git commit (if changes) && git push
  Post ✅ "complete" with summary to agent Discord channel
  Print TASK COMPLETE + DISCORD_SUMMARY (parsed by N8N Collect Results)
```

### Git Strategy on Agent Branches

| File type | Strategy | Why |
|-----------|----------|-----|
| `.cursor/rules/*` | `merge=ours` | Agents should never overwrite orchestrator-managed rules |
| `docs/*` | `merge=ours` | Prevents doc conflicts when agents work on shared docs |
| Application code | Normal merge | Agents own their assigned files |
| Conflicts on any file | `-X theirs` (dev wins) | Dev is always source of truth |

### Cursor CLI Key Flags

| Flag | Purpose |
|------|---------|
| `--print` | Non-interactive/headless mode — outputs to stdout |
| `--yolo` | Auto-approve all file edits and shell commands |
| `--trust` | Trust the workspace without prompting |
| `--workspace` | Set the repo root directory |
| `--model` | Specify which Cursor model to use |

### Why This Architecture

| Decision | Reason |
|----------|--------|
| N8N over custom orchestrator | Visual workflow editor, built-in SSH nodes, no code to maintain |
| SSH over API | Agents are VMs, not services — SSH is the natural interface |
| Cursor CLI over Cursor GUI | GUI has no API or headless mode; CLI is fully automatable |
| `.agent-identity` file | Lets each VM know who it is without hardcoding in scripts |
| `merge=ours` in .gitattributes | Prevents constant conflicts on shared files across 8+ branches |
| Discord webhooks | Async notification without polling — agents push results when done |

---

## Changelog

| Date | Change |
|------|--------|
| May 2026 | Initial release |
| May 2026 | Added SSH node expression mode fix (Fixed → Expression) |
| May 2026 | Added Parse Body body nesting fix (`input.body \|\| input`) |
| May 2026 | Added Switch node routing to replace direct Parse Body → SSH connections |
| May 2026 | Added persistent DNS fix via systemd-resolved |
| May 2026 | Added passwordless sudo setup |
| May 2026 | Added `.gitattributes` merge=ours for cursor rules and docs |
| May 2026 | Added `.venv` and `.agent-identity` to `.gitignore` |
| May 2026 | Added `-X theirs` to `git merge origin/dev` in run-agent-task.sh |
| May 2026 | Added `-TimeoutSec 600` to PowerShell dispatch command |
| May 2026 | Added stale branch cleanup procedure |
| May 2026 | Added pre-flight `git reset --hard origin/dev` to run-agent-task.sh |
| May 2026 | Added slice discipline prompt injection in run-agent-task.sh |
| May 2026 | Added hard scope enforcement — out-of-scope files auto-reset before commit |
| May 2026 | Added Slice Discipline section to Part 6 |
| May 2026 | Added troubleshooting 9.13 (scope creep), 9.14 (force-push policy), 9.15 (git attribution) |
| May 2026 | Added Part 7 — Sample Cursor Rules Files (git-rules, agent-network, dispatch-agents, orchestration) |
| May 2026 | Added pre-push scope violation check to run-agent-task.sh (blocks push if undeclared files in diff) |
| May 2026 | Added troubleshooting 11.17 (scope violation) and 11.18 (non-ASCII commit subjects) |
| May 2026 | Added commit subject style rules to git-rules.mdc Rule 6 and dispatch-agents.mdc slice block |
| May 2026 | Added squash-before-push guidance and Rule 12 (one clean commit per slice) |
| May 2026 | Added troubleshooting 11.16 (empty push — slice already on dev) |

---

*Post new issues and this document will be updated to stay current.*

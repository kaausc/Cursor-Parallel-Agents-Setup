# Parallel AI Coding Agents — Setup Guide

> **Run a fleet of AI coding agents in parallel on your own infrastructure, orchestrated by N8N, powered by Cursor CLI, with live Discord notifications.**

---

## What This Is

A complete, battle-tested guide and bootstrap toolkit for setting up multiple AI coding agents that work on your codebase simultaneously. Each agent runs on its own Ubuntu VM, receives tasks via N8N webhooks, executes them headlessly using Cursor CLI, and reports results to Discord — all without you manually copying and pasting instructions into multiple windows.

This was built and refined through real-world use on a production codebase with 8 parallel agents running simultaneously.

---

## What's Included

### 📄 `parallel-agents-setup-guide.md`
The complete setup guide — 11 parts covering everything from VM creation to production use.

| Part | Contents |
|------|----------|
| 1 | Infrastructure planning — VM specs, networking, Proxmox setup |
| 2 | N8N server setup — install, SSH key generation |
| 3 | Agent VM bootstrap — what the script does, manual steps |
| 4 | Discord setup — channels, webhooks, connectivity testing |
| 5 | N8N workflow — Parse Body, Switch, SSH nodes, Collect Results |
| 6 | Orchestrator setup — Cursor rules, dispatch format, slice discipline |
| 7 | Sample Cursor rules files — ready-to-use templates for all 4 key rule files |
| 8 | Verification — fleet health check, identity test, full dispatch test |
| 9 | Adding a new agent — step-by-step expansion checklist |
| 10 | Troubleshooting — 15 documented issues with fixes |
| 11 | Architecture reference — how the script works, git strategy, design decisions |

### 🔧 `bootstrap-agent.sh`
A single shell script that sets up a fresh Ubuntu 24.04 VM as a coding agent. Edit the variables at the top and run it — it handles everything automatically with two interactive pauses (Cursor auth + GitHub key).

**What it installs and configures:**
- System updates and dependencies (git, curl, python3, openssh)
- Passwordless sudo
- Persistent PATH and DNS configuration
- Cursor CLI + interactive browser authentication
- GitHub SSH key generation and configuration
- Git global configuration with correct agent identity
- Repo clone + agent branch creation
- `.gitattributes` merge strategy (prevents cursor rules and docs conflicts)
- `.gitignore` updates (excludes `.agent-identity` and `.venv`)
- `.agent-identity` file (machine-local, never committed)
- `run-agent-task.sh` deployment (the script N8N calls on every dispatch)

### 📋 Sample Cursor Rules Files (inside the guide, Part 7)
Generalized starter templates for the four rules files every agent fleet needs:

- **`git-rules.mdc`** — startup checklist, commit discipline, force-push policy, git identity
- **`agent-network.mdc`** — roster, topology, responsibilities, communication formats
- **`dispatch-agents.mdc`** — `/dispatch` trigger, payload format, slice discipline, overlap check
- **`orchestration.mdc`** — delegation protocol, review checklist, merge policy, escalation rules

---

## How It Works

```
You type /dispatch in Cursor
    ↓
PowerShell sends POST to N8N webhook
    ↓
N8N splits payload → routes to each agent via SSH
    ↓
Each agent VM:
  1. Resets branch to origin/dev (clean slate)
  2. Runs Cursor CLI headlessly with the task
  3. Only commits declared files (scope enforced automatically)
  4. Posts live updates to Discord
    ↓
N8N collects all results → posts summary to #orchestration channel
```

---

## Stack

| Component | Purpose |
|-----------|---------|
| **Ubuntu 24.04** | Agent VM OS |
| **Proxmox** | VM hypervisor (any hypervisor works) |
| **N8N** | Task orchestration and SSH dispatch |
| **Cursor CLI** | Headless AI coding on each agent |
| **GitHub** | Source control — one branch per agent |
| **Discord** | Live notifications and blocker alerts |
| **PowerShell** | Dispatch trigger from orchestrator machine |

---

## Key Features

- **True parallelism** — all agents work simultaneously on non-overlapping files
- **Automatic scope enforcement** — agents physically cannot commit files outside their assigned slice
- **Pre-flight reset** — every task starts from a clean `origin/dev` baseline, eliminating stale history
- **Slice discipline** — prompt injection + post-task file scope check on every coding task
- **Discord integration** — live `🔄 starting` / `✅ complete` / `⛔ blocked` notifications per agent
- **Git attribution** — every commit clearly identified by agent name and email
- **Conflict prevention** — `.gitattributes` `merge=ours` strategy on cursor rules and docs
- **Self-healing DNS** — persistent `systemd-resolved` config survives reboots
- **Passwordless sudo** — N8N can run privileged commands without interactive prompts
- **Force-push safe** — pre-task resets use `--force-with-lease`, never `--force`

---

## Requirements

- A Cursor Pro or Business subscription (required for Cursor CLI headless mode)
- GitHub repository with SSH access
- N8N instance (self-hosted)
- Ubuntu 24.04 VMs (one per agent + one for N8N)
- Discord server with webhook permissions
- Orchestrator machine running Windows/Mac/Linux with Cursor installed

---

## Quick Start

1. **Spin up VMs** — one N8N VM, one per agent (see Part 1 of the guide)
2. **Set up N8N** — install, generate SSH key (Part 2)
3. **Edit variables** in `bootstrap-agent.sh` and run on each agent VM (Part 3)
4. **Create Discord channels and webhooks** (Part 4)
5. **Import N8N workflow** — wire Parse Body → Switch → SSH nodes → Collect Results (Part 5)
6. **Add Cursor rules** to your repo from the Part 7 templates (Part 6–7)
7. **Run verification** — fleet health check + dispatch test (Part 8)
8. **Start dispatching** — type `/dispatch` in Cursor and watch agents work in parallel

---

## Troubleshooting

The guide documents 15 real issues encountered during setup and production use:

- Merge conflicts on agent branches
- DNS resolution failures (Cursor API, GitHub)
- `.agent-identity` file going missing
- N8N SSH node expression mode (Fixed vs Expression)
- N8N Parse Body returning `undefined`
- `sudo: command not found` on minimal Ubuntu installs
- Virtual environments accidentally committed
- Orchestrator timeout on long tasks
- Cursor CLI authentication failures
- Agent branches accumulating stale commits
- Agents touching files outside assigned scope
- Force-push warnings explained
- Missing git commit attribution
- N8N `executeCommand` node removed in newer versions
- `gitattributes` conflict prevention

---

## Changelog

The guide includes a full changelog tracking every issue discovered and fix applied during real-world use. The guide is designed to be updated as new issues are discovered — post issues and the documentation will be kept current.

---

## License

MIT — use freely, adapt for your own projects.

---

*Built for real production use. Every fix in this guide was discovered the hard way.*

#!/bin/bash
# =============================================================================
# Parallel Coding Agent — Bootstrap Script
# Run this on a FRESH Ubuntu 24.04 VM as the agent user
# Usage: bash bootstrap-agent.sh
# =============================================================================

set -e

# =============================================================================
# CONFIGURATION — Edit these before running
# =============================================================================

AGENT_USER="youruser"                              # Linux username on this VM
AGENT_NAME="agent-01"                             # Unique agent name (e.g. agent-01)
AGENT_ROLE="coder"                                # coder or monitor
AGENT_BRANCH="agent-agent-01"                     # Git branch for this agent
AGENT_IP="10.0.0.11"                              # This VM's IP address

N8N_IP="10.0.0.10"                                # N8N server IP
N8N_PORT="5678"                                   # N8N port (default 5678)
N8N_WEBHOOK_PATH="dispatch-task"                  # N8N webhook path

REPO_URL="git@github.com:yourorg/yourrepo.git"    # GitHub SSH repo URL
REPO_NAME="yourrepo"                              # Repo folder name
REPO_DIR="/home/$AGENT_USER/$REPO_NAME"           # Full path to repo

MODEL="composer-2-fast"                           # Cursor model to use
REPORT_TO="orchestrator"                          # Orchestrator agent name

DISCORD_WEBHOOK=""                                # This agent's Discord webhook URL
DISCORD_BLOCKED_WEBHOOK=""                        # #blocked channel webhook URL

GITHUB_EMAIL="$AGENT_NAME@your-project"          # Git commit email
GITHUB_NAME="$AGENT_NAME"                        # Git commit display name

# =============================================================================
# PHASE 1 — System Updates + Dependencies
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 1 — System Updates + Dependencies"
echo "=========================================="

sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq \
  git \
  curl \
  python3 \
  python3-pip \
  openssh-server \
  ca-certificates

echo "✅ System packages installed"

# =============================================================================
# PHASE 2 — Passwordless Sudo
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 2 — Passwordless Sudo"
echo "=========================================="

echo "$AGENT_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$AGENT_USER
sudo chmod 440 /etc/sudoers.d/$AGENT_USER
echo "✅ Passwordless sudo configured for $AGENT_USER"

# =============================================================================
# PHASE 3 — PATH Setup
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 3 — PATH Setup"
echo "=========================================="

grep -q 'local/bin' ~/.bashrc || \
  echo 'export PATH=$HOME/.local/bin:$PATH:/usr/bin:/bin:/sbin:/usr/sbin' >> ~/.bashrc
grep -q 'local/bin' ~/.profile || \
  echo 'export PATH=$HOME/.local/bin:$PATH:/usr/bin:/bin:/sbin:/usr/sbin' >> ~/.profile
export PATH=$HOME/.local/bin:$PATH:/usr/bin:/bin:/sbin:/usr/sbin
echo "✅ PATH configured"

# =============================================================================
# PHASE 4 — Persistent DNS Fix
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 4 — Persistent DNS Fix"
echo "=========================================="

sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null << 'DNSEOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1
FallbackDNS=9.9.9.9
DNSEOF

sudo systemctl restart systemd-resolved
echo "✅ DNS configured (8.8.8.8, 8.8.4.4, 1.1.1.1)"

# =============================================================================
# PHASE 5 — Install Cursor CLI Agent
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 5 — Install Cursor CLI Agent"
echo "=========================================="

curl https://cursor.com/install -fsSL | bash
export PATH=$HOME/.local/bin:$PATH
~/.local/bin/agent --version
echo "✅ Cursor CLI installed"
echo ""
echo "⚠️  ACTION REQUIRED: Authenticate with your Cursor account."
echo "   Run: ~/.local/bin/agent login"
echo "   Open the printed URL in your browser and approve."
echo "   Press ENTER when done."
read -r

~/.local/bin/agent status && echo "✅ Cursor CLI authenticated" || \
  echo "❌ Auth failed — re-run: ~/.local/bin/agent login"

# =============================================================================
# PHASE 6 — GitHub SSH Key Setup
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 6 — GitHub SSH Key Setup"
echo "=========================================="

if [ ! -f ~/.ssh/github_agent ]; then
  ssh-keygen -t ed25519 -C "$AGENT_NAME@your-project" -f ~/.ssh/github_agent -N ""
fi

mkdir -p ~/.ssh
cat >> ~/.ssh/config << SSHEOF
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_agent
  StrictHostKeyChecking no
SSHEOF
chmod 600 ~/.ssh/config

echo ""
echo "⚠️  ACTION REQUIRED: Add this public key to GitHub."
echo "   GitHub → Settings → SSH and GPG keys → New SSH key"
echo "   Title: $AGENT_NAME"
echo ""
echo "   === PUBLIC KEY (copy everything below) ==="
cat ~/.ssh/github_agent.pub
echo "   ==========================================="
echo ""
echo "   Press ENTER after adding the key to GitHub."
read -r

ssh -T git@github.com 2>&1 | grep -E 'success|denied|verified' && \
  echo "✅ GitHub SSH auth OK" || echo "❌ GitHub auth failed — check the key"

# =============================================================================
# PHASE 7 — Git Configuration
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 7 — Git Configuration"
echo "=========================================="

git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$AGENT_NAME"
git config --global init.defaultBranch main
git config --global merge.ours.driver true

# Verify attribution is set correctly
echo "Git user.name  : $(git config user.name)"
echo "Git user.email : $(git config user.email)"
echo "✅ Git configured"

# =============================================================================
# PHASE 8 — Clone Repo + Create Agent Branch
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 8 — Clone Repo + Create Branch"
echo "=========================================="

if [ ! -d "$REPO_DIR" ]; then
  git clone $REPO_URL $REPO_DIR
fi

cd $REPO_DIR
git checkout dev
git pull origin dev

if git ls-remote --heads origin $AGENT_BRANCH | grep -q $AGENT_BRANCH; then
  git checkout $AGENT_BRANCH
  git pull origin $AGENT_BRANCH
  echo "✅ Switched to existing branch $AGENT_BRANCH"
else
  git checkout -b $AGENT_BRANCH
  git push origin $AGENT_BRANCH
  echo "✅ Branch $AGENT_BRANCH created and pushed"
fi

# =============================================================================
# PHASE 9 — Configure .gitattributes
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 9 — Configure .gitattributes"
echo "=========================================="

cd $REPO_DIR
grep -q '.cursor/rules/\*' .gitattributes 2>/dev/null || \
  echo '.cursor/rules/* merge=ours' >> .gitattributes
grep -q 'docs/\*' .gitattributes 2>/dev/null || \
  echo 'docs/* merge=ours' >> .gitattributes

git add .gitattributes
git diff --staged --quiet || \
  git commit -m "chore: set merge strategy to ours for cursor rules and docs"
git push origin $AGENT_BRANCH
echo "✅ .gitattributes configured — cursor rules and docs won't conflict"

# =============================================================================
# PHASE 10 — Update .gitignore
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 10 — Update .gitignore"
echo "=========================================="

cd $REPO_DIR
grep -q '.agent-identity' .gitignore || echo '.agent-identity' >> .gitignore
grep -q '.venv/' .gitignore        || echo '.venv/' >> .gitignore
grep -q '^.venv$' .gitignore       || echo '.venv' >> .gitignore

git add .gitignore
git diff --staged --quiet || \
  git commit -m "chore: add .agent-identity and .venv to .gitignore"
git push origin $AGENT_BRANCH
echo "✅ .gitignore updated"

# =============================================================================
# PHASE 11 — Create .agent-identity
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 11 — Create .agent-identity"
echo "=========================================="

cat > $REPO_DIR/.agent-identity << EOF
AGENT_NAME=$AGENT_NAME
AGENT_ROLE=$AGENT_ROLE
AGENT_BRANCH=$AGENT_BRANCH
PROJECT_ROOT=$REPO_DIR
REPORT_TO=$REPORT_TO
MODEL=$MODEL
DISCORD_WEBHOOK=$DISCORD_WEBHOOK
EOF

echo "✅ .agent-identity created (not tracked by git)"

# =============================================================================
# PHASE 12 — Deploy run-agent-task.sh
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 12 — Deploy run-agent-task.sh"
echo "=========================================="

SCRIPT_PATH="/home/$AGENT_USER/run-agent-task.sh"

cat > $SCRIPT_PATH << SCRIPTEOF
#!/bin/bash
set -e
export PATH=\$HOME/.local/bin:\$PATH:/usr/bin:/bin:/sbin:/usr/sbin

TASK="\$1"
FILES="\$2"
BRANCH="\$3"
REPO="$REPO_DIR"
IDENTITY_FILE="\$REPO/.agent-identity"
LOGFILE="/home/$AGENT_USER/agent-task-\$(date +%Y%m%d-%H%M%S).log"

AGENT_ID=\$(grep '^AGENT_NAME=' \$IDENTITY_FILE | cut -d'=' -f2)
AGENT_ROLE=\$(grep '^AGENT_ROLE=' \$IDENTITY_FILE | cut -d'=' -f2)
MODEL=\$(grep '^MODEL=' \$IDENTITY_FILE | cut -d'=' -f2)
DISCORD_AGENT_WEBHOOK=\$(grep '^DISCORD_WEBHOOK=' \$IDENTITY_FILE | cut -d'=' -f2)
DISCORD_BLOCKED_WEBHOOK="$DISCORD_BLOCKED_WEBHOOK"

discord_post() {
  local WEBHOOK="\$1"
  local MESSAGE="\$2"
  curl -s -X POST "\$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"\$MESSAGE\"}" \
    > /dev/null 2>&1 || true
}

echo "=== Agent: \$AGENT_ID ===" | tee \$LOGFILE
echo "=== Role: \$AGENT_ROLE ===" | tee -a \$LOGFILE
echo "=== Model: \$MODEL ===" | tee -a \$LOGFILE
echo "=== Branch: \$BRANCH ===" | tee -a \$LOGFILE
echo "=== Task: \$TASK ===" | tee -a \$LOGFILE
echo "=== Files: \$FILES ===" | tee -a \$LOGFILE

if [ "\$TASK" != "n/a" ] && [ "\$FILES" != "n/a" ]; then
  discord_post "\$DISCORD_AGENT_WEBHOOK" \
    "🔄 **\$AGENT_ID** starting task\n\\\`\\\`\\\`Task: \$TASK\nFiles: \$FILES\nBranch: \$BRANCH\\\`\\\`\\\`"
fi

cd \$REPO

# ── PRE-FLIGHT: always start clean from origin/dev ────────────────────────
# Resets the agent branch to dev state before every task.
# Eliminates stale local history that causes drive-by diffs on merge.
git fetch origin
git checkout \$BRANCH
git reset --hard origin/dev
echo "=== Pre-flight: branch reset to origin/dev ===" | tee -a \$LOGFILE
git status | tee -a \$LOGFILE
# ──────────────────────────────────────────────────────────────────────────

EXIT_CODE=0
AGENT_OUTPUT=""

if [ "\$TASK" = "n/a" ]; then
  echo "No task — skipping" | tee -a \$LOGFILE

elif [ "\$FILES" = "n/a" ]; then
  AGENT_OUTPUT=\$(agent \
    --print \
    --yolo \
    --trust \
    --workspace "\$REPO" \
    --model "\$MODEL" \
    "\$TASK" \
    2>&1 | tee -a \$LOGFILE) || EXIT_CODE=\$?

else
  # ── SLICE DISCIPLINE appended to every real task ────────────────────────
  SLICE_BLOCK="SLICE DISCIPLINE — STRICTLY ENFORCED:
- Work ONLY on these files: \$FILES
- Do NOT modify any file outside this list under any circumstances
- Do NOT make drive-by fixes, formatting changes, or improvements to unrelated files
- Do NOT merge, cherry-pick, or carry over any unrelated local work
- If a change seems needed outside your assigned files, note it in your report — do NOT make it
- Commit ONLY the changes to your assigned files
- Commit message format: '<type>: <description>'"
  # ────────────────────────────────────────────────────────────────────────

  AGENT_OUTPUT=\$(agent \
    --print \
    --yolo \
    --trust \
    --workspace "\$REPO" \
    --model "\$MODEL" \
    "\$TASK. Work only on these files: \$FILES. Follow the rules in .cursor/rules/. Commit your changes with a descriptive commit message when done.

\$SLICE_BLOCK" \
    2>&1 | tee -a \$LOGFILE) || EXIT_CODE=\$?
fi

# ── POST-TASK: check for undeclared file changes ──────────────────────────
if [ "\$FILES" != "n/a" ] && [ "\$TASK" != "n/a" ]; then
  CHANGED_FILES=\$(git diff --name-only origin/dev HEAD 2>/dev/null || true)
  UNDECLARED=""
  for f in \$CHANGED_FILES; do
    if ! echo "\$FILES" | grep -qw "\$f"; then
      UNDECLARED="\$UNDECLARED \$f"
    fi
  done
  if [ -n "\$UNDECLARED" ]; then
    echo "=== ⚠️  WARNING: Undeclared files changed:\$UNDECLARED ===" | tee -a \$LOGFILE
    discord_post "\$DISCORD_AGENT_WEBHOOK" \
      "⚠️ **\$AGENT_ID** touched files outside declared scope:\n\\\`\\\`\\\`\$UNDECLARED\\\`\\\`\\\`\nOrchestrator: cherry-pick only assigned-file commits before merging to dev."
  fi
fi
# ──────────────────────────────────────────────────────────────────────────

if [ \$EXIT_CODE -ne 0 ]; then
  ERROR_MSG=\$(tail -5 \$LOGFILE | tr '\n' ' ' | sed 's/[\"\\\\]//g' | cut -c1-500)
  discord_post "\$DISCORD_BLOCKED_WEBHOOK" \
    "⛔ **BLOCKED — \$AGENT_ID**\n\\\`\\\`\\\`Task: \$TASK\nError: \$ERROR_MSG\nLog: \$LOGFILE\\\`\\\`\\\`\n@here"
  echo "BLOCKED"
  echo "Agent: \$AGENT_ID"
  echo "Branch: \$BRANCH"
  echo "Error: \$ERROR_MSG"
  exit 1
fi

git add .
git diff --staged --quiet || git commit -m "chore: end of session commit by \$AGENT_ID"

# Only push if there is new content vs origin/dev
NEW_COMMITS=\$(git log origin/dev..HEAD --oneline 2>/dev/null | wc -l)
if [ "\$NEW_COMMITS" -eq 0 ]; then
  echo "=== ℹ️  No new commits vs origin/dev — skipping push ===" | tee -a \$LOGFILE
  discord_post "\$DISCORD_AGENT_WEBHOOK" \
    "ℹ️ **\$AGENT_ID** — no new content vs dev, nothing pushed (slice already on dev)"
else
  PUSH_ATTEMPTS=0
  PUSH_SUCCESS=0
  while [ \$PUSH_ATTEMPTS -lt 3 ]; do
    PUSH_ATTEMPTS=\$((\$PUSH_ATTEMPTS + 1))
    git push --force-with-lease origin \$BRANCH 2>&1 | tee -a \$LOGFILE
    git fetch origin \$BRANCH 2>/dev/null
    LOCAL_SHA=\$(git rev-parse HEAD)
    REMOTE_SHA=\$(git rev-parse origin/\$BRANCH 2>/dev/null || echo "unknown")
    if [ "\$LOCAL_SHA" = "\$REMOTE_SHA" ]; then
      echo "=== Push verified: local matches remote ===" | tee -a \$LOGFILE
      PUSH_SUCCESS=1
      break
    else
      echo "=== Push attempt \$PUSH_ATTEMPTS failed verification — retrying in 5s ===" | tee -a \$LOGFILE
      sleep 5
    fi
  done
  if [ \$PUSH_SUCCESS -eq 0 ]; then
    discord_post "\$DISCORD_BLOCKED_WEBHOOK" \
      "⛔ **PUSH FAILED — \$AGENT_ID**\`\`\`Branch \$BRANCH did not reach GitHub after 3 attempts.
Local: \$LOCAL_SHA
Remote: \$REMOTE_SHA\`\`\`
@here"
    echo "BLOCKED"
    echo "Agent: \$AGENT_ID"
    echo "Branch: \$BRANCH"
    echo "Error: Push verification failed after 3 attempts"
    exit 1
  fi
fi

SUMMARY=\$(echo "\$AGENT_OUTPUT" | tail -20 | tr '\n' ' ' | sed 's/[\"\\\\\ \`]//g' | cut -c1-800)

if [ "\$TASK" != "n/a" ] && [ "\$FILES" != "n/a" ]; then
  discord_post "\$DISCORD_AGENT_WEBHOOK" \
    "✅ **\$AGENT_ID** task complete\n\\\`\\\`\\\`Branch: \$BRANCH\nPushed: Yes\n\nSummary:\n\$SUMMARY\\\`\\\`\\\`"
fi

echo "TASK COMPLETE"
echo "Agent: \$AGENT_ID"
echo "Branch: \$BRANCH"
echo "Pushed: Yes"
echo "Log: \$LOGFILE"
echo "DISCORD_SUMMARY: \$SUMMARY"
SCRIPTEOF

chmod +x $SCRIPT_PATH
echo "✅ run-agent-task.sh deployed to $SCRIPT_PATH"

# =============================================================================
# PHASE 13 — Verify Everything
# =============================================================================

echo ""
echo "=========================================="
echo " Phase 13 — Verification"
echo "=========================================="

echo "Agent ID    : $(grep AGENT_NAME $REPO_DIR/.agent-identity | cut -d'=' -f2)"
echo "Branch      : $(cd $REPO_DIR && git branch --show-current)"
echo "Git status  : $(cd $REPO_DIR && git status --short | wc -l) uncommitted files"
echo "Cursor CLI  : $(~/.local/bin/agent --version 2>/dev/null || echo 'NOT FOUND')"
echo "GitHub SSH  : $(ssh -T git@github.com 2>&1 | grep -o 'successfully authenticated' || echo 'CHECK NEEDED')"
echo "DNS         : $(curl -s -o /dev/null -w '%{http_code}' https://cursor.com) (200=OK)"
echo "Sudo        : $(sudo echo 'OK')"
echo ""
echo "=========================================="
echo " Bootstrap Complete — $AGENT_NAME"
echo "=========================================="
echo ""
echo "Next steps on the N8N machine:"
echo "  1. ssh-copy-id -i ~/.ssh/n8n_agents.pub $AGENT_USER@$AGENT_IP"
echo "  2. Add SSH credential in N8N for $AGENT_NAME ($AGENT_IP)"
echo "  3. Add SSH node + Switch rule in N8N workflow for $AGENT_NAME"
echo "  4. Update the dispatch Cursor rule to include $AGENT_NAME"

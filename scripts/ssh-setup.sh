#!/bin/bash
# GitHub SSH + gh CLI Setup for Cowork Integration
# Run each section one at a time and confirm before continuing

set -e

echo ""
echo "=========================================="
echo " STEP 1: Install gh CLI (if not present)"
echo "=========================================="
if command -v gh &> /dev/null; then
  echo "✅ gh is already installed: $(gh --version | head -1)"
else
  echo "Installing gh via brew..."
  brew install gh
  echo "✅ gh installed: $(gh --version | head -1)"
fi

echo ""
echo "=========================================="
echo " STEP 2: Check for existing SSH keys"
echo "=========================================="
if [ -f "$HOME/.ssh/id_ed25519" ]; then
  echo "✅ SSH key already exists at ~/.ssh/id_ed25519"
  echo "   Public key:"
  cat "$HOME/.ssh/id_ed25519.pub"
else
  echo "No ed25519 key found. Generating one..."
  ssh-keygen -t ed25519 -C "justin.h.stottlemyer@gmail.com" -f "$HOME/.ssh/id_ed25519"
  echo "✅ SSH key generated."
fi

echo ""
echo "=========================================="
echo " STEP 3: Add key to ssh-agent"
echo "=========================================="
eval "$(ssh-agent -s)"

# Ensure key is auto-loaded in future sessions
SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q "id_ed25519" "$SSH_CONFIG" 2>/dev/null; then
  mkdir -p "$HOME/.ssh"
  cat >> "$SSH_CONFIG" << 'EOF'

Host github.com
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
EOF
  echo "✅ Added GitHub host config to ~/.ssh/config"
else
  echo "✅ SSH config already has id_ed25519 entry"
fi

ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || ssh-add "$HOME/.ssh/id_ed25519"
echo "✅ Key added to ssh-agent"

echo ""
echo "=========================================="
echo " STEP 4: Copy public key (add to GitHub)"
echo "=========================================="
cat "$HOME/.ssh/id_ed25519.pub" | pbcopy
echo "✅ Public key copied to clipboard."
echo ""
echo "   → Paste it at: https://github.com/settings/ssh/new"
echo "   → Title: 'Mac - Cowork' (or your preference)"
echo "   → Key type: Authentication Key"
echo ""
echo "   Your public key:"
cat "$HOME/.ssh/id_ed25519.pub"

echo ""
echo "=========================================="
echo " STEP 5: Authenticate gh CLI with SSH"
echo "=========================================="
echo "Running: gh auth login"
echo "(Choose: GitHub.com → SSH → your id_ed25519 key → Login with browser)"
gh auth login

echo ""
echo "=========================================="
echo " STEP 6: Verify connection"
echo "=========================================="
ssh -T git@github.com 2>&1 || true
gh auth status
echo ""
echo "✅ All done! GitHub SSH + gh CLI is configured."
echo "   Cowork can now use 'gh' commands via your mounted folder."

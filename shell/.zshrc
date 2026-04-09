# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# Dev session aliases
alias cosmic='~/scripts/dev-session.sh cosmic'
alias dev='~/scripts/dev-session.sh'

# Claude Code aliases
alias claude='command claude --dangerously-skip-permissions'
alias cc='tmux new-session -s claude -n claude -c "$(pwd)" \; send-keys "claude --dangerously-skip-permissions" Enter 2>/dev/null || tmux attach -t claude'

# Quick Xcode helpers
alias xb='xcodebuild -quiet build'
alias xt='xcodebuild -quiet test'
alias sim='xcrun simctl list devices available'

# Gastown shell hook removed 2026-03-25 (pipeline V2 replaces Gastown)
# Original: source ~/.config/gastown/shell-hook.sh
export PATH="$HOME/.local/bin:$PATH"

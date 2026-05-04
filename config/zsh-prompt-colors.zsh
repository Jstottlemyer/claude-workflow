# MonsterFlow prompt colors — sourced from ~/.zshrc inside a sentinel block.
# Theme-only. No behavioral changes (no aliases, no completion tweaks, no
# PATH edits, no history mods, no cd overrides). Override locally by
# exporting MONSTERFLOW_PROMPT_* vars BEFORE this file is sourced.

# Color palette (256-color, matches config/tmux.conf — cyan/grey high-contrast)
MONSTERFLOW_PROMPT_CYAN=${MONSTERFLOW_PROMPT_CYAN:-'%F{51}'}
MONSTERFLOW_PROMPT_GREY=${MONSTERFLOW_PROMPT_GREY:-'%F{244}'}
MONSTERFLOW_PROMPT_GOLD=${MONSTERFLOW_PROMPT_GOLD:-'%F{220}'}
MONSTERFLOW_PROMPT_RED=${MONSTERFLOW_PROMPT_RED:-'%F{196}'}
MONSTERFLOW_PROMPT_RESET=${MONSTERFLOW_PROMPT_RESET:-'%f'}

# Minimal git-branch helper (no plugins required; safe outside git repos)
_monsterflow_git_branch() {
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || return 0
    [[ -n "$branch" ]] && print -n " (${branch})"
}

# Enable command substitution in PROMPT
setopt PROMPT_SUBST

# Two-line prompt:
#   <cyan>~/path</cyan>  <grey>(branch)</grey>
#   <gold>❯</gold>
PROMPT='${MONSTERFLOW_PROMPT_CYAN}%~${MONSTERFLOW_PROMPT_RESET}${MONSTERFLOW_PROMPT_GREY}$(_monsterflow_git_branch)${MONSTERFLOW_PROMPT_RESET}
${MONSTERFLOW_PROMPT_GOLD}❯${MONSTERFLOW_PROMPT_RESET} '

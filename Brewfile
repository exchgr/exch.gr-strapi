# Command-line dependencies for scripts/upgrade.sh (see scripts/lib/preflight.bash REQUIRED_TOOLS).
# yarn and node are intentionally NOT here — they are managed by asdf (.tool-versions);
# yarn itself is fetched by `yarn set version berry`.
brew "git"
brew "gh"
brew "jq"
brew "yq"
brew "curl"
brew "asdf"
# `yq` must be the mikefarah v4 flavor (what this formula installs) —
# scripts/lib/lookups.bash parse_uses_line depends on its syntax, and
# scripts/lib/preflight.bash rejects the kislyuk/Python yq sharing the name.

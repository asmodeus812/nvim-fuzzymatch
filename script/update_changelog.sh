#!/usr/bin/env bash
set -euo pipefail

version="${1:-1.0.0}"
today="$(date +%F)"

tmp_dir="$(mktemp -d)"
pre="$tmp_dir/pre"
unrel="$tmp_dir/unrel"
post="$tmp_dir/post"

awk -v pre="$pre" -v unrel="$unrel" -v post="$post" '
BEGIN { mode = "pre" }
/^## \[Unreleased\]/ { mode = "unrel"; next }
/^## \[/ {
  if (mode == "unrel") { mode = "post" }
}
{
  if (mode == "pre") print > pre
  else if (mode == "unrel") print > unrel
  else print > post
}
' CHANGELOG.md

added_items="$tmp_dir/added_items"
awk '
BEGIN { in_added = 0 }
/^### Added/ { in_added = 1; next }
/^### / { if (in_added) exit }
{ if (in_added && $0 ~ /^- /) print }
' "$unrel" > "$added_items"

last_changelog_commit="$(git log -n 1 --format=%H -- CHANGELOG.md)"
commits="$tmp_dir/commits"
git log --no-merges --format='%s' "${last_changelog_commit}..HEAD" > "$commits"
commits_added="$tmp_dir/commits_added"
commits_fixed="$tmp_dir/commits_fixed"
commits_changed="$tmp_dir/commits_changed"
commits_breaking="$tmp_dir/commits_breaking"
commits_misc="$tmp_dir/commits_misc"

# Conventional commit parsing
grep -iE '^[a-z]+(\([^)]+\))?!:' "$commits" | sed 's/^/- /' > "$commits_breaking" || true
grep -iE '^feat(\([^)]+\))?:' "$commits" | sed 's/^/- /' > "$commits_added" || true
grep -iE '^fix(\([^)]+\))?:' "$commits" | sed 's/^/- /' > "$commits_fixed" || true
grep -iE '^(perf|refactor)(\([^)]+\))?:' "$commits" | sed 's/^/- /' > "$commits_changed" || true
grep -viE '^[a-z]+(\([^)]+\))?!:|^feat(\([^)]+\))?:|^fix(\([^)]+\))?:|^(perf|refactor)(\([^)]+\))?:' "$commits" | sed 's/^/- /' > "$commits_misc" || true

{
  printf '## [Unreleased]\n\n'
  printf '### Added\n\n'
  printf '### Fixed\n\n'
  printf '## [%s] - %s\n\n' "$version" "$today"
  printf '### Added\n'
  if [ -s "$added_items" ]; then
    cat "$added_items"
  fi
  printf '\n\n### Added\n'
  if [ -s "$commits_added" ]; then
    cat "$commits_added"
  else
    printf '- (no changes)\n'
  fi
  printf '\n\n### Fixed\n'
  if [ -s "$commits_fixed" ]; then
    cat "$commits_fixed"
  else
    printf '- (no changes)\n'
  fi
  printf '\n\n### Changed\n'
  if [ -s "$commits_changed" ]; then
    cat "$commits_changed"
  else
    printf '- (no changes)\n'
  fi
  printf '\n\n### Breaking\n'
  if [ -s "$commits_breaking" ]; then
    cat "$commits_breaking"
  else
    printf '- (no changes)\n'
  fi
  printf '\n\n### Misc\n'
  if [ -s "$commits_misc" ]; then
    cat "$commits_misc"
  else
    printf '- (no changes)\n'
  fi
  printf '\n\n'
  if [ -s "$pre" ]; then
    cat "$pre"
  fi
  if [ -s "$post" ]; then
    cat "$post"
  fi
} > CHANGELOG.md

rm -rf "$tmp_dir"

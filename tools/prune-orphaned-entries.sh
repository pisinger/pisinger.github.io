#!/usr/bin/env bash
#
# Prune orphaned radar and digest entries.
#
# The tab pages only list a fixed window of each collection (see the MAX_DIGESTS
# and MAX_ENTRIES constants in _tabs/*.md). Entries that fall outside that window
# are still built and published, but nothing on the site links to them any more.
# This removes them so the repo matches what the site actually shows.
#
# Full history is retained in the generator repo (pisinger/private-openclaw),
# which is also what the pisinger.tngx-voice.com apps read, so pruning here does
# not shorten the lookback offered by those apps.
#
# Usage:
#   tools/prune-orphaned-entries.sh            # delete orphans
#   tools/prune-orphaned-entries.sh --dry-run  # list orphans, delete nothing

set -euo pipefail

# Keep in sync with the MAX_* constants in the matching _tabs/*.md page.
declare -A KEEP=(
  ["_ms_release_radar"]=6    # _tabs/ms-release-radar.md   MAX_DIGESTS
  ["_wiz_release_radar"]=6   # _tabs/wiz-release-radar.md  MAX_DIGESTS
  ["_ms_tech_news"]=20       # _tabs/ms-tech-news.md       MAX_ENTRIES
)

dry_run=false
[[ "${1:-}" == "--dry-run" ]] && dry_run=true

cd "$(dirname "$0")/.."

pruned=0

for dir in "${!KEEP[@]}"; do
  keep="${KEEP[$dir]}"
  [[ -d "$dir" ]] || { echo "skip: $dir does not exist"; continue; }

  # Entry filenames are YYYY-MM.md / YYYY-Www.md, so a reverse lexicographic
  # sort is chronological, newest first. Leading-underscore files (_template.md)
  # are excluded by the glob and never counted or pruned.
  mapfile -t entries < <(find "$dir" -maxdepth 1 -type f -name '[0-9]*.md' -printf '%f\n' | sort -r)

  total="${#entries[@]}"
  if (( total <= keep )); then
    echo "$dir: $total entries, window $keep - nothing to prune"
    continue
  fi

  orphans=("${entries[@]:$keep}")
  echo "$dir: $total entries, window $keep - pruning ${#orphans[@]}"

  for f in "${orphans[@]}"; do
    echo "  - $dir/$f"
    if [[ "$dry_run" == false ]]; then
      # -f because the entry may carry uncommitted edits; it is being deleted
      # either way. Untracked entries never reached the index, so plain rm.
      if git ls-files --error-unmatch "$dir/$f" >/dev/null 2>&1; then
        git rm -f --quiet "$dir/$f"
      else
        rm -f "$dir/$f"
      fi
    fi
    pruned=$((pruned + 1))
  done
done

if [[ "$dry_run" == true ]]; then
  echo "dry run: $pruned entries would be pruned"
else
  echo "pruned $pruned entries"
fi

# Signal to the workflow whether anything changed.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  if (( pruned > 0 )); then
    echo "pruned=true" >> "$GITHUB_OUTPUT"
  else
    echo "pruned=false" >> "$GITHUB_OUTPUT"
  fi
fi

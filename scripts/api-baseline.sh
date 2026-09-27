#!/bin/bash
# Prints the commit to use for API comparison. The pre-migration baseline must
# resolve Persistence 0.1.0: its original `from: 0.1.0` also admits the incompatible
# 0.2.0 protocol. Pin only that historical snapshot; never change the PR's sources
# or its dependency on 0.2.0. No branch or tag points to the temporary commit.
set -euo pipefail

BASELINE=$(git rev-parse --verify "${1:?Pass the API baseline revision}^{commit}")
if [[ "$BASELINE" != f3a316b1e285cff78874e07313dcb0a0e9acda1d ]]; then
  printf '%s\n' "$BASELINE"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git show "$BASELINE:Package.swift" > "$WORK/Package.swift.original"
sed 's|swift-persistence.git", from: "0.1.0"|swift-persistence.git", exact: "0.1.0"|' \
  "$WORK/Package.swift.original" > "$WORK/Package.swift"
if cmp -s "$WORK/Package.swift.original" "$WORK/Package.swift"; then
  echo "Expected Persistence dependency not found in the historical baseline." >&2
  exit 1
fi

# An isolated index preserves every baseline file except the dependency bound.
# SwiftPM can then build this snapshot with ordinary, fresh dependency resolution.
export GIT_INDEX_FILE="$WORK/index"
git read-tree "$BASELINE"
MANIFEST=$(git hash-object -w "$WORK/Package.swift")
git update-index --cacheinfo "100644,$MANIFEST,Package.swift"
TREE=$(git write-tree)

# Stable metadata makes repeated checks reuse the same baseline identity.
export GIT_AUTHOR_DATE
GIT_AUTHOR_DATE=$(git show -s --format=%cI "$BASELINE")
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
git -c user.name='API baseline' -c user.email='api-baseline@localhost' \
  commit-tree "$TREE" -p "$BASELINE" \
  -m 'Resolve the historical API baseline with Persistence 0.1.0'

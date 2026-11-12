#!/usr/bin/env bash
# axiom-audit.sh — which of this paper's Lean theorems does the kernel accept without a hole?
#
#   bash docs/paper/lean/axiom-audit.sh        (build.sh runs it after `lake build`)
#
# Prints `lean: n/m kernel-checked Lean statements` and names every theorem
# whose axioms include sorryAx. That is the kernel's own answer: a text search
# for the word sorry misses a hole reached through another lemma and counts
# the word in a comment. Only theorems in this paper's own libraries are
# counted (the lean_lib roots in the lakefile), never a dependency under .lake/.
#
# A statement with a hole is a Gap, not a build failure: exit 0 with the count.
# Exit 1 only when the audit itself could not run.
set -uo pipefail

cd "$(dirname "$0")"
export PATH="${HOME}/.elan/bin:${PATH:-}"
command -v lake >/dev/null 2>&1 || { echo "lean: lake not on PATH — axiom audit skipped"; exit 1; }

# lean_lib roots: `[[lean_lib]]` then `name = "X"` in lakefile.toml, or `lean_lib X` in lakefile.lean.
roots=""
if [ -f lakefile.toml ]; then
  roots="$(awk '
    /^\[\[lean_lib\]\]/ { lib = 1; next }
    /^\[/ { lib = 0 }
    lib && /^[[:space:]]*name[[:space:]]*=/ {
      gsub(/^[^"]*"|".*$/, ""); print; lib = 0
    }' lakefile.toml | tr '\n' ' ')"
elif [ -f lakefile.lean ]; then
  roots="$(sed -n 's/^[[:space:]]*lean_lib[[:space:]]\{1,\}«\{0,1\}\([A-Za-z0-9_.]*\)».*$/\1/p; s/^[[:space:]]*lean_lib[[:space:]]\{1,\}\([A-Za-z0-9_.]*\).*$/\1/p' lakefile.lean | sort -u | tr '\n' ' ')"
fi
roots="${roots% }"
if [ -z "$roots" ]; then
  echo "lean: no lean_lib in the lakefile — axiom audit skipped"
  exit 1
fi

mkdir -p .lake
audit=".lake/paper-axiom-audit.lean"
{
  echo "import Lean"
  for r in $roots; do echo "import $r"; done
  cat <<'LEAN'
open Lean Elab Command

/-- One line per theorem in the paper's own modules: `AXIOMS <name> <axioms>`. -/
elab "#paper_axiom_audit " roots:ident* : command => do
  let env ← getEnv
  let rootNames := roots.map (·.getId)
  let mods := env.header.moduleNames
  for (name, info) in env.constants.map₁.toList do
    if let .thmInfo _ := info then
      if let some idx := env.getModuleIdxFor? name then
        let modName := mods[idx.toNat]!
        if rootNames.any (·.isPrefixOf modName) && !name.isInternal then
          let axs ← Lean.collectAxioms name
          logInfo m!"AXIOMS {name} {axs.toList}"

LEAN
  echo "#paper_axiom_audit $roots"
} > "$audit"

out="$(lake env lean "$audit" 2>&1)"; rc=$?
rows="$(printf '%s\n' "$out" | grep -o 'AXIOMS .*' || true)"
if [ "$rc" -ne 0 ] || [ -z "$rows" ]; then
  echo "lean: axiom audit did not run (exit $rc) — count by hand with #print axioms"
  printf '%s\n' "$out" | head -5 | sed 's/^/  /'
  exit 1
fi
total="$(printf '%s\n' "$rows" | grep -c .)"
open="$(printf '%s\n' "$rows" | grep -c 'sorryAx' || true)"
echo "lean: $((total - open))/$total kernel-checked Lean statements"
if [ "$open" -gt 0 ]; then
  echo "lean: on Gaps (axioms include sorryAx):"
  printf '%s\n' "$rows" | grep 'sorryAx' | awk '{print "  " $2}' | sort
fi
exit 0

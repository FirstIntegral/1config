/-
  paper-template Lean scaffold. First writepaper_project copies this
  directory to docs/paper/lean/.

  `template_sanity` proves the toolchain works. Delete it when real paper
  theorems exist. Unproved statements stay holes (`sorryAx`) and go on Gaps.

  `lake build` green means the Lean declaration type-checks / is proved.
  It does not mean the Lean statement matches the LaTeX theorem.
-/

theorem template_sanity : 2 + 2 = 4 := rfl

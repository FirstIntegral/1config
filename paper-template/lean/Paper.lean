/-
  paper-template Lean scaffold (writepaper_project, opt-in).

  Copy this directory to docs/paper/lean/ only when a theorem is being
  formalized. Do not copy it onto every new paper.

  `template_sanity` proves the toolchain works. Delete it when real paper
  theorems exist. Unproved statements stay `sorry` and go on the Gaps list.

  `lake build` green means the Lean declaration type-checks / is proved.
  It does not mean the Lean statement matches the LaTeX theorem.
-/

theorem template_sanity : 2 + 2 = 4 := rfl

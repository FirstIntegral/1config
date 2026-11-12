# jeepney (vendored)

- Upstream: https://gitlab.com/takluyver/jeepney
- Version: 0.9.0, the PyPI release `jeepney==0.9.0`. The `.py` files are byte-identical to that release (the upstream `tests/` package at the top level is not copied).
- License: MIT, Copyright (c) 2017 Thomas Kluyver. Full text: `LICENSE` in this directory.
- Why it is here: `hooks/gpg-keyring.py` reads the GPG passphrase from the Secret Service over D-Bus. That has to work on a fresh machine before any package is installed, and jeepney is pure Python with no build step.
- Update: replace the directory with the files of a newer release, keep `LICENSE`, change the version line above and `__version__` will follow. `verify.sh` checks that this file and `LICENSE` exist and that the version here matches `__init__.py`.

#!/usr/bin/env bash
#
# mayhem/build.sh — build the defusedxml Atheris fuzz harness + its standalone reproducer,
# and prepare the project's own test suite. Runs inside the commit image (mayhem/Dockerfile)
# as `mayhem` in /mayhem. Python adaptation of the C/C++ template.
#
# What it does (must be idempotent + air-gapped on re-run — SPEC §6.2 item 9 / §6.5):
#   1. Populate / reuse an in-image wheelhouse under /opt/toolchains/python (HOME-independent),
#      then install atheris + the test deps OFFLINE from that wheelhouse into a fixed site dir on
#      PYTHONPATH. The first (CI, online) build fills the wheelhouse; the air-gapped PATCH re-run
#      resolves entirely from it (pip --no-index --find-links).
#   2. Compile launcher.c -> the ELF Mayhem target `parse-fuzz` (Atheris is a Python script; Mayhem
#      needs an ELF cmd, and the gate needs DWARF < 4 — hence a compiled wrapper).
#   3. Build the same launcher as the standalone (run-once) reproducer `parse-fuzz-standalone`.
#   4. Compile run_tests.c -> `defusedxml_run_tests`, the NON-system ELF wrapper test.sh runs the
#      suite through (so the anti-reward-hack sabotage check bites — SPEC §6.3).
#
# defusedxml itself is a pure-Python FLAT-layout package (defusedxml/ at the repo root) kept as the
# editable source tree — we expose it via PYTHONPATH (=/mayhem), so a PATCH agent's edits under
# defusedxml/ take effect with no reinstall. Keep everything ADDITIVE — the harness only CALLS
# defusedxml, never edits it.
#
# The base image exports the build contract (CC, SANITIZER_FLAGS, DEBUG_FLAGS, ...). For a Python
# target we only need DEBUG_FLAGS here: the launcher is a thin C exec wrapper, so building it with
# $SANITIZER_FLAGS would just instrument the wrapper, NOT the fuzzed Python — Atheris instruments
# the defusedxml library itself at import time (with atheris.instrument_imports), which is where
# coverage and the findings actually come from. The default SANITIZER_FLAGS (ASan+UBSan, halting)
# still flows through the image ENV and governs Atheris's native libFuzzer runtime.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export DEBUG_FLAGS CC MAYHEM_JOBS

SRC="${SRC:-/mayhem}"
cd "$SRC"

# ── Python toolchain caches at a FIXED, $HOME-independent prefix (SPEC §6.2 item 8) ──
PY_PREFIX=/opt/toolchains/python
WHEELHOUSE="$PY_PREFIX/wheelhouse"
SITE="$PY_PREFIX/site"
mkdir -p "$WHEELHOUSE" "$SITE"

PY="$(command -v python3)"

# 1) Wheelhouse: download every runtime/test dependency ONCE (online). On the air-gapped re-run the
#    directory is already populated, so pip never reaches the network. atheris and lxml ship prebuilt
#    manylinux wheels for this CPython, so no compilation is needed. pytest is the suite runner;
#    lxml enables the defusedxml.lxml half of the test suite (skipped without it).
PKGS=(atheris pytest lxml)
need_download=0
"$PY" -c "import os,glob,sys; sys.exit(0 if glob.glob(os.path.join('$WHEELHOUSE','atheris-*.whl')) else 1)" || need_download=1
if [ "$need_download" -eq 1 ]; then
  echo ">> populating wheelhouse (online) at $WHEELHOUSE"
  "$PY" -m pip download --dest "$WHEELHOUSE" "${PKGS[@]}"
else
  echo ">> wheelhouse already populated — reusing $WHEELHOUSE (air-gapped re-run path)"
fi

# 2) Install the deps into the fixed site dir, OFFLINE from the wheelhouse. --no-index +
#    --find-links guarantees no PyPI access (works on the air-gapped re-run). Guarded to be
#    idempotent: once the site dir holds atheris+pytest+lxml we SKIP the reinstall.
if "$PY" -c "import os,glob,sys; sys.exit(0 if (glob.glob(os.path.join('$SITE','atheris*')) and glob.glob(os.path.join('$SITE','pytest*')) and glob.glob(os.path.join('$SITE','lxml*'))) else 1)"; then
  echo ">> deps already installed in $SITE — skipping (idempotent re-run)"
else
  echo ">> installing deps (offline) into $SITE"
  "$PY" -m pip install --no-index --find-links="$WHEELHOUSE" --target "$SITE" "${PKGS[@]}"
fi
# defusedxml itself: keep it as the editable source tree (FLAT layout => repo root on PYTHONPATH).
PYRUN="$SITE:$SRC"

# Record the site dir + interpreter for test.sh to consume.
cat > "$PY_PREFIX/env.sh" <<EOF
export PYTHONPATH="$PYRUN\${PYTHONPATH:+:\$PYTHONPATH}"
export PYTHON_BIN="$PY"
EOF

# Sanity: the harness imports must resolve offline now.
PYTHONPATH="$PYRUN" "$PY" -c 'import atheris, pytest, lxml; import defusedxml.ElementTree; print("imports OK")'

# 3) Compile the ELF launcher target + the standalone reproducer (DWARF < 4 via $DEBUG_FLAGS).
#    The launcher execs $PY on the harness; PYTHONPATH is baked into the env the binary inherits at
#    run time (the Dockerfile sets ENV PYTHONPATH), so the Python side finds atheris + defusedxml.
# Three targets: the fork's original parse-fuzz harness + the two OSS-Fuzz harnesses (§6.2 item 12).
# The standalone reproducer is the same launcher: libFuzzer runs a single input file once when the
# harness is given a file path (no fuzzing loop) — exactly the run-once reproducer contract.
build_target() {
  local bin="$1" harness="$SRC/mayhem/$2"
  echo ">> compiling $bin (+ standalone) with DEBUG_FLAGS=$DEBUG_FLAGS"
  $CC $DEBUG_FLAGS -DPYTHON="\"$PY\"" -DHARNESS="\"$harness\"" \
      "$SRC/mayhem/launcher.c" -o "$SRC/$bin"
  $CC $DEBUG_FLAGS -DPYTHON="\"$PY\"" -DHARNESS="\"$harness\"" \
      "$SRC/mayhem/launcher.c" -o "$SRC/$bin-standalone"
}
build_target parse-fuzz         fuzz_parse.py
build_target fuzz_etree_parse   fuzz_etree_parse.py
build_target fuzz_parse_string  fuzz_parse_string.py

# 4) The pytest oracle runs through a compiled NON-system ELF wrapper so the gate's anti-reward-hack
#    sabotage check (which neuters non-system binaries to exit(0)) actually bites the suite — a
#    test.sh that shelled straight to the /usr/bin python would be spared and look reward-hackable.
$CC $DEBUG_FLAGS -DPYTHON="\"$PY\"" "$SRC/mayhem/run_tests.c" -o "$SRC/defusedxml_run_tests"

echo ">> build.sh complete"
ls -la "$SRC"/parse-fuzz* "$SRC"/fuzz_etree_parse* "$SRC"/fuzz_parse_string* "$SRC/defusedxml_run_tests"

#!/usr/bin/env bash
#
# Scheme A: use github.com/ROCm/rocm-systems/projects/amdsmi as a Go dependency
# even though that monorepo subdirectory ships no go.mod.
#
# Idea: bring the subdirectory local, give it a go.mod, and wire it into this
# project with a filesystem `replace` (already present in ./go.mod).
#
# Run this ONCE from the project root, then `make run` on a ROCm host.
set -euo pipefail

REPO_URL="https://github.com/ROCm/rocm-systems.git"
REF="develop"                                   # branch that actually gets updates
DEST="third_party/rocm-systems"                 # matches the replace path in go.mod
SUBDIR="projects/amdsmi"

if [[ -d "$DEST/$SUBDIR" ]]; then
  echo "[setup] $DEST/$SUBDIR already exists; pulling latest"
  git -C "$DEST" pull --ff-only
else
  echo "[setup] sparse-cloning only $SUBDIR from the monorepo (no blobs upfront)"
  git clone --filter=blob:none --sparse --branch "$REF" "$REPO_URL" "$DEST"
  git -C "$DEST" sparse-checkout set "$SUBDIR"
fi

# The crucial step: the upstream subdir has NO go.mod. Create one whose module
# path is EXACTLY the import path we use, so the filesystem replace resolves.
if [[ ! -f "$DEST/$SUBDIR/go.mod" ]]; then
  echo "[setup] initializing go.mod inside the local checkout"
  ( cd "$DEST/$SUBDIR" && go mod init github.com/ROCm/rocm-systems/projects/amdsmi )
else
  echo "[setup] go.mod already present in checkout, leaving it"
fi

echo "[setup] tidying the demo module"
go mod tidy

cat <<'EOF'

[setup] done.

Prerequisites to actually build/run (cgo -> libgoamdsmi_shim64):
  export CGO_ENABLED=1
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/rocm/lib:/opt/rocm/lib64
  ls /opt/rocm/include/amdsmi_go_shim.h        # header the cgo #include needs
  ls /opt/rocm/lib*/libgoamdsmi_shim64.so      # lib the cgo LDFLAGS links

If libgoamdsmi_shim64.so is missing, build the shim from
  third_party/rocm-systems/projects/amdsmi/goamdsmi_shim/ (CMake) and install it.

Then:
  make run
EOF

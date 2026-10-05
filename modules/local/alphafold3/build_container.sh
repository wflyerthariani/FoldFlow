#!/usr/bin/env bash
# Build the AlphaFold 3 Singularity image without root.
#
# DeepMind publishes no prebuilt AF3 image, and their docker/Dockerfile needs root (apt-get).
# Fakeroot builds are not enabled for users on Ibex, so this reproduces that Dockerfile
# unprivileged: pull a base image that already ships the Dockerfile's apt packages
# (python3.12 + headers, gcc/g++, make, git, wget, zlib, patch) as a writable sandbox,
# run the remaining Dockerfile steps inside it, then pack the sandbox into a SIF.
# CUDA comes from the jax[cuda12] wheels, so no CUDA base image is needed.
#
# Needs Singularity and internet access (Ibex: the GPU login node, after `module load singularity`):
#   bash modules/local/alphafold3/build_container.sh [OUTPUT_SIF]
# Point _container in configs/AlphaFold3.yaml at the resulting SIF.
set -euo pipefail

AF3_VERSION="${AF3_VERSION:-v3.0.4}"
BASE_IMAGE="docker://python:3.12-bookworm"
UV_VERSION="0.9.24"
HMMER_SHA256="ca70d94fd0cf271bd7063423aabb116d42de533117343a9b27a65c17ff06fbf3"
OUT_SIF="${1:-/ibex/user/$(id -un)/containers/alphafold3_${AF3_VERSION}.sif}"
BUILD_DIR="${BUILD_DIR:-$(dirname "$OUT_SIF")/alphafold3_build}"
JOBS="${JOBS:-8}"

SANDBOX="$BUILD_DIR/sandbox"
mkdir -p "$BUILD_DIR/cache" "$BUILD_DIR/tmp" "$BUILD_DIR/uv-cache"
export SINGULARITY_CACHEDIR="$BUILD_DIR/cache"
export SINGULARITY_TMPDIR="$BUILD_DIR/tmp"

echo "[1/4] Pulling ${BASE_IMAGE} into a writable sandbox"
if [ -d "$SANDBOX" ]; then
    chmod -R u+w "$SANDBOX" && rm -rf "$SANDBOX"
fi
singularity build --sandbox "$SANDBOX" "$BASE_IMAGE"

echo "[2/4] Fetching AlphaFold 3 ${AF3_VERSION}"
git clone --quiet --depth 1 --branch "$AF3_VERSION" \
    https://github.com/google-deepmind/alphafold3.git "$SANDBOX/app/alphafold"
# A writable sandbox cannot create bind destinations, so make them up front: the build binds,
# plus the Ibex filesystems so they also bind cleanly into the final image.
mkdir -p "$SANDBOX"/{uv-cache,buildtmp} \
    "$SANDBOX"/ibex/{user,reference,project,scratch,sw} "$SANDBOX"/ibex/ai/{reference,project}

# Runtime environment, mirroring the ENV lines of the upstream Dockerfile.
cat > "$SANDBOX/.singularity.d/env/90-alphafold3.sh" <<'EOF'
export PATH="/hmmer/bin:/alphafold3_venv/bin:$PATH"
export XLA_FLAGS="${XLA_FLAGS:---xla_gpu_enable_triton_gemm=false}"
export XLA_PYTHON_CLIENT_PREALLOCATE="${XLA_PYTHON_CLIENT_PREALLOCATE:-true}"
export XLA_CLIENT_MEM_FRACTION="${XLA_CLIENT_MEM_FRACTION:-0.95}"
EOF

cat > "$SANDBOX/opt/build_alphafold3.sh" <<EOF
set -euo pipefail
export PATH=/hmmer/bin:/alphafold3_venv/bin:/usr/local/bin:/usr/bin:/bin
export TMPDIR=/buildtmp CMAKE_BUILD_PARALLEL_LEVEL=${JOBS}
export UV_CACHE_DIR=/uv-cache UV_LINK_MODE=copy UV_COMPILE_BYTECODE=1
export UV_PROJECT_ENVIRONMENT=/alphafold3_venv
export UV_PYTHON=/usr/local/bin/python3.12 UV_PYTHON_DOWNLOADS=never

python3.12 -m pip install --quiet --no-cache-dir "uv==${UV_VERSION}"
uv venv /alphafold3_venv

# HMMER 3.4 with the jackhmmer --seq_limit patch, as in the upstream Dockerfile.
mkdir -p /hmmer_build /hmmer
cd /hmmer_build
wget --quiet http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz
echo "${HMMER_SHA256}  hmmer-3.4.tar.gz" | sha256sum --check
tar zxf hmmer-3.4.tar.gz && rm hmmer-3.4.tar.gz
patch -p0 < /app/alphafold/docker/jackhmmer_seq_limit.patch
cd hmmer-3.4
./configure --quiet --prefix /hmmer
make -j${JOBS} && make install && (cd easel && make install)
cd / && rm -rf /hmmer_build

cd /app/alphafold
uv sync --frozen --all-groups --no-editable
/alphafold3_venv/bin/build_data

# gemmi converts AF3's mmCIF output to PDB, matching the AlphaFold 2 module's outputs.
uv pip install --quiet --python /alphafold3_venv/bin/python gemmi
EOF

echo "[3/4] Installing HMMER and AlphaFold 3 inside the sandbox"
singularity exec --writable --no-home --cleanenv \
    --bind "$BUILD_DIR/uv-cache:/uv-cache" --bind "$BUILD_DIR/tmp:/buildtmp" \
    "$SANDBOX" bash /opt/build_alphafold3.sh

echo "[4/4] Packing ${OUT_SIF}"
singularity build -F "$OUT_SIF" "$SANDBOX"

singularity exec "$OUT_SIF" python -c "import alphafold3, gemmi, jax"
singularity exec "$OUT_SIF" jackhmmer -h >/dev/null
echo "Smoke test passed"

chmod -R u+w "$SANDBOX" && rm -rf "$SANDBOX" "$BUILD_DIR/uv-cache" "$BUILD_DIR/tmp"
echo "Done: ${OUT_SIF}"

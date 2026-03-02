#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 --input-dir <video_dir> [--output-root <dir>] [--overwrite] [--dry-run]"
    echo
    echo "Finds all .mp4 files in --input-dir, creates a temporary SLURM array job,"
    echo "and runs run_slurm.sh once per video."
}

INPUT_DIR=""
OUTPUT_ROOT="output"
OVERWRITE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input-dir)
            INPUT_DIR="$2"
            shift 2
            ;;
        --output-root)
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --overwrite)
            OVERWRITE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "${INPUT_DIR}" ]]; then
    echo "Error: --input-dir is required." >&2
    usage
    exit 1
fi

if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Error: input directory does not exist: ${INPUT_DIR}" >&2
    exit 1
fi

mkdir -p "${OUTPUT_ROOT}" slurm_logs

STAMP="$(date +%Y%m%d_%H%M%S)"
FILE_LIST="slurm_logs/video_list_${STAMP}.txt"
JOB_SCRIPT="slurm_logs/video_array_job_${STAMP}.sh"

find "${INPUT_DIR}" -type f \( -iname "*.mp4" \) -print0 | sort -z > "${FILE_LIST}"

NUM_FILES="$(python - <<'PY' "${FILE_LIST}"
import sys
path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()
print(0 if not data else data.count(b"\0"))
PY
)"

if [[ "${NUM_FILES}" -eq 0 ]]; then
    echo "No .mp4 files found in ${INPUT_DIR}"
    exit 0
fi

cat > "${JOB_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
#SBATCH --partition=submit
#SBATCH --job-name=diffusion_light_batch
#SBATCH --nodes=1
#SBATCH --time=1-00:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-task=1
#SBATCH --constraint="rtx_a6000|a100"
#SBATCH --output=slurm_logs/%x_%A_%a.log

set -euo pipefail

mapfile -d '' FILES < "${FILE_LIST}"
VIDEO_PATH="${FILES[${SLURM_ARRAY_TASK_ID}]}"
VIDEO_BASENAME="$(basename "${VIDEO_PATH}")"
VIDEO_STEM="${VIDEO_BASENAME%.*}"
RUN_OUTPUT_DIR="${OUTPUT_ROOT}/${VIDEO_STEM}"
EXPECTED_EXR="${RUN_OUTPUT_DIR}/hdr/${VIDEO_STEM}.exr"

if [[ "${OVERWRITE}" != "1" && -f "${EXPECTED_EXR}" ]]; then
    echo "[$SLURM_ARRAY_TASK_ID] Skipping ${VIDEO_PATH}; found ${EXPECTED_EXR}"
    exit 0
fi

mkdir -p "${RUN_OUTPUT_DIR}"
echo "[$SLURM_ARRAY_TASK_ID] Processing ${VIDEO_PATH} -> ${RUN_OUTPUT_DIR}"
bash "./run_slurm.sh" "${VIDEO_PATH}" "${RUN_OUTPUT_DIR}" "${OVERWRITE}"
EOF

chmod +x "${JOB_SCRIPT}"

echo "Video list: ${FILE_LIST}"
echo "Array script: ${JOB_SCRIPT}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Dry run enabled: array job was not submitted."
    exit 0
fi

sbatch_output="$(sbatch \
    --array=0-$((NUM_FILES - 1))%16 \
    --export=ALL,FILE_LIST="${FILE_LIST}",OUTPUT_ROOT="${OUTPUT_ROOT}",OVERWRITE="${OVERWRITE}" \
    "${JOB_SCRIPT}")"

echo "${sbatch_output}"

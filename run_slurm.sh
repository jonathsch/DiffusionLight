#!/bin/bash
#SBATCH --partition=submit
#SBATCH --job-name=diffusion_light
#SBATCH --nodes=1
#SBATCH --time=1-00:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-task=1
#SBATCH --constraint="rtx_a6000|a100"
#SBATCH --output=slurm_logs/%x_%j.log

set -euo pipefail

INPUT_SOURCE="${1:-example}"
OUTPUT_DIR="${2:-output}"
OVERWRITE="${3:-0}"

INPUT_STEM="$(basename "${INPUT_SOURCE}")"
INPUT_STEM="${INPUT_STEM%.*}"
EXPECTED_EXR="${OUTPUT_DIR}/hdr/${INPUT_STEM}.exr"

if [[ "${OVERWRITE}" != "1" && -f "${EXPECTED_EXR}" ]]; then
    echo "Skipping ${INPUT_SOURCE}: ${EXPECTED_EXR} already exists."
    exit 0
fi

source /rhome/jschmidt/.bashrc
# Load conda for non-interactive shell (bashrc often skips it under sbatch)
if [[ -f "${HOME}/miniconda3/etc/profile.d/conda.sh" ]]; then
    source "${HOME}/miniconda3/etc/profile.d/conda.sh"
elif [[ -f "${HOME}/miniforge3/etc/profile.d/conda.sh" ]]; then
    source "${HOME}/miniforge3/etc/profile.d/conda.sh"
elif [[ -n "${CONDA_ROOT:-}" && -f "${CONDA_ROOT}/etc/profile.d/conda.sh" ]]; then
    source "${CONDA_ROOT}/etc/profile.d/conda.sh"
fi
conda activate diffusionlight

nvidia-smi

python inpaint.py --dataset "${INPUT_SOURCE}" --output_dir "${OUTPUT_DIR}"

python ball2envmap.py --ball_dir "${OUTPUT_DIR}/square" --envmap_dir "${OUTPUT_DIR}/envmap"

python exposure2hdr.py --input_dir "${OUTPUT_DIR}/envmap" --output_dir "${OUTPUT_DIR}/hdr"
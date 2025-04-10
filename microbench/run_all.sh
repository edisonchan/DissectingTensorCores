#!/bin/sh

# Function to get GPU model and replace spaces with underscores
get_gpu_model_with_underscore() {
    device_query_output=$($CUDAToolkit_ROOT/extras/demo_suite/deviceQuery 2>/dev/null)
    gpu_model=$(echo "$device_query_output" | awk -F': ' '/Device 0:/ {print $2}' | sed 's/ /_/g' | tr -d '"')
    if [ -z "$gpu_model" ]; then
        echo "Failed to parse GPU model from deviceQuery. Please confirm that the CUDA environment is correctly configured."
        exit 1
    fi
    echo "$gpu_model"
}

# Use deviceQuery to dynamically obtain GPU SM version
get_gpu_sm_version() {
    device_query_output=$($CUDAToolkit_ROOT/extras/demo_suite/deviceQuery 2>/dev/null)
    sm_version=$(echo "$device_query_output" | awk '/CUDA Capability Major\/Minor version number:/ {print $6}' | sed 's/\.//g')
    if [ -z "$sm_version" ]; then
        echo "Failed to parse SM version from deviceQuery. Please confirm that the CUDA environment is correctly configured."
        exit 1
    fi
    echo "$sm_version"
}

# Use deviceQuery to dynamically obtain GPU nominal frequency
get_gpu_nominal_frequency() {
    device_query_output=$($CUDAToolkit_ROOT/extras/demo_suite/deviceQuery 2>/dev/null)
    nominal_freq=$(echo "$device_query_output" | awk '/GPU Max Clock rate:/ {print $5}' | sed 's/[^0-9]//g')
    if [ -z "$nominal_freq" ]; then
        echo "Failed to parse GPU nominal frequency from deviceQuery. Please confirm that the CUDA environment is correctly configured."
        exit 1
    fi
    echo "$nominal_freq"
}

# Obtain GPU model, SM version, and nominal frequency
gpu_model=$(get_gpu_model_with_underscore)
sm_version=$(get_gpu_sm_version)
nominal_freq=$(get_gpu_nominal_frequency)

# Export TargetSM
export TargetSM="$sm_version"

# Display collected information
echo "Collected GPU Information:"
echo "  GPU Model: $gpu_model"
echo "  SM Version: $sm_version"
echo "  Nominal Frequency: $nominal_freq MHz"

# Pause and confirm whether the information is correct
echo "Do you confirm that the information is correct? (yes/no)"
read user_confirmation
if [ "$user_confirmation" != "yes" ]; then
    echo "Operation aborted by user."
    exit 0
fi

# Additional step: Ask whether to lock the GPU frequency
echo "Do you want to lock the GPU frequency to $nominal_freq MHz? (yes/no)"
read lock_frequency_confirmation

if [ "$lock_frequency_confirmation" = "yes" ]; then
    # Enable persistent mode and lock GPU frequency
    echo "Enabling persistent mode and locking GPU frequency."
    set_gpu_frequency() {
        freq=$1
        sudo nvidia-smi -pm 1 # Enable persistent mode
        # Optionally set power limit if necessary (commented out, user can enable if needed)
        # sudo nvidia-smi -pl [power_limit_value]
        sudo nvidia-smi -lgc "$freq" "$freq" # Lock GPU frequency
    }
    set_gpu_frequency "$nominal_freq"

    # Function to unlock GPU frequency
    reset_gpu_frequency() {
        sudo nvidia-smi -rgc # Unlock GPU frequency
    }
else
    echo "Skipping GPU frequency lock as per user request."
fi

max=8
THIS_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

i=1
while [ "$i" -le "$max" ]; do
    cd "$SCRIPT_DIR" || exit 1
    make clean
    ILPconfig=$i
    echo "ILP = $ILPconfig"
    make -k ILP="$ILPconfig"
    cd "${SCRIPT_DIR}/bin" || exit 1
    for f in ./*; do
        log_file="${SCRIPT_DIR}/${gpu_model}-ILP${ILPconfig}.log"
        echo "Running $f microbenchmark"
        "$f" >> "$log_file"
        echo "/////////////////////////////////"
    done
    i=$((i + 1))
done

# If the GPU frequency was locked, unlock it
if [ "$lock_frequency_confirmation" = "yes" ]; then
    echo "Unlocking GPU frequency"
    reset_gpu_frequency
fi

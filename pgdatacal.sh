#!/bin/bash

# Check if nethogs is installed
if ! command -v nethogs &> /dev/null; then
    echo "nethogs is not installed. Please install it first."
    exit 1
fi

# Check if the script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

# Check if a program name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <program_name>"
    exit 1
fi

PROGRAM_NAME="$1"
LOG_FILE="network_usage_${PROGRAM_NAME}.log"
TEMP_FILE=$(mktemp)

# Function to convert bytes to human-readable format
human_readable() {
    local bytes=$1
    if ((bytes < 1024)); then
        echo "${bytes}B"
    elif ((bytes < 1048576)); then
        echo "$(( (bytes + 512) / 1024 ))KB"
    else
        echo "$(( (bytes + 524288) / 1048576 ))MB"
    fi
}

# Initialize totals file
echo "0 0" > "$TEMP_FILE"

# Function to handle Ctrl+C and script exit
cleanup() {
    echo "Calculating totals..."
    
    # Read final totals from temp file
    read total_sent total_recv < "$TEMP_FILE"
    
    # Calculate elapsed time
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    hours=$((elapsed / 3600))
    minutes=$(( (elapsed % 3600) / 60 ))
    seconds=$((elapsed % 60))

    # Convert to human-readable format
    sent_hr=$(human_readable $total_sent)
    recv_hr=$(human_readable $total_recv)

    # Calculate totals in KB and MB
    total_sent_kb=$(echo "scale=2; $total_sent / 1024" | bc)
    total_recv_kb=$(echo "scale=2; $total_recv / 1024" | bc)
    total_sent_mb=$(echo "scale=2; $total_sent / 1048576" | bc)
    total_recv_mb=$(echo "scale=2; $total_recv / 1048576" | bc)

    # Log the results
    {
        echo "Summary for $PROGRAM_NAME:"
        echo "Duration: $(printf "%02d:%02d:%02d" $hours $minutes $seconds)"
        echo "Total sent: ${sent_hr} (${total_sent_kb} KB / ${total_sent_mb} MB)"
        echo "Total received: ${recv_hr} (${total_recv_kb} KB / ${total_recv_mb} MB)"
    } | tee -a $LOG_FILE

    echo "Results logged to $LOG_FILE"
    
    # Clean up temp file
    rm -f "$TEMP_FILE"
    exit 0
}

# Set up trap for script exit
trap cleanup EXIT

# Start time
start_time=$(date +%s)

echo "Tracking network usage for $PROGRAM_NAME. Press Ctrl+C to stop."

# Run nethogs and process its output
sudo nethogs -t | while read -r line
do
    if [[ $line == *"$PROGRAM_NAME"* ]]; then
        sent=$(echo $line | awk '{printf "%.0f", $2 * 1024}')  # Convert KB to bytes
        recv=$(echo $line | awk '{printf "%.0f", $3 * 1024}')  # Convert KB to bytes
        
        # Read current totals, update them, and write back to temp file
        read curr_sent curr_recv < "$TEMP_FILE"
        curr_sent=$((curr_sent + sent))
        curr_recv=$((curr_recv + recv))
        echo "$curr_sent $curr_recv" > "$TEMP_FILE"
        
        sent_hr=$(human_readable $sent)
        recv_hr=$(human_readable $recv)
        echo "Data for $PROGRAM_NAME - Sent: $sent_hr, Received: $recv_hr"
    fi
done

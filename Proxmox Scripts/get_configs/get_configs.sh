#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is not installed. Please install jq to run this script."
  exit 1
fi

# Function to display usage information
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -nodes <node1-node5>       Specify a range or list of nodes."
  echo "  -vmids <id1-id5>           Specify a range or list of VM IDs."
  echo "  -node <nodename>            Specify a single node."
  echo "  -vmid <vmid>                Specify a single VM ID."
  echo "  -key <key1,key2,...>       Specify one or more keys to filter output."
  echo "  -log                        Enable logging."
  echo "  -v                          Enable verbose logging."
  echo "  -help                       Display this help message."
  exit 1
}

# Function to generate a sequence from a node or VM range
generate_range() {
  local start=$1
  local end=$2
  local prefix=$(echo "$start" | sed 's/[0-9]*//g')
  local start_num=$(echo "$start" | sed 's/[^0-9]*//g')
  local end_num=$(echo "$end" | sed 's/[^0-9]*//g')

  seq -f "${prefix}%g" "$start_num" "$end_num"
}

# Function to run the pvesh command and check output
run_pvesh_command() {
  local nodename="$1"
  local vmnumber="$2"
  local keys="$3"

  # Prepare the command
  local command="pvesh get /nodes/$nodename/qemu/$vmnumber/config"
  
  # Add output format if keys are provided
  if [[ -n "$keys" ]]; then
    command+=" --output-format json-pretty"
  fi

  # Log the command if logging is enabled
  if [[ "$log_enabled" == true ]]; then
    echo "Executing command: $command" | tee -a "$log_file"
  fi

  # Run the pvesh command and capture the output
  output=$($command 2>&1)

  # Log the output if logging is enabled
  if [[ "$log_enabled" == true ]]; then
    echo "Output: $output" | tee -a "$log_file"
  fi

  # Check if the command executed successfully
  if [[ $? -ne 0 ]]; then
    echo "Error: Command failed to execute. Output was: $output" | tee -a "$log_file"
    return 1
  fi

  # Check if output is valid JSON (only if keys are provided)
  if [[ -n "$keys" ]]; then
    if echo "$output" | grep -q "proxy handler failed: Configuration file"; then
      # Suppress this specific error
      return 0
    fi

    echo "$output" | jq empty 2>/dev/null
    if [[ $? -ne 0 ]]; then
      # Suppress the specific "does not exist" error messages
      if ! echo "$output" | grep -q -E "Configuration file 'nodes/[^']+/qemu-server/[0-9]+\.conf' does not exist"; then
        echo "Error: Invalid JSON output. The output was: $output" | tee -a "$log_file"
      fi
      return 1
    fi
  fi

  # Check if the output contains the "does not exist" message
  if echo "$output" | grep -q "Configuration file 'nodes/$nodename/qemu-server/$vmnumber.conf' does not exist"; then
    return 0 # Suppress output if file does not exist
  fi

  # If keys are provided, parse JSON to CSV format
  if [[ -n "$keys" ]]; then
    # Output the VM ID followed by key values
    IFS=',' read -r -a key_array <<< "$keys"
    value_line="$vmnumber"
    for key in "${key_array[@]}"; do
      value=$(echo "$output" | jq -r ".[\"$key\"] // empty")
      value_line+=",$value"
    done
    echo "$value_line"
  else
    # Output the entire JSON directly (no parsing)
    echo "$output" # Output raw JSON as ASCII
  fi
}

# Parse command line arguments
nodenames=()
vmnumbers=()
single_node=""
single_vmid=""
keys=""
header_printed=false
log_enabled=false
verbose=false
log_file="logs/log.txt"  # Log file name in the logs directory

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -nodes)
      shift
      if [[ "$1" == *-* && "$1" != *,* ]]; then
        # Handle ranges like node1-node5
        IFS='-' read -r start_node end_node <<< "$1"
        nodenames=($(generate_range "$start_node" "$end_node"))
      elif [[ "$1" == *,* ]]; then
        # Handle comma-separated node names
        IFS=',' read -r -a nodenames <<< "$1"
      else
        nodenames+=("$1")
      fi
      ;;
    -vmids)
      shift
      if [[ "$1" == *-* ]]; then
        IFS='-' read -r start_vm end_vm <<< "$1"
        vmnumbers=($(seq "$start_vm" "$end_vm"))
      elif [[ "$1" == *,* ]]; then
        IFS=',' read -r -a vmnumbers <<< "$1"
      else
        vmnumbers+=("$1")
      fi
      ;;
    -node)
      shift
      single_node="$1"
      ;;
    -vmid)
      shift
      single_vmid="$1"
      ;;
    -key)
      shift
      keys="$1"
      ;;
    -log)
      log_enabled=true
      ;;
    -v)
      verbose=true
      ;;
    -help)
      usage
      ;;
    *)
      usage
      ;;
  esac
  shift
done

# Create logs directory if logging is enabled
if [[ "$log_enabled" == true ]]; then
  mkdir -p logs
  log_file="logs/log.txt"  # Update log file path
  echo "Logging started at $(date)" > "$log_file"
fi

# Function to print the CSV header
print_header() {
  if [[ "$header_printed" == false && -n "$keys" ]]; then
    IFS=',' read -r -a key_array <<< "$keys"
    # Properly format the header with commas
    echo "vmid,${key_array[*]}" | sed 's/ /,/g'  # Replace spaces with commas
    header_printed=true
  fi
}

# Validate input combinations and call the appropriate function
if [[ -n "$single_node" && -n "$single_vmid" ]]; then
  print_header
  run_pvesh_command "$single_node" "$single_vmid" "$keys"

elif [[ -n "$single_node" && -n "${vmnumbers[*]}" ]]; then
  # Single node with multiple VM IDs
  print_header
  for vmnumber in "${vmnumbers[@]}"; do
    run_pvesh_command "$single_node" "$vmnumber" "$keys"
  done

elif [[ -n "${nodenames[*]}" && -n "$single_vmid" ]]; then
  # Multiple nodes with a single VM ID
  print_header
  for nodename in "${nodenames[@]}"; do
    run_pvesh_command "$nodename" "$single_vmid" "$keys"
  done

elif [[ -n "${nodenames[*]}" && -n "${vmnumbers[*]}" ]]; then
  # Multiple nodes with multiple VM IDs
  print_header
  for nodename in "${nodenames[@]}"; do
    for vmnumber in "${vmnumbers[@]}"; do
      run_pvesh_command "$nodename" "$vmnumber" "$keys"
    done
  done

else
  echo "Error: At least one node or VM ID must be provided."
  usage
fi

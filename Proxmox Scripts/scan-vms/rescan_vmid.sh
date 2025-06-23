#!/bin/bash

# Get the script name without the extension
script_name=$(basename "$0" .sh)

# Function to display usage
usage() {
  echo "Usage: ./$script_name -startvmid <starting_vmid> [-endvmid <ending_vmid>] [-vmids <vmid_list>] [-log] [--additional-args] | [-h | --help]"
  echo "       -startvmid <starting_vmid>   Required. Starting VMID."
  echo "       -endvmid <ending_vmid>       Optional. Ending VMID (press enter to skip)."
  echo "       -vmids <vmid_list>           Optional. Comma-separated list of VMIDs to run."
  echo "       -log                          Optional. Enable logging to a file."
  echo "       --additional-args             Optional arguments to pass to the qm rescan command."
  echo "       -h, --help                    Display this help message."
  exit 1
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

# Initialize variables
start_vmid=""
end_vmid=""
vmid_list=()
log_enabled=false
additional_args=""

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -startvmid)
      start_vmid="$2"
      shift 2
      ;;
    -endvmid)
      end_vmid="$2"
      shift 2
      ;;
    -vmids)
      IFS=',' read -r -a vmid_list <<< "$2"
      shift 2
      ;;
    -log)
      log_enabled=true
      shift
      ;;
    --additional-args)
      shift
      additional_args="$@"
      break
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Check if starting VMID is provided
if [[ -z "$start_vmid" ]]; then
  echo "Error: -startvmid argument is required."
  usage
fi

# Check if the starting VMID is a valid number
if ! [[ "$start_vmid" =~ ^[0-9]+$ ]]; then
  echo "Invalid input. Please enter a valid starting VMID."
  usage
fi

# Check if the ending VMID is a valid number if provided
if [[ -n "$end_vmid" ]] && ! [[ "$end_vmid" =~ ^[0-9]+$ ]]; then
  echo "Invalid input. Please enter a valid ending VMID."
  usage
fi

# Check if the starting VMID is less than or equal to the ending VMID if provided
if [[ -n "$end_vmid" ]] && [ "$start_vmid" -gt "$end_vmid" ]; then
  echo "Starting VMID must be less than or equal to ending VMID."
  usage
fi

# Create a log file if logging is enabled
if $log_enabled; then
  # Define the subfolder for logs and create it if it doesn't exist
  log_folder="logs"
  mkdir -p "$log_folder"

  current_time=$(date +"%Y%m%d_%H%M%S")
  log_file="${log_folder}/${script_name}_${current_time}.log"
  exec > >(tee -a "$log_file") 2>&1
  echo "Logging output to: $log_file"
else
  # Redirect output to terminal only
  exec > /dev/stdout 2>&1
fi

# Function to run the command and check for the specific error
run_command() {
  local vmid="$1"
  local output
  output=$(qm rescan --vmid "$vmid" $additional_args 2>&1)

  # Check for the specific error message
  if [[ "$output" == *"Configuration file 'nodes/"* ]]; then
    echo "VM with ID $vmid is not on this node. Please check which node it's on and run the script there."
  else
    echo "$output"
  fi
}

# If vmid_list is provided, iterate over it
if [[ ${#vmid_list[@]} -gt 0 ]]; then
  for vmid in "${vmid_list[@]}"; do
    echo "Running command: qm rescan --vmid $vmid $additional_args"
    run_command "$vmid"
  done
else
  # If ending VMID is not provided, run the command once with the starting VMID
  if [[ -z "$end_vmid" ]]; then
    echo "Running command: qm rescan --vmid $start_vmid $additional_args"
    run_command "$start_vmid"
  else
    # Loop through the range and run the command
    for (( vmid=start_vmid; vmid<=end_vmid; vmid++ )); do
      echo "Running command: qm rescan --vmid $vmid $additional_args"
      run_command "$vmid"
    done
  fi
fi

echo "All commands executed."

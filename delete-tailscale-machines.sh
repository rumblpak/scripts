#!/bin/bash

# Script to delete all Tailscale machines with a given tag
# Requires: curl, jq, sed, awk, mktemp, date, and a Tailscale API key

set -euo pipefail

# Configuration
TAILSCALE_API_BASE="https://api.tailscale.com"
API_KEY=""
TAILNET=""
TAG_TO_DELETE=""
AUTO_CONFIRM=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Function to validate JSON
is_valid_json() {
    jq -e '.' >/dev/null 2>&1 <<< "$1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -k <api-key> -n <tailnet> -t <tag-to-delete> [options]"
    echo ""
    echo "Required options:"
    echo "  -k <api-key>        Your Tailscale API key (tskey-api-...)"
    echo "  -n <tailnet>        Your tailnet (e.g., example.com or example.ts.net)"
    echo "  -t <tag-to-delete>  Tag to filter devices for deletion"
    echo ""
    echo "Optional:"
    echo "  -h                  Show this help message"
    echo "  -y                  Auto-confirm deletion without prompting"
    echo ""
    echo "Examples:"
    echo "  $0 -k \"tskey-api-...\" -n \"example.com\" -t \"tag:ephemeral\""
    echo "  $0 -k \"tskey-api-...\" -n \"example.com\" -t \"ephemeral\"  # 'tag:' prefix will be added automatically"
    echo ""
    echo "Note: If the tag doesn't start with 'tag:', the prefix will be added automatically"
    echo ""
    echo "Environment variable fallback:"
    echo "  If -k or -n are not provided, the script will try to use:"
    echo "  TAILSCALE_API_KEY and TAILSCALE_TAILNET environment variables"
}

# Function to validate dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v sed &> /dev/null; then
        missing_deps+=("sed")
    fi
    
    if ! command -v awk &> /dev/null; then
        missing_deps+=("awk")
    fi
    
    if ! command -v mktemp &> /dev/null; then
        missing_deps+=("mktemp")
    fi
    
    if ! command -v date &> /dev/null; then
        missing_deps+=("date")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install missing dependencies and try again"
        exit 1
    fi
}

# Function to parse command line options
parse_options() {
    local OPTIND
    
    while getopts ":k:n:t:hy" opt; do
        case "${opt}" in
            k)
                API_KEY="${OPTARG}"
                ;;
            n)
                TAILNET="${OPTARG}"
                ;;
            t)
                TAG_TO_DELETE="${OPTARG}"
                ;;
            y)
                AUTO_CONFIRM=true
                ;;
            h)
                show_usage
                exit 0
                ;;
            \?)
                print_error "Invalid option: -${OPTARG}"
                show_usage
                exit 1
                ;;
            :)
                print_error "Option -${OPTARG} requires an argument"
                show_usage
                exit 1
                ;;
        esac
    done
    
    shift $((OPTIND-1))
}

# Function to validate inputs
validate_inputs() {
    # If arguments are empty, try to fall back to environment variables
    if [ -z "$API_KEY" ]; then
        API_KEY="${TAILSCALE_API_KEY:-}"
    fi
    
    if [ -z "$TAILNET" ]; then
        TAILNET="${TAILSCALE_TAILNET:-}"
    fi
    
    if [ -z "$TAG_TO_DELETE" ]; then
        print_error "Tag to delete not specified"
        show_usage
        exit 1
    fi
    
    if [ -z "$API_KEY" ]; then
        print_error "API key not provided as argument or TAILSCALE_API_KEY environment variable"
        show_usage
        exit 1
    fi
    
    if [ -z "$TAILNET" ]; then
        print_error "Tailnet not provided as argument or TAILSCALE_TAILNET environment variable"
        show_usage
        exit 1
    fi
    
    # Validate tag format
    if [[ ! "$TAG_TO_DELETE" =~ ^tag: ]]; then
        print_warning "Tag doesn't start with 'tag:' prefix. Adding it automatically."
        TAG_TO_DELETE="tag:$TAG_TO_DELETE"
    fi
}

# Function to make API calls with error handling
make_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local response
    
    # Make the API call
    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" \
                       -H "Authorization: Bearer $API_KEY" \
                       -H "Content-Type: application/json" \
                       -d "$data" \
                       -w "\n%{http_code}" \
                       "$TAILSCALE_API_BASE$endpoint" 2>/dev/null) || return 1
    else
        response=$(curl -s -X "$method" \
                       -H "Authorization: Bearer $API_KEY" \
                       -H "Content-Type: application/json" \
                       -w "\n%{http_code}" \
                       "$TAILSCALE_API_BASE$endpoint" 2>/dev/null) || return 1
    fi
    
    # Extract status code and response body
    local status_code
    local response_body
    
    # Get the last line (status code) and everything before it (response body)
    status_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')
    
    # Check response status
    if [[ ! "$status_code" =~ ^[0-9]+$ ]]; then
        print_error "Invalid status code received: $status_code"
        return 1
    fi
    
    # Handle DELETE operations specially
    if [ "$method" = "DELETE" ] && { [ "$status_code" = "200" ] || [ "$response_body" = "null" ]; }; then
        return 0
    fi
    
    # For other methods, check for empty response
    if [ -z "$response_body" ]; then
        print_error "Empty response received from API"
        return 1
    fi
    
    if [ "$status_code" != "200" ]; then
        print_error "API request failed with status code: $status_code"
        echo "Response: $response_body" >&2
        return 1
    fi
    
    # For non-empty responses, verify JSON
    if [ -n "$response_body" ]; then
        if ! is_valid_json "$response_body"; then
            print_error "Invalid JSON response received"
            echo "Raw response: $response_body" >&2
            return 1
        fi
        echo "$response_body"
    fi
    return 0
}

# Function to get all devices
get_devices() {
    print_info "Fetching all devices from tailnet: $TAILNET" >&2
    make_api_call "GET" "/api/v2/tailnet/$TAILNET/devices"
}

    # Filter devices by tag
filter_devices_by_tag() {
    local devices_json="$1"
    local tag="$2"
    
    # Ensure we're working with valid JSON that contains devices
    if ! jq -e '.devices' >/dev/null 2>&1 <<< "$devices_json"; then
        return 1
    fi
    
    # Filter and format devices
    local filter_result
    filter_result=$(jq -r --arg tag "$tag" '
        .devices | map(
            select(
                (.tags != null) and 
                (.tags | type == "array") and
                (any(.tags[]; . == $tag))
            ) | {
                id,
                name,
                hostname,
                tags
            }
        )' <<< "$devices_json" 2>/dev/null)
    
    if [ "$(jq 'length' <<< "$filter_result")" -gt 0 ]; then
        jq -c '.[]' <<< "$filter_result"
    fi
}

# Function to delete a device (parallel-safe)
delete_device() {
    local device_id="$1"
    local device_name="$2"
    local result_file="$3"
    
    print_info "Deleting device: $device_name (ID: $device_id)" >&2
    
    local start_time=$(date +%s)
    if make_api_call "DELETE" "/api/v2/device/$device_id" > /dev/null 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_success "Successfully deleted device: $device_name" >&2
        printf "%s\t%s\t%s\t%d\n" "success" "$device_id" "$device_name" "$duration" >> "$result_file"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_error "Failed to delete device: $device_name" >&2
        printf "%s\t%s\t%s\t%d\n" "failure" "$device_id" "$device_name" "$duration" >> "$result_file"
        return 1
    fi
}

# Function to confirm deletion
confirm_deletion() {
    local device_count="$1"
    
    echo ""
    print_warning "This will delete $device_count device(s) with tag '$TAG_TO_DELETE'"
    
    if [ "$AUTO_CONFIRM" = true ]; then
        print_info "Auto-confirming deletion (-y flag provided)"
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (y/N): "
    read -r confirmation
    
    case "$confirmation" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            print_info "Operation cancelled"
            exit 0
            ;;
    esac
}

# Main function
main() {
    print_info "Starting Tailscale machine deletion script"
    
    # Parse command line options
    parse_options "$@"
    
    # Validate dependencies and inputs
    check_dependencies
    validate_inputs
    
    print_info "Target tag: $TAG_TO_DELETE"
    print_info "Tailnet: $TAILNET"
    
    # Get devices
    local devices_response
    devices_response=$(get_devices) || {
        print_error "Failed to fetch devices"
        exit 1
    }
    
    # Validate JSON response
    if [ -z "$devices_response" ] || ! is_valid_json "$devices_response"; then
        print_error "Invalid JSON response"
        exit 1
    fi
    
    # Check for devices array
    if ! jq -e '.devices' >/dev/null 2>&1 <<< "$devices_response"; then
        print_error "JSON response missing devices array"
        echo "Response structure:"
        jq -r 'keys[]' >&2 <<< "$devices_response"
        exit 1
    fi

    # Filter devices by tag
    local matching_devices
    matching_devices=$(filter_devices_by_tag "$devices_response" "$TAG_TO_DELETE")
    
    if [ -z "$matching_devices" ] || [ "$matching_devices" = "null" ]; then
        print_info "No devices found with tag '$TAG_TO_DELETE'"
        exit 0
    fi
    
    # Display matching devices
    print_info "Found devices with tag '$TAG_TO_DELETE':"
    jq -r '"  - \(.name) (\(.hostname)) - ID: \(.id)"' <<< "$matching_devices"
    
    local device_count
    device_count=$(jq -s length <<< "$matching_devices")
    
    # Confirm deletion
    confirm_deletion "$device_count"
    
    # Delete devices in parallel
    echo ""
    print_info "Starting parallel deletion process..."
    
    # Create temporary file for results
    local result_file
    result_file=$(mktemp)
    
    # Ensure cleanup on exit or error
    cleanup_temp() {
        if [ -n "$result_file" ] && [ -f "$result_file" ]; then
            rm -f "$result_file"
        fi
    }
    trap cleanup_temp EXIT INT TERM
    
    # Track background processes
    local pids=()
    local max_parallel=10  # Limit concurrent deletions to avoid rate limiting
    local active_jobs=0
    
    local total_start=$(date +%s)
    
    # Process each device in parallel
    while IFS=$'\t' read -r id name; do
        if [ -n "$id" ] && [ -n "$name" ]; then
            # Wait if we've hit the parallel limit
            while [ $active_jobs -ge $max_parallel ]; do
                # Wait for any job to complete
                wait -n 2>/dev/null || true
                active_jobs=$(($(jobs -r | wc -l)))
            done
            
            # Launch deletion in background
            delete_device "$id" "$name" "$result_file" &
            pids+=($!)
            active_jobs=$((active_jobs + 1))
        fi
    done < <(jq -r '[.id, .name] | @tsv' <<< "$matching_devices")
    
    # Wait for all background jobs to complete
    print_info "Waiting for all deletions to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    local total_end=$(date +%s)
    local total_duration=$((total_end - total_start))
    
    # Generate summary report
    echo ""
    print_info "=== Deletion Summary Report ==="
    echo ""
    
    # Parse results
    declare -i success_count=0
    declare -i failure_count=0
    declare -a successful_devices=()
    declare -a failed_devices=()
    local total_api_time=0
    
    while IFS=$'\t' read -r status id name duration; do
        if [ "$status" = "success" ]; then
            success_count+=1
            successful_devices+=("$name")
            total_api_time=$((total_api_time + duration))
        else
            failure_count+=1
            failed_devices+=("$name")
        fi
    done < "$result_file"
    
    # Display summary statistics
    printf "Devices processed:    %d\n" "$device_count"
    printf "Successfully deleted: %d\n" "$success_count"
    printf "Failed to delete:     %d\n" "$failure_count"
    printf "Total runtime:        %ds\n" "$total_duration"
    
    if [ $success_count -gt 0 ]; then
        local avg_time=$((total_api_time / success_count))
        printf "Avg deletion time:    %ds\n" "$avg_time"
        printf "Parallelization gain: %.1fx\n" $(awk "BEGIN {printf \"%.1f\", $total_api_time / ($total_duration > 0 ? $total_duration : 1)}")
    fi
    
    echo ""
    
    # List successful deletions
    if [ $success_count -gt 0 ]; then
        print_success "Successfully deleted devices:"
        printf '%s\n' "${successful_devices[@]}" | sed 's/^/  ✓ /'
        echo ""
    fi
    
    # List failures
    if [ $failure_count -gt 0 ]; then
        print_error "Failed to delete devices:"
        printf '%s\n' "${failed_devices[@]}" | sed 's/^/  ✗ /'
        echo ""
        
        # Cleanup temp file before exit
        cleanup_temp
        trap - EXIT INT TERM
        exit 1
    else
        print_success "All devices with tag '$TAG_TO_DELETE' have been deleted!"
    fi
    
    # Cleanup temp file on successful completion
    cleanup_temp
    trap - EXIT INT TERM
}

# Handle script interruption
trap 'print_warning "Script interrupted by user"; exit 130' INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/bin/bash

# Script to delete all Tailscale machines with a given tag
# Requires: curl, jq, and a Tailscale API key

set -euo pipefail

# Configuration
TAILSCALE_API_BASE="https://api.tailscale.com/api/v2"
API_KEY=""
TAILNET=""
TAG_TO_DELETE=""

# Detect sed version and set up compatible command
if sed --version 2>/dev/null | grep -q GNU; then
    SED_EXTRACT="sed -n '/^{/,\$p'"
else
    SED_EXTRACT="sed -n '1,/^{/!p'"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install missing dependencies and try again"
        exit 1
    fi
}

# Function to parse command line options
parse_options() {
    local OPTIND
    
    while getopts "k:n:t:h" opt; do
        case $opt in
            k)
                API_KEY="$OPTARG"
                ;;
            n)
                TAILNET="$OPTARG"
                ;;
            t)
                TAG_TO_DELETE="$OPTARG"
                ;;
            h)
                show_usage
                exit 0
                ;;
            \?)
                print_error "Invalid option: -$OPTARG"
                show_usage
                exit 1
                ;;
            :)
                print_error "Option -$OPTARG requires an argument"
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
    response_body=$(echo "$response" | head -n -1 | tr -d '\r')
    
    # Check response status
    if [[ ! "$status_code" =~ ^[0-9]+$ ]]; then
        print_error "Invalid status code received: $status_code"
        return 1
    fi
    
    if [ -z "$response_body" ]; then
        if [ "$method" = "DELETE" ] && [ "$status_code" = "200" ]; then
            # Special case: DELETE operations might return empty body with 200
            return 0
        fi
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
        if ! echo "$response_body" | jq -e '.' >/dev/null 2>&1; then
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
    print_info "Fetching all devices from tailnet: $TAILNET"
    make_api_call "GET" "/tailnet/$TAILNET/devices"
}

    # Filter devices by tag
filter_devices_by_tag() {
    local devices_json="$1"
    local tag="$2"
    
    # Store JSON in a temporary file to avoid string parsing issues
    local tmp_file
    tmp_file=$(mktemp)
    echo "$devices_json" > "$tmp_file"
    
    # Ensure we're working with valid JSON that contains devices
    if ! jq -e '.devices' "$tmp_file" > /dev/null 2>&1; then
        rm -f "$tmp_file"
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
        )' "$tmp_file" 2>/dev/null)
    rm -f "$tmp_file"
    
    if [ "$(echo "$filter_result" | jq 'length')" -gt 0 ]; then
        echo "$filter_result" | jq -c '.[]'
    fi
}

# Function to delete a device
delete_device() {
    local device_id="$1"
    local device_name="$2"
    
    print_info "Deleting device: $device_name (ID: $device_id)"
    
    if make_api_call "DELETE" "/device/$device_id" > /dev/null; then
        print_success "Successfully deleted device: $device_name"
        return 0
    else
        print_error "Failed to delete device: $device_name"
        return 1
    fi
}

# Function to confirm deletion
confirm_deletion() {
    local device_count="$1"
    
    echo ""
    print_warning "This will delete $device_count device(s) with tag '$TAG_TO_DELETE'"
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
    
    # Get devices and extract JSON using compatible sed command
    local devices_response
    devices_response=$(get_devices | eval "$SED_EXTRACT" | jq -M '.' 2>/dev/null)
    local get_devices_status=${PIPESTATUS[0]}
    
    # Check if API call failed or invalid JSON
    if [ $get_devices_status -ne 0 ] || [ -z "$devices_response" ]; then
        print_error "Failed to fetch devices or invalid JSON response"
        exit 1
    fi
    
    # Check for devices array
    if ! echo "$devices_response" | jq -e '.devices' >/dev/null 2>&1; then
        print_error "JSON response missing devices array"
        echo "Response structure:"
        echo "$devices_response" | jq -r 'keys[]' >&2
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
    echo "$matching_devices" | jq -r '"  - \(.name) (\(.hostname)) - ID: \(.id)"'
    
    local device_count
    device_count=$(echo "$matching_devices" | jq -s length)
    
    # Confirm deletion
    confirm_deletion "$device_count"
    
    # Delete devices
    local success_count=0
    local failure_count=0
    
    echo ""
    print_info "Starting deletion process..."
    
    echo "$matching_devices" | while IFS= read -r device; do
        if [ -n "$device" ]; then
            local device_id device_name
            device_id=$(echo "$device" | jq -r '.id')
            device_name=$(echo "$device" | jq -r '.name')
            
            if delete_device "$device_id" "$device_name"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        fi
    done
    
    # Summary
    echo ""
    print_info "Deletion completed:"
    print_success "Successfully deleted: $success_count devices"
    if [ $failure_count -gt 0 ]; then
        print_error "Failed to delete: $failure_count devices"
        exit 1
    else
        print_success "All devices with tag '$TAG_TO_DELETE' have been deleted"
    fi
}

# Handle script interruption
trap 'print_warning "Script interrupted by user"; exit 130' INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

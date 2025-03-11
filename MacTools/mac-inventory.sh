#!/bin/bash

#------------------------------------------------------------------------------
# Configuration and Constants
#------------------------------------------------------------------------------
readonly INVENTORY_TITLE="My Mac Setup Inventory"
readonly OUTPUT_DIR="$HOME/Documents"
readonly OUTPUT_FILE="$OUTPUT_DIR/my_mac_inventory.md"
readonly CURRENT_DATE=$(date "+%Y-%m-%d")

readonly APPLICATIONS_DIR="/Applications"
readonly SERVICES_DIR="$HOME/Library/Services"
readonly SECTION_APPS="Installed Applications"
readonly SECTION_BREW="Homebrew Packages"
readonly SECTION_WORKFLOWS="Custom Automator Workflows"

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------
print_error() {
    echo "Error: $1" >&2
    exit 1
}

check_prerequisites() {
    if [ ! -w "$(dirname "$OUTPUT_FILE")" ]; then
        print_error "Cannot write to output directory: $OUTPUT_DIR"
    fi
}

get_sorted_listing() {
    local directory=$1
    ls -1 "$directory" 2>/dev/null | sort
}

get_brew_packages() {
    if command -v brew &> /dev/null; then
        brew list
    else
        echo "Homebrew not installed"
    fi
}

write_section() {
    local section_header=$1
    local section_content=$2

    {
        echo "## ${section_header}"
        echo
        echo "${section_content}"
        echo
    } >> "$OUTPUT_FILE"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    check_prerequisites

    # Create inventory file with header
    echo "# ${INVENTORY_TITLE} - ${CURRENT_DATE}" > "$OUTPUT_FILE"

    # Generate inventory sections
    write_section "$SECTION_APPS" "$(get_sorted_listing "$APPLICATIONS_DIR")"
    write_section "$SECTION_BREW" "$(get_brew_packages)"
    write_section "$SECTION_WORKFLOWS" "$(get_sorted_listing "$SERVICES_DIR")"

    echo "Inventory saved to $OUTPUT_FILE"
}

main
#!/usr/bin/env bash

# Verify required environment variables
if [ -z "${USER}" ]; then
    echo "Error: USER environment variable is not set" >&2
    exit 1
fi

if [ -z "${win_password}" ]; then
    echo "Error: win_password environment variable is not set" >&2
    exit 1
fi

output_file="${script_path}/smbios_data.bin"

# Create two separate strings
string1="user=${USER}"
string2="password=${win_password}"

# Calculate size including headers and terminators

# Create binary file
(
    printf '\x0B\x05'                  # Type 11 length 5
    printf '\x00\xB0'             # Handle (0x00B0)
    printf '\x02'                 # Count (2 strings)
    printf '%s\0%s\0\0' "$string1" "$string2"  # Strings with terminators
) > "$output_file"

# For debugging if needed
#echo "Created $output_file:"
#xxd "$output_file"

chmod 600 "$output_file"


echo "Successfully created $output_file with proper permissions"


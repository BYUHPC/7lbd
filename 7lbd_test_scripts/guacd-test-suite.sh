#!/bin/bash

# Source configuration
CONFIG_FILE="./config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi
source "$CONFIG_FILE"

# Set default port if not defined in config.sh
CONNECTOR_PORT=${CONNECTOR_PORT:-8080}

# Set required environment variables
export JOB_TMP_DIR
export SPANK_ISO_NETNS_LISTENING_FD_0="use-insecure-testing-port"
export SPANK_ISO_NETNS_LISTENING_PORT_0="$CONNECTOR_PORT"
export script_path=$JOB_TMP_DIR

# Print help information
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Control and monitor test suite system components"
    echo
    echo "Options:"
    echo "  --start-all          Start all components (VM, connector server, and guacd)"
    echo "  --start-vm           Start the virtual machine"
    echo "  --start-connector    Start the guacamole connector server"
    echo "  --start-guacd        Start the guacd container"
    echo "  --stop-all           Stop all components and clean temporary files"
    echo "  --stop-vm            Stop the virtual machine"
    echo "  --stop-connector     Stop the guacamole connector server"
    echo "  --stop-guacd         Stop the guacd container"
    echo "  --status             Show status of all components"
    echo "  --preflight-only     Run all preflight checks without starting anything"
    echo "  --clean-tmp          Clean up all temporary files (must stop services first)"
    echo "  --help               Display this help message"
    echo
    echo "Examples:"
    echo "  # Start everything:"
    echo "  $0 --start-all"
    echo
    echo "  # Start components individually:"
    echo "  $0 --start-vm --start-connector --start-guacd"
    echo
    echo "  # Check status of all components:"
    echo "  $0 --status"
    echo
    echo "  # Stop everything:"
    echo "  $0 --stop-all"
    echo
    echo "  # Common workflow:"
    echo "  $0 --preflight-only          # Check prerequisites"
    echo "  $0 --start-all               # Start all services"
    echo "  $0 --status                  # Verify everything is running"
    echo "  $0 --stop-all                # Stop all services when done"
    echo "  $0 --clean-tmp               # Clean up temporary files"
    echo ""
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    print_help
    exit 0
fi

VALID_ARGS=$(getopt -o hp --long help,start-all,start-vm,start-connector,start-guacd,stop-all,stop-vm,stop-connector,stop-guacd,status,preflight-only,clean-tmp -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1
fi
eval set -- "$VALID_ARGS"

# Initialize flags
START_ALL=false
START_VM=false
START_CONNECTOR=false
START_GUACD=false
STOP_ALL=false
STOP_VM=false
STOP_CONNECTOR=false
STOP_GUACD=false
STATUS=false
PREFLIGHT=false
CLEAN_TMP=false

# Process arguments
while true; do
    case "$1" in 
        -h|--help) print_help; exit 0 ;;
        --start-all) START_ALL=true; shift ;;
        --start-vm) START_VM=true; shift ;;
        --start-connector) START_CONNECTOR=true; shift ;;
        --start-guacd) START_GUACD=true; shift ;;
        --stop-all) STOP_ALL=true; shift ;;
        --stop-vm) STOP_VM=true; shift ;;
        --stop-connector) STOP_CONNECTOR=true; shift ;;
        --stop-guacd) STOP_GUACD=true; shift ;;
        --status) STATUS=true; shift ;;
        --preflight-only) PREFLIGHT=true; shift ;;
        --clean-tmp) CLEAN_TMP=true; shift ;;
        --) shift; break ;;
    esac
done

# Function to check virtualization support
check_virtualization() {
    # Check CPU virtualization support
    if ! grep -E 'vmx|svm' /proc/cpuinfo &>/dev/null; then
        echo "✗ CPU virtualization not available"
        return 1
    fi
    
    # Check KVM device access
    if [[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]]; then
        echo "✗ No access to KVM device (/dev/kvm)"
        return 1
    fi
    
    echo "✓ Virtualization support verified"
    return 0
}

# PID file management functions
get_pid_file() {
    local service_name=$1
    echo "${JOB_TMP_DIR}/${service_name}.pid"
}

write_pid() {
    local service_name=$1
    local pid=$2
    local pid_file=$(get_pid_file "$service_name")
    echo "$pid" > "$pid_file"
}

read_pid() {
    local service_name=$1
    local pid_file=$(get_pid_file "$service_name")
    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    else
        echo ""
    fi
}

remove_pid() {
    local service_name=$1
    local pid_file=$(get_pid_file "$service_name")
    rm -f "$pid_file"
}

check_process() {
    local service_name=$1
    local pid=$(read_pid "$service_name")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0  # Process is running
    else
        remove_pid "$service_name"  # Clean up stale PID file
        return 1  # Process is not running
    fi
}

# Apptainer initialization check
check_apptainer() {
    # First try direct apptainer check
    if command -v apptainer &> /dev/null; then
        # Check if we've initialized apptainer in this session
        local init_marker="${JOB_TMP_DIR}/.apptainer_initialized"
        if [[ -f "$init_marker" ]]; then
            # Already initialized in this session
            return 0
        fi
        
        # Try to run apptainer without prereq
        if apptainer --version &> /dev/null; then
            # Create marker file
            touch "$init_marker"
            return 0
        fi
    fi
    
    # If we get here, we need to run the prereq
    echo "Initializing apptainer environment..."
    eval $CONTAINER_PREREQ
    
    # Create marker file after successful prereq
    touch "${JOB_TMP_DIR}/.apptainer_initialized"
    
    return 0
}

# Create config files for guacd_connector
create_connector_config_files() {
    # Generate credentials
    local authtoken=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    local guac_key=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    local CREDENTIALS_FILE="${JOB_TMP_DIR}/rdp_credentials"
    
    # Create the credentials file
    cat <<EOF > "$CREDENTIALS_FILE"
{
    "username": "$WIN_USER",
    "password": "$WIN_PASSWORD",
    "authtoken": "$authtoken",
    "guac_key": "$guac_key",
    "cypher": "AES-256-CBC"
}
EOF

chmod 700 "$CREDENTIALS_FILE"

    # Resolve GUACD_CONNECTOR_JSON path if it's relative
    local CONFIG_FILE="${JOB_TMP_DIR}/guacd_rdp.json"
    local SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local JSON_PATH="$GUACD_CONNECTOR_JSON"
    
    if [[ ! -f "$JSON_PATH" && ! "$JSON_PATH" =~ ^/ ]]; then
        JSON_PATH="$SCRIPT_DIR/$GUACD_CONNECTOR_JSON"
    fi
    
    # Copy the provided RDP configuration file to the job tmp directory
    if [[ -f "$JSON_PATH" ]]; then
        cp "$JSON_PATH" "$CONFIG_FILE"
        echo "Using provided guacd_rdp.json configuration file from $JSON_PATH"
    else
        echo "Warning: guacd_rdp.json not found at $JSON_PATH. Creating default configuration."
        # Create default RDP connection config file
        cat <<EOF > "$CONFIG_FILE"
{
    "type": "rdp",
    "useCredentials": true,
    "defaultWidth": 1920,
    "defaultHeight": 1080,
    "guacd": {
        "port": 4822
    },
    "logLevel": "ERRORS",
    "settings": {
        "hostname": "localhost",
        "port": 3389,
        "enable-drive": false,
        "create-drive-path": false,
        "enable-wallpaper": false,
        "enable-theming": false,
        "enable-font-smoothing": false,
        "enable-desktop-composition": false,
        "enable-menu-animations": false,
        "security": "any",
        "ignore-cert": true,
        "dpi": 96
    }
}
EOF
    fi

    echo "Configuration files created successfully"
    return 0
}

# Preflight checks function
preflight_check() {
    local error_count=0
    local vm_errors=0
    local connector_errors=0
    local guacd_errors=0
    
    echo "Running preflight checks..."
    echo "============================="
    
    # Check for already running services first
    echo "Checking for already running services:"
    local services_running=false
    
    # Check if connector port is in use
    if netstat -tuln | grep -q ":${CONNECTOR_PORT:-8080} "; then
        echo "✗ Port ${CONNECTOR_PORT:-8080} is in use - connector may already be running"
        echo "  Process using the port:"
        netstat -tulpn 2>/dev/null | grep ":${CONNECTOR_PORT:-8080}" || netstat -tuln | grep ":${CONNECTOR_PORT:-8080}"
        services_running=true
    fi
    
    # Check if guacd port is in use
    if netstat -tuln | grep -q ":4822 "; then
        echo "✗ Port 4822 is in use - guacd likely already running"
        echo "  Process using the port:"
        netstat -tulpn 2>/dev/null | grep ":4822" || netstat -tuln | grep ":4822"
        services_running=true
    fi
    
    # Check for VM process
    if pgrep -f "${USER}_insecure_test_win11" > /dev/null; then
        echo "✗ VM process found with name '${USER}_insecure_test_win11'"
        echo "  Process details:"
        ps -f -u $USER | grep -v grep | grep "${USER}_insecure_test_win11"
        services_running=true
    fi
    
    # If existing services are found, suggest cleanup
    if [[ "$services_running" == "true" ]]; then
        echo
        echo "⚠ ERROR: Services appear to be already running."
        echo "You should stop existing services before starting new ones."
        echo "Run the following commands to stop services and clean up:"
        echo "  $0 --stop-all"
        echo "  $0 --clean-tmp"
        echo
        echo "To see detailed status of current services:"
        echo "  $0 --status"
        echo
        echo "To forcibly stop all related processes (use with caution):"
        echo "  pkill -f \"${USER}_insecure_test_win11\" # Kill VM"
        echo "  pkill -f \"guacd\" # Kill guacd"
        echo "  pkill -f \"node.*guacd_connector.js\" # Kill connector"
        echo
        return 1
    fi
    
    # Common checks
    echo "Common Environment Check:"
    [[ -d "$JOB_TMP_DIR" ]] || mkdir -p "$JOB_TMP_DIR"
    chmod 700 "$JOB_TMP_DIR"
    echo "✓ Job temporary directory setup complete"
    
    # Print key configuration variables for debugging
    echo "Configuration:"
    echo "- JOB_TMP_DIR: $JOB_TMP_DIR"
    echo "- BEAN_DIP_DIR: $BEAN_DIP_DIR"
    echo "- GUACD_CONNECTOR_JSON: $GUACD_CONNECTOR_JSON"
    echo
    
    # If preflight_only is true and no specific components selected, check all
    if [[ $PREFLIGHT == true ]] && ! $START_VM && ! $START_CONNECTOR && ! $START_GUACD; then
        START_VM=true
        START_CONNECTOR=true
        START_GUACD=true
    fi
    
    # VM-specific checks
    if [[ $START_VM == true ]]; then
        echo "VM Prerequisites Check:"
        if ! check_virtualization; then
            ((vm_errors++))
        fi
        if [[ ! -f "$READ_ONLY_VM_FILE" ]]; then
            echo "✗ VM image file not found at $READ_ONLY_VM_FILE"
            ((vm_errors++))
        else
            echo "✓ VM image file found"
        fi
        if ! command -v $QEMU_BIN_PATH &> /dev/null; then
            echo "✗ qemu-kvm not installed"
            ((vm_errors++))
        else
            echo "✓ qemu-kvm installed"
        fi
        if ! command -v qemu-img &> /dev/null; then
            echo "✗ qemu-img not installed"
            ((vm_errors++))
        else
            echo "✓ qemu-img installed"
        fi
        ((error_count+=vm_errors))
        echo
    fi
    
    # Connector server checks
    if [[ $START_CONNECTOR == true ]]; then
        echo "Connector Server Prerequisites Check:"
        
        # Convert relative path to absolute path for BEAN_DIP_DIR
        local SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
        local ABSOLUTE_BEAN_DIP_DIR="$( cd "$SCRIPT_DIR/$BEAN_DIP_DIR" 2>/dev/null && pwd )"
        
        if [[ -z "$ABSOLUTE_BEAN_DIP_DIR" ]]; then
            echo "✗ Cannot resolve absolute path for BEAN_DIP_DIR: $BEAN_DIP_DIR (from $SCRIPT_DIR)"
            ((connector_errors++))
        else
            echo "✓ Connector directory resolved to: $ABSOLUTE_BEAN_DIP_DIR"
            
            # Check for guacd_connector.js at the resolved path
            if [[ ! -f "$ABSOLUTE_BEAN_DIP_DIR/guacd_connector.js" ]]; then
                echo "✗ guacd_connector.js not found at $ABSOLUTE_BEAN_DIP_DIR/guacd_connector.js"
                echo "  Contents of the directory:"
                ls -la "$ABSOLUTE_BEAN_DIP_DIR"
                ((connector_errors++))
            else
                echo "✓ guacd_connector.js found at $ABSOLUTE_BEAN_DIP_DIR/guacd_connector.js"
            fi
            
            # Check only for index.html in the public directory
            if [[ ! -f "$ABSOLUTE_BEAN_DIP_DIR/public/index.html" ]]; then
                echo "✗ index.html not found at $ABSOLUTE_BEAN_DIP_DIR/public/index.html"
                echo "  The Guacamole web client files appear to be missing"
                ((connector_errors++))
            else
                echo "✓ Guacamole client files found (index.html exists)"
            fi
        fi

        if ! command -v node &> /dev/null; then
            echo "✗ NodeJS not installed"
            ((connector_errors++))
        else
            echo "✓ NodeJS installed"
        fi
        
        # Check if the port is available
        if netstat -tuln | grep -q ":${CONNECTOR_PORT:-8080} "; then
            echo "⚠ Port ${CONNECTOR_PORT:-8080} is already in use. The connector may fail to start."
            echo "  You can set CONNECTOR_PORT in config.sh to use a different port."
        else
            echo "✓ Port ${CONNECTOR_PORT:-8080} is available"
        fi
        
        # If GUACD_CONNECTOR_JSON is also a relative path, resolve it
        if [[ ! -f "$GUACD_CONNECTOR_JSON" && ! "$GUACD_CONNECTOR_JSON" =~ ^/ ]]; then
            local ABSOLUTE_JSON_PATH="$SCRIPT_DIR/$GUACD_CONNECTOR_JSON"
            if [[ -f "$ABSOLUTE_JSON_PATH" ]]; then
                echo "✓ guacd_rdp.json found at $ABSOLUTE_JSON_PATH"
                GUACD_CONNECTOR_JSON="$ABSOLUTE_JSON_PATH"
            else
                echo "⚠ guacd_rdp.json not found at $ABSOLUTE_JSON_PATH (will use default configuration)"
            fi
        elif [[ ! -f "$GUACD_CONNECTOR_JSON" ]]; then
            echo "⚠ guacd_rdp.json not found at $GUACD_CONNECTOR_JSON (will use default configuration)"
        else
            echo "✓ guacd_rdp.json configuration file found at $GUACD_CONNECTOR_JSON"
        fi
        
        ((error_count+=connector_errors))
        echo
    fi
    
    # Guacd checks
    if [[ $START_GUACD == true ]]; then
        echo "Guacd Prerequisites Check:"
        if [[ ! -f "$GUACD_CONTAINER" ]]; then
            echo "✗ Guacd container not found at $GUACD_CONTAINER"
            ((guacd_errors++))
        else
            echo "✓ Guacd container found"
        fi
        # Use check_apptainer function instead of just checking command existence
        if ! check_apptainer; then
            echo "✗ Apptainer not available"
            ((guacd_errors++))
        else
            echo "✓ Apptainer available"
        fi
        ((error_count+=guacd_errors))
        echo
    fi
    
    # Summary
    echo "Preflight Check Summary:"
    echo "----------------------"
    [[ $START_VM == true ]] && echo "VM Prerequisites: $([ $vm_errors -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL ($vm_errors errors)")"
    [[ $START_CONNECTOR == true ]] && echo "Connector Prerequisites: $([ $connector_errors -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL ($connector_errors errors)")"
    [[ $START_GUACD == true ]] && echo "Guacd Prerequisites: $([ $guacd_errors -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL ($guacd_errors errors)")"
    echo
    
    return $error_count
}

# Status check function
check_status() {
    echo "System Status:"
    echo "-------------"
    
    local all_running=true
    
    local vm_pid=$(read_pid "vm")
    if [[ -n "$vm_pid" ]] && kill -0 "$vm_pid" 2>/dev/null; then
        echo "VM: Running (PID: $vm_pid)"
        
        # Check if RDP is listening
        if netstat -tuln | grep -q ":3389 "; then
            echo "  ✓ RDP port 3389 is open and listening"
        else
            echo "  ✗ RDP port 3389 is not listening - VM may not be fully booted or RDP service not started"
            all_running=false
        fi
    else
        echo "VM: Stopped"
        remove_pid "vm"
        all_running=false
    fi
    
    local connector_pid=$(read_pid "connector")
    if [[ -n "$connector_pid" ]] && kill -0 "$connector_pid" 2>/dev/null; then
        echo "Connector Server: Running (PID: $connector_pid)"
        
        # Check if the connector is listening on port 8080
        if netstat -tuln | grep -q ":8080 "; then
            echo "  ✓ Connector is listening on port 8080"
        else
            echo "  ✗ Connector is not listening on port 8080 - web connections will fail"
            all_running=false
        fi
        
        # Instead of showing recent logs, just mention the log location.
        echo "  Connector logs can be found at /tmp/connector-logs/connector-debug.log"
    else
        echo "Connector Server: Stopped"
        remove_pid "connector"
        all_running=false
    fi
    
    local guacd_pid=$(read_pid "guacd")
    if [[ -n "$guacd_pid" ]] && kill -0 "$guacd_pid" 2>/dev/null; then
        echo "Guacd: Running (PID: $guacd_pid)"
        
        # Check if guacd is listening on port 4822
        if netstat -tuln | grep -q ":4822 "; then
            echo "  ✓ Guacd is listening on port 4822"
        else
            echo "  ✗ Guacd is not listening on port 4822 - connections will fail"
            all_running=false
        fi
    else
        echo "Guacd: Stopped"
        remove_pid "guacd"
        all_running=false
    fi
    
    # If all services are running, try to show the connection URL
    if [[ "$all_running" == "true" ]]; then
        echo
        local CREDENTIALS_FILE="${JOB_TMP_DIR}/rdp_credentials"
        if [[ -f "$CREDENTIALS_FILE" ]]; then
            local authtoken=$(jq -r '.authtoken' "$CREDENTIALS_FILE")
            if [[ -n "$authtoken" ]]; then
                echo "Connection URL:"
                echo "$ONDEMAND_SERVER/node/$(hostname -f)/8080/?authtoken=$authtoken"
                echo
                echo "You can connect using the following credentials:"
                echo "Username: $WIN_USER"
                echo "Password: [configured in config.sh]"
                echo ""
            fi
        fi
    else
        echo
        echo "⚠ WARNING: One or more services are not running correctly."
        echo "Review the status above and address any issues marked with ✗."
        echo "Try running with --stop-all and then --start-all again."
    fi
}

cleanup_tmp() {
    echo "Checking for running services before cleanup..."
    local running_services=false

    # Check each service
    if check_process "vm"; then
        echo "Error: VM is still running. Please stop it first."
        running_services=true
    fi

    if check_process "connector"; then
        echo "Error: Connector server is still running. Please stop it first."
        running_services=true
    fi

    if check_process "guacd"; then
        echo "Error: Guacd is still running. Please stop it first."
        running_services=true
    fi

    if [[ "$running_services" == "true" ]]; then
        echo "Please stop all services before cleaning up temporary files."
        return 1
    fi

    echo "Cleaning up temporary files in $JOB_TMP_DIR..."

    # Remove PID files
    rm -f "${JOB_TMP_DIR}"/*.pid

    # Remove credentials and config files
    rm -f "${JOB_TMP_DIR}/rdp_credentials"
    rm -f "${JOB_TMP_DIR}/guacd_rdp.json"

    # Remove VNC socket
    rm -f "${JOB_TMP_DIR}/vnc.socket"

    # Remove overlay file (updated path)
    rm -f "${JOB_TMP_DIR}/${USER}-test-suite.qcow2"

    # Remove apptainer initialization marker
    rm -f "${JOB_TMP_DIR}/.apptainer_initialized"

    echo "Cleanup complete"
    return 0
}

# Stop functions
stop_vm() {
    local pid=$(read_pid "vm")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "Stopping VM..."
        kill "$pid"
        sleep 2
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "VM stopped successfully"
            remove_pid "vm"
        else
            echo "Failed to stop VM gracefully, forcing..."
            kill -9 "$pid"
            remove_pid "vm"
        fi
    else
        echo "VM is not running"
        remove_pid "vm"
    fi
}

stop_connector() {
    local pid
    pid=$(read_pid "connector")
    
    if [[ -n "$pid" ]]; then
        # Check that the PID belongs to a guacd_connector.js process.
        local proc_cmd
        proc_cmd=$(ps -p "$pid" -o args= 2>/dev/null)
        if [[ -n "$proc_cmd" && "$proc_cmd" == *"guacd_connector.js"* ]]; then
            echo "Stopping connector server (PID: $pid)..."
            kill "$pid"
            local timeout=0
            # Wait up to 5 seconds for the process to terminate.
            while ps -p "$pid" -o args= 2>/dev/null | grep -q "guacd_connector.js" && [[ $timeout -lt 5 ]]; do
                sleep 1
                timeout=$((timeout + 1))
            done
            # After waiting, re-check if the process is still running.
            if ps -p "$pid" -o args= 2>/dev/null | grep -q "guacd_connector.js"; then
                echo "Connector server did not stop gracefully after $timeout seconds; forcing termination with kill -9..."
                kill -9 "$pid"
                sleep 1
                if ps -p "$pid" -o args= 2>/dev/null | grep -q "guacd_connector.js"; then
                    echo "Failed to forcefully terminate connector server (PID: $pid)."
                    return 1
                else
                    echo "Connector server forcefully terminated (PID: $pid)."
                    remove_pid "connector"
                fi
            else
                echo "Connector server stopped gracefully (PID: $pid)."
                remove_pid "connector"
            fi
        else
            echo "Connector server is not running (PID file present but process not found or mismatched)."
            remove_pid "connector"
        fi
    else
        echo "No PID file found for connector server."
    fi
}

stop_guacd() {
    local pid=$(read_pid "guacd")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "Stopping guacd..."
        kill "$pid"
        sleep 2
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "Guacd stopped successfully"
            remove_pid "guacd"
        else
            echo "Failed to stop guacd gracefully, forcing..."
            kill -9 "$pid"
            remove_pid "guacd"
        fi
    else
        echo "Guacd is not running"
        remove_pid "guacd"
    fi
}

# Create overlay function
create_overlay() {
    export overlay_path="${JOB_TMP_DIR}/${USER}-test-suite.qcow2"
    if [[ -f "$overlay_path" ]]; then
        echo "Removing existing overlay file..."
        rm -f "$overlay_path"
    fi
    
    echo "Creating new overlay file..."
    if ! qemu-img create -f qcow2 -b "$READ_ONLY_VM_FILE" -F qcow2 "$overlay_path"; then
        echo "Failed to create overlay file at $overlay_path"
        return 1
    fi
    echo "Overlay file created successfully at $overlay_path"
    return 0
}

# Start functions
start_vm() {
    if check_process "vm"; then
        echo "VM is already running"
        return 1
    fi
    
    # Create overlay file before starting VM
    if ! create_overlay; then
        echo "Failed to create overlay file. Aborting VM start."
        return 1
    fi
    
    echo "Starting VM..."
    ulimit -c 0
    $QEMU_BIN_PATH \
        -name guest=${USER}_insecure_guac_test_win11,debug-threads=on \
        -machine pc-q35-rhel9.4.0 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
        -device ich9-ahci,id=sata_controller \
        -drive file=$overlay_path,format=qcow2,if=none,id=drive0 \
        -device ide-hd,drive=drive0,bus=sata_controller.0 \
        -m 8G \
        -cpu max \
        -smp 4 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,net=169.254.100.0/24,dhcpstart=169.254.100.15,host=169.254.100.2,hostfwd=tcp::3389-:3389 \
        -device virtio-net-pci,netdev=net1 \
        -netdev user,id=net1 \
        -boot c \
        -vga none \
        -device virtio-gpu-pci \
        -vnc unix:${JOB_TMP_DIR}/vnc.socket,lossy=on,non-adaptive=on \
        -rtc base=localtime \
        -usb -device usb-tablet &
    
    local pid=$!
    sleep 5
    if kill -0 "$pid" 2>/dev/null; then
        write_pid "vm" "$pid"
        echo "VM started successfully"
    else
        echo "Failed to start VM"
        return 1
    fi
}

start_connector() {
    if check_process "connector"; then
        echo "Connector server is already running"
        return 1
    fi

    echo "Creating configuration files for connector..."
    if ! create_connector_config_files; then
        echo "Failed to create configuration files"
        return 1
    fi

    echo "Starting connector server..."

    local SCRIPT_DIR
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local ABSOLUTE_BEAN_DIP_DIR
    ABSOLUTE_BEAN_DIP_DIR="$( cd "$SCRIPT_DIR/$BEAN_DIP_DIR" &> /dev/null && pwd )"

    if [[ -z "$ABSOLUTE_BEAN_DIP_DIR" ]]; then
        echo "Error: Could not resolve absolute path for BEAN_DIP_DIR: $BEAN_DIP_DIR"
        echo "Current directory: $(pwd)"
        return 1
    fi

    if [[ ! -f "$ABSOLUTE_BEAN_DIP_DIR/guacd_connector.js" ]]; then
        echo "Error: guacd_connector.js not found at $ABSOLUTE_BEAN_DIP_DIR/guacd_connector.js"
        ls -la "$ABSOLUTE_BEAN_DIP_DIR"
        return 1
    fi

    # Create log directory and define log file.
    mkdir -p "/tmp/connector-logs"
    local log_file="/tmp/connector-logs/connector-debug.log"

    # Final check for port availability.
    if netstat -tuln | grep -q ":$CONNECTOR_PORT "; then
        echo "ERROR: Port $CONNECTOR_PORT is now in use. Cannot continue."
        echo "Run --status to check current processes and --stop-all to clean up."
        return 1
    fi

    echo "Starting connector with logging to $log_file..."
    # Use a subshell and exec so that the node process replaces the shell.
    (
      cd "${JOB_TMP_DIR}" || exit 1
      exec node "${ABSOLUTE_BEAN_DIP_DIR}/guacd_connector.js" guacd_rdp.json
    ) > "$log_file" 2>&1 &
    local pid=$!

    sleep 5
    if kill -0 "$pid" 2>/dev/null; then
        write_pid "connector" "$pid"
        local authtoken
        authtoken=$(jq -r '.authtoken' "${JOB_TMP_DIR}/rdp_credentials")
        echo "Connector server started with PID $pid"
        echo "URL for HTML5 Guacamole session: $ONDEMAND_SERVER/node/$(hostname -f)/8080/?authtoken=$authtoken"
        echo "Connector logs are available at: $log_file"
    else
        echo "Failed to start connector server"
        echo "Check logs at $log_file for details"
        return 1
    fi
}

start_guacd() {
    if check_process "guacd"; then
        echo "Guacd is already running"
        return 1
    fi
    
    echo "Starting guacd..."
    if ! check_apptainer; then
        echo "Failed to initialize apptainer"
        return 1
    fi
    
    apptainer run ${GUACD_CONTAINER} &
    local pid=$!
    
    sleep 3
    if kill -0 "$pid" 2>/dev/null; then
        write_pid "guacd" "$pid"
        echo "Guacd started successfully"
    else
        echo "Failed to start guacd"
        return 1
    fi
}

# Main execution logic
if [[ $PREFLIGHT == true ]]; then
    echo "Running preflight checks..."
    preflight_check
    exit
fi

if [[ $STATUS == true ]]; then
    check_status
    exit
fi

if [[ $CLEAN_TMP == true ]]; then
    cleanup_tmp
    exit
fi

# Handle stop-all first if requested
if [[ $STOP_ALL == true ]]; then
    stop_vm
    stop_connector
    stop_guacd
    cleanup_tmp
    exit 0
fi

# Handle individual stop requests
[[ $STOP_VM == true ]] && stop_vm
[[ $STOP_CONNECTOR == true ]] && stop_connector
[[ $STOP_GUACD == true ]] && stop_guacd

# Handle start-all if requested
if [[ $START_ALL == true ]]; then
    START_VM=true
    START_CONNECTOR=true
    START_GUACD=true
fi

# Start processes if requested and preflight checks pass
if $START_VM || $START_CONNECTOR || $START_GUACD; then
    echo "Running preflight checks before starting services..."
    if ! preflight_check; then
        echo "Preflight checks failed. Aborting startup."
        exit 1
    fi
    
    [[ $START_VM == true ]] && start_vm
    [[ $START_CONNECTOR == true ]] && start_connector
    [[ $START_GUACD == true ]] && start_guacd
fi


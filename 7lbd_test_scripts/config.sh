# config.sh
# Environment variables for test suite

# Open OnDemand reverse proxy server
# This url is used to access your VM through the reverse proxy.
# For example:
# https://ondemand.example.edu/node/server1.example.edu/8080/?authtoken=DAf7doLzRUGmFvWb4pQTza0IYTVxv7WH
ONDEMAND_SERVER="https://ondemand.rc.byu.edu"

# Temporary directory for job
# This folder will hold the VM overlay file, connector logs, rdp credentials, etc.
# NOTE:  Your rdp credentials for your VM will be copied to a file at this path in plain text, with 700 permissions.
# In the production code, the RDP credentials are randomly generated and saved to the user’s ondemand job folder in
# their home space.
JOB_TMP_DIR="/tmp/${USER}-7lbd-server-test"

# guacd connector configuration
# This is the folder where the guacamole lite application is located
# This folder can be placed in a common apps area on a network drive
BEAN_DIP_DIR="../7lbd_apps"
# Location of the guacd container.  This was downloaded when running build_7lbd_apps.sh
GUACD_CONTAINER="${BEAN_DIP_DIR}/guacd_latest.sif"
# This should be the commands necessary to create an environment where you can run 
# the guacd container.  Load modules, etc.  It needs to be a one-line bash script.
CONTAINER_PREREQ="module load spack; spack load apptainer@1.3.2/2zcgvx6"
# Location of the json file that tells the guacd connector where the guacd container is
# and what settings to connect with.  
GUACD_CONNECTOR_JSON="../7lbd_ood/template/guacd_rdp.json"

#qemu configuration
# Path to the qemu-kvm binary
QEMU_BIN_PATH="/usr/libexec/qemu-kvm"

#VM run configuration
# Location of the read-only Windows VM file to boot
# For production systems this should be a soft-link to a file in a shared network space
#READ_ONLY_VM_FILE="/apps/.vd/latest.qcow2"
READ_ONLY_VM_FILE="/home/ja56/win11/winpractice-clone.qcow2"
# Username and password to connect to the VM with for testing
# Yes, this is super insecure and only used for testing
# The production system will use a randomly generated password
# passed through Open OnDemand to the user’s browser
WIN_USER="user1"
WIN_PASSWORD="insecurepassword123"

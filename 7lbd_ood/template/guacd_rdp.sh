#!/usr/bin/env bash

echo "GUACD_RDP.SH:  Loading modules for guac..."
#Create environment necessary for loading the guac container
module load spack
spack load apptainer
echo "GUACD_RDP.SH:  launching guacd:..."
# Load in a while loop so if the container is killed, another one will start up
( while true; do apptainer run ${s7lbd_dir}/guacd_latest.sif; sleep 1; done ) &
# Load in a while loop so if 7lbd_server.js is killed, another one will start up
echo "GUACD_RDP.SH:  Starting Guacd RDP Connector..."
( while true; do node ${s7lbd_dir}/guacd_connector.js guacd_rdp.json; sleep 1; done ) & 


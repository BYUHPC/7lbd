#!/usr/bin/env bash

mkdir -p ${JOB_TMP_DIR}/samba/log
mkdir -p ${JOB_TMP_DIR}/samba/lock
mkdir -p ${JOB_TMP_DIR}/samba/private
mkdir -p ${JOB_TMP_DIR}/samba/cache 
mkdir -p ${JOB_TMP_DIR}/samba/ncalrpc

cat > ${script_path}/smb.conf <<EOL
[global]
   workgroup = WORKGROUP
   server string = Samba Server
   security = user
   map to guest = Bad User
   log file = ${JOB_TMP_DIR}/samba.log
   max log size = 50
   interfaces = 127.0.0.1/8
   bind interfaces only = yes
   follow symlinks = yes
   wide links = yes
   unix extensions = no

 workgroup = WORKGROUP
   server string = Samba Server
   security = user
   map to guest = Bad User
   log file = ${JOB_TMP_DIR}/samba/log/log.%m
   max log size = 50
   logging = file
   panic action = /bin/echo %d >> ${JOB_TMP_DIR}/samba/panic_action.log
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   disable netbios = yes
   server role = standalone server
   server services = -dns, -nbt
   smb ports = 445
   interfaces = 127.0.0.1/8
   bind interfaces only = yes
   pid directory = ${JOB_TMP_DIR}/samba
   lock directory = ${JOB_TMP_DIR}/samba/lock
   state directory = ${JOB_TMP_DIR}/samba
   cache directory = ${JOB_TMP_DIR}/samba/cache
   private dir = ${JOB_TMP_DIR}/samba/private
   ncalrpc dir = ${JOB_TMP_DIR}/samba/ncalrpc
   usershare allow guests = yes
   map to guest = Bad User
   guest account = $SLURM_JOB_USER
   enable core files = yes
   restrict anonymous = no
   allow insecure wide links = yes


[home]
   path = /home/$SLURM_JOB_USER
   read only = no
   guest ok = yes
   guest only = yes
   create mask = 0777
   directory mask = 0777

[groups]
   path = /home/$SLURM_JOB_USER/groups
   read only = no
   guest ok = yes
   guest only = yes
   create mask = 0777
   directory mask = 0777

[nobackup]
   path = /home/$SLURM_JOB_USER/nobackup
   read only = no
   guest ok = yes
   guest only = yes
   create mask = 0777
   directory mask = 0777

EOL

while true; do
    echo "SAMBA.SH:  $(date): Starting smbd..."

    if [[ $(</proc/sys/crypto/fips_enabled) == 1 ]]
    then
	echo "SAMBA.SH:  Preload launching smbd..."
	# Launch smbd such that it is not aware of FIPS mode
        LD_PRELOAD=/apps/7lbd/7lbd.v0.4.4/gnutls_fips_override/gnutls_fips_override.so smbd --configfile=${script_path}/smb.conf --no-process-group --foreground --debug-stdout
    else
	echo "SAMBA.SH: native smbd..."
	# Launch smbd normally
        smbd --configfile=${script_path}/smb.conf --no-process-group --foreground --debug-stdout
    fi
    # Check the exit status
    exit_status=$?
    echo "SAMBA.SH:  $(date): smbd exited with status $exit_status"

    # Optional: add a short delay before restarting to prevent rapid restart loops
    sleep 1

    echo "SAMBA.SH:  $(date): Restarting smbd..."
done &
disown


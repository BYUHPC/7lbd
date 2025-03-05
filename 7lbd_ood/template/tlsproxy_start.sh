#!/usr/bin/env bash

fd=$1
connect=$2

export stunnelconf_path="${OODPROXY_DIR}/stunnel.conf"
cat > "$stunnelconf_path" <<EOL
foreground = yes
pid =
debug = 5
fips = yes

[fd]
#stunnel will use sd_listen_fds (https://www.freedesktop.org/software/systemd/man/latest/sd_listen_fds.html) if configured but, at present, it is completely undocumented.
#Set up the environment for sd_listen_fds then set 'accept' in the conf file to be empty
accept =
CAfile = ${OODPROXY_DIR}/ca+client.crt
cert = ${OODPROXY_DIR}/server.crt
key = ${OODPROXY_DIR}/server.key
requireCert = yes
verifyChain = yes
verifyPeer = yes
connect = $connect
EOL

# sd_listen_fds requires that the fd be available on fd 3
exec 3>&-
exec 3>&"$fd"-

#Why not just use the bash builtin `exec`, you ask? In my testing, it does a fork before exec.
#LISTEN_PID must be set to stunnel's pid, which is only possible if it does not fork before exec.
#This method using perl was easy enough, though maybe there's a more "correct" way to do this.
exec perl -e '$ENV{LISTEN_FDS}=1; $ENV{LISTEN_PID}=$$; exec("stunnel", $ENV{stunnelconf_path});'

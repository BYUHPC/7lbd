#!/bin/bash
set -e  # Exit on any error

################################################################
#                     Pre-flight checks                         #
################################################################
echo "Running pre-flight checks..."

# Check if we have internet access
echo "Checking internet connectivity..."
if ! ping -c 1 apache.org &>/dev/null; then
    echo "ERROR: No internet connection detected. Please check your network connection."
    exit 1
fi

# Check if apptainer can be loaded and run
echo "Loading apptainer environment"
module load spack
spack load apptainer

echo "Checking apptainer availability..."
if ! spack load apptainer 2>/dev/null || ! command -v apptainer &>/dev/null; then
    echo "ERROR: Unable to load or run apptainer. Please check your environment setup."
    exit 1
fi

# Check if npm is installed and available
echo "Checking for npm..."
if ! command -v npm &>/dev/null; then
    echo "ERROR: npm is not installed or not in PATH. Please install Node.js and npm."
    exit 1
fi

# Check if wget is available
echo "Checking for wget..."
if ! command -v wget &>/dev/null; then
    echo "ERROR: wget is not installed. Please install wget to download required files."
    exit 1
fi

# Check if gcc is available
echo "Checking for gcc..."
if ! command -v gcc &>/dev/null; then
    echo "ERROR: gcc is not installed. Please install gcc to compile the FIPS override."
    exit 1
fi

# Check if we have write permissions in current directory
echo "Checking write permissions..."
if ! touch .write_test 2>/dev/null; then
    echo "ERROR: No write permissions in current directory."
    exit 1
else
    rm .write_test
fi

echo "All pre-flight checks passed successfully!"

################################################################
#     Download guacd container and convert to apptainer        #
################################################################
echo "Pulling guacd container"
apptainer pull docker://guacamole/guacd

################################################################
#  Download and install guacamole client code for 7lbd client  #
################################################################
# Set Guacamole client version - update this when new versions are released
GUAC_CLIENT_VERSION="1.5.5"

# Create the destination directory
echo "Creating guacamole client directory"
mkdir -p public/js/guacamole

# Download both the source and checksum files
echo "Downloading guacamole client code"
wget "https://dlcdn.apache.org/guacamole/${GUAC_CLIENT_VERSION}/source/guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz"
wget "https://dlcdn.apache.org/guacamole/${GUAC_CLIENT_VERSION}/source/guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz.sha256"

# Verify the checksum
echo "Verifying guacamole client checksum"
if ! sha256sum -c "guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz.sha256"; then
    echo "ERROR: Checksum verification failed. The download might be corrupted or tampered with."
    rm "guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz"*
    exit 1
fi

# If checksum passes, proceed with extraction and copying
echo "Uncompressing guacamole client code and extracting js files to client directory"
tar xzf "guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz" && \
cp "guacamole-client-${GUAC_CLIENT_VERSION}/guacamole-common-js/src/main/webapp/modules/"* public/js/guacamole/ && \
rm -f "guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz" "guacamole-client-${GUAC_CLIENT_VERSION}.tar.gz.sha256" && \
rm -rf "guacamole-client-${GUAC_CLIENT_VERSION}"

################################################################
#                      Build 7lbd server                       #
################################################################
# Only run npm init if package.json doesn't exist
if [ ! -f package.json ]; then
    echo "Initializing npm project"
    npm init -y
fi

echo "Installing dependencies"
npm install express guacamole-lite


################################################################
#              Build GNUTLS FIPS Override                      #
################################################################
echo "Building GNUTLS FIPS override..."

# Check if source file exists
if [ ! -f "gnutls_fips_override/gnutls_fips_override.c" ]; then
    echo "ERROR: gnutls_fips_override.c not found in gnutls_fips_override directory!"
    exit 1
fi

# Compile the shared object
echo "Compiling gnutls_fips_override.so..."
gcc -shared -o gnutls_fips_override/gnutls_fips_override.so -fPIC gnutls_fips_override/gnutls_fips_override.c

# Check if compilation was successful
if [ ! -f "gnutls_fips_override/gnutls_fips_override.so" ]; then
    echo "ERROR: Failed to compile gnutls_fips_override.so!"
    exit 1
fi

################################################################
#              Post-installation verification                  #
################################################################
echo "Running post-installation checks..."

# Check for guacd container
if [ ! -f "guacd_latest.sif" ]; then
    echo "ERROR: guacd container file not found!"
    exit 1
fi

# Check for guacamole client files
REQUIRED_CLIENT_FILES=(
    "public/js/guacamole/ArrayBufferReader.js"
    "public/js/guacamole/ArrayBufferWriter.js"
    "public/js/guacamole/AudioContextFactory.js"
    "public/js/guacamole/AudioPlayer.js"
    "public/js/guacamole/AudioRecorder.js"
    "public/js/guacamole/BlobReader.js"
    "public/js/guacamole/BlobWriter.js"
    "public/js/guacamole/Client.js"
    "public/js/guacamole/DataURIReader.js"
    "public/js/guacamole/Display.js"
    "public/js/guacamole/Event.js"
    "public/js/guacamole/InputSink.js"
    "public/js/guacamole/InputStream.js"
    "public/js/guacamole/IntegerPool.js"
    "public/js/guacamole/JSONReader.js"
    "public/js/guacamole/Keyboard.js"
    "public/js/guacamole/Layer.js"
    "public/js/guacamole/Mouse.js"
    "public/js/guacamole/Namespace.js"
    "public/js/guacamole/Object.js"
    "public/js/guacamole/OnScreenKeyboard.js"
    "public/js/guacamole/OutputStream.js"
    "public/js/guacamole/Parser.js"
    "public/js/guacamole/Position.js"
    "public/js/guacamole/RawAudioFormat.js"
    "public/js/guacamole/SessionRecording.js"
    "public/js/guacamole/Status.js"
    "public/js/guacamole/StringReader.js"
    "public/js/guacamole/StringWriter.js"
    "public/js/guacamole/Touch.js"
    "public/js/guacamole/Tunnel.js"
    "public/js/guacamole/UTF8Parser.js"
    "public/js/guacamole/Version.js"
    "public/js/guacamole/VideoPlayer.js"
)

echo "Verifying guacamole client files..."
MISSING_FILES=0
for file in "${REQUIRED_CLIENT_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required guacamole client file not found: $file"
        MISSING_FILES=1
    fi
done

if [ $MISSING_FILES -eq 1 ]; then
    echo "ERROR: Some required guacamole client files are missing!"
    exit 1
fi

# Check for npm dependencies in node_modules
echo "Verifying npm dependencies..."
REQUIRED_MODULES=(
    "express"
    "guacamole-lite"
)

MISSING_MODULES=0
for module in "${REQUIRED_MODULES[@]}"; do
    if [ ! -d "node_modules/$module" ]; then
        echo "ERROR: Required npm module not found: $module"
        MISSING_MODULES=1
    fi
done

if [ $MISSING_MODULES -eq 1 ]; then
    echo "ERROR: Some required external npm modules are missing!"
    exit 1
fi

# Check if package.json exists and contains required dependencies
if [ ! -f "package.json" ]; then
    echo "ERROR: package.json not found!"
    exit 1
fi

# Check for GNUTLS FIPS override shared object
echo "Verifying GNUTLS FIPS override compilation..."
if [ ! -f "gnutls_fips_override/gnutls_fips_override.so" ]; then
    echo "ERROR: gnutls_fips_override.so not found!"
    exit 1
fi

# Verify it's a valid shared object
if ! file "gnutls_fips_override/gnutls_fips_override.so" | grep -q "shared object"; then
    echo "ERROR: gnutls_fips_override.so is not a valid shared object!"
    exit 1
fi

echo "✓ All post-installation checks passed successfully!"
echo "Installation completed successfully!"

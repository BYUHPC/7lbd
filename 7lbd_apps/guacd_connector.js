const express = require('express');
const http = require('http');
const GuacamoleLite = require('guacamole-lite');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// Check for configuration file argument
if (process.argv.length < 3) {
    console.error('Usage: node guacd_connector.js <config_file>');
    console.error('Example: node guacd_connector.js guacd_rdp.json');
    process.exit(1);
}

const configFileName = process.argv[2];
const protocolNameMatch = configFileName.match(/^guacd_(\w+)\.json$/);
if (!protocolNameMatch) {
    console.error('Configuration filename does not match expected format: guacd_<protocol>.json');
    process.exit(1);
}
const protocolName = protocolNameMatch[1];
const credentialsFileName = `${protocolName}_credentials`;

const app = express();
const server = http.createServer(app);
const listeningfd = process.env.SPANK_ISO_NETNS_LISTENING_FD_0 || -1;
const port = parseInt(process.env.SPANK_ISO_NETNS_LISTENING_PORT_0, 10) || 8080;

// Validate and sanitize the script_path environment variable
const scriptPath = process.env.script_path;
if (!scriptPath) {
    console.error('Environment variable script_path is not defined.');
    process.exit(1);
}
const resolvedScriptPath = path.resolve(scriptPath);
try {
    const stats = fs.statSync(resolvedScriptPath);
    if (!stats.isDirectory()) {
        throw new Error('script_path is not a directory');
    }
} catch (error) {
    console.error(`Invalid script_path: ${error.message}`);
    process.exit(1);
}

// Helper function for consistent logging
function log(message, error = false) {
    const prefix = `GUACD_CONNECTOR: (${configFileName})`;
    if (error) {
        console.error(`${prefix} ${message}`);
    } else {
        console.log(`${prefix} ${message}`);
    }
}

log(`SPANK_ISO_NETNS_LISTENING_FD_0: ${listeningfd}`);
log(`SPANK_ISO_NETNS_LISTENING_PORT_0: ${port}`);
log(`script_path: ${resolvedScriptPath}`);

// Load configuration files using the validated script_path
let credentials;
let connectionConfig;
try {
    // Load protocol-specific credentials
    const credentialsPath = path.join(resolvedScriptPath, credentialsFileName);
    log(`Attempting to load credentials from: ${credentialsPath}`);
    const credentialsContent = fs.readFileSync(credentialsPath, 'utf8');
    credentials = JSON.parse(credentialsContent);
    log('Credentials loaded successfully');

    // Load connection configuration
    const configPath = path.join(resolvedScriptPath, configFileName);
    log(`Attempting to load configuration from: ${configPath}`);
    const configContent = fs.readFileSync(configPath, 'utf8');
    connectionConfig = JSON.parse(configContent);
    log('Connection configuration loaded successfully');
} catch (error) {
    log(`Error reading configuration: ${error.message}`, true);
    process.exit(1);
}

// Define clientOptions and guacdOptions using loaded configuration
const clientOptions = {
    crypt: {
        // We'll use AES-256-CBC for encryption, compatible with existing Guacamole code.
        cypher: 'AES-256-CBC',
        key: credentials.guac_key
    },
    log: {
        level: connectionConfig.logLevel || 'ERRORS'
    }
};

const guacdOptions = {
    port: connectionConfig.guacd?.port || 4822
};

// Validate that the provided encryption key is exactly 32 bytes long.
const providedKeyBuffer = Buffer.from(clientOptions.crypt.key, 'utf8');
if (providedKeyBuffer.length !== 32) {
    console.error(`Invalid encryption key length: expected 32 bytes, got ${providedKeyBuffer.length}.`);
    process.exit(1);
}

// Middleware to extract and handle proxied traffic (if needed)
app.use((req, res, next) => {
    const basePathMatch = req.originalUrl.match(/\/node\/([^\/]+)\/(\d+)\//);
    if (basePathMatch) {
        const proxyServer = basePathMatch[1];
        const proxyPort = basePathMatch[2];
        req.basePath = `/node/${proxyServer}/${proxyPort}`;
    }
    next();
});

// Pre-register static file middleware once during initialization
const staticPath = path.join(__dirname, 'public');
app.use('/node/:server/:port', express.static(staticPath));
app.use(express.static(staticPath));

// Add middleware to parse JSON bodies for POST requests
app.use(express.json());

// Middleware to validate the authtoken for sensitive routes
function validateAuthtoken(req, res, next) {
    // Now check the authtoken from the POST body
    const authtoken = req.body.authtoken;
    if (!authtoken || authtoken !== credentials.authtoken) {
        log('Unauthorized access attempt with invalid or missing authtoken', true);
        return res.status(403).json({ error: 'Forbidden: Invalid or missing authtoken' });
    }
    next();
}

// Route to serve token generation for proxy requests (using POST)
app.post('/node/:server/:port/getToken', validateAuthtoken, handleGetToken);

// Serve the index.html file for proxied access
app.get('/node/:server/:port/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

/**
 * Encrypts the Guacamole connection configuration token using AES-256-CBC.
 * Expects the encryption key to be exactly 32 bytes long.
 * The token format is a base64-encoded JSON object with an IV and ciphertext.
 */
function encryptToken(data) {
    try {
        // The provided key is already validated to be 32 bytes.
        const keyBuffer = Buffer.from(clientOptions.crypt.key, 'utf8');
        // Generate a 16-byte IV for AES-256-CBC.
        const iv = crypto.randomBytes(16);
        const cipher = crypto.createCipheriv('aes-256-cbc', keyBuffer, iv);
        let encrypted = cipher.update(JSON.stringify(data), 'utf8', 'binary');
        encrypted += cipher.final('binary');
        // Package the IV and ciphertext in a JSON object, then base64 encode it.
        return Buffer.from(JSON.stringify({
            iv: iv.toString('base64'),
            value: Buffer.from(encrypted, 'binary').toString('base64')
        })).toString('base64');
    } catch (error) {
        log(`Error encrypting token: ${error.message}`, true);
        throw error;
    }
}

/**
 * Decrypts the Guacamole connection configuration token using AES-256-CBC.
 * Expects a base64-encoded JSON token containing the IV and ciphertext.
 */
function decryptToken(token) {
    try {
        const decodedToken = Buffer.from(decodeURIComponent(token), 'base64').toString('utf8');
        const parsedToken = JSON.parse(decodedToken);
        const keyBuffer = Buffer.from(clientOptions.crypt.key, 'utf8');
        const iv = Buffer.from(parsedToken.iv, 'base64');
        const decipher = crypto.createDecipheriv('aes-256-cbc', keyBuffer, iv);
        let decrypted = decipher.update(Buffer.from(parsedToken.value, 'base64'), 'binary', 'utf8');
        decrypted += decipher.final('utf8');
        return JSON.parse(decrypted);
    } catch (error) {
        log(`Error in decryptToken: ${error.message}`, true);
        throw error;
    }
}

/**
 * Handles token generation for proxy requests by encrypting the Guacamole connection configuration.
 * This token is then sent back to the client.
 */
function handleGetToken(req, res) {
    // Use POST body parameters instead of query parameters
    const width = req.body.width || connectionConfig.defaultWidth || 1920;
    const height = req.body.height || connectionConfig.defaultHeight || 1080;

    // Create connection configuration.
    const config = {
        connection: {
            type: connectionConfig.type,
            settings: {
                ...connectionConfig.settings,
                width: width,
                height: height
            }
        }
    };

    // Add credentials if specified in the configuration.
    if (connectionConfig.useCredentials) {
        config.connection.settings.username = credentials.username;
        config.connection.settings.password = credentials.password;
    }

    try {
        const token = encryptToken(config);
        res.setHeader('Content-Type', 'application/json');
        res.send(JSON.stringify({ token: token }));
    } catch (error) {
        log(`Error generating token: ${error.message}`, true);
        res.status(500).json({ error: 'Failed to generate token' });
    }
}

const guacServer = new GuacamoleLite({ server: server }, guacdOptions, clientOptions);

// Start server based on listeningfd value.
if (listeningfd === 'use-insecure-testing-port') {
    server.listen(port, () => {
        log(`Server is running in insecure testing mode on port ${port}`);
    }).on('error', (error) => {
        log(`Error starting server: ${error.message}`, true);
        process.exit(1);
    });
} else {
    const fd = parseInt(listeningfd, 10);
    if (isNaN(fd)) {
        log('Invalid file descriptor value', true);
        process.exit(1);
    }
    server.listen({ fd: fd }, () => {
        log('Server is running on the passed-in socket.');
    }).on('error', (error) => {
        log(`Error starting server: ${error.message}`, true);
        process.exit(1);
    });
}


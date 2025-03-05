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
// Extract protocol name from config filename and create credentials filename
const protocolName = configFileName.match(/guacd_(\w+)\.json/)[1];
const credentialsFileName = `${protocolName}_credentials`;

const app = express();
const server = http.createServer(app);
const listeningfd = process.env.SPANK_ISO_NETNS_LISTENING_FD_0 || -1;
const port = parseInt(process.env.SPANK_ISO_NETNS_LISTENING_PORT_0, 10) || 8080;
const scriptPath = process.env.script_path;

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
log(`script_path: ${scriptPath}`);

// Load configuration files
let credentials;
let connectionConfig;
try {
    // Load protocol-specific credentials
    const credentialsPath = path.join(scriptPath, credentialsFileName);
    log(`Attempting to load credentials from: ${credentialsPath}`);
    const credentialsContent = fs.readFileSync(credentialsPath, 'utf8');
    credentials = JSON.parse(credentialsContent);
    log('Credentials loaded successfully');

    // Load connection configuration
    const configPath = path.join(scriptPath, configFileName);
    log(`Attempting to load configuration from: ${configPath}`);
    const configContent = fs.readFileSync(configPath, 'utf8');
    connectionConfig = JSON.parse(configContent);
    log('Connection configuration loaded successfully');
} catch (error) {
    log(`Error reading configuration: ${error.message}`, true);
    process.exit(1);
}

// Middleware to extract and handle proxied traffic
app.use((req, res, next) => {
    const basePathMatch = req.originalUrl.match(/\/node\/([^\/]+)\/(\d+)\//);
    if (basePathMatch) {
        const proxyServer = basePathMatch[1];
        const proxyPort = basePathMatch[2];
        req.basePath = `/node/${proxyServer}/${proxyPort}`;
    }
    next();
});

// Serve static files for proxy path
app.use((req, res, next) => {
    const staticPath = path.join(__dirname, 'public');
    console.log("Request path:", req.path, "basePath:", req.basePath); // Add logging
    if (req.basePath) {
        app.use(req.basePath, express.static(staticPath));
    } else {
        // Serve static files at the root if no basePath
        app.use(express.static(staticPath));
    }
    next();
});

const guacdOptions = {
    port: connectionConfig.guacd?.port || 4822
};

const clientOptions = {
    crypt: {
        cypher: credentials.cypher || 'AES-256-CBC',
        key: credentials.guac_key
    },
    log: {
        level: connectionConfig.logLevel || 'ERRORS'
    }
};

// Handle token generation for proxy requests
app.get('/node/:server/:port/getToken', validateAuthtoken, handleGetToken);

// Serve the index.html file for proxied access
app.get('/node/:server/:port/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Middleware to validate the authtoken
function validateAuthtoken(req, res, next) {
    const authtoken = req.query.authtoken;

    if (!authtoken || authtoken !== credentials.authtoken) {
        log('Unauthorized access attempt with invalid or missing authtoken', true);
        return res.status(403).json({ error: 'Forbidden: Invalid or missing authtoken' });
    }
    next();
}

function encryptToken(data) {
    try {
        const iv = crypto.randomBytes(16);
        const cipher = crypto.createCipheriv(clientOptions.crypt.cypher, Buffer.from(clientOptions.crypt.key), iv);
        let encrypted = cipher.update(JSON.stringify(data), 'utf8', 'binary');
        encrypted += cipher.final('binary');

        return Buffer.from(JSON.stringify({
            iv: iv.toString('base64'),
            value: Buffer.from(encrypted, 'binary').toString('base64')
        })).toString('base64');
    } catch (error) {
        log(`Error encrypting token: ${error.message}`, true);
        throw error;
    }
}

function decryptToken(token) {
    try {
        const decodedToken = decodeURIComponent(token);
        const tokenBuffer = Buffer.from(decodedToken, 'base64');
        const tokenString = tokenBuffer.toString('utf8');
        const parsedToken = JSON.parse(tokenString);

        const decipher = crypto.createDecipheriv(
            clientOptions.crypt.cypher,
            Buffer.from(clientOptions.crypt.key),
            Buffer.from(parsedToken.iv, 'base64')
        );
        let decrypted = decipher.update(parsedToken.value, 'base64', 'utf8');
        decrypted += decipher.final('utf8');
        decrypted = decrypted.replace(/\0+$/, '');

        return JSON.parse(decrypted);
    } catch (error) {
        log(`Error in decryptToken: ${error.message}`, true);
        throw error;
    }
}

function handleGetToken(req, res) {
    const width = req.query.width || connectionConfig.defaultWidth || 1920;
    const height = req.query.height || connectionConfig.defaultHeight || 1080;

    // Create connection configuration
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

    // Add credentials if specified in the configuration
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

// Create GuacamoleLite instance
const guacServer = new GuacamoleLite({
    server: server,
}, guacdOptions, clientOptions);

// Start server based on listeningfd value
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

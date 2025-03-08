let client;

document.addEventListener('DOMContentLoaded', function() {
    console.log("DOMContentLoaded event fired.");
    const margin = 20;
    const width = window.innerWidth - margin;
    const height = window.innerHeight - margin;

    createLoadingDisplay();

    // Determine the proxy path and set up the token URL
    const proxyPathMatch = window.location.pathname.match(/\/node\/([^\/]+)\/(\d+)\//);
    if (!proxyPathMatch) {
        handleError('Proxy path not found in the URL');
        return;
    }

    // Get the authtoken from the URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const authtoken = urlParams.get('authtoken');
    if (!authtoken) {
        handleError('No authtoken provided in the URL');
        return;
    }

    // Construct the getToken URL without sensitive data in the query string
    const getTokenUrl = `${window.location.origin}${proxyPathMatch[0]}getToken`;
    console.log("Attempting to fetch token from URL:", getTokenUrl);

    // Use POST to send authtoken, width, and height in the request body
    fetch(getTokenUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            authtoken: authtoken,
            width: width,
            height: height
        })
    })
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        return response.text();
    })
    .then(text => {
        console.log('Raw response text:', text);
        const data = JSON.parse(text);
        if (!data || !data.token) {
            throw new Error('No token received from server');
        }
        const token = encodeURIComponent(data.token);
        console.log('Token received and encoded:', token);

        // Build the WebSocket URL using the proxy path
        const websocketUrl = `wss://${window.location.host}${proxyPathMatch[0]}?token=${token}&dpi=24&`;
        console.log("Attempting to connect to WebSocket URL:", websocketUrl);

        // Create the tunnel
        const tunnel = new Guacamole.WebSocketTunnel(websocketUrl);

        // Tunnel error handler
        tunnel.onerror = function(status) {
            handleError("Tunnel error:", JSON.stringify(status));
        };

        // Create the Guacamole client
        client = new Guacamole.Client(tunnel);

        // Append the display element to the page
        const display = document.getElementById("display");
        display.appendChild(client.getDisplay().getElement());

        // Force remote cursor and hide the local cursor
        client.getDisplay().useRemoteCursor = true;
        client.getDisplay().showCursor(false);

        // Client error handler
        client.onerror = function(error) {
            handleError("Client error:", JSON.stringify(error));
        };

        // Track client state changes
        client.onstatechange = function(state) {
            console.log("Client state changed to:", state);
            switch(state) {
                case 1:
                    updateLoadStateDesc("Connecting to the remote session...");
                    break;
                case 2:
                    updateLoadStateDesc("Waiting for the remote session...");
                    break;
                case 3:
                    updateLoadStateDesc("Connection established.");
                    destroyLoadingDisplay();
                    break;
                case 4:
                    updateLoadStateDesc("Disconnecting...");
                    break;
                case 5:
                    updateLoadStateDesc("Disconnected.");
                    updateLoadingDesc("Disconnected from remote session.");
                    break;
            }
        };

        // *** MOUSE AND KEYBOARD INPUT HANDLING ***
        // Hide/show remote cursor when mouse leaves/enters the window
        display.addEventListener("mouseleave", function(event) {
            hideRemoteCursor();
        });
        display.addEventListener("mouseenter", function(event) {
            showRemoteCursor();
        });
        
        // Hide/show remote cursor when mouse hovers over error divs
        ["error-display", "toggle-error-display"].forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.addEventListener("mouseenter", function(event) {
                    hideRemoteCursor();
                });
                element.addEventListener("mouseleave", function(event) {
                    showRemoteCursor();
                });
            }
        });

        // Keyboard input handling
        const keyboard = new Guacamole.Keyboard(document);
        keyboard.onkeydown = function(keysym) {
            client.sendKeyEvent(1, keysym); // key press
        };
        keyboard.onkeyup = function(keysym) {
            client.sendKeyEvent(0, keysym); // key release
        };

        // Mouse input handling
        const mouse = new Guacamole.Mouse(client.getDisplay().getElement());
        mouse.onmousedown = mouse.onmouseup = mouse.onmousemove = function(mouseState) {
            client.sendMouseState(mouseState);
        };

        // Connect to the Guacamole session
        console.log("Attempting to connect to Guacamole session...");
        updateLoadStateDesc("Attempting to connect to Guacamole session...");
        client.connect();

        // Disconnect the client when the window unloads
        window.onunload = function() {
            client.disconnect();
        };
    })
    .catch(error => {
        handleError('Error during fetch or WebSocket connection:', error);
    });
});

// Load Handling Functions

function createLoadingDisplay() {
    const loadingDisplay = document.createElement('div');
    const loader = document.createElement('div');
    const loadingDesc = document.createElement('p');
    const loadStateDesc = document.createElement('p');
    loadingDisplay.id = 'loading-display';
    loader.id = 'loader';
    loadingDesc.id = 'loading-desc';
    loadingDesc.textContent = "Loading. Please be patient as this can take a few minutes.";
    loadStateDesc.id = 'load-state-desc';

    loadingDisplay.appendChild(loader);
    loadingDisplay.appendChild(loadingDesc);
    loadingDisplay.appendChild(loadStateDesc);
    document.body.appendChild(loadingDisplay);
}

function updateLoadStateDesc(update) {
    const loadStateDesc = document.getElementById('load-state-desc');
    if (loadStateDesc) {
        update = prependTimestamp(update);
        loadStateDesc.innerHTML += `<code>${update}</code><br>`;
    }
}

function updateLoadingDesc(update) {
    const loadingDesc = document.getElementById('loading-desc');
    if (loadingDesc) {
        loadingDesc.textContent = update;
    }
}

function destroyLoadingDisplay() {
    const loadingDisplay = document.getElementById('loading-display');
    if (loadingDisplay) {
        loadingDisplay.remove();
    }
}

// Error Handling Functions

function createErrorDisplay() {
    const errorDisplay = document.createElement('div');
    errorDisplay.id = 'error-display';
    errorDisplay.className = 'windows';
    errorDisplay.style.visibility = "hidden";

    const toggleErrorDisplayButton = document.createElement('button');
    toggleErrorDisplayButton.id = 'toggle-error-display';
    toggleErrorDisplayButton.textContent = "!";
    document.body.appendChild(toggleErrorDisplayButton);
    
    const dismissAllButton = document.createElement('button');
    dismissAllButton.className = 'dismiss-all-error-button';
    dismissAllButton.textContent = "Dismiss All";

    errorDisplay.appendChild(dismissAllButton);
    document.body.appendChild(errorDisplay);

    toggleErrorDisplayButton.addEventListener('click', function() {
        const errorDisplay = document.getElementById('error-display');
        if (!errorDisplay) {
            console.error("this should not have happened");
            return;
        }
        if (errorDisplay.style.visibility === 'hidden') {
            errorDisplay.style.visibility = 'visible';
            this.textContent = "—";
        } else if (errorDisplay.style.visibility === 'visible') {
            errorDisplay.style.visibility = 'hidden';
            this.textContent = "!";
        }
    });
    dismissAllButton.addEventListener('click', function() {
        destroyErrorDisplay();
    });

    return errorDisplay;
}

function createNewErrorEntry(error) {
    let errorDisplay = document.getElementById('error-display');
    if (!errorDisplay) {
        errorDisplay = createErrorDisplay();
    }
    const dismissButton = document.createElement('button');
    dismissButton.className = 'dismiss-error-button';
    dismissButton.textContent = "Dismiss";

    const errorEntry = document.createElement('div');
    errorEntry.className = 'error-entry';
    const errorEntryDescription = document.createElement('p');
    errorEntryDescription.className = 'error-entry-description';
    errorEntryDescription.innerHTML = `<code>${error}</code>`;
    
    errorEntry.appendChild(errorEntryDescription);
    errorEntry.appendChild(dismissButton);
    errorDisplay.prepend(errorEntry);

    dismissButton.addEventListener('click', function() {
        this.parentElement.remove();
        if (document.getElementsByClassName("error-entry").length === 0) {
            destroyErrorDisplay();
        }
    });
    
    blinkErrorDisplayToggle();
}

function handleError(...args) {
    const error = prependTimestamp(args.join(' '));
    console.error(error);
    const loadStateDesc = document.getElementById('load-state-desc');
    if (loadStateDesc) {
        loadStateDesc.innerHTML += `<code class='error-code'>${error}</code>`;
        document.getElementById('loader').style.animation = "none";
    } else {
        createNewErrorEntry(error);
    }
}

function destroyErrorDisplay() {
    const errorDisplay = document.getElementById("error-display");
    if (errorDisplay) {
        errorDisplay.remove();
    }
    const toggleErrorDisplayButton = document.getElementById('toggle-error-display');
    if (toggleErrorDisplayButton) {
        toggleErrorDisplayButton.remove();
    }
}

function prependTimestamp(text) {
    const now = new Date();
    const date = now.toLocaleDateString();
    const time = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}.${now.getMilliseconds().toString().padStart(3, '0')}`;
    const timestamp = `[${date} ${time}]`;
    return `${timestamp} ${text}`;
}

function blinkErrorDisplayToggle() {
    const errorDisplayToggle = document.getElementById('toggle-error-display');
    if (!errorDisplayToggle) {
        return;
    }

    let blinkCount = 0;
    const maxBlinks = 4;
    const interval = 100;

    const blinkInterval = setInterval(() => {
        errorDisplayToggle.style.visibility = errorDisplayToggle.style.visibility === 'hidden' ? 'visible' : 'hidden';
        blinkCount++;

        if (blinkCount >= maxBlinks * 2) {
            clearInterval(blinkInterval);
            errorDisplayToggle.style.visibility = 'visible';
        }
    }, interval);
}

function hideRemoteCursor() {
    client.getDisplay().showCursor(false);
}

function showRemoteCursor() {
    client.getDisplay().showCursor(true);
}


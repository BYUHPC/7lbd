//only has one route.  Not hardcoded to a particular proxy server
//has new code for handling authTokens

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
        // console.error('Proxy path not found in the URL');
        handleError('Proxy path not found in the URL');
        return;
    }

    // Get the authtoken from the URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const authtoken = urlParams.get('authtoken');
    if (!authtoken) {
        // console.error('No authtoken provided in the URL');
        handleError('No authtoken provided in the URL');
        return;
    }

    // Append authtoken to the getToken URL
    const getTokenUrl = `${window.location.origin}${proxyPathMatch[0]}getToken?width=${width}&height=${height}&authtoken=${encodeURIComponent(authtoken)}`;
    console.log("Attempting to fetch token from URL:", getTokenUrl);

    fetch(getTokenUrl)
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

            // WebSocket URL using the proxy path
            const websocketUrl = `wss://${window.location.host}${proxyPathMatch[0]}?token=${token}&dpi=24&`;
            console.log("Attempting to connect to WebSocket URL:", websocketUrl);

            // Create tunnel
            const tunnel = new Guacamole.WebSocketTunnel(websocketUrl);

            // Error handler for tunnel
            tunnel.onerror = function(status) {
                // console.error("Tunnel error:", JSON.stringify(status));
                handleError("Tunnel error:", JSON.stringify(status));
            };

            // Create Guacamole client
            client = new Guacamole.Client(tunnel);

            // Add the display to the HTML
            const display = document.getElementById("display");
            display.appendChild(client.getDisplay().getElement());

            // Force remote cursor
            client.getDisplay().useRemoteCursor = true;
            client.getDisplay().showCursor(false); // This hides the local cursor

            // Add client error handler
            client.onerror = function(error) {
                // console.error("Client error:", JSON.stringify(error));
                handleError("Client error:", JSON.stringify(error));
            };

            // Track client state changes
            client.onstatechange = function(state) {
                console.log("Client state changed to:", state);
                switch(state){
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
            // Hide/show remote cursor when mouse leaves window
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
                client.sendKeyEvent(1, keysym); // Send key press to Guacamole client
            };
            keyboard.onkeyup = function(keysym) {
                client.sendKeyEvent(0, keysym); // Send key release to Guacamole client
            };

            // Mouse input handling
            const mouse = new Guacamole.Mouse(client.getDisplay().getElement());
            mouse.onmousedown = mouse.onmouseup = mouse.onmousemove = function(mouseState) {
                client.sendMouseState(mouseState); // Send mouse state to Guacamole client
            };

            // Connect to the Guacamole session
            console.log("Attempting to connect to Guacamole session...");
            updateLoadStateDesc("Attempting to connect to Guacamole session...");
            client.connect();

            // Disconnect on window unload
            window.onunload = function() {
                client.disconnect();
            };
        })
        .catch(error => {
            // console.error('Error during fetch or WebSocket connection:', error);
            handleError('Error during fetch or WebSocket connection:', error);
        });
});

// Load Handling
function createLoadingDisplay() {
    const loadingDisplay = document.createElement('div');
    const loader = document.createElement('div');
    const loadingDesc = document.createElement('p');
    const loadStateDesc = document.createElement('p');
    loadingDisplay.id = 'loading-display';
    loader.id = 'loader';
    loadingDesc.id = 'loading-desc';
    loadingDesc.textContent = "Loading. Please be patient as this can take a few minutes."
    loadStateDesc.id = 'load-state-desc';

    loadingDisplay.appendChild(loader);
    loadingDisplay.appendChild(loadingDesc);
    loadingDisplay.appendChild(loadStateDesc);
    document.body.appendChild(loadingDisplay);
}
function updateLoadStateDesc(update) {
    const loadStateDesc = document.getElementById('load-state-desc');
    if(loadStateDesc){
        update = prependTimestamp(update);
        loadStateDesc.innerHTML += `<code>${update}</code><br>`;
    }
}
function updateLoadingDesc(update) {
    const loadingDesc = document.getElementById('loading-desc');
    if(loadingDesc){
        update = update;
        loadingDesc.textContent = update;
    }
}
function destroyLoadingDisplay() {
    const loadingDisplay = document.getElementById('loading-display');
    if (loadingDisplay){
        loadingDisplay.remove(); 
    }
}

// Error Handling
function createErrorDisplay(){

// Create container for all error entries
    const errorDisplay = document.createElement('div');
    errorDisplay.id = 'error-display';
    errorDisplay.className = 'windows';
    errorDisplay.style.visibility = "hidden";

// Create button to show/hide all errors
    const toggleErrorDisplayButton = document.createElement('button');
    toggleErrorDisplayButton.id = 'toggle-error-display';
    toggleErrorDisplayButton.textContent = "!";
    document.body.appendChild(toggleErrorDisplayButton);
    
// Create button to dismiss all errors
    const dismissAllButton = document.createElement('button');
    dismissAllButton.className = 'dismiss-all-error-button';
    dismissAllButton.textContent = "Dismiss All";

    errorDisplay.appendChild(dismissAllButton)
    document.body.appendChild(errorDisplay);

    toggleErrorDisplayButton.addEventListener('click', function() {
        const errorDisplay = document.getElementById('error-display');
        if(!errorDisplay){
            console.error("this should not have happened");
            return;
        }
        if(errorDisplay.style.visibility == 'hidden') {
            errorDisplay.style.visibility = 'visible';
            this.textContent = "—";
        }else if(errorDisplay.style.visibility == 'visible'){
            errorDisplay.style.visibility = 'hidden';
            this.textContent = "!";
        }
    });
    dismissAllButton.addEventListener('click', function() {
        destroyErrorDisplay();
    });

    return errorDisplay;
}
function createNewErrorEntry(error){
    let errorDisplay = document.getElementById('error-display');
    if(!errorDisplay){
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
        // Destroy error entry
        this.parentElement.remove();
        
        // If there are no more error entries, destroy the error display
        if(document.getElementsByClassName("error-entry").length == 0){
            destroyErrorDisplay();
        }
    });
    
    blinkErrorDisplayToggle();
}
function handleError(...args) {
    error = prependTimestamp(args.join(' '));
    console.error(error);
    loadStateDesc = document.getElementById('load-state-desc');
    if(loadStateDesc){
        loadStateDesc.innerHTML += `<code class='error-code'>${error}</code>`;
        document.getElementById('loader').style.animation = "none";
    }else{
        createNewErrorEntry(error);
    }
}

function destroyErrorDisplay() {
    // Destroy error display
    const errorDisplay = document.getElementById("error-display");
    if(errorDisplay){ errorDisplay.remove(); }
    
    // If all errors are dismissed, then there should be no toggle error display button
    const toggleErrorDisplayButton = document.getElementById('toggle-error-display');
    if(toggleErrorDisplayButton){ toggleErrorDisplayButton.remove(); }
}
function prependTimestamp(text){
    const now = new Date();
    const date = now.toLocaleDateString();  // Format the date
    const time = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}.${now.getMilliseconds().toString().padStart(3, '0')}`;  // Format the time with milliseconds
    const timestamp = `[${date} ${time}]`;  // Create timestamp
    return `${timestamp} ${text}`;  // Prepend timestamp to original text
}
function blinkErrorDisplayToggle() {
    const errorDisplayToggle = document.getElementById('toggle-error-display');
    if(!errorDisplayToggle){
        return;
    }

    let blinkCount = 0;
    const maxBlinks = 4;
    const interval = 100; // Set interval to 100 ms for quick blinking

    const blinkInterval = setInterval(() => {
        errorDisplayToggle.style.visibility = errorDisplayToggle.style.visibility === 'hidden' ? 'visible' : 'hidden';
        blinkCount++;

        // Stop blinking after reaching the maximum blink count
        if (blinkCount >= maxBlinks * 2) { // Multiply by 2 because it toggles twice per blink
            clearInterval(blinkInterval);
            errorDisplayToggle.style.visibility = 'visible'; // Make sure it's visible after blinking
        }
    }, interval);
}

function hideRemoteCursor() {
    client.getDisplay().showCursor(false);
}
function showRemoteCursor() {
    client.getDisplay().showCursor(true);
}

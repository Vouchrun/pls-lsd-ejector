#!/usr/bin/env bash

# working script but shows password in docker inspect, due to ENV use.

if [ "$1" == "debug" ]; then
    set -x
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

set -euo pipefail

# NETWORK SELECTION
echo ""
read -r -p "Use Mainnet or Testnet settings [Main/Test] (default: Main): " NETWORK_TYPE
NETWORK_TYPE="${NETWORK_TYPE:-Main}"
NETWORK_TYPE_LOWER=$(echo "$NETWORK_TYPE" | tr '[:upper:]' '[:lower:]')

case "$NETWORK_TYPE_LOWER" in
    m|main)
        CONFIG_PATH_DEFAULT="/blockchain/validator_keys"
        TESTNET=false
        ;;
    t|test)
        CONFIG_PATH_DEFAULT="/blockchain/validator_keys/testnet"
        TESTNET=true
        ;;
    *)
        echo "Invalid selection. Please enter 'Main' or 'Test'."
        exit 1
        ;;
esac

# CONFIG PATH (WITH TRAILING SLASH FIX)
echo ""
read -e -r -p "Enter keystore location (default)[$CONFIG_PATH_DEFAULT]: " CONFIG_PATH
CONFIG_PATH="${CONFIG_PATH:-$CONFIG_PATH_DEFAULT}"
CONFIG_PATH="${CONFIG_PATH%/}"  # REMOVE TRAILING SLASH

if [ ! -d "$CONFIG_PATH" ]; then
    echo "ERROR: Config path '$CONFIG_PATH' does not exist"
    exit 1
fi

# PASSWORD OPTION SELECTION
echo ""
echo "Select password option:"
echo "1. Start in detached mode: Use local password file (Less Secure - Supports Auto Restart)"
echo "2. Start in interactive mode (More Secure - enter password at startup)"
read -r -p "Enter option [1/2]: " PASSWORD_OPTION
PASSWORD_OPTION="${PASSWORD_OPTION:-1}"

USE_DOCKER_SECRET=false
SECRET_NAME="keystore_password"

if [ "$PASSWORD_OPTION" -eq 1 ]; then
    # PASSWORD FILE SETUP
    echo ""
    echo "Password file setup (REQUIRED for production):"
    PASSWORD_FILE_DEFAULT="$CONFIG_PATH/keystore.pwd"
    read -e -r -p "Enter password file path (default)[$PASSWORD_FILE_DEFAULT]: " PASSWORD_FILE
    PASSWORD_FILE="${PASSWORD_FILE:-$PASSWORD_FILE_DEFAULT}"
    PASSWORD_FILE="${PASSWORD_FILE%/}"  # REMOVE TRAILING SLASH

    # # SECURITY: Verify password file is within CONFIG_PATH
    # if [[ ! "$PASSWORD_FILE" =~ ^"$CONFIG_PATH" ]]; then
    #     echo -e "\033[1;31mERROR: Password file must be within keystore directory for security!\033[0m"
    #     echo "This prevents accidental exposure of passwords outside validator storage"
    #     echo "Please use default location or a subdirectory of $CONFIG_PATH"
    #     exit 1
    # fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$PASSWORD_FILE")" 2>/dev/null

    # CORRECTED PASSWORD HANDLING (NO TRAILING NEWLINE)
    if [ -f "$PASSWORD_FILE" ]; then
        read -r -p "Password file exists. Overwrite? [y/N]: " OVERWRITE
        if [[ "${OVERWRITE:0:1}" =~ ^[Yy]$ ]]; then
            echo "Overwriting password file: $PASSWORD_FILE"

            # Secure password entry with history protection (NO TRAILING NEWLINE)
            history -c
            stty -echo
            echo -n "Enter keystore password: "
            read PASS1
            stty echo
            echo
            echo -n "Confirm password: "
            stty -echo
            read PASS2
            stty echo
            echo

            if [ "$PASS1" != "$PASS2" ]; then
                echo "Passwords don't match!" >&2
                exit 1
            fi

            # Write password with STRICT security (NO TRAILING NEWLINE)
            umask 077
            printf "%s" "$PASS1" > "$PASSWORD_FILE"  # CRITICAL: NO NEWLINE
            chmod 600 "$PASSWORD_FILE"
            chown 65532:65532 "$PASSWORD_FILE"  # MATCH CONTAINER UID
            unset PASS1 PASS2
        else
            echo "Using existing password file: $PASSWORD_FILE"
            # Verify existing file has correct permissions
            if [ "$(stat -c '%a' "$PASSWORD_FILE")" != "600" ]; then
                echo -e "\033[1;33mWARNING: Password file should have 600 permissions!\033[0m"
                read -r -p "Continue anyway? [y/N]: " CONTINUE
                if [[ ! "${CONTINUE:0:1}" =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            # Verify ownership
            if [ "$(stat -c '%u' "$PASSWORD_FILE")" != "65532" ]; then
                echo -e "\033[1;33mWARNING: Password file should be owned by UID 65532!\033[0m"
                read -r -p "Fix ownership? [Y/n]: " FIX_OWNERSHIP
                FIX_OWNERSHIP="${FIX_OWNERSHIP:-y}"
                if [[ "${FIX_OWNERSHIP:0:1}" =~ ^[Yy]$ ]]; then
                    chown 65532:65532 "$PASSWORD_FILE"
                    echo "✓ Password file ownership fixed"
                fi
            fi
        fi
    else
        # Create new password file (NO TRAILING NEWLINE)
        echo "Creating password file: $PASSWORD_FILE"

        # Secure password entry with history protection
        history -c
        stty -echo
        echo -n "Enter keystore password: "
        read PASS1
        stty echo
        echo
        echo -n "Confirm password: "
        stty -echo
        read PASS2
        stty echo
        echo

        if [ "$PASS1" != "$PASS2" ]; then
            echo "Passwords don't match!" >&2
            exit 1
        fi

        # Write password with STRICT security (NO TRAILING NEWLINE)
        umask 077
        printf "%s" "$PASS1" > "$PASSWORD_FILE"  # CRITICAL: NO NEWLINE
        chmod 600 "$PASSWORD_FILE"
        chown 65532:65532 "$PASSWORD_FILE"  # MATCH CONTAINER UID
        unset PASS1 PASS2
    fi

    echo ""
    read -r -p "Would you like to use Docker Secret instead of password file? [Y/n]: " USE_SECRET_INPUT
    USE_SECRET_INPUT="${USE_SECRET_INPUT:-y}"

    if [[ ${USE_SECRET_INPUT:0:1} =~ ^[Yy]$ ]]; then
        USE_DOCKER_SECRET=true
        
        # Check if swarm is initialized
        if [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" != "active" ]; then
            echo ""
            echo "Docker Swarm is not initialized. Initializing single-node swarm..."
            docker swarm init 2>/dev/null || {
                echo -e "\033[1;33mWARNING:\033[0m Could not initialize swarm automatically"
                read -r -p "Initialize Docker Swarm manually? [Y/n]: " INIT_SWARM
                INIT_SWARM="${INIT_SWARM:-y}"
                if [[ ${INIT_SWARM:0:1} =~ ^[Yy]$ ]]; then
                    docker swarm init || {
                        echo -e "\033[1;31mERROR:\033[0m Failed to initialize Docker Swarm"
                        echo "Falling back to password file method"
                        USE_DOCKER_SECRET=false
                    }
                else
                    echo "Falling back to password file method"
                    USE_DOCKER_SECRET=false
                fi
            }
            
            if $USE_DOCKER_SECRET; then
                echo -e "\033[1;32m✓\033[0m Docker Swarm initialized successfully"
            fi
        fi

        if $USE_DOCKER_SECRET; then
            # Check if secret already exists
            if docker secret ls | grep -q "$SECRET_NAME"; then
                echo ""
                echo -e "\033[1;33mWARNING:\033[0m Docker secret '$SECRET_NAME' already exists"
                read -r -p "Remove and recreate secret? [y/N]: " RECREATE_SECRET
                if [[ ${RECREATE_SECRET:0:1} =~ ^[Yy]$ ]]; then
                    docker secret rm "$SECRET_NAME" 2>/dev/null || {
                        echo -e "\033[1;31mERROR:\033[0m Could not remove existing secret"
                        echo "Secret may be in use by running services"
                        read -r -p "Continue with existing secret? [Y/n]: " USE_EXISTING
                        USE_EXISTING="${USE_EXISTING:-y}"
                        if [[ ! ${USE_EXISTING:0:1} =~ ^[Yy]$ ]]; then
                            echo "Falling back to password file method"
                            USE_DOCKER_SECRET=false
                        fi
                    }
                fi
            fi

            # Create secret if needed
            if $USE_DOCKER_SECRET && ! docker secret ls | grep -q "$SECRET_NAME"; then
                echo "Creating Docker secret '$SECRET_NAME' from password file..."
                docker secret create "$SECRET_NAME" "$PASSWORD_FILE" || {
                    echo -e "\033[1;31mERROR:\033[0m Failed to create Docker secret"
                    echo "Falling back to password file method"
                    USE_DOCKER_SECRET=false
                }
                
                if $USE_DOCKER_SECRET; then
                    echo -e "\033[1;32m✓\033[0m Docker secret created successfully"
                    echo ""
                    echo -e "\033[1;33mSECURITY NOTICE:\033[0m"
                    echo "Your password file still exists at: $PASSWORD_FILE"
                    echo "You may want to securely delete it after verifying the container works:"
                    echo "  shred -vfz -n 10 $PASSWORD_FILE"
                fi
            fi
        fi
    else
        echo "Using traditional password file method"
        USE_DOCKER_SECRET=false
    fi
else
    # Option 2: Just note the selection - we'll handle it at the end
    echo "Interactive mode selected. Container will start after all configuration is complete."
    echo "This ensures all setup steps finish before entering the password prompt."
fi

# NETWORK ENDPOINTS
if $TESTNET; then
    CONSENSUS_ENDPOINT="https://rpc-testnet-pulsechain.g4mm4.io/beacon-api"
    EXECUTION_ENDPOINT="https://rpc-testnet-pulsechain.g4mm4.io"
    WITHDRAW_ADDRESS="0x555E33C8782A0CeF14d2e9064598CE991f58Bc74"
else
    CONSENSUS_ENDPOINT="https://rpc-pulsechain.g4mm4.io/beacon-api"
    EXECUTION_ENDPOINT="https://rpc-pulsechain.g4mm4.io"
    WITHDRAW_ADDRESS="0x1F082785Ca889388Ce523BF3de6781E40b99B060"
fi

# PERMISSIONS & DEPENDENCIES
chown -R 65532:65532 "$CONFIG_PATH"  # INCLUDES PASSWORD FILE

if ! docker --version >/dev/null; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get -qq update
    apt-get -qq install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# CONTAINER NAME
CONTAINER_NAME="ejector"
echo ""
read -r -p "Custom container name (default)[ejector]: " user_container
CONTAINER_NAME="${user_container:-ejector}"

# SECURE START SCRIPT WITH OVERWRITE PROMPT
echo ""
read -r -p "Create start script? [Y/n]: " CREATE_SCRIPT
CREATE_SCRIPT="${CREATE_SCRIPT:-y}"

if [[ ${CREATE_SCRIPT:0:1} =~ ^[Yy]$ ]]; then
    SCRIPT_PATH_DEFAULT="${SCRIPT_PATH:-$(pwd)}/start_ejector.sh"
    read -e -r -p "Script path (default)[$SCRIPT_PATH_DEFAULT]: " user_script
    SCRIPT_PATH="${user_script:-$SCRIPT_PATH_DEFAULT}"

    # Check if file already exists and prompt for overwrite
    CREATE_FILE=true
    if [ -f "$SCRIPT_PATH" ]; then
        read -r -p "File $SCRIPT_PATH already exists. Overwrite? [y/N]: " OVERWRITE_CONFIRM
        if [[ ! "${OVERWRITE_CONFIRM:0:1}" =~ ^[Yy]$ ]]; then
            echo "Skipping start script creation"
            CREATE_FILE=false
        fi
    fi

    if $CREATE_FILE; then
        if [ "$PASSWORD_OPTION" -eq 1 ]; then
            # Generate Option 1 startup script (password file or Docker secret)
            if $USE_DOCKER_SECRET; then
    cat > "$SCRIPT_PATH" << EOF
#!/bin/bash
# Ejector start script - Generated by installation script - Docker Secret Mode

CONTAINER_NAME="$CONTAINER_NAME"
SECRET_NAME="$SECRET_NAME"
CONFIG_PATH="$CONFIG_PATH"
CONSENSUS_ENDPOINT="$CONSENSUS_ENDPOINT"
EXECUTION_ENDPOINT="$EXECUTION_ENDPOINT"
WITHDRAW_ADDRESS="$WITHDRAW_ADDRESS"

# Verify Docker Swarm is active
if [ "\$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" != "active" ]; then
    echo -e "\033[1;31mERROR: Docker Swarm is not active\033[0m"
    echo "Initialize swarm with: docker swarm init"
    exit 1
fi

# Verify secret exists
if ! docker secret ls | grep -q "$SECRET_NAME"; then
    echo -e "\033[1;31mERROR: Docker secret '$SECRET_NAME' not found\033[0m"
    echo "Available secrets:"
    docker secret ls
    exit 1
fi

# Clean up any existing service
if docker service ls --format '{{.Name}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Removing existing service..."
    docker service rm "$CONTAINER_NAME" &>/dev/null || true
    sleep 3
fi

# EJECTOR - DOCKER SERVICE STARTUP CONFIG - DOCKER SECRET MODE
docker service create \\
    --name "$CONTAINER_NAME" \\
    --restart-condition any \\
    --network host \\
    --mount type=bind,source="$CONFIG_PATH",target=/keys \\
    --secret "$SECRET_NAME" \\
    ghcr.io/vouchrun/pls-lsd-ejector:main \\
    start \\
    --consensus_endpoint "$CONSENSUS_ENDPOINT" \\
    --execution_endpoint "$EXECUTION_ENDPOINT" \\
    --keys_dir /keys \\
    --withdraw_address "$WITHDRAW_ADDRESS"
# EJECTOR - DOCKER SERVICE STARTUP CONFIG - END HERE

# Wait for service to start
echo "Waiting for service to start..."
sleep 5

# Verify service is running
SERVICE_STATE=\$(docker service ps "$CONTAINER_NAME" --format '{{.CurrentState}}' 2>/dev/null | head -n1)
if [[ ! "\$SERVICE_STATE" =~ Running ]]; then
    echo -e "\033[1;31mERROR: Failed to start service!\033[0m"
    echo "Service status:"
    docker service ps "$CONTAINER_NAME" --no-trunc
    echo ""
    echo "Check logs with: docker service logs $CONTAINER_NAME"
    exit 1
fi

echo -e "\033[1;32m✓ Service started successfully (using Docker Secret)\033[0m"

# LOG MONITORING (only if running interactively)
if [ -t 0 ]; then
    echo ""
    read -r -p "Monitor service logs? [Y/n]: " MONITOR_LOGS
    MONITOR_LOGS="\${MONITOR_LOGS:-y}"
    if [[ \${MONITOR_LOGS:0:1} =~ ^[Yy]$ ]]; then
        echo -e "\n\033[1;32mMonitoring logs for service '$CONTAINER_NAME'...\033[0m"
        echo -e "Press CTRL+C to exit log monitoring\n"
        docker service logs -f --tail=100 "$CONTAINER_NAME"
    fi
fi
EOF
            else
                cat > "$SCRIPT_PATH" << EOF
#!/bin/bash
# Ejector start script - Generated by installation script - Password File Mode

CONTAINER_NAME="$CONTAINER_NAME"
PASSWORD_FILE="$PASSWORD_FILE"
CONFIG_PATH="$CONFIG_PATH"

# Verify password file exists
if [ ! -f "\$PASSWORD_FILE" ]; then
    echo -e "ERROR: Password file not found at \$PASSWORD_FILE"
    echo "Please ensure your password file is in place before starting"
    exit 1
fi

docker stop "$CONTAINER_NAME" &>/dev/null || true
docker rm "$CONTAINER_NAME" &>/dev/null || true

# EJECTOR - DOCKER STARTUP CONFIG - PASSWORD FILE MODE
docker run --pull always --name "$CONTAINER_NAME" -d \
    --restart unless-stopped \
    --network host \
    -v "$CONFIG_PATH":/keys \
    -v "\$PASSWORD_FILE":/run/secrets/keystore_password:ro \
    ghcr.io/vouchrun/pls-lsd-ejector:main \
    start \\
    --consensus_endpoint "$CONSENSUS_ENDPOINT" \
    --execution_endpoint "$EXECUTION_ENDPOINT" \
    --keys_dir /keys \
    --withdraw_address "$WITHDRAW_ADDRESS"
# EJECTOR - DOCKER STARTUP CONFIG - END HERE

# Verify container is running
if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
    echo -e "\033[1;31mERROR: Failed to start container!\033[0m"
    echo "Check logs with: docker logs $CONTAINER_NAME"
    exit 1
fi

echo -e "\033[1;32m✓ Container started successfully (using password file)\033[0m"

# LOG MONITORING (only if running interactively)
if [ -t 0 ]; then
    echo ""
    read -r -p "Monitor container logs? [Y/n]: " MONITOR_LOGS
    MONITOR_LOGS="\${MONITOR_LOGS:-y}"
    if [[ \${MONITOR_LOGS:0:1} =~ ^[Yy]$ ]]; then
        echo -e "\n\033[1;32mMonitoring logs for container '$CONTAINER_NAME'...\033[0m"
        echo -e "Press CTRL+C to exit log monitoring\n"
        docker logs -f --tail=100 "$CONTAINER_NAME"
    fi
fi
EOF
            fi
        else
            # Generate Option 2 startup script (interactive mode)
            cat > "$SCRIPT_PATH" << EOF
#!/bin/bash
# Ejector start script - Generated by installation script - Interactive Mode

CONTAINER_NAME="$CONTAINER_NAME"
CONFIG_PATH="$CONFIG_PATH"
CONSENSUS_ENDPOINT="$CONSENSUS_ENDPOINT"
EXECUTION_ENDPOINT="$EXECUTION_ENDPOINT"
WITHDRAW_ADDRESS="$WITHDRAW_ADDRESS"

echo -e "\n\n\033[1;37;41m###################################################################\033[0m"
echo -e "\033[1;37;41m#     Enter the Keystore Password for your Ejector when prompted    #\033[0m"
echo -e "\033[1;37;41m#  To Detach and Leave Ejector Running press \"CTRL+p then CTRL+q\"  #\033[0m"
echo -e "\033[1;37;41m#             To Re-attach use: docker attach $CONTAINER_NAME           #\033[0m"
echo -e "\033[1;37;41m###################################################################\033[0m"

# Clean up any existing container
docker stop "$CONTAINER_NAME" &>/dev/null || true
docker rm "$CONTAINER_NAME" &>/dev/null || true

# Start container in interactive mode
docker run --pull always --name "$CONTAINER_NAME" -it \
    --restart unless-stopped \
    --network host \
    -v "$CONFIG_PATH":/keys \
    ghcr.io/vouchrun/pls-lsd-ejector:main \
    start \
    --consensus_endpoint "$CONSENSUS_ENDPOINT" \
    --execution_endpoint "$EXECUTION_ENDPOINT" \
    --keys_dir /keys \
    --withdraw_address "$WITHDRAW_ADDRESS"
EOF
        fi

        chmod 770 "$SCRIPT_PATH"
        echo ""
        echo ""
        echo "✓ Start script created: $SCRIPT_PATH"
        echo ""
        echo "Run start script using: sudo ./$(basename "$SCRIPT_PATH")"

        # SECURITY VERIFICATION
        if [ "$PASSWORD_OPTION" -eq 1 ]; then
            if $USE_DOCKER_SECRET; then
                echo -e "\033[1;32m✓\033[0m Start script configured with Docker Secret (enhanced security)"
            else
                echo -e "\033[1;32m✓\033[0m Start script configured with password file mount (no ENV exposure)"
            fi
        else
            echo -e "\033[1;32m✓\033[0m Interactive start script created successfully"
        fi
    fi
fi

# DETERMINE NETWORK-SPECIFIC FEE RECIPIENT
if $TESTNET; then
    FEE_RECIPIENT_NAME="FeePool"
    FEE_RECIPIENT_ADDRESS="0x4C14073Fa77e3028cDdC60bC593A8381119e9921"
    FEE_RECIPIENT_NOTE="This is the current FeePool contract address for testnet operations."
else
    FEE_RECIPIENT_NAME="ValidatorFeeDeposit"
    FEE_RECIPIENT_ADDRESS="0x9325008eE3B5982c10010C8f12b6CD4943F48fA6"
    FEE_RECIPIENT_NOTE="This has recently changed from the 'FeePool' contract address with the launch of the Vouch Ecosystem and associated VOUCH token."
fi

# FINAL SUCCESS MESSAGE
NETWORK_NAME="MAINNET"
if $TESTNET; then
    NETWORK_NAME="TESTNET"
fi

echo -e "\033[1;32m\nSUCCESS: Ejector Client Configured with these settings:\033[0m"
echo -e "    Network: \033[1;36m$NETWORK_NAME\033[0m"
echo -e "    Consensus Endpoint: \033[1;36m$CONSENSUS_ENDPOINT\033[0m"
echo -e "    Execution Endpoint: \033[1;36m$EXECUTION_ENDPOINT\033[0m"
echo -e "    Withdraw Address: \033[1;36m$WITHDRAW_ADDRESS\033[0m"

if [ "$PASSWORD_OPTION" -eq 1 ]; then
    if $USE_DOCKER_SECRET; then
        echo -e "    Password Method: \033[1;36mDocker Secret (Enhanced Security)\033[0m"
        echo -e "    Secret Name: \033[1;36m$SECRET_NAME\033[0m"
    else
        echo -e "    Password Method: \033[1;36mPassword File\033[0m"
        echo -e "    Password File: \033[1;36m$PASSWORD_FILE\033[0m"
    fi
    echo -e "    Container Name: \033[1;36m$CONTAINER_NAME\033[0m"
else
    echo -e "    Password Option: \033[1;36mInteractive mode\033[0m"
    echo -e "    Container Name: \033[1;36m$CONTAINER_NAME\033[0m"
fi

echo -e "\n\n\033[1;37;41m#############################################################\033[0m"
echo -e "\033[1;37;41m#        IMPORTANT NOTICE - $NETWORK_NAME SETTINGS               #\033[0m"
echo -e "\033[1;37;41m#############################################################\033[0m"
echo -e "\033[1;31mCRITICAL: You MUST set your validator client's suggested-fee-recipient\033[0m"
echo -e "\033[1;31mto the correct contract address for $NETWORK_NAME:\033[0m"
echo ""
echo -e "  \033[1;33m• $NETWORK_NAME Contract:\033[0m \033[1;32m$FEE_RECIPIENT_NAME\033[0m"
echo -e "  \033[1;33m• Contract Address:\033[0m \033[1;32m$FEE_RECIPIENT_ADDRESS\033[0m"
echo ""
echo -e "\033[1;33mNOTE:\033[0m $FEE_RECIPIENT_NOTE"
echo -e "\033[1;33mACTION REQUIRED:\033[0m Configure your validator client with:"
echo -e "  \033[1;36msuggested-fee-recipient= $FEE_RECIPIENT_ADDRESS\033[0m"
echo ""
echo -e "\033[1;37;41m#############################################################\033[0m"

echo ""
read -r -p "Start ejector client now? [Y/n]: " START_CLIENT
START_CLIENT="${START_CLIENT:-y}"

if [[ ${START_CLIENT:0:1} =~ ^[Yy]$ ]]; then
    if [ "$PASSWORD_OPTION" -eq 1 ]; then
        # START SERVICE FOR OPTION 1 (PASSWORD FILE OR DOCKER SECRET)
        
        if $USE_DOCKER_SECRET; then
            # Clean up any existing service
            if docker service ls --format '{{.Name}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo "Removing existing service..."
                docker service rm "$CONTAINER_NAME" &>/dev/null || true
                sleep 3
            fi

            # Start service with Docker Secret
            SERVICE_ID=$(docker service create \
                --name "$CONTAINER_NAME" \
                --restart-condition any \
                --network host \
                --mount type=bind,source="$CONFIG_PATH",target=/keys \
                --secret "$SECRET_NAME" \
                ghcr.io/vouchrun/pls-lsd-ejector:main \
                start \
                --consensus_endpoint "$CONSENSUS_ENDPOINT" \
                --execution_endpoint "$EXECUTION_ENDPOINT" \
                --keys_dir /keys \
                --withdraw_address "$WITHDRAW_ADDRESS")
            
            # Wait for service to be running
            echo "Waiting for service to start..."
            sleep 5
            
            # Verify service is running
            SERVICE_STATE=$(docker service ps "$CONTAINER_NAME" --format '{{.CurrentState}}' 2>/dev/null | head -n1)
            if [[ ! "$SERVICE_STATE" =~ Running ]]; then
                echo -e "\033[1;31mERROR: Service failed to start!\033[0m"
                echo "Service status:"
                docker service ps "$CONTAINER_NAME" --no-trunc
                echo ""
                echo "Check logs with:"
                echo "docker service logs $CONTAINER_NAME"
                echo -e "\033[1;33mTIP: Common issues:\033[0m"
                echo "  • Docker Swarm not active"
                echo "  • Secret not created properly"
                echo "  • Port already in use"
                exit 1
            fi
            
            echo -e "\033[1;32m✓ Service started successfully using Docker Secret\033[0m (Service ID: $SERVICE_ID)"
            
        else
            # Clean up any existing container
            if docker inspect "$CONTAINER_NAME" &>/dev/null; then
                docker stop "$CONTAINER_NAME" &>/dev/null || true
                docker rm "$CONTAINER_NAME" &>/dev/null || true
            fi

            # Start container with password file mount
            CONTAINER_ID=$(docker run --pull always --name "$CONTAINER_NAME" -d \
                --restart unless-stopped \
                --network host \
                -v "$CONFIG_PATH":/keys \
                -v "$PASSWORD_FILE":/run/secrets/keystore_password:ro \
                ghcr.io/vouchrun/pls-lsd-ejector:main \
                start \
                --consensus_endpoint "$CONSENSUS_ENDPOINT" \
                --execution_endpoint "$EXECUTION_ENDPOINT" \
                --keys_dir /keys \
                --withdraw_address "$WITHDRAW_ADDRESS")
            
            # CORRECT VERIFICATION (checks actual container state)
            sleep 5

            # Check if container is running
            if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
                echo -e "\033[1;31mERROR: Container failed to start!\033[0m"
                echo "Container status:"
                docker ps -a --filter "name=$CONTAINER_NAME"
                echo ""
                echo "Check logs with:"
                echo "docker logs $CONTAINER_NAME"
                echo -e "\033[1;33mTIP: Common issues:\033[0m"
                echo "  • Password file not readable by container (UID 65532)"
                echo "  • Password contains special characters"
                exit 1
            fi

            # Verify we see validator processing in logs
            if ! docker logs "$CONTAINER_NAME" 2>&1 | grep -q "validator"; then
                echo -e "\033[1;33mWARNING:\033[0m Container is running but no validator processing detected"
                echo "This might be normal if no validators need processing"
            else
                echo -e "\033[1;32m✓\033[0m Detected validator processing in logs"
            fi

            echo -e "\033[1;32m✓ Service started successfully using password file\033[0m (Container ID: $CONTAINER_ID)"
        fi
    else
        # START SERVICE FOR OPTION 2 (INTERACTIVE MODE)
        echo -e "\n\n\033[1;37;41m###################################################################\033[0m"
        echo -e "\033[1;37;41m#     Enter the Keystore Password for your Ejector when prompted    #\033[0m"
        echo -e "\033[1;37;41m#  To Detach and Leave Ejector Running press \"CTRL+p then CTRL+q\"  #\033[0m"
        echo -e "\033[1;37;41m#             To Re-attach use: docker attach $CONTAINER_NAME           #\033[0m"
        echo -e "\033[1;37;41m###################################################################\033[0m"

        # Clean up any existing container
        docker stop "$CONTAINER_NAME" &>/dev/null || true
        docker rm "$CONTAINER_NAME" &>/dev/null || true

        # Start container in interactive mode
        docker run --pull always --name "$CONTAINER_NAME" -it \
            --restart unless-stopped \
            --network host \
            -v "$CONFIG_PATH":/keys \
            ghcr.io/vouchrun/pls-lsd-ejector:main \
            start \
            --consensus_endpoint "$CONSENSUS_ENDPOINT" \
            --execution_endpoint "$EXECUTION_ENDPOINT" \
            --keys_dir /keys \
            --withdraw_address "$WITHDRAW_ADDRESS"
    fi
fi

# LOG MONITORING - POSITIONED AFTER SUCCESS MESSAGE
if [ "$PASSWORD_OPTION" -eq 1 ] && [[ ${START_CLIENT:0:1} =~ ^[Yy]$ ]]; then
    echo -e "\n\033[1;34m################################################################\033[0m"
    echo -e "\033[1;34m#                LOG MONITORING OPTION                        #\033[0m"
    echo -e "\033[1;34m###############################################################\033[0m"
    
    if $USE_DOCKER_SECRET; then
        echo -e "You can now monitor your service logs to verify validator operation."
    else
        echo -e "You can now monitor your container logs to verify validator operation."
    fi
    
    echo -e "This will show the last 100 lines and continue streaming new logs."
    echo -e "Press \033[1;36mCTRL+C\033[0m to exit log monitoring at any time."

    echo ""
    read -r -p "Would you like to monitor logs now? [Y/n]: " MONITOR_LOGS
    MONITOR_LOGS="${MONITOR_LOGS:-y}"

    if [[ ${MONITOR_LOGS:0:1} =~ ^[Yy]$ ]]; then
        if $USE_DOCKER_SECRET; then
            echo -e "\n\033[1;32mMonitoring logs for service '$CONTAINER_NAME'...\033[0m"
            echo -e "Press CTRL+C to exit log monitoring\n"
            docker service logs -f --tail=100 "$CONTAINER_NAME"
        else
            echo -e "\n\033[1;32mMonitoring logs for container '$CONTAINER_NAME'...\033[0m"
            echo -e "Press CTRL+C to exit log monitoring\n"
            docker logs -f --tail=100 "$CONTAINER_NAME"
        fi
    fi
fi
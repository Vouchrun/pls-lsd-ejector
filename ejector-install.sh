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
            # Generate Option 1 startup script (password file)
            cat > "$SCRIPT_PATH" << EOF
#!/bin/bash
# Ejector start script - Generated by installation script edit at own risk.

CONTAINER_NAME="$CONTAINER_NAME"
PASSWORD_FILE="$PASSWORD_FILE"
CONFIG_PATH="$CONFIG_PATH"

# Verify password file exists
if [ ! -f "\$PASSWORD_FILE" ]; then
    echo "ERROR: Password file not found at \$PASSWORD_FILE"
    echo "Please ensure your password file is in place before starting"
    exit 1
fi

# Read password without trailing newline
PASSWORD_CONTENT=\$(tr -d '\n' < "\$PASSWORD_FILE")

# Create temporary env file with correct permissions
ENV_FILE=$(mktemp)
umask 077
echo "KEYSTORE_PASSWORD=\$PASSWORD_CONTENT" > "\$ENV_FILE"
chmod 600 "\$ENV_FILE"

docker stop "$CONTAINER_NAME" &>/dev/null || true
docker rm "$CONTAINER_NAME" &>/dev/null || true

# EJECTOR - DOCKER STARTUP CONFIG - STARTS HERE
docker run --pull always --name "$CONTAINER_NAME" -d \
    --restart unless-stopped \
    --network host \
    -v "$CONFIG_PATH":/keys \
    --env-file "\$ENV_FILE" \
    ghcr.io/vouchrun/pls-lsd-ejector:main \
    start \
    --consensus_endpoint "$CONSENSUS_ENDPOINT" \
    --execution_endpoint "$EXECUTION_ENDPOINT" \
    --keys_dir /keys \
    --withdraw_address "$WITHDRAW_ADDRESS"
# EJECTOR - DOCKER STARTUP CONFIG - END HERE    

# Clean up
rm -f "\$ENV_FILE"

# Verify container is running
if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
    echo -e "\033[1;31mERROR: Failed to start container!\033[0m"
    echo "Check logs with: docker logs $CONTAINER_NAME"
    exit 1
fi

echo -e "\033[1;32m✓ Container started successfully\033[0m"

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
        else
            # Generate Option 2 startup script (interactive mode)
            cat > "$SCRIPT_PATH" << EOF
#!/bin/bash
# Ejector start script - Generated by installation script edit at own risk.

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

        # SMART SECURITY VERIFICATION
        if [ "$PASSWORD_OPTION" -eq 1 ]; then
            if grep -q 'KEYSTORE_PASSWORD=[^$]' "$SCRIPT_PATH" || \
                grep -q 'PASSWORD_CONTENT=[^$(]' "$SCRIPT_PATH"; then
                echo -e "\033[1;33mWARNING:\033[0m Start script contains potential hardcoded passwords!"
                echo "This might indicate a security issue - please verify your script"
                echo "If this is expected behavior (e.g., variable references), you can ignore this warning"
            else
                echo -e "\033[1;32m✓\033[0m Start script security verified (no hardcoded passwords found)"
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

# FINAL SUCCESS MESSAGE (EXACTLY AS REQUESTED)
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
    echo -e "    Password File: \033[1;36m$PASSWORD_FILE\033[0m"
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
        # START SERVICE FOR OPTION 1 (PASSWORD FILE)
        # Clean up any existing container
        if docker inspect "$CONTAINER_NAME" &>/dev/null; then
            docker stop "$CONTAINER_NAME" &>/dev/null || true
            docker rm "$CONTAINER_NAME" &>/dev/null || true
        fi

        # READ PASSWORD WITHOUT TRAILING NEWLINE
        PASSWORD_CONTENT=$(tr -d '\n' < "$PASSWORD_FILE")

        # Create temporary env file with correct permissions
        ENV_FILE=$(mktemp)
        umask 077
        echo "KEYSTORE_PASSWORD=$PASSWORD_CONTENT" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"

        # Start container with environment variable from secure file
        CONTAINER_ID=$(docker run --pull always --name "$CONTAINER_NAME" -d \
            --restart unless-stopped \
            --network host \
            -v "$CONFIG_PATH":/keys \
            --env-file "$ENV_FILE" \
            ghcr.io/vouchrun/pls-lsd-ejector:main \
            start \
            --consensus_endpoint "$CONSENSUS_ENDPOINT" \
            --execution_endpoint "$EXECUTION_ENDPOINT" \
            --keys_dir /keys \
            --withdraw_address "$WITHDRAW_ADDRESS")

        # Immediately remove temporary env file
        rm -f "$ENV_FILE"
        
        # CORRECT VERIFICATION (checks actual container state)
        sleep 5

        # Check if container is running (more reliable than log parsing)
        if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
            echo -e "\033[1;31mERROR: Container failed to start!\033[0m"
            echo "Container status:"
            docker ps -a --filter "name=$CONTAINER_NAME"
            echo ""
            echo "Check logs with:"
            echo "docker logs $CONTAINER_NAME"
            echo -e "\033[1;33mTIP: Common issues:\033[0m"
            echo "  • Password contains Docker-incompatible characters"
            echo "  • Password file not owned by UID 65532"
            exit 1
        fi

        # Verify we see validator processing in logs (more accurate check)
        if ! docker logs "$CONTAINER_NAME" 2>&1 | grep -q "validator"; then
            echo -e "\033[1;33mWARNING:\033[0m Container is running but no validator processing detected"
            echo "This might be normal if no validators need processing"
        else
            echo -e "\033[1;32m✓\033[0m Detected validator processing in logs"
        fi

        echo -e "\033[1;32m✓ Service started successfully\033[0m (Container ID: $CONTAINER_ID)"
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

# LOG MONITORING - POSITIONED AFTER SUCCESS MESSAGE (AS REQUESTED)
if [ "$PASSWORD_OPTION" -eq 1 ] && [[ ${START_CLIENT:0:1} =~ ^[Yy]$ ]]; then
    echo -e "\n\033[1;34m################################################################\033[0m"
    echo -e "\033[1;34m#                LOG MONITORING OPTION                        #\033[0m"
    echo -e "\033[1;34m###############################################################\033[0m"
    echo -e "You can now monitor your container logs to verify validator operation."
    echo -e "This will show the last 100 lines and continue streaming new logs."
    echo -e "Press \033[1;36mCTRL+C\033[0m to exit log monitoring at any time."

    echo ""
    read -r -p "Would you like to monitor container logs now? [Y/n]: " MONITOR_LOGS
    MONITOR_LOGS="${MONITOR_LOGS:-y}"

    if [[ ${MONITOR_LOGS:0:1} =~ ^[Yy]$ ]]; then
        echo -e "\n\033[1;32mMonitoring logs for container '$CONTAINER_NAME'...\033[0m"
        echo -e "Press CTRL+C to exit log monitoring\n"
        docker logs -f --tail=100 "$CONTAINER_NAME"
    fi
fi

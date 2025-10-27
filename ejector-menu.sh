#!/bin/bash

set -euo pipefail

# Show a debug trace if environment variable DEBUG is set
if [[ ${DEBUG:-0} == 1 ]]; then
  set -x
fi

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as "root" aka sudo"
    exit 1
  fi
}

install_docker_if_missing() {
  if ! docker --version >/dev/null 2>&1; then
    echo "Docker not found. Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get -qq update
    apt-get -qq install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo -e "\e[32m Docker installed successfully \e[0m"
  fi
}

ensure_swarm_initialized() {
  SWARM_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)"
  if [ "$SWARM_STATE" != "active" ]; then
    echo "Docker Swarm not initialized. Running: docker swarm init..."
    docker swarm init
  fi
}

prompt_network_type() {
  local NETWORKTYPE
  while true; do
    read -r -p "Use Mainnet or Testnet settings [Main/Test] (default: Main): " NETWORKTYPE
    NETWORKTYPE=${NETWORKTYPE:-Main}
    NETWORKTYPE=$(echo "$NETWORKTYPE" | tr '[:upper:]' '[:lower:]')
    case "$NETWORKTYPE" in
      main)
          TESTNET=false
          CONFIGPATHDEFAULT="blockchain/validator/keys"
          CONSENSUSENDPOINT_DEFAULT="https://rpc-pulsechain.g4mm4.io/beacon-api"
          EXECUTIONENDPOINT_DEFAULT="https://rpc-pulsechain.g4mm4.io"
          WITHDRAWADDRESS_DEFAULT="0x1F082785Ca889388Ce523BF3de6781E40b99B060"
          break
          ;;
      test)
          TESTNET=true
          CONFIGPATHDEFAULT="blockchain/validator/keys-testnet"
          CONSENSUSENDPOINT_DEFAULT="https://rpc-testnet-pulsechain.g4mm4.io/beacon-api"
          EXECUTIONENDPOINT_DEFAULT="https://rpc-testnet-pulsechain.g4mm4.io"
          WITHDRAWADDRESS_DEFAULT="0x555E33C8782A0CeF14d2e9064598CE991f58Bc74"
          break
          ;;
      *)
          echo "Invalid selection. Please enter Main or Test."
          ;;
    esac
  done

  # Prompt for custom endpoints with defaults
  echo ""
  read -r -p "Enter Consensus Endpoint [default: $CONSENSUSENDPOINT_DEFAULT]: " CONSENSUSENDPOINT
  CONSENSUSENDPOINT="${CONSENSUSENDPOINT:-$CONSENSUSENDPOINT_DEFAULT}"

  read -r -p "Enter Execution Endpoint [default: $EXECUTIONENDPOINT_DEFAULT]: " EXECUTIONENDPOINT
  EXECUTIONENDPOINT="${EXECUTIONENDPOINT:-$EXECUTIONENDPOINT_DEFAULT}"

  read -r -p "Enter Withdraw Address [default: $WITHDRAWADDRESS_DEFAULT]: " WITHDRAWADDRESS
  WITHDRAWADDRESS="${WITHDRAWADDRESS:-$WITHDRAWADDRESS_DEFAULT}"

  echo ""
  echo "Configuration:"
  echo "  Network: $NETWORKTYPE"
  echo "  Consensus Endpoint: $CONSENSUSENDPOINT"
  echo "  Execution Endpoint: $EXECUTIONENDPOINT"
  echo "  Withdraw Address: $WITHDRAWADDRESS"
  echo ""
}

interactive_setup() {
  check_root
  install_docker_if_missing
  prompt_network_type

  # Loop until valid config path is provided
  while true; do
    read -e -r -p "Enter keystore location [default: $CONFIGPATHDEFAULT]: " CONFIGPATH
    CONFIGPATH="${CONFIGPATH:-$CONFIGPATHDEFAULT}"
    CONFIGPATH="${CONFIGPATH%/}"

    if [ ! -d "$CONFIGPATH" ]; then
      echo "ERROR: Config path '$CONFIGPATH' does not exist"
      echo "Please enter a valid directory path."
    else
      break
    fi
  done

  read -r -p "Custom container name [default: ejector]: " CONTAINERNAME
  CONTAINERNAME="${CONTAINERNAME:-ejector}"

  echo "Interactive mode configured!"
  echo "Container name: $CONTAINERNAME"
  echo "Config path: $CONFIGPATH"
  sleep 2
}

interactive_start() {
  check_root
  if [ -z "${CONTAINERNAME:-}" ] || [ -z "${CONFIGPATH:-}" ]; then
    interactive_setup
  fi

  # Check if container already exists and remove it
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINERNAME}$"; then
    echo "Container '$CONTAINERNAME' already exists. Removing it..."
    docker stop "$CONTAINERNAME" 2>/dev/null || true
    docker rm "$CONTAINERNAME" 2>/dev/null || true
  fi

  echo "Starting container: $CONTAINERNAME"
  echo "Press Ctrl+C to stop the container and return to menu"
  echo ""

  # Trap to handle Ctrl+C and container exit/failure
  trap 'echo ""; echo "Container stopped. Cleaning up..."; docker stop "$CONTAINERNAME" 2>/dev/null || true; docker rm "$CONTAINERNAME" 2>/dev/null || true; echo "Returning to menu..."; sleep 2; trap - INT EXIT; return 0' INT EXIT

  docker run --pull always \
    --name "$CONTAINERNAME" \
    -it \
    --restart unless-stopped \
    --network host \
    -v "$CONFIGPATH":/keys \
    ghcr.io/vouchrun/pls-lsd-ejector:staging start \
      --consensus_endpoint "$CONSENSUSENDPOINT" \
      --execution_endpoint "$EXECUTIONENDPOINT" \
      --keys_dir /keys \
      --withdraw_address "$WITHDRAWADDRESS" || {
    echo "Container failed or stopped unexpectedly."
    docker stop "$CONTAINERNAME" 2>/dev/null || true
    docker rm "$CONTAINERNAME" 2>/dev/null || true
    echo "Returning to menu..."
    sleep 2
    trap - INT EXIT
    return 0
  }

  # Reset trap if container exits normally
  trap - INT EXIT
  echo "Container exited. Returning to menu..."
  sleep 2
}


interactive_stop() {
  check_root
  if [ -z "${CONTAINERNAME:-}" ]; then
    read -r -p "Enter the container name to stop [default: ejector]: " CONTAINERNAME
    CONTAINERNAME="${CONTAINERNAME:-ejector}"
  fi
  docker stop "$CONTAINERNAME" || true
  docker rm "$CONTAINERNAME" || true
  echo "Stopped and removed container: $CONTAINERNAME"
  sleep 2
}

interactive_remove() {
  interactive_stop
  echo "Removal of additional files (config/start scripts) not implemented by default."
  sleep 2
}

detached_setup() {
  check_root
  install_docker_if_missing
  ensure_swarm_initialized
  prompt_network_type

  while true; do
    read -e -r -p "Enter keystore location [default: $CONFIGPATHDEFAULT]: " CONFIGPATH
    CONFIGPATH="${CONFIGPATH:-$CONFIGPATHDEFAULT}"
    CONFIGPATH="${CONFIGPATH%/}"

    if [ ! -d "$CONFIGPATH" ]; then
      echo "ERROR: Config path '$CONFIGPATH' does not exist"
      echo "Please enter a valid directory path."
      echo ""
    else
      break
    fi
  done

  read -r -p "Custom service name [default: ejector]: " SERVICENAME
  SERVICENAME="${SERVICENAME:-ejector}"

  SECRETNAME="keystore_password"

  # Check if Docker secret already exists
  SECRET_EXISTS=false
  if docker secret ls --format '{{.Name}}' | grep -q "^${SECRETNAME}$"; then
    SECRET_EXISTS=true
    echo "Docker secret '$SECRETNAME' already exists."
    read -r -p "Do you want to replace it? [y/N]: " REPLACE_SECRET
    if [[ ! "$REPLACE_SECRET" =~ ^[Yy]$ ]]; then
      echo "Using existing Docker secret: $SECRETNAME"
      echo "Detached mode setup complete!"
      sleep 2
      return 0
    else
      echo "Removing existing service if running..."
      docker service rm "$SERVICENAME" 2>/dev/null || true
      echo "Removing existing secret..."
      docker secret rm "$SECRETNAME"
      SECRET_EXISTS=false
    fi
  fi

  # Prompt for password (no file involved)
  while true; do
    echo "Enter keystore password:"
    stty -echo
    read PASS1
    stty echo
    echo
    echo "Confirm password:"
    stty -echo
    read PASS2
    stty echo
    echo

    if [ "$PASS1" != "$PASS2" ]; then
      echo "ERROR: Passwords do not match!"
      echo "Please try again."
      echo ""
      unset PASS1 PASS2
    elif [ -z "$PASS1" ]; then
      echo "ERROR: Password cannot be empty!"
      echo "Please try again."
      echo ""
      unset PASS1 PASS2
    else
      break
    fi
  done

  # Create Docker secret directly from stdin
  echo "Creating Docker secret $SECRETNAME..."
  printf "%s" "$PASS1" | docker secret create "$SECRETNAME" -
  
  # Clear password variables
  unset PASS1 PASS2
  
  echo "Docker secret created successfully."
  echo -e "\033[1;32mDetached mode setup complete!\033[0m"
  sleep 2
}


detached_start() {
  check_root
  if [ -z "${SERVICENAME:-}" ] || [ -z "${CONFIGPATH:-}" ]; then
    echo "Setup not found. Running setup first..."
    sleep 2
    detached_setup
    # After setup completes, check if user wants to continue starting
    if [ -z "${SERVICENAME:-}" ] || [ -z "${CONFIGPATH:-}" ]; then
      echo "Setup incomplete. Returning to menu."
      sleep 2
      return 0
    fi
  fi
  SECRETNAME="keystore_password"
  
  if docker service ls --format '{{.Name}}' | grep -q "^${SERVICENAME}$"; then
    echo "ERROR: Service '$SERVICENAME' already exists."
    echo "Please stop the service first (option 3) or use a different service name."
    sleep 3
    return 0
  fi
  
  echo "Starting service: $SERVICENAME"
  echo "Config path: $CONFIGPATH"
  echo ""
  
  trap 'echo ""; echo "Error occurred while starting service."; echo "Returning to menu..."; sleep 2; trap - ERR; return 0' ERR
  
  docker service create \
    --name "$SERVICENAME" \
    --restart-condition any \
    --network host \
    --mount type=bind,source="$CONFIGPATH",target=/keys \
    --secret "$SECRETNAME" \
    ghcr.io/vouchrun/pls-lsd-ejector:staging start \
    --consensus_endpoint "$CONSENSUSENDPOINT" \
    --execution_endpoint "$EXECUTIONENDPOINT" \
    --keys_dir /keys \
    --withdraw_address "$WITHDRAWADDRESS" || {
    echo ""
    echo "ERROR: Failed to create service."
    echo "Please check:"
    echo "  - Service name is not already in use"
    echo "  - Config path exists: $CONFIGPATH"
    echo "  - Docker secret exists: $SECRETNAME"
    echo ""
    echo "Returning to menu..."
    sleep 3
    trap - ERR
    return 0
  }
  
  # Reset trap
  trap - ERR
  
  echo ""
  echo -e "\033[1;32mService '$SERVICENAME' started successfully!\033[0m"
  sleep 2
}


detached_stop() {
  check_root
  if [ -z "${SERVICENAME:-}" ]; then
    read -r -p "Enter the ejector service name to stop [default: ejector]: " SERVICENAME
    SERVICENAME="${SERVICENAME:-ejector}"
  fi
  docker service rm "$SERVICENAME" || true
  echo "Stopped and removed Docker Swarm service: $SERVICENAME"
  sleep 2
}

detached_logs() {
  check_root
  if [ -z "${SERVICENAME:-}" ]; then
    read -r -p "Enter the ejector service name for logs [default: ejector]: " SERVICENAME
    SERVICENAME="${SERVICENAME:-ejector}"
  fi
  
  echo "========================================="
  echo "Showing logs for: $SERVICENAME"
  echo "Press Ctrl+C to return to menu"
  echo "========================================="
  echo ""
  
  # Trap SIGINT (Ctrl+C) to return gracefully
  trap 'echo ""; echo "Returning to menu..."; sleep 1; trap - INT; return 0' INT
  
  docker service logs -f --tail 100 "$SERVICENAME" || true
  
  # Reset trap (in case logs exit normally)
  trap - INT
}


detached_remove() {
  detached_stop
  SECRETNAME="keystore_password"
  if docker secret ls | grep -q "$SECRETNAME"; then
    docker secret rm "$SECRETNAME"
    echo "Docker secret $SECRETNAME removed."
  fi
  echo "Removal of of this Ejector tool (ejector-menu.sh) needs to be done manually."
  sleep 2
}

# ------------------ Terminal Menu ------------------

# Display welcome message with formatted description
display_welcome() {
  echo ""
  echo -e "\033[1;33m=============================================================\033[0m"
  echo -e "\033[1;33m          VOUCH EJECTOR SETUP & MANAGEMENT TOOL\033[0m"
  echo -e "\033[1;33m=============================================================\033[0m"
  echo ""
  echo "This terminal app allows you to setup and manage the Ejector in Interactive"
  echo "or Detached mode. The Ejector client will make use of Docker containers"
  echo "in either mode."
  echo ""
  echo -e "\033[1;33mInteractive Mode:\033[0m"
  echo "  Setup up and Run a simple docker container for the Ejector."
  echo "  In this mode, you will enter the password at startup. If the"
  echo "  ejector stops for any reason, you will need to re-enter the password."
  echo "  While this is the most secure mode, auto-restart is not supported."
  echo ""
  echo -e "\033[1;33mDetached Mode:\033[0m"
  echo "  Uses Docker Secrets (in simple Swarm mode) for a more robust setup"
  echo "  which supports auto-restart of the container. You will be guided"
  echo "  through the setup, and create a Secret (keystore_password) the container"
  echo "  uses at startup."
  echo ""
  echo -e "\033[1;32mPress ENTER to continue and setup the Ejector using your preferred mode.\033[0m"
  read -r
  clear
}

main_menu() {
  while true; do
    echo ""
    echo -e "\033[1;33m========== Ejector Mode Menu ==========\033[0m"
    echo "1) Interactive Mode Menu"
    echo "2) Detached Mode Menu"
    echo "3) Exit"
    read -p "Select option: " main_choice

    case "$main_choice" in
      1) interactive_mode_menu ;;
      2) detached_mode_menu ;;
      3) exit 0 ;;
      *) echo "Invalid option, try again." ;;
    esac
  done
}

interactive_mode_menu() {
  while true; do
    echo ""
    echo -e "\033[1;33m--- Interactive Mode ---\033[0m"
    echo "1) Setup Ejector"
    echo "2) Start Ejector"
    echo "3) Stop Ejector"
    echo "4) Remove Ejector"
    echo "5) Back to Main Menu"
    echo "6) Exit"
    read -p "Select option: " interactive_choice

    case "$interactive_choice" in
      1) interactive_setup ;;
      2) interactive_start ;;
      3) interactive_stop ;;
      4) interactive_remove ;;
      5) break ;;
      6) exit 0 ;;
      *) echo "Invalid option, try again." ;;
    esac
  done
}

detached_mode_menu() {
  while true; do
    echo ""
    echo -e "\033[1;33m--- Detached Mode ---\033[0m"
    echo "1) Setup Ejector (Also creates Docker Swarm)"
    echo "2) Start Ejector"
    echo "3) Stop Ejector"
    echo "4) View Ejector Logs"
    echo "5) Remove Ejector (Leaves Docker Swarm)"
    echo "6) Back to Main Menu"
    echo "7) Exit"
    read -p "Select option: " detached_choice

    case "$detached_choice" in
      1) detached_setup ;;
      2) detached_start ;;
      3) detached_stop ;;
      4) detached_logs ;;
      5) detached_remove ;;
      6) break ;;
      7) exit 0 ;;
      *) echo "Invalid option, try again." ;;
    esac
  done
}

# Start with welcome message
display_welcome
main_menu
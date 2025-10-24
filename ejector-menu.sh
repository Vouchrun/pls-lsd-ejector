#!/bin/bash

set -euo pipefail

# Show a debug trace if environment variable DEBUG is set
if [[ ${DEBUG:-0} == 1 ]]; then
  set -x
fi

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
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
  read -r -p "Use Mainnet or Testnet settings [Main/Test] (default: Main): " NETWORKTYPE
  NETWORKTYPE=${NETWORKTYPE:-Main}
  NETWORKTYPE=$(echo "$NETWORKTYPE" | tr '[:upper:]' '[:lower:]')
  case "$NETWORKTYPE" in
    main)
        TESTNET=false
        CONFIGPATHDEFAULT="blockchain/validator/keys"
        CONSENSUSENDPOINT="https://rpc-pulsechain.g4mm4.io/beacon-api"
        EXECUTIONENDPOINT="https://rpc-pulsechain.g4mm4.io"
        WITHDRAWADDRESS="0x1F082785Ca889388Ce523BF3de6781E40b99B060"
        ;;
    test)
        TESTNET=true
        CONFIGPATHDEFAULT="blockchain/validator/keys-testnet"
        CONSENSUSENDPOINT="https://rpc-testnet-pulsechain.g4mm4.io/beacon-api"
        EXECUTIONENDPOINT="https://rpc-testnet-pulsechain.g4mm4.io"
        WITHDRAWADDRESS="0x555E33C8782A0CeF14d2e9064598CE991f58Bc74"
        ;;
    *)
        echo "Invalid selection. Please enter Main or Test."
        exit 1
        ;;
  esac
}

interactive_setup() {
  check_root
  install_docker_if_missing
  prompt_network_type

  read -e -r -p "Enter keystore location [default: $CONFIGPATHDEFAULT]: " CONFIGPATH
  CONFIGPATH="${CONFIGPATH:-$CONFIGPATHDEFAULT}"
  CONFIGPATH="${CONFIGPATH%/}"

  if [ ! -d "$CONFIGPATH" ]; then
    echo "ERROR: Config path $CONFIGPATH does not exist"
    exit 1
  fi

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

  docker run --pull always \
    --name "$CONTAINERNAME" \
    -it \
    --restart unless-stopped \
    --network host \
    -v "$CONFIGPATH":/keys \
    venugopalhegde/pls-lsd-ejector:v5 start \
      --consensus_endpoint "$CONSENSUSENDPOINT" \
      --execution_endpoint "$EXECUTIONENDPOINT" \
      --keys_dir /keys \
      --withdraw_address "$WITHDRAWADDRESS"
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

  read -e -r -p "Enter keystore location [default: $CONFIGPATHDEFAULT]: " CONFIGPATH
  CONFIGPATH="${CONFIGPATH:-$CONFIGPATHDEFAULT}"
  CONFIGPATH="${CONFIGPATH%/}"

  if [ ! -d "$CONFIGPATH" ]; then
    echo "ERROR: Config path $CONFIGPATH does not exist"
    exit 1
  fi

  read -r -p "Custom service name [default: ejector]: " SERVICENAME
  SERVICENAME="${SERVICENAME:-ejector}"

  PASSWORDFILEDEFAULT="$CONFIGPATH/keystore.pwd"
  read -e -r -p "Enter password file path [default: $PASSWORDFILEDEFAULT]: " PASSWORDFILE
  PASSWORDFILE="${PASSWORDFILE:-$PASSWORDFILEDEFAULT}"
  mkdir -p "$(dirname "$PASSWORDFILE")"

  SECRETNAME="keystore_password"

  PASSWORD_ALREADY_THERE=false
  if [ -f "$PASSWORDFILE" ]; then
    read -r -p "Password file exists. Overwrite? [y/N]: " OVERWRITE
    if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
      echo "Using existing password file: $PASSWORDFILE"
      PASSWORD_ALREADY_THERE=true
    else
      rm -f "$PASSWORDFILE"
    fi
  fi

  if [ "$PASSWORD_ALREADY_THERE" = false ]; then
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
      echo "Passwords do not match!"
      exit 1
    fi
    umask 077
    printf "%s" "$PASS1" > "$PASSWORDFILE"
    chmod 600 "$PASSWORDFILE"
    chown 65532:65532 "$PASSWORDFILE" 2>/dev/null || true
    unset PASS1 PASS2
  fi

  echo "Creating Docker secret $SECRETNAME from password file..."
  if docker secret ls | grep -q "$SECRETNAME"; then
    docker service rm "$SERVICENAME" 2>/dev/null || true
    docker secret rm "$SECRETNAME"
  fi
  docker secret create "$SECRETNAME" "$PASSWORDFILE"
  echo "Docker secret created."
  if command -v shred &>/dev/null; then
    shred -vfz -n 10 "$PASSWORDFILE"
  else
    rm -f "$PASSWORDFILE"
  fi

  echo "Detached mode setup complete!"
  sleep 2
}


detached_start() {
  check_root
  if [ -z "${SERVICENAME:-}" ] || [ -z "${CONFIGPATH:-}" ]; then
    echo "You must run setup first!"
    return 1
  fi
  SECRETNAME="keystore_password"
  echo "$CONFIGPATH"
  docker service create \
    --name "$SERVICENAME" \
    --restart-condition any \
    --network host \
    --mount type=bind,source="$CONFIGPATH",target=/keys \
    --secret "$SECRETNAME" \
    venugopalhegde/pls-lsd-ejector:v5 start \
    --consensus_endpoint "$CONSENSUSENDPOINT" \
    --execution_endpoint "$EXECUTIONENDPOINT" \
    --keys_dir /keys \
    --withdraw_address "$WITHDRAWADDRESS"
}


detached_stop() {
  check_root
  if [ -z "${SERVICENAME:-}" ]; then
    read -r -p "Enter the service name to stop [default: ejector]: " SERVICENAME
    SERVICENAME="${SERVICENAME:-ejector}"
  fi
  docker service rm "$SERVICENAME" || true
  echo "Stopped and removed Docker Swarm service: $SERVICENAME"
  sleep 2
}

detached_logs() {
  check_root
  if [ -z "${SERVICENAME:-}" ]; then
    read -r -p "Enter the service name for logs [default: ejector]: " SERVICENAME
    SERVICENAME="${SERVICENAME:-ejector}"
  fi
  docker service logs -f --tail 100 "$SERVICENAME"
}

detached_remove() {
  detached_stop
  SECRETNAME="keystorepassword"
  if docker secret ls | grep -q "$SECRETNAME"; then
    docker secret rm "$SECRETNAME"
    echo "Docker secret $SECRETNAME removed."
  fi
  echo "Removal of any config/start files must be done manually if needed."
  sleep 2
}

# ------------------ Terminal Menu ------------------
main_menu() {
  while true; do
    echo ""
    echo "========== Ejector Menu =========="
    echo "1) Interactive Mode"
    echo "2) Detached Mode"
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
    echo "--- Interactive Mode ---"
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
    echo "--- Detached Mode ---"
    echo "1) Setup Ejector (Swarm)"
    echo "2) Start Ejector (Swarm)"
    echo "3) Stop Ejector (Swarm)"
    echo "4) View Ejector Logs"
    echo "5) Remove Ejector (Swarm)"
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

# Start
main_menu

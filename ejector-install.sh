#!/usr/bin/env bash

if [ "$1" == "debug" ]; then
    set -x
fi

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

set -euo pipefail

echo ""
read -r -p "Use testnet settings [y/n] (press Enter to confirm): " TESTNET

if [[ ${TESTNET:0:1} =~ ^[Yy]$ ]]; then
    DEFAULT_CONFIG_PATH="/blockchain/validator_keys/testnet"
else
    DEFAULT_CONFIG_PATH="/blockchain/validator_keys"
fi

echo ""
echo -n "If you require a customised ejector keystore location enter the path (default)[$DEFAULT_CONFIG_PATH]: "
read -r CONFIG_PATH

if [ -z "${CONFIG_PATH}" ]; then
    CONFIG_PATH="$DEFAULT_CONFIG_PATH"
fi


echo ""
echo -n "Please enter your keystore password (your password won't be displayed as you type): "
read -r -s KEYSTORE_PASSWORD
echo


if [[ ${TESTNET:0:1} =~ ^[Yy]$ ]]
then
    CONSENSUS_ENDPOINT=https://rpc-testnet-pulsechain.g4mm4.io/beacon-api
    EXECUTION_ENDPOINT=https://rpc-testnet-pulsechain.g4mm4.io
    WITHDRAW_ADDRESS=0x555E33C8782A0CeF14d2e9064598CE991f58Bc74
else
    CONSENSUS_ENDPOINT=https://rpc-pulsechain.g4mm4.io/beacon-api
    EXECUTION_ENDPOINT=https://rpc-pulsechain.g4mm4.io
    WITHDRAW_ADDRESS=0x1F082785Ca889388Ce523BF3de6781E40b99B060
fi


# Set the keystore to be readable by the ejector docker user
chown -R 65532:65532 "$CONFIG_PATH"

if docker --version ; then
    echo "Detected existing docker installation, skipping install..."
else
    # Add Docker's official GPG key:
    apt-get update
    apt-get install ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get -qq update

    apt-get -qq install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin unattended-upgrades apt-listchanges

    arch=$(uname -i)
    if [[ $arch == arm* ]] || [[ $arch == aarch* ]]; then
        apt-get -qq -y install binfmt-support qemu-user-static
    fi
fi

read -r -p "Enable automatic updates? [y/n] (press Enter to confirm): " AUTOMATIC_UPDATES

if [[ ${AUTOMATIC_UPDATES:0:1} =~ ^[Yy]$ ]]; then
    echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "true";
EOF
    if ! docker ps -q -f name=watchtower | grep -q .; then
        docker run --detach \
            --name watchtower \
            --volume /var/run/docker.sock:/var/run/docker.sock \
            containrrr/watchtower
    else
        echo "Watchtower is already running, skipping setup..."
    fi
fi

echo ""
read -r -p "Start ejector service? (starting now will pass through your key password) [y/n] (press Enter to confirm): " START_SERVICE

if [[ ${START_SERVICE:0:1} =~ ^[Nn]$ ]]; then
    echo ""
    echo ""
    echo "To start the ejector client, run: "
    echo "docker run --name ejector -d -e KEYSTORE_PASSWORD=\"$KEYSTORE_PASSWORD\" --restart always -v \"$CONFIG_PATH\":/keys ghcr.io/vouchrun/pls-lsd-ejector:main start --base-path /keys --consensus_endpoint \"$CONSENSUS_ENDPOINT\" --execution_endpoint \"$EXECUTION_ENDPOINT\" --withdraw_address \"$WITHDRAW_ADDRESS\""
else
    echo -n "Enter a customised container name for the ejector service (default)[ejector]: "
    read -r EJECTOR_CONTAINER_NAME

    if [ -z "${EJECTOR_CONTAINER_NAME}" ]; then
        EJECTOR_CONTAINER_NAME="ejector"
    fi

    docker run --name "$EJECTOR_CONTAINER_NAME" -d -e KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" --restart always -v "$CONFIG_PATH":/keys ghcr.io/vouchrun/pls-lsd-ejector:main start --base-path /keys --consensus_endpoint "$CONSENSUS_ENDPOINT" --execution_endpoint "$EXECUTION_ENDPOINT" --withdraw_address "$WITHDRAW_ADDRESS"
fi
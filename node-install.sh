#!/bin/bash

echo -n Please enter keystore password: 
# shellcheck disable=SC2034
read -rs KEYSTORE_PASSWORD

echo -n Please enter consensus endpoint: 
# shellcheck disable=SC2034
read -rs CONSENSUS_ENDPOINT

echo -n Please enter execution endpoint: 
# shellcheck disable=SC2034
read -rs EXECUTION_ENDPOINT

echo -n Please enter wallet withdraw address: 
# shellcheck disable=SC2034
read -rs WITHDRAW_ADDRESS

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
apt-get update

apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin unattended-upgrades apt-listchanges

echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

docker run --detach \
    --name watchtower \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower

docker run --name ejector -it -e KEYSTORE_PASSWORD --restart always -v "/blockchain/validator_keys":/keys ghcr.io/j-tt/pls-lsd-ejector:feature-docker start \
    --consensus_endpoint "$($CONSENSUS_ENDPOINT | xargs)" \
    --execution_endpoint "$($EXECUTION_ENDPOINT | xargs)" \
    --keys_dir /keys \
    --withdraw_address "$($WITHDRAW_ADDRESS | xargs)"
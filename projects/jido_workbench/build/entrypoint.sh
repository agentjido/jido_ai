#!/bin/sh

# pull in OTP environment variables

export ERL_AFLAGS="-proto_dist inet6_tcp"
export RELEASE_DISTRIBUTION="name"

# Set default hostname if not provided
HOST_NAME=${HOSTNAME:-"localhost"}
RELEASE_NODE_NAME=${FLY_APP_NAME:-"jido_workbench"}

# Ensure we have a valid IP address
if [ -n "${FLY_PRIVATE_IP}" ]; then
    export RELEASE_NODE="${RELEASE_NODE_NAME}@${FLY_PRIVATE_IP}"
else
    # For local Docker, use the container's hostname
    export RELEASE_NODE="${RELEASE_NODE_NAME}@${HOST_NAME}"
fi

export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

echo "HOST NAME: $HOST_NAME"
echo "ERL FLAGS: $ERL_AFLAGS"
echo "RELEASE_DISTRIBUTION: $RELEASE_DISTRIBUTION"
echo "RELEASE_NODE: $RELEASE_NODE"
echo "LANG: $LANG"
echo "LC_ALL: $LC_ALL"
echo -e "\n"

exec "$@"
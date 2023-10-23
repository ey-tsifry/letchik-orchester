#!/bin/sh
#
# Script to create a local Docker image registry container for custom-built Docker images when
# testing Kubernetes on a local machine. (Mostly to avoid having to upload images to Docker Hub).
#
# Adjust as needed for the local env.
#
# adapted from https://kind.sigs.k8s.io/docs/user/local-registry/
set -o errexit

KIND_BIN="kind"
DOCKER_BIN="docker"

CLUSTER_NETWORK_NAME="kind"

CLUSTER_NAME=${1:?"First argument must be a cluster name"}

# 1. Create registry container unless it already exists
reg_name='kind-registry'
reg_port='5001'
if [ "$(${DOCKER_BIN} inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
  $DOCKER_BIN run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

# 2. Add the registry config to the nodes
#
# This is necessary because localhost resolves to loopback addresses that are
# network-namespace local.
# In other words: localhost in the container is not localhost on the host.
#
# We want a consistent name that works from both ends, so we tell containerd to
# alias localhost:${reg_port} to the registry container when pulling images
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${reg_port}"
for node in $(${KIND_BIN} get nodes --name ${CLUSTER_NAME}); do
  $DOCKER_BIN exec "${node}" mkdir -p "${REGISTRY_DIR}"
  $DOCKER_BIN exec "${node}" sh -c "echo '[host.\"http://$reg_name:5000\"]' > \"${REGISTRY_DIR}/hosts.toml\""
  echo "Added registry config for node: $node"
done

# 3. Connect the registry to the cluster network if not already connected
# This allows kind to bootstrap the network but ensures they're on the same network
if [ "$(${DOCKER_BIN} inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  $DOCKER_BIN network connect "${CLUSTER_NETWORK_NAME}" "${reg_name}"
fi

# 4. Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
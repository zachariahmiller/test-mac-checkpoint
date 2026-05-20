#!/bin/bash
# Copyright 2024 Defense Unicorns
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Defense-Unicorns-Commercial

set -euo pipefail

K3S_CONTAINER="k3d-uds-server-0"
IMAGE_NAME="ghcr.io/defenseunicorns/uds-core/checkpoint:latest"

# Verify the cluster is running before we start.
CONTAINER_ID=$(docker ps -qf "name=^${K3S_CONTAINER}$")
if [ -z "$CONTAINER_ID" ]; then
  echo "error: container '${K3S_CONTAINER}' not running" >&2
  exit 1
fi

# Commit the container image with a brief pause for a consistent snapshot.
# The pause is short (a few seconds) but will trip readiness probes with very
# tight timeouts — acceptable for a dev-only checkpoint workflow.
echo "Committing container ${K3S_CONTAINER} ..."
docker commit -p "$CONTAINER_ID" "$IMAGE_NAME" >/dev/null

# Stream volume data via the Docker API using docker cp.
#
# docker cp <container>:<path> - streams the directory as a tar over the Docker
# socket without touching the host filesystem. This works on macOS (Lima,
# OrbStack, Docker Desktop) where Docker volume host paths are inside the VM
# and inaccessible from the macOS host. No sudo required.
echo "Streaming k3s volume ..."
docker cp "${K3S_CONTAINER}:/var/lib/rancher/k3s/." - > k3s_data.tar

echo "Streaming kubelet volume ..."
docker cp "${K3S_CONTAINER}:/var/lib/kubelet/." - > kubelet_data.tar

echo "Saving checkpoint image ..."
docker save -o uds-k3d-checkpoint-latest.tar "$IMAGE_NAME"

echo "Saving busybox helper image ..."
docker pull busybox
docker save busybox -o busybox.tar

# Pack the three tarballs into a single bundle for Zarf to embed.
echo "Creating bundle ..."
tar --blocking-factor=64 -cf uds-checkpoint.tar \
  k3s_data.tar \
  kubelet_data.tar \
  uds-k3d-checkpoint-latest.tar

rm -f k3s_data.tar kubelet_data.tar uds-k3d-checkpoint-latest.tar

echo "Successfully checkpointed the cluster!"

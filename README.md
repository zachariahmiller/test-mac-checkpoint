# K3d + UDS Core Slim Dev Checkpoint

## Overview

A Zarf package that snapshots a running K3d cluster (named `uds` by default) and
rehydrates it on demand — replacing a ~7-minute `uds deploy` with a ~1-2 minute
restore from a local artifact.

Works on **macOS and Linux**. Does not require sudo.

## How it works

**Create** (`uds zarf package create`):
1. Commits the running k3s server container into a checkpoint image.
2. Streams the k3s and kubelet volume data out of the container via the Docker
   API (`docker cp`) — no host filesystem access required.
3. Packs image and volume tarballs into `uds-checkpoint.tar` for Zarf to embed.

**Deploy** (`uds zarf package deploy`):
1. Loads the checkpoint image into Docker.
2. Creates named Docker volumes and injects the volume tarballs via a busybox
   helper container. Named volumes live inside the Docker VM, so this works
   on macOS (Lima, OrbStack, Docker Desktop) without bind-mounting host paths.
3. Reads the cluster token from the restored volume and calls `k3d cluster create`
   with the checkpoint image and named volumes — k3d handles networking,
   kubeconfig, and the serverlb.
4. Waits for Keycloak to become ready before returning.

## Requirements

- Docker (macOS: Lima, OrbStack, or Docker Desktop; Linux: standard Docker)
- `k3d`
- `uds` / `zarf`
- A running K3d cluster named `uds` to checkpoint (create only)

## Create

```sh
uds zarf package create packages/checkpoint-dev --confirm
```

## Deploy

```sh
uds zarf package deploy <path-to-zarf-tarball> --confirm
```

## Known limitations

- **ARM64**: Network policy enforcement in GitHub CI has known issues on ARM64;
  additional unexpected behavior is possible.
- **Single cluster name**: k3s bakes node identity and the cluster token into
  etcd state. The cluster is always restored with its original name (`uds`).
- **Snapshot consistency**: The container is paused briefly during `docker commit`
  to capture a consistent image. Readiness probes with very tight timeouts may
  trip during this window (~a few seconds).

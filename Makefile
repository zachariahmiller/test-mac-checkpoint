NAME    ?= uds
BUNDLE  ?= oci://ghcr.io/defenseunicorns/packages/uds/bundles/k3d-core-slim-dev:latest
PACKAGE ?= zarf-package-k3d-core-slim-dev-*.tar.zst

VOL_K3S     = k3d-$(NAME)-k3s
VOL_KUBELET = k3d-$(NAME)-kubelet

.PHONY: help smoke deploy-bundle create clean restore validate e2e

help:
	@echo "Targets:"
	@echo "  smoke         Validate docker cp + volume injection (any k3d cluster, no uds-core needed)"
	@echo "  deploy-bundle Deploy uds-core slim-dev (~7 min, required before create)"
	@echo "  create        Checkpoint the running cluster into a Zarf package"
	@echo "  clean         Tear down the cluster and remove volumes"
	@echo "  restore       Deploy the Zarf package to restore the cluster"
	@echo "  validate      Wait for all pods to be ready"
	@echo "  e2e           Full round-trip: deploy-bundle → create → clean → restore → validate"

# ── smoke ──────────────────────────────────────────────────────────────────────
# Validates the three new moving parts — docker cp /. format, busybox volume
# injection, and token readback — against a throwaway k3d cluster.
# Does not require a uds-core deployment.
smoke:
	@echo "==> creating throwaway cluster ..."
	k3d cluster create smoke-ckpt
	@echo "==> streaming k3s volume via docker cp ..."
	docker cp k3d-smoke-ckpt-server-0:/var/lib/rancher/k3s/. - > /tmp/smoke-k3s.tar
	@echo "==> injecting into named volume ..."
	docker volume create smoke-k3s-vol
	cat /tmp/smoke-k3s.tar | docker run --rm -i -v smoke-k3s-vol:/data busybox tar -x -C /data
	@echo "==> reading token from volume ..."
	docker run --rm -v smoke-k3s-vol:/data busybox cat /data/server/token
	@echo "==> cleaning up ..."
	k3d cluster delete smoke-ckpt
	docker volume rm smoke-k3s-vol
	rm -f /tmp/smoke-k3s.tar
	@echo "==> smoke test passed."

# ── deploy-bundle ──────────────────────────────────────────────────────────────
deploy-bundle:
	uds deploy $(BUNDLE) --confirm

# ── create ─────────────────────────────────────────────────────────────────────
# Runs checkpoint.sh (via onCreate) and builds the Zarf package.
create:
	uds zarf package create . --confirm

# ── clean ──────────────────────────────────────────────────────────────────────
clean:
	k3d cluster delete $(NAME)
	docker volume rm $(VOL_K3S)     2>/dev/null || true
	docker volume rm $(VOL_KUBELET) 2>/dev/null || true

# ── restore ────────────────────────────────────────────────────────────────────
restore:
	uds zarf package deploy $(PACKAGE) --confirm

# ── validate ───────────────────────────────────────────────────────────────────
validate:
	kubectl wait --for=condition=Ready pods --all -A --timeout=300s
	@echo "==> all pods ready."

# ── e2e ────────────────────────────────────────────────────────────────────────
e2e: deploy-bundle create clean restore validate

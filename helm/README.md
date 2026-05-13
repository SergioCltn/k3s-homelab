# Helm Addons

This folder contains a console-driven setup for:

- `metallb` for `LoadBalancer` services
- `ingress-nginx` for Ingress handling
- `cert-manager` for automatic TLS certificates
- `cloudflared` for public access behind CGNAT
- `spend-app` backend and PostgreSQL manifests

## Layout

Use the folders by concern:

- `helm/platform/`: MetalLB, ingress-nginx, cert-manager, cluster issuers, and external-dns
- `helm/access/`: Cloudflare DNS and tunnel secrets/manifests
- `helm/apps/pi-hole/`: Pi-hole for LAN DNS rewrites
- `helm/apps/gitea/`: self-hosted Git service resources
- `helm/apps/registry/`: in-cluster Docker registry resources
- `helm/apps/spend-app/`: the real backend, database, namespace, and ingress
- `helm/examples/spendapp/`: old dummy example app for ingress testing

Recommended reading order:

1. `platform/` to make the cluster reachable on the LAN and ready for Ingress/TLS.
2. `apps/pi-hole/` if you want local DNS overrides on your LAN.
3. `platform/external-dns*.yaml` if you want Kubernetes to manage Pi-hole records automatically.
4. `access/` to publish the cluster through Cloudflare when behind CGNAT.
5. `apps/gitea/` if you want self-hosted Git inside the cluster.
6. `apps/registry/` if you want a local image registry for pushes and pod pulls.
7. `apps/spend-app/` to deploy the real application.
8. `apps/gitea/actions-*.yaml` if you want in-cluster Gitea Actions with BuildKit.
9. `platform/argocd-*.yaml` if you want Argo CD for GitOps-style reconciliation.

These commands assume:

- `k3s` is already installed
- `helm` is installed locally
- `kubectl` points at `./kubeconfig/aetherion.yaml`

## Use The Repo Kubeconfig

```bash
export KUBECONFIG=./kubeconfig/aetherion.yaml
kubectl get nodes
```

## Install MetalLB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  -f helm/platform/metallb-values.yaml
kubectl wait --for=condition=Ready pod -n metallb-system -l app.kubernetes.io/component=controller --timeout=120s
kubectl apply -f helm/platform/metallb-ipaddresspool.yaml
```

The configured address pool is `192.168.1.240-192.168.1.250`.

## Install ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f helm/platform/ingress-nginx-values.yaml
```

This exposes the ingress controller with a `LoadBalancer` service so MetalLB can assign it an IP for LAN access.

The bundled values also enable `use-forwarded-headers`, which is required when traffic arrives through Cloudflare Tunnel. Without it, `ingress-nginx` can loop on HTTPS redirects.

## Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  -f helm/platform/cert-manager-values.yaml
kubectl wait --for=condition=Available deployment -n cert-manager cert-manager --timeout=180s
kubectl wait --for=condition=Available deployment -n cert-manager cert-manager-webhook --timeout=180s
kubectl wait --for=condition=Available deployment -n cert-manager cert-manager-cainjector --timeout=180s
```

## Configure DNS Challenge For Let's Encrypt

Create a Cloudflare API token with permission to edit DNS for `sergiocltn.com`.

Copy the example secret, fill in the token, and apply it:

```bash
cp helm/access/cloudflare-api-token.secret.yaml.example helm/access/cloudflare-api-token.secret.yaml
$EDITOR helm/access/cloudflare-api-token.secret.yaml
kubectl apply -f helm/access/cloudflare-api-token.secret.yaml
```

Create the production issuer:

```bash
kubectl apply -f helm/platform/clusterissuer-letsencrypt-production.yaml
kubectl get clusterissuer letsencrypt-production
```

## Point DNS At ingress-nginx

Use this only when you have a real public IPv4 on your router WAN and inbound `80/443` actually reach the cluster. It is not the recommended public path when the WAN is behind CGNAT.

Get the external IP from the ingress controller service:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Create a Cloudflare DNS `A` record:

- Name: `spendapp`
- Target: the external IP assigned to `ingress-nginx-controller`

## Public Hostname Ownership

`spendapp.sergiocltn.com` is currently owned by `helm/apps/spend-app/ingress.yaml` in namespace `spend-app` and routes to the Go backend service on port `8000`.

If you want that hostname to point somewhere else, replace or remove that ingress first. `ingress-nginx` will reject duplicate host and path ownership.

## Public Access Behind CGNAT With Cloudflare Tunnel

This is the recommended public access path when your router WAN is private or behind CGNAT.

Create a tunnel in Cloudflare Zero Trust, then create a public hostname:

- Tunnel name: `k3s-aetherion`
- Public hostname: `spendapp.sergiocltn.com`
- Service type: `HTTP`
- Service URL: `http://ingress-nginx-controller.ingress-nginx.svc.cluster.local`

Cloudflare will terminate the public TLS connection at the edge and forward the request through the tunnel to `ingress-nginx` inside the cluster.

After Cloudflare creates the tunnel, copy the tunnel token into a local secret file:

```bash
cp helm/access/cloudflared-token.secret.yaml.example helm/access/cloudflared-token.secret.yaml
$EDITOR helm/access/cloudflared-token.secret.yaml
kubectl apply -f helm/access/cloudflared-token.secret.yaml
kubectl apply -f helm/access/cloudflared-deployment.yaml
kubectl rollout status deployment/cloudflared -n cloudflare-tunnel
```

Check the tunnel pod:

```bash
kubectl get pods -n cloudflare-tunnel
kubectl logs -n cloudflare-tunnel deploy/cloudflared --tail=200
```

With the tunnel in place, Cloudflare can publish `spendapp.sergiocltn.com` without router port forwarding.

If you use the tunnel for public traffic, you can keep the ingress and app manifests as they are. MetalLB remains useful for LAN access, but it is no longer required for internet reachability.

Important notes:

- The deployment uses `cloudflare/cloudflared:latest` and exposes metrics on `0.0.0.0:2000` for Kubernetes readiness and liveness probes.
- The public certificate presented to browsers is Cloudflare's edge certificate. The in-cluster Let's Encrypt certificate can still be useful for direct LAN access to the ingress IP.

## Deploy Pi-hole For Local DNS

Use this when you want local hostnames such as `spendapp.home.arpa` to resolve to a LAN IP without publishing them publicly.

Apply the namespace first:

```bash
kubectl apply -f helm/apps/pi-hole/namespace.yaml
```

Create the web password secret from the example:

```bash
cp helm/apps/pi-hole/web-password.secret.yaml.example helm/apps/pi-hole/web-password.secret.yaml
$EDITOR helm/apps/pi-hole/web-password.secret.yaml
kubectl apply -f helm/apps/pi-hole/web-password.secret.yaml
```

Apply the namespace and workload:

```bash
kubectl apply -f helm/apps/pi-hole/pi-hole.yaml
kubectl rollout status deployment/pi-hole -n pi-hole
kubectl get svc -n pi-hole pi-hole
```

This service is exposed through MetalLB as a `LoadBalancer` on:

- TCP/UDP `53` for DNS
- TCP `80` for the web UI

For this setup, keep DHCP on your router and only point the router's DNS setting at Pi-hole. Running Pi-hole's DHCP server inside Kubernetes is not the intended path here.

Recommended setup flow:

1. Get the assigned LAN IP from `kubectl get svc -n pi-hole pi-hole`.
2. Open `http://<pi-hole-ip>/admin`.
3. Log in with the password from `helm/apps/pi-hole/web-password.secret.yaml`.
4. Point your router DHCP DNS setting at the Pi-hole service IP.

If you are not using `external-dns`, you can add local DNS records manually, for example:

- `spendapp.home.arpa -> <ingress-nginx-loadbalancer-ip>`

For long-term router use, prefer a stable service IP. Before first apply, you can set `spec.loadBalancerIP` in `helm/apps/pi-hole/pi-hole.yaml` to an unused address from the MetalLB pool.

Pi-hole is also a better fit than AdGuard Home here because `external-dns` has a built-in Pi-hole provider.

## Deploy ExternalDNS For Automatic Pi-hole Records

Use this when you want Kubernetes ingress resources to create and update LAN DNS records in Pi-hole automatically.

Apply the namespace first:

```bash
kubectl apply -f helm/platform/external-dns-namespace.yaml
```

Create the Pi-hole API password secret from the example:

```bash
cp helm/platform/external-dns-pihole.secret.yaml.example helm/platform/external-dns-pihole.secret.yaml
$EDITOR helm/platform/external-dns-pihole.secret.yaml
kubectl apply -f helm/platform/external-dns-pihole.secret.yaml
```

Deploy ExternalDNS:

```bash
kubectl apply -f helm/platform/external-dns.yaml
kubectl rollout status deployment/external-dns -n external-dns
kubectl logs -n external-dns deploy/external-dns --tail=100
```

This deployment is intentionally scoped to LAN names only:

- provider: `pihole`
- source: `ingress` and `service`
- domain filter: `home.arpa`
- policy: `upsert-only`

That means it will ignore public names such as `spendapp.sergiocltn.com` and only manage hosts like `spendapp.home.arpa`.

The checked-in `helm/apps/spend-app/ingress.yaml` already includes:

- `external-dns.alpha.kubernetes.io/hostname: spendapp.home.arpa`

So once `external-dns` is running, Pi-hole should learn that record automatically.

Service resources can also publish LAN records through Pi-hole when they include `external-dns.alpha.kubernetes.io/hostname` annotations.

If you previously deployed AdGuard Home, remove it after Pi-hole is working:

```bash
kubectl delete namespace adguard-home
```

The checked-in `helm/apps/spend-app/ingress.yaml` already accepts `spendapp.home.arpa` for LAN HTTP access.

Example local DNS model:

- `spendapp.home.arpa -> 192.168.1.240`
- `budget.home.arpa -> 192.168.1.240`

Both names can then route through `ingress-nginx` based on the host header.

Quick verification:

```bash
kubectl get pods -n pi-hole
kubectl logs -n pi-hole deploy/pi-hole --tail=100
nslookup spendapp.home.arpa <pi-hole-ip>
```

## Deploy The In-Cluster Docker Registry

Use this when you want to push images from your LAN into the cluster and let pods pull them back through k3s containerd.

First reconcile k3s so the managed `/etc/rancher/k3s/registries.yaml` trusts the registry endpoint:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/install.yml
```

That configures containerd to trust these registry names:

- `192.168.1.243:5000`
- `registry.home.arpa:5000`

Then deploy the registry app:

```bash
kubectl apply -f helm/apps/registry/namespace.yaml
kubectl apply -f helm/apps/registry/registry.yaml
kubectl rollout status deployment/registry -n registry
kubectl get svc -n registry registry
```

The service is exposed on a fixed MetalLB IP:

- `192.168.1.243:5000`

And `external-dns` publishes:

- `registry.home.arpa -> 192.168.1.243`

Push from a LAN machine after marking the registry as insecure in your local Docker daemon:

```bash
docker tag my-image:latest registry.home.arpa:5000/my-image:latest
docker push registry.home.arpa:5000/my-image:latest
```

Use it from Kubernetes pods with image references such as:

```yaml
image: registry.home.arpa:5000/my-image:latest
```

Or directly by IP:

```yaml
image: 192.168.1.243:5000/my-image:latest
```

Quick verification:

```bash
curl -fsS http://192.168.1.243:5000/v2/
nslookup registry.home.arpa <pi-hole-ip>
```

## Deploy Argo CD

Use this when you want GitOps-style application reconciliation from a Git repository into the cluster.

Install the official chart with the checked-in values:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f helm/platform/argocd-values.yaml
kubectl rollout status deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-repo-server -n argocd
kubectl rollout status deployment/argocd-applicationset-controller -n argocd
kubectl rollout status deployment/argocd-redis -n argocd
kubectl rollout status statefulset/argocd-application-controller -n argocd
```

Then publish the LAN ingress:

```bash
kubectl apply -f helm/platform/argocd-server-ingress.yaml
kubectl get ingress -n argocd
```

This setup uses:

- the official `argo-cd` Helm chart
- a LAN-only ingress at `argocd.home.arpa`
- `external-dns` to publish the hostname through Pi-hole
- `server.insecure: true` so `ingress-nginx` can terminate plain HTTP on the LAN without Argo CD's own redirect loop

Get the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && printf '\n'
```

Open:

```text
http://argocd.home.arpa
```

Default login:

- username: `admin`
- password: value from `argocd-initial-admin-secret`

Quick verification:

```bash
kubectl get pods -n argocd
kubectl logs -n argocd deploy/argocd-server --tail=100
nslookup argocd.home.arpa <pi-hole-ip>
curl -I http://argocd.home.arpa
```

## Create The First Argo CD Application

The checked-in example application tracks the committed `spend-app` Kubernetes manifests from this `k3s` repo.

Apply it with:

```bash
kubectl apply -f helm/platform/argocd-application-spend-app.yaml
kubectl get applications.argoproj.io -n argocd
kubectl describe application spend-app -n argocd
```

Important detail:

- the application uses the in-cluster Gitea URL `http://gitea.gitea.svc.cluster.local:3000/sergiocltn/k3s.git`
- this avoids relying on `git.home.arpa`, which is only published through Pi-hole on the LAN side

This first application targets:

- repo: `sergiocltn/k3s`
- path: `helm/apps/spend-app`
- destination namespace: `spend-app`

It enables automated self-heal but does not enable prune, so Argo CD can reconcile drift without immediately deleting anything extra you created manually.

## Create The Argo CD App-Of-Apps Root

Use this when you want Argo CD to manage the child `Application` objects from Git as well, not just the workload manifests behind them.

Apply the root app:

```bash
kubectl apply -f helm/platform/argocd-app-of-apps.yaml
kubectl get applications.argoproj.io -n argocd
kubectl describe application root-apps -n argocd
```

The root app watches:

- `helm/platform/argocd-apps/`

The checked-in child apps currently include:

- `spend-app`
- `gitea`
- `registry`
- `pi-hole`
- `external-dns`
- `sealed-secrets`

That means future child applications can be added by dropping more `Application` manifests into `helm/platform/argocd-apps/` and letting Argo CD reconcile them.

## Deploy Sealed Secrets

Use this when you want to keep encrypted secrets in Git and let the cluster turn them back into normal `Secret` objects.

The checked-in app-of-apps child installs the official Sealed Secrets controller into namespace `sealed-secrets`.

Quick verification:

```bash
kubectl get applications.argoproj.io -n argocd sealed-secrets
kubectl get pods -n sealed-secrets
kubectl get crd sealedsecrets.bitnami.com
```

Example sealed secret now checked into this repo:

- `helm/apps/pi-hole/pi-hole-web.sealedsecret.yaml`

That file is included by `helm/apps/pi-hole/kustomization.yaml`, so Argo CD can manage the Pi-hole secret from Git without storing the raw password in the repository.

To seal another secret later, use the controller's public key through `kubeseal`:

```bash
kubectl create secret generic my-secret \
  --namespace my-namespace \
  --from-literal=key=value \
  --dry-run=client -o yaml \
| kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  --format yaml \
> my-secret.sealedsecret.yaml
```

Commit the `SealedSecret`, not the plain `Secret`.

## Deploy Gitea

Use this when you want a lightweight self-hosted Git service on the LAN that can work with your in-cluster registry and future CI.

Apply the namespace and workload:

```bash
kubectl apply -f helm/apps/gitea/namespace.yaml
kubectl apply -f helm/apps/gitea/gitea.yaml
kubectl rollout status deployment/gitea -n gitea
kubectl get ingress -n gitea
```

This setup uses:

- SQLite inside the persistent `/data` volume
- HTTP on `git.home.arpa`
- `external-dns` to publish the LAN hostname automatically through Pi-hole

After the pod is running, open:

```text
http://git.home.arpa
```

Then finish the first-run setup in the web UI. The database values are already prefilled for SQLite, so the main thing is creating your first admin account.

Once configured, you can create repositories there and clone/push over HTTP from your LAN.

Quick verification:

```bash
kubectl get pods -n gitea
kubectl logs -n gitea deploy/gitea --tail=100
nslookup git.home.arpa <pi-hole-ip>
curl -I http://git.home.arpa
```

## Deploy Gitea Actions Runner And BuildKit

Use this when you want Gitea Actions to run inside the cluster and build images with BuildKit before pushing them to the local registry.

Create the runner registration token secret from the example:

```bash
cp helm/apps/gitea/actions-runner-token.secret.yaml.example helm/apps/gitea/actions-runner-token.secret.yaml
$EDITOR helm/apps/gitea/actions-runner-token.secret.yaml
kubectl apply -f helm/apps/gitea/actions-runner-token.secret.yaml
```

The token should come from one of these Gitea pages:

- instance-level: `http://git.home.arpa/-/admin/actions/runners`
- organization-level: `http://git.home.arpa/<org>/settings/actions/runners`
- repository-level: `http://git.home.arpa/<owner>/<repo>/settings/actions/runners`

Then deploy BuildKit and the runner:

```bash
kubectl apply -f helm/apps/gitea/actions-buildkit.yaml
kubectl apply -f helm/apps/gitea/actions-runner.yaml
kubectl rollout status deployment/gitea-buildkit -n gitea
kubectl rollout status deployment/gitea-actions-runner -n gitea
kubectl get pods -n gitea
```

This setup intentionally splits responsibilities:

- `gitea-actions-runner`: polls Gitea and starts job containers
- `docker:27-dind`: gives the runner a local Docker API for those job containers
- `gitea-buildkit`: performs image builds and pushes to `registry.home.arpa:5000`

The BuildKit endpoint inside the cluster is:

- `tcp://gitea-buildkit.gitea.svc.cluster.local:1234`

For image pushes to your current registry, use `registry.insecure=true` in the BuildKit output string because the local registry is HTTP.

Repository setup checklist:

1. Enable Actions in the repository settings.
2. Add a repository secret named `KUBECONFIG_B64` containing `base64 -w0 kubeconfig/aetherion.yaml`.
3. Commit a workflow under `.gitea/workflows/`.

Example workflow for `spend-app/backend`:

```yaml
name: Deploy spend-app backend

on:
  push:
    branches: [main]
    paths:
      - spend-app/backend/**
      - helm/apps/spend-app/backend.yaml

jobs:
  deploy:
    runs-on: ubuntu-22.04
    env:
      IMAGE_NAME: registry.home.arpa:5000/spend-app-backend:latest
      BUILDKIT_HOST: tcp://gitea-buildkit.gitea.svc.cluster.local:1234
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: spend-app/backend/go.mod
      - name: Run unit tests
        working-directory: spend-app/backend
        run: make test-unit
      - name: Build arm64 binary for Dockerfile.k3s
        working-directory: spend-app/backend
        run: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o dist/spend-api .
      - name: Install buildctl and kubectl
        run: |
          set -eu
          case "$(uname -m)" in
            aarch64|arm64) arch=arm64 ;;
            x86_64|amd64) arch=amd64 ;;
            *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
          esac
          curl -fsSL -o /tmp/buildkit.tgz "https://github.com/moby/buildkit/releases/download/v0.25.1/buildkit-v0.25.1.linux-${arch}.tar.gz"
          tar -C /tmp -xzf /tmp/buildkit.tgz
          sudo install -m 0755 /tmp/bin/buildctl /usr/local/bin/buildctl
          curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/v1.30.10/bin/linux/${arch}/kubectl"
          sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
      - name: Build and push image with BuildKit
        working-directory: spend-app/backend
        run: |
          buildctl --addr "$BUILDKIT_HOST" build \
            --frontend dockerfile.v0 \
            --local context=. \
            --local dockerfile=. \
            --opt filename=Dockerfile.k3s \
            --opt platform=linux/arm64 \
            --output type=image,name=$IMAGE_NAME,push=true,registry.insecure=true
      - name: Write kubeconfig
        env:
          KUBECONFIG_B64: ${{ secrets.KUBECONFIG_B64 }}
        run: |
          mkdir -p "$HOME/.kube"
          printf '%s' "$KUBECONFIG_B64" | base64 -d > "$HOME/.kube/config"
      - name: Restart backend deployment
        run: |
          kubectl -n spend-app rollout restart deployment/spend-app-backend
          kubectl -n spend-app rollout status deployment/spend-app-backend --timeout=300s
```

Quick verification:

```bash
kubectl logs -n gitea deploy/gitea-actions-runner --tail=100
kubectl logs -n gitea deploy/gitea-buildkit --tail=100
kubectl get deployments -n gitea
```

## Deploy Spend App Backend And Database

The backend is a Go API that expects PostgreSQL and runs schema migrations on startup.

Create the namespace first:

```bash
kubectl apply -f helm/apps/spend-app/namespace.yaml
```

Create the database and backend secrets from the examples:

```bash
cp helm/apps/spend-app/postgres.secret.yaml.example helm/apps/spend-app/postgres.secret.yaml
cp helm/apps/spend-app/backend.secret.yaml.example helm/apps/spend-app/backend.secret.yaml
$EDITOR helm/apps/spend-app/postgres.secret.yaml
$EDITOR helm/apps/spend-app/backend.secret.yaml
kubectl apply -f helm/apps/spend-app/postgres.secret.yaml
kubectl apply -f helm/apps/spend-app/backend.secret.yaml
```

The password embedded in `DATABASE_URL` must match `POSTGRES_PASSWORD` from `helm/apps/spend-app/postgres.secret.yaml`.

Apply the database resources:

```bash
kubectl apply -f helm/apps/spend-app/postgres.yaml
kubectl rollout status deployment/spend-app-postgres -n spend-app
```

Optional backup job:

```bash
kubectl apply -f helm/apps/spend-app/postgres-backup.yaml
kubectl get cronjob -n spend-app spend-app-postgres-backup
```

This creates:

- a backup PVC: `spend-app-postgres-backups`
- a daily `pg_dump` CronJob at `03:00`
- gzip-compressed dumps under `/backups`
- automatic cleanup for backup files older than 7 days

To trigger one backup immediately:

```bash
kubectl create job --from=cronjob/spend-app-postgres-backup spend-app-postgres-backup-manual -n spend-app
kubectl logs -n spend-app job/spend-app-postgres-backup-manual
```

To inspect backup job history:

```bash
kubectl get cronjob -n spend-app spend-app-postgres-backup
kubectl get jobs -n spend-app
```

The checked-in backend manifest now uses `spend-app-backend:cluster` because the currently deployed backend image was imported directly into the k3s node's containerd.

If you want to switch back to a registry-pulled image later, update `helm/apps/spend-app/backend.yaml` accordingly.

Deploy it with:

```bash
kubectl apply -f helm/apps/spend-app/backend.yaml
kubectl rollout status deployment/spend-app-backend -n spend-app
kubectl get svc -n spend-app
```

The backend service is exposed internally as `spend-app-backend.spend-app.svc.cluster.local:8000`.

To publish it on the existing public hostname, apply the ingress:

```bash
kubectl apply -f helm/apps/spend-app/ingress.yaml
kubectl get ingress -n spend-app
curl -fsS https://spendapp.sergiocltn.com/api/v1/health
```

Verify health:

```bash
kubectl get pods -n spend-app
kubectl logs -n spend-app deploy/spend-app-backend --tail=200
kubectl run spend-app-curl --rm -i --restart=Never --image=curlimages/curl:8.12.1 -- \
  curl -fsS http://spend-app-backend.spend-app.svc.cluster.local:8000/api/v1/health
```

## Check Status

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspools.metallb.io -n metallb-system
kubectl get l2advertisements.metallb.io -n metallb-system
kubectl get svc -n ingress-nginx
kubectl get ingressclass
kubectl get pods -n cert-manager
kubectl get clusterissuer
kubectl get pods -n cloudflare-tunnel
kubectl get pods -n spend-app
```

## Example Test Service

```bash
kubectl create deployment demo --image=nginx:stable
kubectl expose deployment demo --port 80
kubectl create ingress demo \
  --class=nginx \
  --rule='demo.local/*=demo:80'
```

Then point `demo.local` at the external IP shown on the `ingress-nginx-controller` service.

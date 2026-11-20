# NDP-EP Helm Chart

Register an endpoint at [nationaldataplatform.org/endpoints/create](https://nationaldataplatform.org/endpoints/create) (click `Generate Script` and copy the `config-id`).  
Alternatively use the Federation API directly: [federation.ndp.utah.edu/docs](https://federation.ndp.utah.edu/docs) → `POST /ep/simple`.

## Quick install

```bash
bash <(curl -sL https://raw.githubusercontent.com/sci-ndp/ndp-ep-helm/main/helm.sh) \
    --config-id <config-id> \
    --host <cluster-host> \
    --storage-class <storage-class> \
    --ingress-class <ingress-class>
```

## Flags

| Flag | Required | Description |
| --- | --- | --- |
| `--config-id` | yes | Federation config ID |
| `--host` | yes | Internal cluster hostname/IP — drives Ingress rules, Kafka, CKAN |
| `--storage-class` | yes | Kubernetes StorageClass for PVCs (CKAN, JupyterHub) |
| `--ingress-class` | yes | Ingress controller class name |
| `--public-host` | no | Publicly reachable domain (e.g. a reverse-proxy). Used for `REXEC_DEPLOYMENT_API_URL`. Defaults to `--host` |
| `--env` | no | `test` to use the test federation and test IDP. Defaults to `prod` |
| `--namespace` | no | Kubernetes namespace. Defaults to `ndp-ep` |
| `--release-name` | no | Helm release name. Defaults to the namespace value — keep this unique per namespace, since some sub-charts create cluster-scoped resources named after the release |
| `--ndp-token-file` | no | File holding the NDP access token of an admin of the Endpoint, for unattended runs. Without it the script signs you in (see below) |
| `--login-client-id` | no | Public client of the identity provider used to sign in with the device flow. Defaults to `ep-installer-testing` with `--env test`; production has none yet. Also read from `NDP_LOGIN_CLIENT_ID` |

## Signing in and the Federation configuration

Federation 2.0.0 and later give an Endpoint's configuration (`GET /ep/{config-id}`) only to an admin of that Endpoint. `helm.sh` therefore reads it with your NDP access token: from `--ndp-token-file`, or by signing you in with the device flow (it prints a link and a code to open in any browser). When there is no login client (production today) and no token file, it asks without a token, which older Federations accept.

The chart's pre-install Job needs the same configuration inside the cluster. `helm.sh` puts what it read into the Secret `ndp-ep-federation-doc` in the release namespace (this needs `kubectl` on the machine running the script) and passes its name as `federation.docSecret`; the Job reads it and deletes it. Without that Secret the Job fetches the configuration itself, without a token, which only Federations before 2.0.0 accept.

To deploy the chart from a checkout of this repository instead of the published one, run `./helm.local.sh` with the same flags.

## Optional sub-charts

Sub-charts are automatically enabled or disabled based on the federation config at deploy time:

| Sub-chart | Federation field | What it deploys |
| --- | --- | --- |
| `kafka-kraft` | `streaming: true` | Strimzi Kafka in KRaft mode |
| `ndp-jupyterhub` | `jhub: true` | JupyterHub with NDP OAuth |
| `rexec-broker` | `rexec: true` | Remote Execution ZMQ broker |
| `rexec-server-deployment-api` | `rexec: true` | Remote Execution server deployment API |

## Access

| Service | URL |
| --- | --- |
| NDP EP Console | `https://<host>/ep/ui` |
| NDP EP API Docs | `https://<host>/ep/docs` |
| CKAN | `https://<host>/ckan` |
| JupyterHub | `https://<host>/jupyter` *(if enabled)* |
| Kafka | `kcat -L -b <host>:31090` *(if enabled)* |
| Rexec Deployment API | `https://<public-host>/rexec` *(if enabled)* |
| Rexec Broker (ZMQ) | `<public-host>:30001` *(if enabled, TCP — not HTTP)* |

## Example — cluster behind a reverse proxy

```bash
bash <(curl -sL https://raw.githubusercontent.com/sci-ndp/ndp-ep-helm/main/helm.sh) \
    --config-id 6a****************3 \
    --host <internal-host> \
    --public-host <public-host> \
    --storage-class gp2 \
    --ingress-class nginx \
    --env test \
    --namespace ndp-ep
```



```
helm repo add ndp-ep https://sci-ndp.github.io/ndp-ep-helm
helm repo update
```
```
bash <(curl -sL https://github.com/sci-ndp/NDP-EP/releases/latest/download/helm.sh) \
    --config_id <xxxxxxxxxxxxxx> \
    --host <your-host> \
    --storage-class <your-storage-class> \
    --ingress-class <your-ingress-class>
```



# NDP-EP Helm Chart

Register an endpoint on https://nationaldataplatform.org/endpoints/create (click `Generate Script` and ignore generated script) to register your ndp-endpoint on `Federation`.<br>
Or https://federation.ndp.utah.edu/docs, query `/ep/simple` to directly register your endpoint on `Federation`. Copy the `config-id`. 

One-liner install:
```
bash <(curl -sL https://raw.githubusercontent.com/sci-ndp/ndp-ep-helm/main/helm.sh) \
    --config_id <xxxxxxxxxxxxxx> \
    --host <your-host> \
    --storage-class <your-storage-class> \
    --ingress-class <your-ingress-class>
```

Access:
- **NDP EP UI:** `https://<ingress-host>/ep/ui`
- **NDP EP API Docs:** `https://<ingress-host>/ep/api/docs`
- **CKAN:** `https://<ingress-host>/ckan`
- **NDP JHub:** `https://<ingress-host>/jupyter` if it's enabled
- **Kafka:** `kcat -L -b <ingress-host>:31090` if it's enabled

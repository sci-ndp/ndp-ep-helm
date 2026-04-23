

# NDP-EP Helm Chart

Register an endpoint on https://nationaldataplatform.org/endpoints/create (click `Generate Script` and ignore generated script) to register your ndp-endpoint on `Federation`.<br>
Or https://federation.ndp.utah.edu/docs, query `/ep/simple` to directly register your endpoint on `Federation`. Copy the `config-id`. 

One-liner install:
```
bash <(curl -sL https://github.com/sci-ndp/NDP-EP/releases/latest/download/helm.sh) \
    --config_id <xxxxxxxxxxxxxx> \
    --host <your-host> \
    --storage-class <your-storage-class> \
    --ingress-class <your-ingress-class>
```

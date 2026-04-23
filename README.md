
Test:<br>
config from `federation.ndp.utah.edu/test`<br>
authenticate through `idp-test.nationaldataservice.org/temp`
```
./helm.sh \
    --config_id <xxxxxxxxxxxxxx> \
    --host <your-host> \
    --storage-class <your-storage-class> \
    --ingress-class <your-ingress-class>
    --env test
```

Prod:<br>
config from `federation.ndp.utah.edu/prod`<br>
authenticate through `idp.nationaldataservice.org/temp`
```
./helm.sh \
    --config_id <xxxxxxxxxxxxxx> \
    --host <your-host> \
    --storage-class <your-storage-class> \
    --ingress-class <your-ingress-class>
    --env test
```

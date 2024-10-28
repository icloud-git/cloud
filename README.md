# cloud

Main page 

### snell script
```
bash <(curl -s https://raw.githubusercontent.com/icloud-git/cloud/refs/heads/main/script/snell.sh)
```

### shadowsocks 2022
```
bash <(curl -s https://raw.githubusercontent.com/icloud-git/cloud/refs/heads/main/script/ss2022.sh)
```

```
curl -L https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-x86_64-unknown-linux-musl -o /usr/local/bin/shadow-tls; chmod a+x /usr/local/bin/shadow-tls
```

```
shadow-tls --fastopen --v3 server --listen ::0:21468 --server 127.0.0.1:21469 --tls  gateway.icloud.com  --password JsJeWtjiUyJ5yeto
```

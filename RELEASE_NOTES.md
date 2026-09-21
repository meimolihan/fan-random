修复 CI 失败问题

```bash
docker pull mobufan/fan-random:latest
```
```bash
docker pull mobufan/fan-random:v1.0.1
```

```bash
docker pull ghcr.io/meimolihan/fan-random:latest
```
```bash
docker pull ghcr.io/meimolihan/fan-random:v1.0.1
```

## 二进制安装
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-random/main/scripts/install.sh)" -p 8588 -y
```

## 二进制卸载
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-random/main/scripts/uninstall.sh)" -y --purge
```

## Docker 部署
```bash
docker run -d --name fan-random --restart always -p 8588:3000 mobufan/fan-random:v1.0.1
```

# Cloudflare Tunnel

Ingress duy nhat cua VPS. Khong mo port nao tren VCN ngoai 22 — cloudflared ket noi
di ra, Cloudflare terminate TLS.

## Hai che do, loai tru nhau

| | Locally-managed | Remotely-managed |
|---|---|---|
| Ingress khai o | `config.yml` tren may | Dashboard Zero Trust |
| Xac thuc | `cert.pem` (pham vi ca tai khoan) | token (1 tunnel) |
| `cloudflared tunnel route dns` | dung duoc | **khong** — thieu cert.pem |
| `config.yml` | duoc doc | **bi bo qua** |

Day la ly do script quan ly ingress khong chay duoc tren tunnel chay bang token:
`cloudflared tunnel list` bao `Error locating origin cert: client didn't specify
origincert path`.

VPS nay dung **locally-managed**.

## Cai

```bash
curl -fsSL -o /tmp/cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i /tmp/cloudflared.deb
sudo cloudflared tunnel login          # mo URL tren trinh duyet, chon zone
sudo cloudflared tunnel create <ten>
sudo mv /root/.cloudflared/<uuid>.json /etc/cloudflared/
sudo chmod 600 /etc/cloudflared/<uuid>.json
# viet config.yml theo config.example.yml
sudo cloudflared tunnel ingress validate
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

Them repo apt de `apt upgrade` bao gom cloudflared — `.deb` tai truc tiep khong tao
repo, nen no se khong bao gio duoc va:

```bash
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] \
https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
```

## Script `tunnel`

Cai vao `/usr/local/bin/tunnel`. Quan ly ingress + DNS record.

```bash
tunnel list                    # doc config, khong can credential
sudo tunnel add oc-abc 8080    # them ingress + tao DNS CNAME + restart
sudo tunnel remove oc-abc      # xoa ca hai
sudo tunnel restart
```

DNS thao tac qua Cloudflare API voi token scope hep, dat o `/etc/cloudflared/api-token`:

- Permissions: `Zone` -> `DNS` -> **Edit**
- Zone Resources: chi zone cua ban
- Client IP Filtering: IP cua VPS (tuy chon, nen dat)

Token nay khong tao/xoa duoc tunnel va khong dung toi zone khac. Sau khi script chay
duoc, xoa `cert.pem` di — tunnel khong can no luc runtime, chi lenh quan ly moi can.

So voi script bash cu, ban nay: dung PyYAML nen khong lam mat field `originRequest`
hay `path` khi rewrite; xoa theo exact match nen `a.example.com` khong keo theo
`xa.example.com`; backup co timestamp; chay `ingress validate` truoc khi restart va
tu khoi phuc backup neu config sai.

## Khong bao gio commit

```
/etc/cloudflared/cert.pem
/etc/cloudflared/<uuid>.json
/etc/cloudflared/token
/etc/cloudflared/api-token
```

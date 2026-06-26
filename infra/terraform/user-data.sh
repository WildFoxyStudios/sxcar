#!/bin/bash
# cloud-init: prepara el host (Docker + compose). NO hornea secretos ni arranca la app.
# El operador copia docker-compose.prod.yml, Caddyfile y .env a /opt/proyectox y hace `up`.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
usermod -aG docker ubuntu

mkdir -p /opt/proyectox
chown ubuntu:ubuntu /opt/proyectox
cat > /opt/proyectox/README <<'EOF'
Host proyecto-X listo (Docker + compose).
Siguiente (desde tu máquina):
  scp infra/docker-compose.prod.yml infra/Caddyfile infra/.env ubuntu@<DNS>:/opt/proyectox/
  ssh ubuntu@<DNS>
  cd /opt/proyectox && docker login ghcr.io   # si la imagen es privada
  docker compose -f docker-compose.prod.yml up -d
  curl -s localhost/health
EOF

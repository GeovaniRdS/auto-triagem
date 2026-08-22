#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
SERVICE=$REPO/ci-service/src/currencyservice
PKG=$SERVICE/package.json
BACKUP=/tmp/package.json.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=dependencia_inexistente, 2=versao_invalida

# Checagem de segurança: runner precisa estar vivo
if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $PKG $BACKUP   # guarda o estado limpo ANTES de sabotar

case $VARIANT in
  1) sed -i 's/"dependencies": {/"dependencies": {\n    "pacote-que-nao-existe-xyz123": "1.0.0",/' $PKG ;;
  2) sed -i 's|"@grpc/grpc-js": "[^"]*"|"@grpc/grpc-js": "999.999.999"|' $PKG ;;
  3) sed -i '0,/"name"/{s/"name"/"name",/}' $PKG ;;
  4) sed -i 's|"@grpc/grpc-js"|"@grpc/grpc-j"|' $PKG ;;
  5) cp $SERVICE/Dockerfile /tmp/Dockerfile.backup
     sed -i 's/FROM node:.*-alpine.*AS builder/FROM node:inexistente-99-alpine AS builder/' $SERVICE/Dockerfile ;;
esac

git add $PKG
git commit -m "fault-injection: build failure variante $VARIANT (amostra $SAMPLE_NUM)"
git push

echo "Aguardando pipeline iniciar..."
sleep 10
RUN_ID=$(gh run list --workflow=ci-cd.yml --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID — aguardando conclusão..."

# Espera ativa em vez de 'watch' (mais confiável em script)
while true; do
  STATUS=$(gh run view $RUN_ID --json status -q '.status')
  if [ "$STATUS" == "completed" ]; then
    break
  fi
  sleep 5
done

LOG_PATH="data/raw_logs/build/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH

echo "${SAMPLE_NUM},build,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

# Restaura do backup, NÃO do git
cp $BACKUP $PKG
if [ -f /tmp/Dockerfile.backup ]; then
  cp /tmp/Dockerfile.backup $SERVICE/Dockerfile
  rm /tmp/Dockerfile.backup
fi
git add $PKG $SERVICE/Dockerfile
git commit -m "revert: fault-injection build failure amostra $SAMPLE_NUM"
git push

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

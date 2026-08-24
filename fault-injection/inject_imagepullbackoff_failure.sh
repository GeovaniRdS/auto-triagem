#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
MANIFEST=$REPO/manifests/currencyservice.yaml
WORKFLOW=$REPO/.github/workflows/ci-cd.yml
MANIFEST_BACKUP=/tmp/currencyservice.yaml.backup
WORKFLOW_BACKUP=/tmp/ci-cd.yml.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=sufixo_falso, 2=nome_fantasma, 3=dockerhub_inexistente, 4=registry_privado_falso, 5=gcr_inexistente

if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $MANIFEST $MANIFEST_BACKUP
cp $WORKFLOW $WORKFLOW_BACKUP

sed -i 's|imagePullPolicy: Never|imagePullPolicy: Always|' $MANIFEST

case $VARIANT in
  1) sed -i 's|image: currencyservice:\${{ github.sha }}|image: currencyservice:${{ github.sha }}-tagfake|' $WORKFLOW ;;
  2) sed -i 's|image: currencyservice:\${{ github.sha }}|image: imagem-fantasma-xyz:latest|' $WORKFLOW ;;
  3) sed -i 's|image: currencyservice:\${{ github.sha }}|image: docker.io/library/nao-existe-nunca-123:latest|' $WORKFLOW ;;
  4) sed -i 's|image: currencyservice:\${{ github.sha }}|image: registry-privado-fake.example.com/currencyservice:v1|' $WORKFLOW ;;
  5) sed -i 's|image: currencyservice:\${{ github.sha }}|image: gcr.io/projeto-fake-123/currencyservice:v1|' $WORKFLOW ;;
esac

git add $MANIFEST $WORKFLOW
git commit -m "fault-injection: imagepullbackoff failure variante $VARIANT (amostra $SAMPLE_NUM)"
git push

COMMIT_SHA=$(git rev-parse HEAD)
echo "Aguardando pipeline correspondente ao commit ${COMMIT_SHA:0:7}..."
sleep 5
RUN_ID=""
for i in $(seq 1 12); do
  RUN_ID=$(gh run list --workflow=ci-cd.yml --limit 5 --json databaseId,headSha -q ".[] | select(.headSha==\"$COMMIT_SHA\") | .databaseId" | head -1)
  if [ -n "$RUN_ID" ]; then
    break
  fi
  sleep 5
done
if [ -z "$RUN_ID" ]; then
  echo "❌ ERRO: não encontrou o run correspondente ao commit $COMMIT_SHA após 65s. Abortando."
  exit 1
fi
echo "Run ID: $RUN_ID — aguardando conclusão..."

while true; do
  STATUS=$(gh run view $RUN_ID --json status -q '.status')
  if [ "$STATUS" == "completed" ]; then
    break
  fi
  sleep 5
done

LOG_PATH="data/raw_logs/imagepullbackoff/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH

echo "" >> $LOG_PATH
echo "=== kubectl describe pod (diagnóstico local, capturado direto do cluster) ===" >> $LOG_PATH
POD_NAME=$(kubectl get pods -l app=currencyservice --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl describe pod $POD_NAME >> $LOG_PATH 2>&1

echo "${SAMPLE_NUM},imagepullbackoff,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

cp $MANIFEST_BACKUP $MANIFEST
cp $WORKFLOW_BACKUP $WORKFLOW
git add -A
git commit -m "revert: fault-injection imagepullbackoff failure amostra $SAMPLE_NUM"
git push

echo "Aguardando pipeline de reversão corrigir o pod..."
sleep 15

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

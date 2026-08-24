#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
MANIFEST=$REPO/manifests/currencyservice.yaml
MANIFEST_BACKUP=/tmp/currencyservice.yaml.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=replicas_negativo, 2=runAsUser_invalido, 3=requests_maior_que_limits, 4=selector_imutavel, 5=namespace_inexistente

if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $MANIFEST $MANIFEST_BACKUP

case $VARIANT in
  1) sed -i '21a\  replicas: -1' $MANIFEST ;;
  2) sed -i 's|runAsUser: 1000|runAsUser: -1|' $MANIFEST ;;
  3) sed -i '65s/memory: 64Mi/memory: 256Mi/' $MANIFEST ;;
  4) sed -i '24s/app: currencyservice/app: currencyservice-boom/' $MANIFEST ;;
  5) sed -i '17a\  namespace: namespace-fantasma' $MANIFEST ;;
esac

git add $MANIFEST
git commit -m "fault-injection: admissao failure variante $VARIANT (amostra $SAMPLE_NUM)"
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

LOG_PATH="data/raw_logs/admissao/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH

echo "${SAMPLE_NUM},admissao,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

cp $MANIFEST_BACKUP $MANIFEST
git add -A
git commit -m "revert: fault-injection admissao failure amostra $SAMPLE_NUM"
git push

echo "Aguardando pipeline de reversão confirmar o manifest limpo..."
sleep 15

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

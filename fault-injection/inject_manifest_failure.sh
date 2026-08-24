#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
MANIFEST=$REPO/manifests/currencyservice.yaml
BACKUP=/tmp/currencyservice.yaml.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=indentacao_invalida, 2=campo_errado, 3=apiVersion_invalida, 4=selector_ausente, 5=tipo_invalido

if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $MANIFEST $BACKUP

case $VARIANT in
  1) sed -i 's|apiVersion: apps/v1|apiVersion: apps/v99|' $MANIFEST ;;
  2) sed -i 's/matchLabels:/matchLabelz:/' $MANIFEST ;;
  3) sed -i '22,24d' $MANIFEST ;;
  4) sed -i 's/containerPort: 7000/containerPort: "sete"/' $MANIFEST ;;
  5) sed -i '19s/^  labels:/ labels:/' $MANIFEST ;;
esac

git add $MANIFEST
git commit -m "fault-injection: manifest failure variante $VARIANT (amostra $SAMPLE_NUM)"
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

LOG_PATH="data/raw_logs/manifesto_invalido/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH
echo "${SAMPLE_NUM},manifesto_invalido,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

cp $BACKUP $MANIFEST
git add -A
git commit -m "revert: fault-injection manifest failure amostra $SAMPLE_NUM"
git push

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

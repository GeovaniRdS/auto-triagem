#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
WORKFLOW=$REPO/.github/workflows/ci-cd.yml
BACKUP=/tmp/ci-cd.yml.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=tag_errada, 2=stream_truncado, 3=namespace_invalido, 4=comando_typo, 5=socket_invalido

if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $WORKFLOW $BACKUP

case $VARIANT in
  1) sed -i 's|docker save currencyservice:\${{ github.sha }}|docker save currencyservice:tag-inexistente|' $WORKFLOW ;;
  2) sed -i 's|docker save currencyservice:\${{ github.sha }} | sudo k3s ctr images import -|docker save currencyservice:${{ github.sha }} | head -c 500 | sudo k3s ctr images import -|' $WORKFLOW ;;
  3) sed -i 's|sudo k3s ctr images import -|sudo k3s ctr -n namespace-invalido images import -|' $WORKFLOW ;;
  4) sed -i 's|sudo k3s ctr images import -|sudo k3s ctrr images import -|' $WORKFLOW ;;
  5) sed -i 's|sudo k3s ctr images import -|sudo CONTAINERD_ADDRESS=/run/k3s/containerd/invalido.sock k3s ctr images import -|' $WORKFLOW ;;
esac

git add $WORKFLOW
git commit -m "fault-injection: push failure variante $VARIANT (amostra $SAMPLE_NUM)"
git push

echo "Aguardando pipeline iniciar..."
sleep 10
RUN_ID=$(gh run list --workflow=ci-cd.yml --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID — aguardando conclusão..."

while true; do
  STATUS=$(gh run view $RUN_ID --json status -q '.status')
  if [ "$STATUS" == "completed" ]; then
    break
  fi
  sleep 5
done

LOG_PATH="data/raw_logs/push_imagem/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH
echo "${SAMPLE_NUM},push_imagem,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

cp $BACKUP $WORKFLOW
git add -A
git commit -m "revert: fault-injection push failure amostra $SAMPLE_NUM"
git push

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

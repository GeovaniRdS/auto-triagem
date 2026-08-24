#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
MANIFEST=$REPO/manifests/currencyservice.yaml
DOCKERFILE=$REPO/ci-service/src/currencyservice/Dockerfile
PROTO=$REPO/ci-service/src/currencyservice/proto/demo.proto
MANIFEST_BACKUP=/tmp/currencyservice.yaml.backup
DOCKERFILE_BACKUP=/tmp/Dockerfile.backup
PROTO_BACKUP=/tmp/demo.proto.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=porta_invalida, 2=entrypoint_quebrado, 3=probe_porta_errada, 4=proto_corrompido, 5=oom_memory_limit

if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $MANIFEST $MANIFEST_BACKUP
cp $DOCKERFILE $DOCKERFILE_BACKUP
cp $PROTO $PROTO_BACKUP

case $VARIANT in
  1) sed -i 's|value: "7000"|value: "999999"|' $MANIFEST ;;
  2) sed -i 's|ENTRYPOINT \[ "node", "server.js" \]|ENTRYPOINT [ "node", "arquivo-que-nao-existe.js" ]|' $DOCKERFILE ;;
  3) sed -i '58s/port: 7000/port: 9999/' $MANIFEST
     sed -i '61s/port: 7000/port: 9999/' $MANIFEST ;;
  4) sed -i '141d' $PROTO ;;
  5) sed -i '65s/memory: 64Mi/memory: 8Mi/' $MANIFEST
     sed -i '68s/memory: 128Mi/memory: 16Mi/' $MANIFEST ;;
esac

git add $MANIFEST $DOCKERFILE $PROTO
git commit -m "fault-injection: crashloopbackoff failure variante $VARIANT (amostra $SAMPLE_NUM)"
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

echo "Aguardando o kubelet acumular restarts suficientes para expor CrashLoopBackOff nos eventos..."
sleep 20

LOG_PATH="data/raw_logs/crashloopbackoff/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH

echo "" >> $LOG_PATH
echo "=== kubectl describe pod (diagnóstico local, capturado direto do cluster) ===" >> $LOG_PATH
POD_NAME=$(kubectl get pods -l app=currencyservice --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl describe pod $POD_NAME >> $LOG_PATH 2>&1

echo "${SAMPLE_NUM},crashloopbackoff,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

cp $MANIFEST_BACKUP $MANIFEST
cp $DOCKERFILE_BACKUP $DOCKERFILE
cp $PROTO_BACKUP $PROTO
git add -A
git commit -m "revert: fault-injection crashloopbackoff failure amostra $SAMPLE_NUM"
git push

echo "Aguardando pipeline de reversão corrigir o pod..."
sleep 30

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

#!/bin/bash
set -e

REPO=~/projetos/auto-triagem
SERVICE=$REPO/ci-service/src/currencyservice
TESTFILE=$SERVICE/test.js
DATAFILE=$SERVICE/data/currency_conversion.json
TESTBACKUP=/tmp/test.js.backup
DATABACKUP=/tmp/currency_conversion.json.backup
SAMPLE_NUM=$1
VARIANT=$2   # 1=asserção_falha, 2=dado_ausente, 3=erro_sintaxe, 4=modulo_inexistente, 5=erro_runtime

if ! pgrep -f "Runner.Listener" > /dev/null; then
  echo "❌ ERRO: o self-hosted runner não está rodando. Inicie com: cd ~/actions-runner && ./run.sh"
  exit 1
fi

cd $REPO
cp $TESTFILE $TESTBACKUP
cp $DATAFILE $DATABACKUP

case $VARIANT in
  1) sed -i "s/'USD' in data/'ZZZ' in data/" $TESTFILE ;;
  2) echo '{}' > $DATAFILE ;;
  3) sed -i "s/console.log('✅ Todos os testes passaram');/console.log('✅ Todos os testes passaram';/" $TESTFILE ;;
  4) sed -i "1a require('modulo-que-nao-existe-xyz');" $TESTFILE ;;
  5) sed -i "1a undefined.propriedadeInexistente();" $TESTFILE ;;
esac

git add $TESTFILE $DATAFILE
git commit -m "fault-injection: test failure variante $VARIANT (amostra $SAMPLE_NUM)"
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

LOG_PATH="data/raw_logs/teste/sample_${SAMPLE_NUM}.log"
gh run view $RUN_ID --log-failed > $LOG_PATH
echo "${SAMPLE_NUM},teste,${RUN_ID},${LOG_PATH},$(date -Iseconds)" >> data/dataset.csv

cp $TESTBACKUP $TESTFILE
cp $DATABACKUP $DATAFILE

git add -A
git commit -m "revert: fault-injection test failure amostra $SAMPLE_NUM"
git push

echo "✅ Amostra $SAMPLE_NUM (variante $VARIANT) capturada em $LOG_PATH"

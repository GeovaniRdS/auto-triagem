#!/bin/bash
for i in $(seq -w 008 030); do
  VARIANT=$(( (10#$i - 3) % 5 + 1 ))
  echo "=== Rodando amostra $i (variante $VARIANT) ==="
  ./fault-injection/inject_build_failure.sh $i $VARIANT
  if [ $? -ne 0 ]; then
    echo "❌ Amostra $i falhou no script. Parando o lote."
    break
  fi
  echo ""
done
echo "🏁 Lote finalizado. Confira data/dataset.csv"

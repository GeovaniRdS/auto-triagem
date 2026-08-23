const assert = require('node:assert');
const data = require('./data/currency_conversion.json');

// Teste 1: garante que o arquivo de conversão de moedas existe e não está vazio
assert.ok(Object.keys(data).length > 0, 'currency_conversion.json não deve estar vazio');

// Teste 2: garante que USD existe como moeda base de referência
assert.ok('USD' in data, 'USD deve existir no conjunto de moedas suportadas');

console.log('✅ Todos os testes passaram');

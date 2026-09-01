# VRP - pricing principal por labeling exato

Esta versao remove o pricing enumerativo/cache do fluxo normal.

Fluxo de cada iteracao:

1. Resolve o Master LP incremental.
2. Resolve o Master IP periodicamente para atualizar o UB.
3. Resolve o pricing de CADA veiculo por labeling exato.
4. Para cada veiculo, obtem exatamente `min(0, RC*_v)`.
5. Calcula um lower bound certificado:

   LB = z_RMP + sum_v min(0, RC*_v)

6. Adiciona a melhor rota negativa encontrada para cada veiculo.
7. Se nenhum veiculo tiver RC negativo, o RMP atual ja e o otimo do master LP completo e a geracao de colunas termina.

## Arquivos principais

- `pricingPreprocess.jl`: pre-calculos estruturais que nao dependem dos duais.
- `pricingLabeling.jl`: labeling exato, dominancia, heap best-first e bounds.
- `columnGeneration.jl`: fluxo principal e calculo do LB certificado.
- `masterLP.jl`: Master LP incremental.
- `masterIP.jl`: Master inteiro / UB.
- `readData.jl`: leitura direta e tipada dos dados.
- `createRoutes.jl`: rotas iniciais.

## Progresso

A chamada padrao imprime o progresso global por veiculo e, para veiculos mais pesados, uma linha a cada 5000 labels expandidos.

Pode alterar com:

`main(100, 1, 8, 1, 500; labelingProgressEvery=10000)`

ou desligar os prints internos:

`main(100, 1, 8, 1, 500; labelingProgressEvery=0)`


## Painel de progresso do labeling

Durante o pricing, no maximo 5 veiculos sao exibidos simultaneamente.
As mesmas 5 linhas do terminal sao sobrescritas a cada atualizacao.
Quando um dos veiculos exibidos termina, outro veiculo que ainda esta em execucao assume a vaga.

O numero maximo de linhas pode ser alterado diretamente na chamada de
`solve_all_exact_labelings` pelo argumento `maxVisibleVehicles`, mas o padrao e 5.

# Scheduler dinamico de RAM para o pricing

Inicie o Julia com o numero maximo de threads que voce quer disponibilizar, por exemplo:

`julia -t 20 main.jl`

O pricing nao usa necessariamente as 20 ao mesmo tempo. A quantidade de veiculos simultaneos e controlada por RAM:

- RAM < 55%: ate `pricingMaxParallel`
- 55% <= RAM < 68%: ate 6
- 68% <= RAM < 78%: ate 4
- 78% <= RAM < 88%: ate 2
- RAM >= 88%: 1

Os limites sempre sao cortados por `pricingMinParallel` e `pricingMaxParallel`.

Exemplo:

`main(200, 1, 8, 1, 500; pricingMinParallel=1, pricingMaxParallel=8, ramLevel1=0.55, ramLevel2=0.68, ramLevel3=0.78, ramLevel4=0.88, pricingLaunchDelay=0.15)`

O scheduler nunca mata um pricing que ja comecou. Se a RAM sobe, apenas bloqueia novas entradas ate os pricings em execucao terminarem e o numero simultaneo cair para o novo limite.

`pricingLaunchDelay` cria uma pequena espera entre lancamentos para evitar iniciar 8 veiculos de uma vez antes de o uso de RAM atualizar.

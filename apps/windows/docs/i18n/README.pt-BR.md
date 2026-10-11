> 2026-10-11: O ajuste de seis componentes na página de datas ignora e indica horários cuja ausência foi confirmada. Quando todos estão ausentes, não permite adicionar rascunhos de data. Valores inválidos, falhas de leitura e alterações na origem continuam sendo rejeitados. Implementado e verificado localmente; aguardando aceitação do usuário.

> Os cinco modos da página de datas usam o arquivo Swift fixado para prévias assíncronas e rascunhos validados, aguardando aceitação. Compile primeiro o host conforme [as instruções](../../DateHost/README.md). Outras entradas de data mantêm C#; implantação limpa e distribuição ainda não foram verificadas.

# PhotoTrail Windows

### Desenvolvimento para Windows

A versão local de teste para Windows oferece 27 campos XMP comuns, gravação de cópias, troca CSV/XMP, datas em lote com captura do nome de arquivo, prévias JPEG/PNG e JPEG incorporado em DNG, mapas/trilhas e renomeação recuperável. A aparência é restaurada ao reiniciar. O mapa padrão é OpenFreeMap com MapLibre; Google exige uma chave própria e a validação da API real está pendente. Campos completos, traduções da interface, mais formatos e testes em outros computadores continuam incompletos. Sem lançamento oficial. Consulte o [guia de desenvolvimento](../../README.md).

Os caminhos recentes são combinados entre instâncias da mesma sessão do Windows.

A área de transferência GPS copia coordenadas de uma foto; confira a prévia antes de criar rascunhos GPS e salvar cópias. Altitude, horário de medição e regiões não são incluídos.

Fabricante, modelo, lente e número de série da lente podem ser editados em XMP. Os campos EXIF originais são preservados; o número de série mantém zeros iniciais.

As datas XMP de digitalização, criação e modificação são independentes; o ajuste em lote altera apenas a data de captura.

Sete parâmetros de exposição XMP aceitam números ou frações validados; os campos EXIF originais são preservados. São 27 campos manuais.


2026-10-11

Foram adicionados tamanho e espaçamento independentes dos metadados, nomes completos das etiquetas, ordenação persistente das fotos e histórico de pesquisa do mapa com até 3 entradas. Padrões: tamanho e espaçamento normais, nomes completos ativados, nome de arquivo crescente e histórico ativado. A forma abreviada mantém a família de origem; dicas, acessibilidade, pesquisa e cópia usam o nome completo. Comparadores de nome, data de captura e ordem de importação são salvos em ordem crescente ou decrescente, preservando seleção e ordem do processamento de renomeação. Desativar oculta e interrompe novas entradas sem excluir; reativar restaura a exibição. Limpar exclui apenas o histórico; restaurar padrões mantém histórico e chaves. A busca usa a via Google existente com autorização explícita. Implementado e verificado de forma direcionada, aguardando aceitação do usuário. Consulta real on-line não verificada.


2026-10-11

Foram adicionados ordenação do processamento por nome, data, extensão, pasta, tamanho, câmera, cidade, avaliação, metadados e ordem manual, filtros de entrada e arraste de grupos. JPG/RAW/XMP ficam juntos; valores ausentes vão ao fim nas duas direções e empates são estáveis. Ordena e filtra antes de numerar continuamente. Múltiplos grupos preservam a ordem interna e posições ocultas; há posição explícita, Alt+acima/abaixo e Ctrl+Z. A visualização não muda o escopo de execução; alterações de processamento invalidam o plano congelado. Esquemas antigos continuam legíveis, com sort, descending e metadataSortTag opcionais, sem filtros ou IDs manuais. As proteções de execução, cancelamento e recuperação são mantidas. Verificação direcionada, arrastes reais e teclado concluídos; aceitação do usuário pendente. Limites e pendências anteriores permanecem.


## 2026-10-11

A substituição de componentes e o ajuste de seis componentes ignoram datas ausentes confirmadas por foto. Valores iguais e ajustes zero não habilitam Aplicar por rascunhos anteriores. Parâmetros ou tipos inválidos e mudanças na origem de toda a seleção rejeitam o lote. Implementado e verificado; aguardando aceitação do usuário.

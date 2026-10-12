> 2026-10-12: A biblioteca local de esquemas oferece criar, atualizar, salvar como, renomear, excluir e importar/exportar JSON, com cinco modelos iniciais. Exemplos são independentes; alterações pendentes oferecem Salvar/Descartar/Cancelar. A reinicialização restaura o último esquema salvo e mantém uma biblioteca vazia. Salvar configurações não renomeia fotos. Regras antigas do Windows continuam legíveis; novas regras exigem versão 2, sem intercâmbio direto com Mac. Implementado e verificado, aguardando aceitação. O lote anterior de correspondência de trajetos foi aceito com base na validação do agente Windows; limitações anteriores permanecem.

> 2026-10-11: A correspondência de trajetos para fotos selecionadas mantém Calcular resultados → Aplicar resultados. O padrão preenche apenas localizações ausentes; opções avançadas permitem substituir explicitamente ou usar somente o trajeto atual carregado. Cada foto usa seu horário efetivo, incluindo rascunhos, sem supor fuso nem arredondar precisão não representável. Os trajetos são comparados separadamente; ambiguidades não são resolvidas pela ordem de importação. O filtro de resultados sem sucesso altera somente a visualização. Apenas sucessos com mudanças reais são aplicados, com desfazer do lote preservando rascunhos anteriores. Todas as fontes são verificadas antes da confirmação. Aplicar CSV adiciona rascunhos; somente salvar cópias grava arquivos, sem sobrescrever. Implementado e verificado, aguardando aceitação. Lotes anteriores foram aceitos pelo usuário com base na validação do agente Windows; limitações anteriores permanecem.

> 2026-10-11: Os cinco modos de data, CSV e campos comuns usam Aplicar uma vez para criar rascunhos. Carregar predefinições/XMP apenas preenche parâmetros; salvar uma predefinição não salva fotos. Desfazer a última aplicação restaura todos os rascunhos anteriores ao lote, mantendo edições anteriores; salvar/recarregar invalida isso. A verificação final de todas as fontes e o salvamento de cópias permanecem. Implementado e verificado; este lote e as trilhas aguardam aceitação do usuário.

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


## 2026-10-11

O mapa permite visualizar/aplicar ajustes de tempo e leste/norte, desfazer o último ajuste da sessão e reler o original. Instantâneos efetivo/original são salvos localmente e recuperados ao reiniciar. Origem alterada ou ausente impede correspondência e novos ajustes. A exportação GPX cria um novo arquivo e verifica a leitura, sem alterar a origem ou escrever fotos automaticamente. Preserva segmentos, pontos sem horário e elevação; precisão temporal de100ns, sem estilos/extensões originais. Aguardando aceitação do usuário.

## Predefinições ordenadas de metadados

A aba permite adicionar, editar, excluir e ordenar operações nos 27 campos XMP existentes, além de salvar/carregar JSON. Carregar altera somente a cadeia; aplique uma vez aos rascunhos selecionados e desfaça a última aplicação. Somente salvar cópias explicitamente grava arquivos. Há definição, limpeza, preenchimento de ausentes, texto/palavras-chave e cópia de campos por foto. Acrescentar texto se repete em cada aplicação; algoritmos de data e ações desconhecidas são rejeitados por inteiro. Apenas um subconjunto do Mac v1 é compatível.

WIN-LAUNCH-CLOSEOUT-20261019：Os recursos de música foram adiados para a primeira versão do Windows. O esquema inteiro é preservado, mas fica indisponível, inclusive com regras de música desativadas. As ações72–77 e os modelos exclusivos de música não são oferecidos. Configurações e registros são preservados; a rejeição não avança contadores. Autoria, direitos autorais e modelos gerais de fotos são mantidos.

As ações musicais72–77 usam metadados das fotos e renomeação segura, sem adicionar biblioteca ou reprodutor de áudio.

WIN-PRE-RELEASE-20261019: Escape fecha primeiro a lista suspensa. Ao fechar o editor, o foco volta ao controle de origem. Este pacote continua sendo um candidato de desenvolvimento local, aguardando aceitação final e autorização de publicação.

Desenvolvimento POSTM9-R4: a ordenação por nome usa chaves canônicas; a amostra de três arquivos segue a ordem do Mac. A equivalência completa com Foundation ainda não foi verificada. As leituras de restauração reutilizam um processo da janela. [Behavior](../BEHAVIOR.md).

Desenvolvimento POSTM9-R3: os filtros de nome do subconjunto Mac v1 reconhecem equivalência canônica NFC/NFD. As identidades de regras e filtros são preservadas; a ordenação natural usa o comportamento local do Windows. A validação do candidato e os limites pendentes são registrados separadamente.

Desenvolvimento POSTM9: catálogo fixo com nomes de produto e modelos de metadados, entrada personalizada, oito códigos de flash e caminhos Win32 estendidos para gravação e restauração qualificadas. Implantação limpa e redistribuição continuam pendentes.

R10: visibilidade por trilha e recuperação do espaço de trabalho. Gere GPX das fotos selecionadas e salve, releia e adicione explicitamente. Datas sem fuso e referenciais desconhecidos são ignorados com motivo; as fotos não são salvas.

R09b: regiões manuais independentes com seleção congelada e substituição explícita. Persistência de resultados online bloqueada por licença.

R09a: favoritos manuais offline e preferências do mapa. A prévia não aplica GPS; serviço e localização real não verificados.

R08b: sequências avançadas, contadores persistentes e sufixos de conflito por grupo. A conversão de Mac aceita um subconjunto explícito.

R07: a comparação mostra até 20 fotos, mas CSV usa toda a seleção congelada. Valores do disco e rascunhos são separados. Colunas desconhecidas são ignoradas e linhas inválidas são descartadas por inteiro; IDs duplicados, caminhos inseguros e erros de estrutura rejeitam o arquivo. XMP separa instantâneas do disco e exportações com rascunhos; não sobrescreve arquivos nem remapeia IDs entre plataformas automaticamente.

R06b: prévia nativa JPEG/PNG/TIFF e JPEG incorporado em DNG. Remover um grupo da lista preserva arquivos e permite desfazer com os rascunhos. Fontes alteradas ou ausentes ficam desatualizadas e sem escrita; identidades duplicadas são recusadas. Outros RAW não foram verificados; HEIC não tem prévia.

> 2026-10-14 · R06a adiciona importação recursiva, grupos JPEG/RAW, preparação pausável, miniaturas por DPI e faixa de fotos no mapa. Cada arquivo mantém sua origem e permissões. Aguardando aceitação; limites em [IMPORT-THUMBNAILS](../IMPORT-THUMBNAILS.md)。

> 2026-10-14 · R05 adiciona ações ordenadas de data e cópia compatível entre fontes da própria foto, uma aplicação/desfazer e restauração apenas dos parâmetros do último preset salvo. R04c aceito; R05 aguarda aceite. Riscos existentes permanecem. [Contract](../DATE-PRESETS.md).

> O candidato R04c adiciona 21 campos EXIF numéricos, enumerações, orientação e resolução, dois componentes IPTC de data/hora e dois horários do arquivo original, somente para JPEG sem sidecar. Os horários Windows exigem precisão de 100 ns sem perda e não podem ser apagados. Cópias que alteram apenas horários preservam os bytes da imagem. Salvamento misto e restauração v2 verificam os atributos reais; a proteção v1 permanece. R04b foi aceito como resultado do agente Windows; R04c aguarda aceitação. Os riscos anteriores permanecem. [R04c](../NUMERIC-TIME.md).

> O candidato R04b adiciona doze campos IPTC de texto/lista para JPEG sem arquivos auxiliares. Valida limites em bytes UTF8 e codificação explícita; recusa alterações com codificação desconhecida, e a exclusão deve preservar os dados restantes. R04a foi aceita; R04b aguarda aprovação. [Scope / 支持範圍](../IPTC-FIELDS.md).

> 2026-10-14 · Candidato R04a: listas XMP, fontes exatas, texto/equipamento EXIF em JPEG e três grupos de datas. A data principal usa a captura EXIF do JPEG ou XMP CreateDate do arquivo auxiliar; ao apagar, não recorre a outra data. Entrega do agente R03b aceita; R04a aguarda aceitação. Limitações existentes mantidas. [Campos suportados](../METADATA-FIELDS.md).

## 2026-10-13 · R03b

R03b adiciona gravação explícita no arquivo com backup completo, único e obrigatório, releitura do destino real, registros persistentes e restauração por registro revisado. Cópia continua sendo o padrão; Ctrl+S salva apenas cópias selecionadas e mantém rascunhos. São habilitados somente JPEG, XMP associado a JPEG/DNG e XMP independente verificados em NTFS local. Resultados desconhecidos preservam arquivos, backups e rascunhos e bloqueiam gravação, redefinição da origem por releitura e renomeação sem verificação. ACLs personalizadas, links, fluxos adicionais e sistemas não verificados são recusados. A limpeza de GPS com retorno ao EXIF e os limites SDK/NOTICE/SwiftPM continuam pendentes. R03a foi aceito como resultado do agente; R03b exige aceitação separada. [Details](../SAVE-TARGETS.md).

> 2026-10-13 · R03a adiciona um resumo explícito, todos os rascunhos pendentes da biblioteca e o escopo de campos do espaço atual, além de novos XMP ao lado de JPEG/DNG. Ctrl+S continua preparando cópias da seleção; confirme antes de gravar. As cópias mantêm os rascunhos da sessão. XMP existentes usam cópias; gravação direta não está disponível. A limpeza de coordenadas XMP é recusada quando o GPS EXIF original pode reaparecer.

## 2026-10-13 · Inspetor de fontes R02

As visualizações comuns/completas compartilham o modelo. Os 24 campos padrão podem ser pesquisados, selecionados, esvaziados e restaurados; uma lista explicitamente vazia permanece vazia após reiniciar. A pesquisa completa e a cópia preservam fontes, namespaces e instâncias duplicadas. Linhas de referência ausentes permanecem, com indicação de leitura pendente, falha ou desatualizada. A releitura manual prepara snapshots em segundo plano, ignora rascunhos ou entradas não aplicadas e verifica identidades, revisões e fontes antes de aceitar. Cancelamento ou falha mantém o snapshot anterior. Instâncias da fonte e campos líquidos do rascunho são contados separadamente; GPS é um campo lógico. Salvar cópias mantém o rascunho da sessão original. Permissões XMP e date-core-v2 permanecem. A entrega do agente v2 foi aceita; R02 aguarda aceitação. Implantação sem SDK, licenças/NOTICE e SwiftPM/14001 continuam pendentes. As exceções aprovadas para Apple Photos, Apple Maps e etiquetas Finder não isentam outros recursos Windows.

> 2026-10-13 · Datas históricas usam a projeção compartilhada date-core-v2 para ordenar fotos, ordenar e filtrar renomeações por data e converter horários de fotos para trajetos. Segundos inteiros, nanossegundos e texto original são preservados. Trajetos exigem fuso explícito, precisão representável em 100 ns e intervalo da plataforma; sem presumir UTC ou arredondar. Candidato de desenvolvimento aguardando aceitação. Implantação sem Swift SDK, licenças/NOTICE e SwiftPM/14001 continuam pendentes; sem distribuição formal.

> R01b usa validação compartilhada de datas. A projeção histórica para ordenação e trajetos está incompleta. R01a foi aceito; R01b aguarda aceitação. Implantação, licenças e SwiftPM continuam pendentes.

> 2026-10-12: A biblioteca local de predefinições de metadados permite salvar novas, atualizar, copiar, renomear, excluir com confirmação e importar/exportar JSON individual. Selecionar apenas carrega o editor; aplicar continua explícito. Cópia, renomeação e exportação usam o conteúdo salvo e preservam edições pendentes. Trocar, reler e fechar protegem a edição; o padrão é cancelar ou continuar editando. Reiniciar restaura somente a lista, sem ativação, migração ou modelos automáticos. A biblioteca vazia permanece vazia. UTF-8: 1MiB/256 itens; JSON individual v1: 128KiB/27 operações. Local mutex e SHA rejeitam gravações obsoletas na mesma sessão do Windows; não há transação global entre sessões ou gravações externas não cooperativas. Implementado e verificado localmente, aguardando aceitação. A etapa anterior foi aceita com base nos resultados do agente Windows. [Format / 用法](../METADATA-PRESETS.md).

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


R08a adiciona regras por grafemas, regex limitada e fontes verificadas; verifica identidade/SHA/System/ACL, sem sobrescrever. [Limites](../RENAME-RULES.md).


## M8 / M9

Candidato M8/M9: pareamento e fontes de data ordenados, conversão estrita de predefinições, fuso da sessão, salvamento de todos os metadados ou da página atual e edição reversível no mapa. Limpar localização limita-se a cópias JPEG/JPEG+XMP verificadas. As cópias mantêm rascunhos. Serviços, formatos, acessibilidade e aceitação do usuário continuam pendentes.

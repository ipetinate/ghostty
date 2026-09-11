---
title: O editor
description: Abra um arquivo ao lado do terminal que o produziu — gramáticas, minimapa, busca no workspace, divisões, formatação ao salvar e os visualizadores.
sidebar:
  label: O editor
---

O editor do Phantom vive no mesmo painel do terminal. Um arquivo é uma aba ao
lado de `build` ou `dev`, não outro aplicativo.

## Abrir um arquivo

- Clique nele no painel **Files**.
- Clique em um caminho no painel **Git**.
- Pressione ⌘K numa linha do terminal que nomeia um arquivo, ou ⇧⌘K para
  escolher entre as linhas encontradas.
- Peça a um agente, por [`open_file`](/pt-br/docs/mcp/).

Onde o arquivo cai — na mesma célula ou numa nova — segue a configuração de
destino nas Configurações.

## O que o editor faz

- **Gramáticas de sintaxe** — gramáticas TextMate, casadas com Oniguruma,
  contribuídas por extensões em vez de compiladas no binário.
- **Um minimapa** na borda direita.
- **Busca no workspace** (⌥⌘F) na pasta inteira, e busca no arquivo (⌘F).
- **Formatação ao salvar**, por um formatador que uma extensão declarou —
  Prettier para as linguagens web, e um por linguagem para o resto.
- **Mover uma linha ou seleção** com ⌥↑ e ⌥↓.
- **Undo entre execuções** — o histórico sobrevive a fechar o arquivo, e a
  fechar o app.
- **Hot exit** — um arquivo não salvo é guardado, não perdido, e volta como
  estava.

## Dividir

⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ dividem o painel naquela direção e põem o arquivo atual na
célula nova. ⌥⌘1 a ⌥⌘9 selecionam o n-ésimo arquivo aberto. ⌥⌘\\ alterna entre
terminal e editor.

A grade se lembra de si: uma janela restaurada de uma sessão anterior volta com
as mesmas células e os mesmos arquivos nelas.

## Mais que texto

| Tipo | O que abre |
|---|---|
| Markdown | Um preview com scroll sincronizado, ao lado do fonte |
| Imagem, PDF, SVG | Um visualizador, no tamanho certo |
| CSV | Uma tabela |
| Arquivo com marcadores de conflito | Um resolvedor de conflitos, no lugar |
| Arquivo que uma extensão reivindica | O editor daquela extensão — veja [Escrever uma extensão](/pt-br/docs/extensions-authoring/) |

## Diffs

Um arquivo alterado abre como diff, dividido na horizontal ou na vertical, pelo
painel Git. Veja [Git](/pt-br/docs/git/).

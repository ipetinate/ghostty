---
title: Worktrees
description: Crie ou adote uma worktree do git pela sidebar, rode um comando de setup nela, e deixe o editor acompanhar quando um terminal troca.
sidebar:
  label: Worktrees
---

Uma worktree do git é um segundo checkout do mesmo repositório, em outra
branch, em outro diretório. O Phantom as gerencia pela sidebar, então rodar
duas branches ao mesmo tempo não significa dois clones.

## O painel

O painel **Worktrees** mostra uma seção por repositório do workspace, cada uma
listando o checkout principal e todas as worktrees dele. As seções são
indexadas pela raiz comum do repositório, então todas as worktrees dele
dividem uma lista, não importa em qual delas o terminal esteja aberto.

## Criar e adotar

- **Criar** faz uma branch e um checkout sob a raiz gerenciada.
- **Adotar** pega uma worktree que você fez na mão com `git worktree add` e a
  traz para o gerenciamento do Phantom.

A raiz gerenciada é `~/.phantom/worktrees` por padrão, no layout
`<repo>/<branch>`. Mude em **Configurações › Worktrees**.

## Setup, por repositório

Um checkout novo raramente está pronto para rodar: não tem `node_modules`, nem
`.env`, nem saída de build. Por repositório você pode declarar:

- **Um comando** para rodar na worktree nova — `pnpm install`, `make deps`.
- **Arquivos para copiar** do checkout principal — caminhos ignorados pelo git,
  um `.env`, um artefato pré-compilado.

Os dois rodam quando a worktree é criada, então o checkout já nasce usável.

## Trocar a worktree de um terminal

Troque pela linha do terminal, pelo cabeçalho do grupo ou pela toolbar. O
terminal muda de diretório, e **as abas abertas do editor acompanham**: o mesmo
arquivo, no outro checkout.

Um arquivo sem correspondente do outro lado — um que só existe nesta branch —
abre somente leitura e diz por quê, em vez de fingir que se moveu.

## Locks, prune e remoção

O painel informa uma worktree travada e o motivo, repara uma worktree cujos
arquivos administrativos mudaram de lugar, e faz prune das que perderam o
diretório. Remover uma worktree é apagar um diretório de trabalho de verdade,
e forçado apaga um com trabalho não commitado dentro — por isso um agente
precisa da capacidade `worktree` própria para fazer isso. Veja
[O servidor MCP](/phantom/pt-br/docs/mcp/).

---
title: Git
description: Status e staging na sidebar, conflitos resolvidos no arquivo, diffs divididos e branch review contra a base.
sidebar:
  label: Git
---

O painel **Git** trabalha sobre o repositório do terminal que está em foco.

## Status e staging

Os arquivos alterados aparecem por estado — staged, unstaged, untracked. Faça
stage e unstage de um arquivo inteiro ou de um hunk. Adicione um caminho ao
`.gitignore` pelo menu de contexto. Troque de branch pelo seletor no cabeçalho
do painel.

Toda linha de aba também carrega a branch e um ponto quando o checkout está
sujo, então você vê o estado sem abrir o painel. Veja
[Sidebar e grupos](/phantom/pt-br/docs/sidebar-and-groups/).

## Diffs

Clicar num arquivo o abre como diff no editor, dividido na **horizontal ou na
vertical** — o controle fica no canto do diff. Arquivos Markdown podem ser
lidos como preview renderizado em vez de patch.

## Conflitos

Um arquivo com marcadores de conflito abre num resolvedor dentro do próprio
editor, não em outra ferramenta: pegar o nosso, o deles, os dois, ou editar o
resultado à mão, um conflito por vez. Dar stage no arquivo resolvido é um
clique no mesmo painel.

## Branch review

O branch review lista cada commit da branch atual contra a base dela, e cada
arquivo que esses commits tocaram. Abra qualquer um como diff. Serve para ler a
sua própria branch antes de dar push, sem uma aba de navegador.

## O que o Phantom não faz

O Phantom conduz o `git` e o GitHub CLI; ele não substitui nenhum dos dois.
Commits, rebases e pushes são seus, no terminal — que está a uma tecla de
distância, no mesmo painel.

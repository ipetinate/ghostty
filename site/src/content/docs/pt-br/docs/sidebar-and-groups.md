---
title: Sidebar e grupos
description: Como a sidebar substitui a barra de abas, como um grupo reivindica uma pasta de projeto, e o que cada linha de aba informa.
sidebar:
  label: Sidebar e grupos
---

Com `sidebar = true` o Phantom esconde a barra de abas nativa do macOS e põe
cada terminal numa lista lateral. Essa lista é o fork.

## Os cinco painéis

Uma trilha no topo da sidebar seleciona um painel por vez:

| Painel | O que traz |
|---|---|
| **Terminals** | Todo terminal aberto, agrupado |
| **Files** | Um explorador de arquivos do workspace |
| **Git** | Status, staging e branch review — veja [Git](/phantom/pt-br/docs/git/) |
| **Worktrees** | Uma seção por repositório — veja [Worktrees](/phantom/pt-br/docs/worktrees/) |
| **Extensions** | O que está instalado — veja [Extensões](/phantom/pt-br/docs/extensions/) |

A sidebar recolhe pelo botão na barra de título. A largura é `sidebar-width`,
em pontos.

## Grupos

Um grupo é uma seção do painel Terminals. Existem dois tipos.

**Um grupo manual** guarda as abas que você põe nele, e mais nada.

**Um grupo de projeto** nomeia uma pasta e reivindica todo terminal cujo
diretório de trabalho seja aquela pasta ou algo abaixo dela. Você nunca
atribui uma aba: abriu um terminal no projeto, ele já está na seção certa.

Um grupo de projeto funciona mesmo sem abas, porque conhece a própria raiz — é
isso que permite ao cabeçalho oferecer *New Terminal in Worktree* antes de
existir o primeiro terminal.

Um grupo tem nome, uma segunda linha opcional, um ícone (um SF Symbol ou um
único emoji) e uma cor que tinge a seção inteira.

### Mover uma aba

Arrastar uma aba para outra seção a atribui explicitamente, e uma atribuição
explícita vence a regra do projeto. Arrastar para fora a marca como
desagrupada, o que também vence a regra — uma aba que você tirou de um grupo
não volta sozinha.

## O que uma linha de aba informa

Cada linha diz onde o terminal dela está. Todo campo pode ser desligado nas
Configurações.

- **O diretório**, abreviado.
- **A branch**, com um ponto quando há alterações não commitadas.
- **O pull request aberto** daquela branch, clicável, quando existe.
- **A porta de um dev server**, como uma etiqueta `:3000` clicável, no instante
  em que o processo daquela aba abre a porta. A detecção lê o processo e os
  sockets em escuta, não um arquivo de configuração, então funciona com
  qualquer framework e sem setup.
- **O estado do agente** — veja [Agentes](/phantom/pt-br/docs/agents/).
- **A worktree**, quando a aba está em uma.

## Os pull requests do projeto

O cabeçalho de um grupo de projeto abre a lista de todo pull request aberto em
todo repositório sob a raiz dele — inclusive uma pasta de workspace com vários
repositórios lado a lado, não só aquele em que há uma aba aberta. Precisa do
GitHub CLI (`gh`) autenticado.

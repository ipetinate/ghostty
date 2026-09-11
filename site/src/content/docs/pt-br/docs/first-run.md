---
title: Primeira execução
description: O que o Phantom configura numa instalação nova, e os cinco passos do tour de boas-vindas.
sidebar:
  label: Primeira execução
---

Numa instalação nova o Phantom grava um conjunto pequeno de padrões e mostra um
tour. Nada disso é definitivo: cada valor é uma configuração normal que você
muda depois.

## Os padrões de uma instalação nova

O Phantom aplica estes **apenas** onde você ainda não definiu a chave.

| Chave | Valor | Por quê |
|---|---|---|
| `sidebar` | `true` | A sidebar é o ponto do fork; ela substitui a barra de abas nativa. |
| `window-save-state` | `always` | Restaurar a sessão é o comportamento esperado com abas agrupadas. |
| `background-opacity` | `0.70` | O visual de fábrica é translúcido. |
| `background-blur` | `80` | Junto com a opacidade, é o material. |
| `theme` | `Dracula by Phantom` | Escrito em `~/.config/phantom/themes/` como arquivo de verdade. |
| `auto-update` | `download` | Verifica em segundo plano, instala ao sair. |

## O tour

Cinco passos, nesta ordem:

1. **Abertura** — o que é o Phantom e a versão que você instalou.
2. **Básico** — a sidebar, seus painéis, e como um terminal vira uma aba.
3. **Posição das abas** — onde fica a barra e como grupos reivindicam abas.
4. **Tema** — escolha um tema e um pacote de ícones.
5. **Agentes** — os seis agentes suportados e a instalação de hooks com um clique.

Desmarque **Show at startup** no canto inferior esquerdo para não vê-lo de novo.
Ele volta pelo menu Ajuda quando você quiser.

## Depois

- Aponte um grupo para uma pasta — [Sidebar e grupos](/pt-br/docs/sidebar-and-groups/)
- Instale uma linguagem — [Extensões](/pt-br/docs/extensions/)
- Deixe um agente dirigir a janela — [O servidor MCP](/pt-br/docs/mcp/)

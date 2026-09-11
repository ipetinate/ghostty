---
title: Agentes
description: Os seis agentes de código que o Phantom conhece, o estado que ele mostra na aba, o resume de sessão e a instalação de hooks com um clique.
sidebar:
  label: Agentes
---

O Phantom é construído em torno de rodar vários agentes de código ao mesmo
tempo. Ele conhece seis deles e trata a sessão de um agente como algo que a aba
*tem*, não como algo que você precisa lembrar.

## Agentes suportados

Claude Code, Codex, OpenCode, Antigravity, Kimi Code e Pi.

Cada um tem uma marca própria na sidebar, uma entrada no menu de novo terminal
e um instalador para o formato de configuração dele — JSON na maioria, TOML no
Codex.

## Iniciar uma sessão

Pelo cabeçalho de um grupo ou pelo menu de novo terminal, escolha um agente. O
Phantom abre uma aba no diretório certo com o agente já rodando. Um grupo de
projeto inicia na raiz do projeto; uma worktree inicia naquele checkout.

## O estado na aba

Uma linha mostra se a sessão está **trabalhando**, **esperando por você** ou
**concluída**. É essa a razão de a sidebar existir: uma dúzia de agentes em uma
dúzia de repositórios é, de outra forma, uma dúzia de abas idênticas.

O estado vem de hooks que o agente executa. Instale-os em
**Configurações › Agents** com um clique — o Phantom escreve um script no
diretório de hooks do próprio agente e o registra. O nome do script carrega o
nome do build, então um build de desenvolvimento não sobrescreve o que a sua
cópia instalada usa.

No Claude Code a aba também mostra o plano atual, quando existe um.

## Resume

Fechar uma aba mata os processos dentro dela, agente incluído. Reabrir a aba —
restaurando a sessão ou pelo menu da própria aba — inicia o agente de novo com
`--resume` contra a conversa que ele tinha, então a sessão continua em vez de
recomeçar.

Desligue isso em **Restore agent sessions**, nas Configurações.

## Deixar um agente dirigir o Phantom

Um agente também pode agir sobre a janela em que está rodando: abrir um arquivo
numa linha, ler a saída de outro terminal, criar uma worktree. Isso é o servidor
MCP, documentado em [O servidor MCP](/phantom/pt-br/docs/mcp/).

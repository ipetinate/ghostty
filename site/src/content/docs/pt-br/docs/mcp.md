---
title: O servidor MCP
description: O Phantom se expõe por MCP — 25 ferramentas, um socket que todo terminal conhece, um handshake que confere quem chama, e permissões que você concede.
sidebar:
  label: O servidor MCP
---

O Phantom é um servidor Model Context Protocol. Um agente rodando numa aba dele
pode abrir um arquivo numa linha, ler a saída de outro terminal, criar uma
worktree, ou perguntar quais diagnósticos um language server reportou.

## Conectar

Todo terminal que o Phantom abre exporta `PHANTOM_MCP_SOCKET`. O cliente é o
próprio binário do aplicativo, falando stdio de um lado e o socket do outro:

```sh
/Applications/Phantom.app/Contents/MacOS/ghostty +mcp-server \
  --socket="$PHANTOM_MCP_SOCKET" --client=<seu nome>
```

**Configurações › MCP** escreve essa entrada no arquivo de configuração do
próprio agente — JSON na maioria, TOML no Codex — então na prática você clica
um botão.

O socket é `~/.cache/phantom/<bundle id>.sock`. Um build de desenvolvimento tem
o seu, porque o identificador faz parte do nome.

### O handshake

A primeira linha depois de conectar é um hello com uma versão, o pid de quem
chama, o nome dele e o arquivo de estado da aba. O Phantom confere esse pid
contra as credenciais do peer do socket e recusa uma divergência, um peer
ilegível, ou uma versão que ele não conhece. O arquivo de estado da aba é o que
identifica *em qual aba* o agente está.

A versão do protocolo é `2025-06-18`, e o servidor responde três métodos:
`initialize`, `tools/list` e `tools/call`.

## Permissões

Nenhuma ferramenta concede permissão. Um agente que pudesse ampliar o próprio
alcance pediria tudo na primeira chamada e ninguém seria consultado de novo.

**Quatro capacidades:**

| Capacidade | Cobre |
|---|---|
| `read` | Ler o scrollback de um terminal — chaves, tokens, saída de produção |
| `run` | Digitar num terminal ocioso |
| `configure` | Mudar como um language server inicia |
| `worktree` | Criar, mover, reparar, destravar, podar ou remover uma worktree |

**Três escopos**, do estreito ao largo: `tab`, `group`, `all`. Uma concessão
cobre um pedido quando alcança pelo menos tão longe.

Você responde uma folha. Uma concessão marcada *sempre* é gravada; uma dada
para uma chamada só não é, e morre com a conexão. Só uma folha aparece por vez,
e uma aba que foi recusada é dispensada por sessenta segundos sem perguntar de
novo — um agente que pede em loop não pode te treinar a clicar em Permitir.

**Configurações › MCP** lista toda concessão permanente e revoga qualquer uma.

## As ferramentas

### Terminais

| Ferramenta | Faz |
|---|---|
| `list_terminals` | Cada aba: id, título, diretório, processo em primeiro plano, ocioso, porta de dev server, grupo, worktree, estado do agente |
| `read_output` | As últimas linhas do scrollback — precisa de `read` |
| `create_terminal` | Uma aba nova, num diretório ou numa worktree, opcionalmente num grupo, opcionalmente rodando um agente |
| `run_command` | Digitar um comando num terminal **ocioso** — precisa de `run` |
| `focus_terminal` | Trazer uma aba para a frente |
| `update_terminal` | Nome, ícone e cor dela |

### Grupos

`list_groups`, `create_group`, `update_group`, `move_to_group`,
`list_theme_colors`.

### Editor

| Ferramenta | Faz |
|---|---|
| `list_panes` | As células do editor desta janela, e o que cada uma guarda |
| `open_file` | Abrir um arquivo, opcionalmente numa linha |
| `open_file_in_split` | Abrir ao lado do que já está aberto, dividindo o painel |
| `focus_tab` | Trazer um arquivo aberto para a frente |
| `close_tab` | Fechar um |
| `reveal_line` | Pôr o cursor numa linha, rolar até ela, e deixar uma marca na gutter |

### Diagnósticos e language servers

`list_diagnostics`, `list_language_servers`, `restart_language_server`,
`configure_language_server` — a última precisa de `configure`.

### Worktrees

`list_worktrees`, `add_worktree`, `remove_worktree`, `tidy_worktrees` — todas
precisam de `worktree`.

## O que as ferramentas de editor exigem

As ferramentas de editor agem sobre **a janela em que está o terminal do agente
que chamou**. Elas a encontram pelo arquivo de estado de aba do handshake,
então um agente rodando fora de uma aba do Phantom recebe uma recusa clara em
vez de agir sobre uma janela que ninguém escolheu.

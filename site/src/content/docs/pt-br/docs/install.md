---
title: Instalar o Phantom
description: Baixe o DMG, passe pelo Gatekeeper na primeira abertura e saiba o que o app escreve no disco.
sidebar:
  label: Instalação
---

O Phantom é distribuído como dois `.dmg` na página de Releases do repositório:
um universal e um só de Apple silicon. Não há cask do Homebrew nem script de
instalação.

## Requisitos

| | |
|---|---|
| Sistema | macOS 13 Ventura ou superior |
| Arquitetura | Apple silicon e Intel (universal), ou só Apple silicon |
| Disco | Cerca de 100 MB para o aplicativo universal, cerca de metade disso para o de Apple silicon |

## Download

Pegue o **Phantom.dmg** no [último release](https://github.com/ipetinate/phantom/releases/latest),
abra e arraste o Phantom para `/Applications`.

Num Mac com Apple silicon você pode pegar o **Phantom-arm64.dmg** no lugar. É o
mesmo aplicativo sem a metade Intel — cerca de metade do download, e nada mais
de diferente, já que o universal também roda nativo em Apple silicon. Cada build
segue o seu próprio feed de atualização, então o que você instalar é o que o
**Check for Updates** mantém.

## Primeira abertura

O aplicativo é assinado ad-hoc e **não é notarizado**. Dar dois cliques na
primeira vez faz o Gatekeeper recusá-lo como sendo de um desenvolvedor não
identificado.

Faça um destes no lugar:

- Clique com o botão direito no Phantom, no Finder, e escolha **Abrir**, depois
  confirme.
- Ou limpe o atributo de quarentena pelo terminal:

  ```sh
  xattr -cr /Applications/Phantom.app
  ```

Isso é só uma vez. Toda versão seguinte chega pelo
[Sparkle](/pt-br/docs/updates/) e nunca mais pergunta.

## O que o Phantom escreve

| Caminho | Guarda |
|---|---|
| `~/.config/phantom/config` | O arquivo de configuração que você edita na mão |
| `~/.config/phantom/gui-settings` | Tudo o que a janela de Configurações escreve |
| `~/.config/phantom/themes/` | Temas que você importa ou cria |
| `~/.config/phantom/icon-themes/` | Temas de ícones de arquivo |
| `~/.config/phantom/extensions/` | Extensões instaladas |
| `~/Library/Application Support/com.ipetinate.phantom/` | Sessão, grupos da sidebar, histórico de undo |
| `~/.cache/phantom/` | O socket MCP e os arquivos de estado por aba |

O Phantom mantém o próprio diretório de configuração em vez de dividir o do
Ghostty, então os dois convivem na mesma máquina. Veja
[Configuração](/pt-br/docs/configuration/).

## Desinstalar

Apague `/Applications/Phantom.app` e, se quiser levar o estado junto, os quatro
diretórios acima.

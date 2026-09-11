---
title: Configuração
description: Dois arquivos, onde eles ficam, as chaves que o Phantom acrescenta, e os padrões que ele muda.
sidebar:
  label: Configuração
---

O Phantom lê o formato de configuração do Ghostty — `chave = valor`, um por
linha — a partir do próprio diretório.

## Onde

| | |
|---|---|
| Diretório | `$XDG_CONFIG_HOME/phantom/`, por padrão `~/.config/phantom/` |
| Seu | `config` — editado à mão, nunca reescrito |
| Do app | `gui-settings` — tudo o que a janela de Configurações escreve |

O `config` é seu. O Phantom acrescenta exatamente uma linha a ele, uma diretiva
`config-file` que puxa o `gui-settings`, e nada mais. Os valores do
`gui-settings` são lidos depois dos seus, então a janela de Configurações vence
numa chave definida nos dois — mova um valor para o `config` e apague-o do
painel para mantê-lo.

Um build cujo bundle identifier não é `com.ipetinate.phantom` usa um diretório
próprio. Veja [Compilar do fonte](/pt-br/docs/build-from-source/).

## As chaves que o Phantom acrescenta

| Chave | Tipo | Padrão | Significado |
|---|---|---|---|
| `sidebar` | bool | `false`, semeado `true` | Mostrar a sidebar e esconder a barra de abas nativa. Só macOS. |
| `sidebar-width` | inteiro | `480` | Largura da sidebar, em pontos. |

## Os padrões que o Phantom muda

| Chave | Ghostty | Phantom |
|---|---|---|
| `background-opacity` | `1.0` | `0.85`, semeado `0.70` |
| `background-blur` | desligado | raio `50`, semeado `80` |

"Semeado" é o valor que uma instalação nova escreve no `gui-settings`; o outro
é o padrão compilado, que vale quando ninguém escreveu a chave.

## Todo o resto

Cerca de 211 opções — fonte, cursor, scrollback, shell integration, keybinds,
comportamento de janela, cores — vêm do Ghostty sem alteração. Estão na
[referência do próprio Ghostty](https://ghostty.org/docs/config/reference), e o
mesmo texto está em `man 5 ghostty`.

Só ponha no `gui-settings` chaves que o Ghostty conhece. Uma chave
desconhecida ali levanta um erro de configuração na inicialização.

## Erros

Um valor inválido não falha em silêncio: o Phantom informa o arquivo, a linha e
a chave, e segue com o valor anterior.

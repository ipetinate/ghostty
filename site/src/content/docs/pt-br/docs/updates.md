---
title: Atualizações
description: Como o Phantom se atualiza pelo Sparkle, o que as três configurações fazem, e por que a primeira abertura é o único passo manual.
sidebar:
  label: Atualizações
---

O Phantom se atualiza no lugar, pelo [Sparkle](https://sparkle-project.org). O
feed é um appcast publicado como asset na página de Releases do próprio
repositório, então a página de Releases é toda a infraestrutura de atualização
— não existe servidor.

Cada release publica dois deles, um por build: o aplicativo universal lê o
`appcast.xml` e o de Apple silicon lê o `appcast-arm64.xml`. O aplicativo
decide qual contando as arquiteturas do próprio executável, então uma
atualização nunca troca um build pelo outro.

## As configurações

**Configurações › General** traz a versão em execução, um botão **Check Now** e
dois interruptores. Juntos eles soletram um valor de configuração,
`auto-update`:

| Valor | Comportamento |
|---|---|
| `off` | Nunca verifica. |
| `check` | Verifica em segundo plano e avisa. |
| `download` | Verifica, baixa antes, instala ao sair. |

Uma instalação nova é semeada com `download`. A semente só preenche uma chave
que ninguém definiu, então `off` sobrevive a um relaunch depois que você
escolhe.

## Instalação

Uma atualização instala quando você sai, não enquanto você trabalha. O Phantom
não se reinicia por baixo de você nem interrompe um agente rodando.

## O que você faz uma vez

A primeira cópia que você instala é assinada ad-hoc e não é notarizada, então o
Gatekeeper pede que você abra explicitamente — veja
[Instalação](/pt-br/docs/install/). Toda versão depois dessa chega pelo
Sparkle e nunca mais pergunta.

## Uma consequência que vale saber

O macOS amarra uma permissão de privacidade à assinatura exata do binário que a
recebeu. Como cada release é assinado ad-hoc em vez de com um certificado
Developer ID, **uma atualização zera as permissões que você concedeu ao
Phantom** — gravação de tela e acessibilidade entre elas. Conceda de novo
depois de atualizar, se você usa algum recurso que precise delas.

## Versões antigas

A 0.14.0 e anteriores não se atualizam sozinhas. Baixe o `.dmg` atual e
substitua o aplicativo; a sua configuração e a sua sessão ficam intactas.

---
title: Language servers
description: Nenhuma linguagem é compilada no binário. Cada uma chega como extensão que declara o servidor, e o Phantom o executa por LSP.
sidebar:
  label: Language servers
---

Desde a 0.17.0 o Phantom **não tem tabela de linguagens embutida**. Toda
linguagem existe porque uma extensão a declarou: os nomes de arquivo, a
gramática, o formatador e o servidor que responde sobre ela.

Instale uma linguagem pela loja — veja [Extensões](/phantom/pt-br/docs/extensions/).

## O que o editor ganha de um servidor

- Hover
- Ir para a definição e encontrar referências
- Renomear símbolo
- Autocompletar, com configurações por linguagem e globais
- Diagnósticos
- Code actions, incluindo fix-all quando o servidor oferece
- Formatação, quando o manifesto nomeia um formatador

## Os dois tipos de diagnóstico

Alguns servidores **empurram** diagnósticos enquanto você digita. Outros
declaram um provedor de diagnóstico e só respondem quando perguntados. O
Phantom faz os dois: lê a capacidade do servidor e, para um servidor de pull,
pergunta ao abrir, depois de uma alteração e no refresh. Um relatório
`unchanged` move o id do resultado e não escreve nada; um relatório `full` com
lista vazia limpa o arquivo.

Nos dois casos um único escritor é dono dos diagnósticos do arquivo, então um
servidor que empurra se comporta exatamente como sempre se comportou.

## Configurações que o servidor pede

Um servidor que lê a configuração por `workspace/configuration` — o ESLint é o
caso conhecido — a recebe de um bloco `settings` declarado no manifesto da
extensão. Uma seção que ninguém declarou é respondida como **null**, não como
objeto vazio: são respostas diferentes, e inventar a segunda é como um cliente
faz um servidor desligar um recurso que viria ligado por padrão.

## Quando duas extensões reivindicam o mesmo arquivo

O Phantom resolve nesta ordem: uma contribuição de usuário que você promoveu,
depois uma embutida promovida, depois usuário, depois embutida. Empates
resolvem pelo nome do diretório. A perdedora continua listada nas
Configurações, marcada como em conflito, então a disputa é visível em vez de
silenciosa.

## Sobrescrever como um servidor inicia

**Configurações › Extensions** permite trocar o comando de um servidor, seus
argumentos e as opções de inicialização, por linguagem. A sua sobrescrita vence
o manifesto e fica marcada como sua.

Um agente faz o mesmo por
[`configure_language_server`](/phantom/pt-br/docs/mcp/), e é por isso que mudar
a inicialização de um servidor é uma capacidade MCP própria, e não parte de
`run`.

## Quando um servidor falta

O editor diz isso no topo do arquivo, com o comando de instalação que a
extensão declarou, e um botão **Check Again**. Ele não falha em silêncio.

---
title: Escrever uma extensão
description: O manifesto extension.json, o que ele pode contribuir, as views que uma extensão desenha, e as regras que uma página não contorna.
sidebar:
  label: Escrever uma extensão
---

Uma extensão é um diretório com um `extension.json` na raiz. Nada é compilado;
o manifesto é lido na inicialização e relido quando muda.

## O manifesto

```json
{
  "schemaVersion": 1,
  "id": "solid",
  "name": "Solid",
  "version": "1.2.0",
  "publisher": "phantom",
  "contributes": { }
}
```

O arquivo tem teto de 512 KB, e os bytes crus dele são hasheados para o
registro de confiança. Um `schemaVersion` desconhecido mantém a metade que o
Phantom entende — as definições de linguagem — e descarta a metade de servidor
e formatador, informando que a extensão precisa de um app mais novo em vez de
falhar inteira.

Chaves desconhecidas dentro de `contributes` são contadas e reportadas nas
Configurações, nunca recusadas: uma extensão escrita para um Phantom futuro
ainda instala.

## O que ela pode contribuir

| Chave | O que acrescenta |
|---|---|
| `languages` | Nomes de arquivo, sufixos, sintaxe de comentário, um ícone, um servidor |
| `servers` | Um language server companheiro para uma linguagem que outro declarou |
| `formatters` | Um formatador, usado na formatação ao salvar |
| `grammars` | Uma gramática TextMate |
| `themes` | Temas de terminal |
| `iconThemes` | Um pacote de ícones de arquivo, metade clara e metade escura |
| `agents` | A definição de um agente de código |
| `views` | Um painel ou um editor que a extensão desenha |

Cada chave tem um máximo declarado.

### Uma linguagem

```json
{
  "languageId": "solid",
  "extensions": [".tsx"],
  "fileNames": [],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
  "icon": "solid",
  "server": {
    "command": "typescript-language-server",
    "args": ["--stdio"],
    "installHint": "npm i -g typescript-language-server",
    "initializationOptions": { },
    "settings": { }
  }
}
```

`settings` é o que um servidor lê de volta por `workspace/configuration`. Uma
seção pontuada entra no objeto; uma seção que você não declarou é respondida
como null. Veja [Language servers](/phantom/pt-br/docs/language-servers/).

## Views: uma extensão que desenha

Desde a 0.19.0 uma extensão pode renderizar uma página de verdade dentro do
Phantom. `contributes.views[]` declara cada uma, e `surface` diz o tipo:

- **`sidebar`** — um painel que a trilha da sidebar seleciona. Declara um
  posicionamento.
- **`editor`** — um editor associado a `filenamePatterns`, aberto para um
  arquivo que casa. Não declara posicionamento, e uma entrada `sidebar` que
  declara um padrão é recusada do mesmo jeito, então as duas formas ficam
  simétricas.

`filenamePatterns` recusa um separador de caminho: um editor reivindica um
**nome**, nunca um local. `priority: "option"` mantém o editor de texto como
padrão, porque um terceiro não deveria decidir como você abre um arquivo que
é, afinal, texto.

Uma view de editor é identificada pelo arquivo que mostra, então fechar,
reabrir, a marca de não salvo, ⌘W e a restauração de sessão são o comportamento
que o editor já tem, e não algo que a extensão reimplementa.

### O que a página alcança

A página é um módulo ES empacotado mais uma folha de estilo opcional, sob
`default-src 'none'`. Ela não toca em nada diretamente. Ela pede, e o app
responde **apenas os métodos que o manifesto declarou** — a string que o autor
escreve é a string que o app compara, sem tabela no meio.

Todo caminho é relativo. Um caminho absoluto, um `~`, uma barra invertida ou um
`..` é recusado **antes** de resolver, e o resultado é contido duas vezes: no
caminho, e de novo depois de resolver symlinks.

Três recusas merecem nome, porque são uma regra só — uma extensão instalada não
pode conseguir rodar código que você não pediu:

- **Nenhum segmento de caminho pode começar com ponto.** Isso fecha
  `.git/hooks/pre-commit`, `.github/workflows` e `.envrc`. É sintático de
  propósito: o conjunto de dotfiles perigosos não é fechado, então uma lista de
  nomes precisaria de uma entrada por ferramenta e ainda erraria no meio.
- **`workspace.replace` não alcança o diretório da própria extensão**, cujo
  `extension.json` é o que concede esses métodos.
- **`state.write` recusa uma chave que começa com `$`**, que é onde vive o
  workspace escolhido.

`workspace.create` e `workspace.replace` são declarações separadas, disjuntas
em vez de aninhadas: uma acrescenta um arquivo e recusa um caminho existente, a
outra escreve por cima e recusa um caminho ausente. Uma extensão que só
acrescenta arquivos não consegue sobrescrever o seu trabalho, e a lista
`permissions` dela diz qual das duas pediu.

## Publicar

Faça push em [ipetinate/phantom-extensions](https://github.com/ipetinate/phantom-extensions).
O workflow de lá empacota, calcula o digest e publica o índice a cada push na
`main`. A URL de download segue
`releases/download/<publisher>.<id>-v<version>/<publisher>.<id>-<version>.zip`.

Entregue um ícone de 128 px e um `extension.mdx` — essa página é o que a loja
mostra antes de alguém baixar o código.

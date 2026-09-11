---
title: Extensões
description: Instale linguagens, formatadores, temas, pacotes de ícones e agentes a partir do registro, e saiba o que é verificado antes de qualquer coisa ser descompactada.
sidebar:
  label: Extensões
---

As linguagens, os formatadores, os temas, os pacotes de ícones e as definições
de agente do Phantom não são compilados no binário. São extensões, instaladas
a partir de um registro.

## A loja

**Configurações › Extensions** lista o que o registro oferece, filtrado por
tipo — All, Languages, Formatters, Themes, Icons, Agents — e ordenado por nome,
por atualização recente ou por publisher.

Tudo o que a loja lista também dá para navegar neste site, em
[Extensões](/phantom/pt-br/extensions/) — o mesmo índice, as mesmas páginas de
documento.

O registro é [ipetinate/phantom-extensions](https://github.com/ipetinate/phantom-extensions).
O índice dele é um único arquivo JSON publicado como asset de release, então a
loja é um GET HTTPS simples, sem serviço por trás.

## O que é conferido antes de instalar

Cada entrada do índice carrega, para cada asset, uma **URL, um sha256 e um
tamanho em bytes** — os três obrigatórios. Uma entrada sem qualquer um deles é
recusada; não existe "baixar e torcer".

Ao instalar, o Phantom confere o tamanho e o digest, e só então descompacta. O
leitor do arquivo recusa caminhos absolutos, `..`, symlinks e caracteres
inseguros, então um pacote não consegue escrever fora do próprio diretório. As
extensões ficam em `~/.config/phantom/extensions/`, um diretório cada.

Uma extensão também declara uma **versão mínima do Phantom**. Abaixo dela, a
loja avisa em vez de instalar algo que não roda.

## Ler antes de instalar

Cada extensão tem uma página de documento — `extension.mdx` — renderizada na
loja sem baixar o código: navegar custa um documento pequeno, não o pacote.

A página é renderizada numa web view com content security policy estrita, sem
acesso à rede e sem scripts inline. É um documento, nunca executado.

## Sugestões

O Phantom oferece o que um arquivo precisa em vez de esperar que você peça.
Duas coisas levantam uma sugestão, e as duas aparecem como um cartão no canto
inferior direito do painel.

**Um arquivo que ninguém reivindica.** Abra um e, se nenhuma extensão instalada
cuidar daquele tipo de arquivo, o cartão nomeia as extensões do registry que
cuidam, com um botão de instalar. Depois da instalação, o cartão só volta se a
extensão ainda precisar de um programa que não está no seu `PATH` — um language
server ou um formatador — com o comando de instalação que a própria extensão
declarou.

**Um projeto que pede extensões.** Um repositório pode trazer a própria lista em
`.phantom/suggestions.json`, procurada a partir do diretório do terminal para
cima. O cartão mostra o ícone de cada extensão sugerida e instala todas de uma
vez.

```json
{
  "extensions": ["phantom.rust", "phantom.toml"],
  "message": "A toolchain com que este repositório é construído."
}
```

`extensions` guarda ids do registry, e o que já estiver instalado fica de fora
do cartão. `message` é opcional e substitui a lista de nomes no cartão.

Um cartão dispensado continua dispensado pelo resto da sessão.

## Confiança

Um manifesto que declara um **servidor** ou um **formatador** pede para rodar
um programa na sua máquina. O Phantom registra uma decisão de confiança,
indexada por um hash dos bytes do manifesto, e pergunta de novo quando o
manifesto muda.

Esse registro vive no `UserDefaults`, deliberadamente não ao lado do manifesto:
o diretório da extensão é gravável por quem pôs o manifesto ali, então uma
decisão de confiança guardada junto seria uma que o autor poderia se conceder
sozinho.

## Escrever uma

Veja [Escrever uma extensão](/phantom/pt-br/docs/extensions-authoring/).

---
title: Temas e ícones
description: O catálogo de temas, o criador embutido, pacotes de ícones de arquivo, ícones que leem o projeto, e os ícones alternativos do app.
sidebar:
  label: Temas e ícones
---

## Temas de terminal

O Phantom traz o catálogo completo do Ghostty mais o próprio, e a interface do
app — Configurações, Sobre, o navegador de temas — segue o tema ativo em vez do
modo claro/escuro do sistema. Escolher um tema escuro não deixa você com uma
janela de configurações branca.

Uma instalação nova começa no **Dracula by Phantom**, escrito em
`~/.config/phantom/themes/` como arquivo de verdade em vez de referenciado por
nome.

### Criar um

O criador de temas é embutido, com preview ao vivo: edite fundo, texto, cursor,
seleção e as dezesseis cores da paleta, e veja um terminal se repintar
enquanto você mexe. O que você faz vai para o seu diretório de temas e pode ser
compartilhado como arquivo simples.

### Materiais e opacidade

A janela é translúcida sobre um `NSVisualEffectView`. Dois materiais —
**Soft** e **Deep** — e um controle de opacidade. Uma instalação nova começa
em Deep, a 0.45.

## Ícones de arquivo

Pacotes de ícones vêm de extensões. Qualquer tema de ícones do VS Code baseado
em SVG funciona: ponha a pasta da extensão em `~/.config/phantom/icon-themes/`,
um diretório por tema, cada um com o próprio `icon-theme.json`.

Um pacote declara as duas metades — a clara e a escura — e o Phantom usa a que
combina com o tema ativo.

### Ícones que leem o projeto

Um sufixo nem sempre diz qual framework escreveu o arquivo. React, Solid,
Preact e Qwik escrevem `.tsx`; `user.service.ts` é Angular num projeto e NestJS
em outro.

O Phantom lê o `package.json` mais próximo subindo a partir do arquivo e escolhe
o ícone pelas dependências do projeto. Um `.tsx` num projeto que depende de
`solid-js` usa o ícone do Solid.

## O ícone do aplicativo

Nove ícones alternativos vêm com o app, incluindo cinco tributos ao Ghostty.
Escolha em **Configurações › Appearance**; o Dock, o alternador e o Finder
acompanham na hora.

## Fontes

Um seletor de fontes busca em toda fonte instalada na máquina, com preview ao
vivo, e guarda duas escolhas separadas: uma para o terminal, outra para a
interface do Phantom.

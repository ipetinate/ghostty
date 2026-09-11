---
title: Atalhos de teclado
description: As três camadas de atalhos — os do Ghostty, os comandos remapeáveis do Phantom, e as teclas fixas de painel.
sidebar:
  label: Atalhos
---

O Phantom tem três conjuntos de atalhos. Saber a qual conjunto uma tecla
pertence já diz onde mudá-la.

## 1. Comandos do Phantom — remapeáveis

Dezessete comandos, em **Configurações › Keyboard Shortcuts**. Cada um pode ser
remapeado, e o painel recusa uma combinação que colida com outra.

### Explorador de arquivos

| Comando | Padrão |
|---|---|
| Novo arquivo | ⇧⌘N |
| Nova pasta | ⇧⌘M |
| Buscar no workspace | ⌥⌘F |

### Editor

| Comando | Padrão |
|---|---|
| Salvar | ⌘S |
| Salvar tudo | ⇧⌘S |
| Fechar aba | ⌘W |
| Buscar no arquivo | ⌘F |
| Formatar documento | ⇧⌘F |
| Sugestões | ⌃Space |
| Quick fix | ⌃. |
| Ir para a definição | ⌃⌘J |
| Encontrar referências | ⌃⌘G |
| Renomear símbolo | ⌃⌘R |
| Mover linha para cima | ⌥↑ |
| Mover linha para baixo | ⌥↓ |
| Anexar linha ao agente | ⌘K |
| Anexar linha ao agente (seletor) | ⇧⌘K |

## 2. Teclas de painel — fixas

Estas não são remapeáveis.

| Tecla | Ação |
|---|---|
| ⌥⌘\\ | Alternar entre terminal e editor |
| ⌥⌘1 … ⌥⌘9 | Selecionar o n-ésimo arquivo aberto |
| ⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ | Dividir o painel naquela direção |

Recolher a sidebar não tem atalho; é o botão na barra de título.

## 3. Ações de terminal do Ghostty

Tudo o que o terminal em si faz — nova janela, splits, scrollback, busca,
copiar e colar, tamanho da fonte — vem do Ghostty e se configura com linhas
`keybind` no arquivo de configuração. **Configurações › Keyboard Shortcuts**
lista cerca de 75 dessas ações, em sete grupos, e escreve as linhas `keybind`
por você.

O Phantom muda duas coisas nessa camada:

- `alt+backspace` apaga a palavra à esquerda, seja qual for o valor de
  `macos-option-as-alt`.
- Undo e redo (⌘Z, ⇧⌘Z, ⇧⌘T) nunca digitam um caractere literal no terminal
  quando não há o que desfazer.

A sintaxe e a lista completa estão na
[documentação do Ghostty](https://ghostty.org/docs/config/keybind).

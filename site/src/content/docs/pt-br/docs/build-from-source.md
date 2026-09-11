---
title: Compilar do código-fonte
description: Compile o Phantom com Zig e Xcode, rode as verificações, e saiba qual build escreve onde.
sidebar:
  label: Compilar do fonte
---

O Phantom compila exatamente como o Ghostty. Leia o
[`HACKING.md`](https://github.com/ipetinate/phantom/blob/main/HACKING.md) do
repositório para o setup completo do toolchain; esta página cobre o que é
específico do fork.

## Compilar

```sh
git clone https://github.com/ipetinate/phantom.git
cd phantom
zig build -Doptimize=ReleaseFast
```

O bundle do macOS sai de um passo `xcodebuild` que o `zig build` conduz. Pule
esse passo quando você só precisa do core:

```sh
zig build -Demit-macos-app=false
```

Rode o `xcodebuild` a partir de `macos/`, nunca da raiz do repositório: na raiz
ele escreve o `GhosttyKit.xcframework` no diretório atual e o build seguinte
falha com "Multiple commands produce".

## Verificações

```sh
zig fmt --check .
swiftlint lint --strict macos/Sources
zig build test -Dtest-filter=<nome>
```

`zig build test` sem filtro é lento. A suíte completa, a suíte Swift e o build
do macOS rodam no CI a cada pull request.

## Um build de desenvolvimento escreve em outro lugar

Um build cujo bundle identifier não é `com.ipetinate.phantom` é tratado como
variante, e tudo o que ele escreve carrega o nome da variante:

| | Build de release | Build de debug |
|---|---|---|
| Configuração | `~/.config/phantom/` | `~/.config/phantom-debug/` |
| Estado | `…/com.ipetinate.phantom/` | `…/com.ipetinate.phantom.debug/` |
| Socket MCP | `…phantom.sock` | `…phantom.debug.sock` |
| Hooks dos agentes | `phantom-*.sh` | `phantom-debug-*.sh` |

Na primeira abertura, a variante copia o seu `config` e o `gui-settings` — uma
cópia, nunca um move, e nunca por cima de um arquivo que já existe. Então um
build que você fez não consegue escrever sobre a configuração do build que você
usa.

## Versão

O `build.zig.zon` declara a versão e o `MARKETING_VERSION` do projeto Xcode a
repete. O CI falha quando as duas divergem, porque o Sparkle compara a cópia do
Xcode com o appcast para decidir se um update é mais novo.

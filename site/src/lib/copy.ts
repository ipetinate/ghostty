export type Feature = {
  index: string;
  title: string;
  body: string[];
  links: { label: string; href: string }[];
  /** Names the clip, the screenshot and the fallback, in that order. */
  media: string;
  alt: string;
  code?: { label: string; lang: string; body: string };
};

export type Copy = {
  lang: string;
  htmlLang: string;
  docsHome: string;
  nav: { docs: string; extensions: string; github: string; skip: string };
  hero: {
    titleLead: string;
    titleEm: string;
    titleTail: string;
    lede: string;
    download: string;
    docs: string;
    meta: string[];
    counter: string;
    shotAlt: string;
  };
  credit: { label: string; body: string[] };
  featuresLabel: string;
  features: Feature[];
  numbers: { value: string; label: string }[];
  download: {
    title: string;
    body: string;
    button: string;
    other: string;
    gatekeeperTitle: string;
    gatekeeperBody: string;
    updatesTitle: string;
    updatesBody: string;
  };
  footer: { legal: string; links: { label: string; href: string }[] };
  emptyShot: string;
  lightbox: { expand: string; close: string };
  tour: {
    caption: string;
    play: string;
    pause: string;
    back: string;
    forward: string;
    fullscreen: string;
    pip: string;
    seek: string;
    chapters: { at: number; label: string }[];
  };
  store: {
    title: string;
    lede: string;
    search: string;
    kinds: Record<string, string>;
    contributes: Record<string, string>;
    empty: string;
    generated: string;
    countLabel: string;
    back: string;
    install: string;
    installBody: string;
    openRegistry: string;
    download: string;
    fields: {
      version: string;
      publisher: string;
      license: string;
      updated: string;
      requires: string;
      size: string;
      releases: string;
      contributes: string;
      tags: string;
      homepage: string;
    };
    documentMissing: string;
  };
  downloads: {
    title: string;
    lede: string;
    now: string;
    soon: string;
    counted: string;
    get: string;
    checksum: string;
    targets: {
      universal: { name: string; detail: string };
      arm: { name: string; detail: string };
      linux: { name: string; detail: string };
    };
  };
};

const docsPath = (slug: string, prefix = "") => `${prefix}docs/${slug}/`;

export const en: Copy = {
  lang: "en",
  htmlLang: "en",
  docsHome: docsPath("install"),
  nav: {
    docs: "Documentation",
    extensions: "Extensions",
    github: "GitHub",
    skip: "Skip to content",
  },
  hero: {
    titleLead: "Your whole workflow, ",
    titleEm: "inside",
    titleTail: " the terminal.",
    lede: "Phantom is a macOS terminal built on Ghostty's engine. Around it: a sidebar that groups your projects, an editor with language servers, git and worktrees, and the coding agents you already run. One window, no alt-tab.",
    download: "Download for macOS",
    docs: "Read the documentation",
    meta: ["macOS 13 or later", "Apple silicon and Intel", "MIT"],
    counter: "downloads",
    shotAlt:
      "The Phantom window: sidebar with grouped terminals on the left, an editor and a terminal on the right.",
  },
  credit: {
    label: "Built on Ghostty",
    body: [
      "Phantom is a personal fork of Ghostty by Mitchell Hashimoto and its contributors. Everything that makes a terminal a terminal — the multi-threaded core, the Metal renderer, the standards-compliant VT emulation, libghostty — is theirs, and it is untouched here.",
      "This fork adds the application around that engine, and it tracks upstream so it can keep merging. For the engine itself — performance, supported sequences, platform notes — read Ghostty's own documentation.",
    ],
  },
  featuresLabel: "What the app adds",
  features: [
    {
      index: "01",
      title: "Tabs that carry the project with them",
      body: [
        "Group terminals by hand, or point a group at a project folder and every terminal opened underneath it joins on its own.",
        "Each row states where it stands: the branch, a dot when the checkout is dirty, the open pull request for that branch, and a clickable :3000 the moment a dev server binds a port. The port detection reads the process, not a config file, so it works for any framework.",
      ],
      links: [{ label: "Sidebar and groups", href: docsPath("sidebar-and-groups") }],
      media: "groups",
      alt: "Sidebar showing terminals grouped by project, each row with its branch and dev-server port.",
    },
    {
      index: "02",
      title: "The agent's state, on the tab",
      body: [
        "Claude Code, Codex, OpenCode, Antigravity, Kimi Code and Pi. A row shows whether its session is working, waiting on you, or done \u2014 so a dozen agents across a dozen repositories stop being a dozen identical tabs.",
        "Sessions resume where they left off when a tab reopens, and the hooks that report the state install from Settings with one click.",
      ],
      links: [{ label: "Agents", href: docsPath("agents") }],
      media: "agents",
      alt: "Terminal tabs in the sidebar showing per-agent status badges.",
    },
    {
      index: "03",
      title: "An editor in the same pane",
      body: [
        "Open a file next to the terminal that produced it. Syntax grammars, a minimap, workspace-wide search, format on save, and a grid you can split in any direction.",
        "Language servers arrive from the store rather than the binary, and bring hover, definition, references, rename, completion and diagnostics with them. Markdown, images, PDF, SVG and CSV each open in a viewer of their own.",
      ],
      links: [
        { label: "The editor", href: docsPath("editor") },
        { label: "Language servers", href: docsPath("language-servers") },
      ],
      media: "editor",
      alt: "The Phantom editor beside a terminal, with a minimap and a split pane.",
    },
    {
      index: "04",
      title: "Git, and a worktree for every branch",
      body: [
        "Status and staging in the sidebar, conflicts resolved in the file itself rather than in a separate tool, split diffs, and a branch review of every commit and file against the base.",
        "Create or adopt a git worktree from the same place, one section per repository. Switch a terminal's worktree and the open editor tabs follow it; a file with no counterpart on the other side opens read-only and says why.",
      ],
      links: [
        { label: "Git", href: docsPath("git") },
        { label: "Worktrees", href: docsPath("worktrees") },
      ],
      media: "git",
      code: {
        label: "branch review",
        lang: "diff",
        body: `--- feat/status-dots against main        4 commits, 6 files

    7b4b688  Wire the status dots to the session state
    5f6655d  Group sessions by workspace
    9a1c204  Keep a waiting session at the top
    c31f8ad  Read the state from the hook, not the title

+++ src/lib/session.ts             18 added, 4 removed
+++ src/components/StatusDot.tsx    9 added, 1 removed
+++ src/lib/worktree.ts            21 added, 0 removed`,
      },
      alt: "The git panel with staged and unstaged changes beside a split diff.",
    },
    {
      index: "05",
      title: "Agents can drive the window",
      body: [
        "Phantom is an MCP server. Twenty-five tools across terminals, groups, the editor, diagnostics, language servers and worktrees: open a file at a line, read a terminal's output, create a worktree, list the diagnostics a server reported.",
        "Every terminal exports the socket, the handshake verifies the peer's process id, and each capability is granted by you in a prompt \u2014 scoped to one tab, one group, or everything.",
      ],
      links: [{ label: "The MCP server", href: docsPath("mcp") }],
      media: "mcp",
      code: {
        label: "tools/call",
        lang: "jsonc",
        body: `{
  "method": "tools/call",
  "params": {
    "name": "open_file",
    "arguments": {
      "path": "/Users/me/atlas-web/src/lib/session.ts",
      "line": 24
    }
  }
}

// -> Opened session.ts in this window's editor.`,
      },
      alt: "The MCP settings pane listing connected clients and their granted capabilities.",
    },
    {
      index: "06",
      title: "An extension store, and a look of your own",
      body: [
        "Languages, formatters, themes, icon packs and agents install from a registry, and every download is checked against the sha256 in the index before it is unpacked.",
        "Since 0.19.0 an extension can also draw: a panel in the sidebar or an editor bound to a file name, written in TypeScript. Themes and icon packs come from the same place, and the app's own chrome follows whichever theme is active.",
      ],
      links: [
        { label: "Extensions", href: docsPath("extensions") },
        { label: "Themes and icons", href: docsPath("themes-and-icons") },
      ],
      media: "extensions",
      code: {
        label: "index.json",
        lang: "json",
        body: `{
  "id": "typescript",
  "publisher": "phantom",
  "version": "2.1.0",
  "minimumPhantomVersion": "0.17.0",
  "contributes": ["languages", "servers", "grammars"],
  "download": {
    "url": ".../phantom.typescript-2.1.0.zip",
    "sha256": "9f2b\u2026c41d",
    "bytes": 184320
  }
}`,
      },
      alt: "The extension store showing installable languages, themes and icon packs.",
    },
  ],
  numbers: [
    { value: "25", label: "MCP tools" },
    { value: "6", label: "coding agents" },
    { value: "13+", label: "macOS version" },
    { value: "MIT", label: "license" },
  ],
  download: {
    title: "Download Phantom",
    body: "A universal .dmg and an Apple-silicon-only one, built and published from this repository on every release. Requires macOS 13 Ventura or later.",
    button: "Download the .dmg",
    other: "All releases",
    gatekeeperTitle: "First launch",
    gatekeeperBody:
      "The app is ad-hoc signed and not notarized. On first launch, right-click it and choose Open — or run <code>xattr -cr Phantom.app</code> — instead of double-clicking, or Gatekeeper will refuse it as coming from an unidentified developer.",
    updatesTitle: "Updates",
    updatesBody:
      "Every later version arrives in place through Phantom &rsaquo; Check for Updates, and stays on the build you installed — a universal app never updates into the Apple silicon one, or the other way round. A fresh install checks in the background and installs at the next quit; you can turn that off in Settings.",
  },
  footer: {
    legal:
      "Phantom is MIT licensed, and so is Ghostty, the terminal it is built on. Phantom is not affiliated with the Ghostty project.",
    links: [
      { label: "Documentation", href: docsPath("install") },
      { label: "Extensions", href: "extensions/" },
      { label: "Registry", href: "https://github.com/ipetinate/phantom-extensions" },
      { label: "Repository", href: "https://github.com/ipetinate/phantom" },
      { label: "Ghostty", href: "https://ghostty.org" },
    ],
  },
  emptyShot: "screenshot pending",
  lightbox: { expand: "Expand this screenshot", close: "Close" },
  tour: {
    caption:
      "A pass over the whole application, four minutes, no sound. Nothing loads until you press play.",
    play: "Play the tour",
    pause: "Pause",
    back: "Back ten seconds",
    forward: "Forward ten seconds",
    fullscreen: "Full screen",
    pip: "Picture in picture",
    seek: "Seek",
    chapters: [
      { at: 0, label: "Welcome" },
      { at: 52, label: "Appearance" },
      { at: 62, label: "Sidebar and groups" },
      { at: 82, label: "Files" },
      { at: 90, label: "Extension store" },
      { at: 107, label: "The editor" },
      { at: 140, label: "A language server" },
      { at: 190, label: "Groups and tabs" },
    ],
  },
  store: {
    title: "Extensions",
    lede: "Languages, formatters, themes, icon packs and agents, from the registry Phantom itself reads. Install any of them from Settings \u203a Extensions, inside the app.",
    search: "Search extensions",
    kinds: {
      all: "All",
      languages: "Languages",
      formatters: "Formatters",
      themes: "Themes",
      icons: "Icons",
      agents: "Agents",
    },
    contributes: {
      languages: "Languages",
      servers: "Language servers",
      formatters: "Formatters",
      grammars: "Grammars",
      themes: "Themes",
      iconThemes: "Icon packs",
      agents: "Agents",
      views: "Views",
    },
    empty: "Nothing matches that.",
    generated: "Index generated",
    countLabel: "extensions",
    back: "All extensions",
    install: "How to install",
    installBody:
      "Open Phantom, go to Settings \u203a Extensions, find it by name and press Install. The app verifies the download against the sha256 in the index before unpacking it.",
    openRegistry: "Source",
    download: "Download the package",
    fields: {
      version: "Version",
      publisher: "Publisher",
      license: "License",
      updated: "Updated",
      requires: "Requires Phantom",
      size: "Package",
      releases: "Releases",
      contributes: "Contributes",
      tags: "Tags",
      homepage: "Homepage",
    },
    documentMissing: "This extension ships no document page.",
  },
  downloads: {
    title: "Download Phantom",
    lede: "Two builds today, and the one the fork is working towards. Every release is published from this repository, with the appcast each build updates itself from beside it.",
    now: "Available",
    soon: "Coming soon",
    counted: "downloads since",
    get: "Download the .dmg",
    checksum: "macOS 13 Ventura or later",
    targets: {
      universal: {
        name: "macOS \u00b7 Universal",
        detail:
          "One .dmg holding both slices: it runs natively on Apple silicon and on Intel, with no Rosetta in between. This is the build every release ships and the one Check for Updates follows.",
      },
      arm: {
        name: "macOS \u00b7 Apple silicon only",
        detail:
          "The same app with the Intel half left out \u2014 about half the download, and nothing else different. The universal build above already runs natively on Apple silicon, so this is a smaller file rather than a faster one.",
      },
      linux: {
        name: "Linux",
        detail:
          "Ghostty's own GTK application runs on Linux today; Phantom's sidebar, editor and settings are written in AppKit and do not. Porting them is the work this target waits on.",
      },
    },
  },
};

export const ptBr: Copy = {
  lang: "pt-br",
  htmlLang: "pt-BR",
  docsHome: docsPath("install", "pt-br/"),
  nav: {
    docs: "Documentação",
    extensions: "Extensões",
    github: "GitHub",
    skip: "Ir para o conteúdo",
  },
  hero: {
    titleLead: "Todo seu fluxo de trabalho, ",
    titleEm: "dentro",
    titleTail: " do terminal.",
    lede: "Phantom é um terminal para macOS construído sobre o motor do Ghostty. Em volta dele: uma sidebar que agrupa seus projetos, um editor com language servers, git e worktrees, e os agentes de código que você já usa. Uma janela só, sem alt-tab.",
    download: "Baixar para macOS",
    docs: "Ler a documentação",
    meta: ["macOS 13 ou superior", "Apple silicon e Intel", "MIT"],
    counter: "downloads",
    shotAlt:
      "A janela do Phantom: sidebar com terminais agrupados à esquerda, um editor e um terminal à direita.",
  },
  credit: {
    label: "Construído sobre o Ghostty",
    body: [
      "Phantom é um fork pessoal do Ghostty, de Mitchell Hashimoto e seus contribuidores. Tudo o que faz de um terminal um terminal — o núcleo multi-thread, o renderizador Metal, a emulação VT em conformidade com os padrões, a libghostty — é deles, e aqui está intocado.",
      "Este fork acrescenta a aplicação em volta desse motor, e acompanha o upstream para continuar fazendo merge. Para o motor em si — desempenho, sequências suportadas, notas de plataforma — leia a documentação do próprio Ghostty.",
    ],
  },
  featuresLabel: "O que o app acrescenta",
  features: [
    {
      index: "01",
      title: "Abas que carregam o projeto junto",
      body: [
        "Agrupe terminais na m\u00e3o, ou aponte um grupo para a pasta de um projeto: todo terminal aberto sob ela entra no grupo sozinho.",
        "Cada linha diz onde est\u00e1: a branch, um ponto quando h\u00e1 altera\u00e7\u00f5es n\u00e3o commitadas, o pull request aberto daquela branch, e um :3000 clic\u00e1vel no instante em que um dev server abre a porta. A detec\u00e7\u00e3o l\u00ea o processo, n\u00e3o um arquivo de configura\u00e7\u00e3o, ent\u00e3o funciona com qualquer framework.",
      ],
      links: [{ label: "Sidebar e grupos", href: docsPath("sidebar-and-groups", "pt-br/") }],
      media: "groups",
      alt: "Sidebar com terminais agrupados por projeto, cada linha com sua branch e a porta do dev server.",
    },
    {
      index: "02",
      title: "O estado do agente, na aba",
      body: [
        "Claude Code, Codex, OpenCode, Antigravity, Kimi Code e Pi. Uma linha mostra se a sess\u00e3o est\u00e1 trabalhando, esperando por voc\u00ea ou conclu\u00edda \u2014 assim uma d\u00fazia de agentes em uma d\u00fazia de reposit\u00f3rios deixa de ser uma d\u00fazia de abas id\u00eanticas.",
        "As sess\u00f5es retomam de onde pararam quando a aba reabre, e os hooks que reportam esse estado se instalam nas Configura\u00e7\u00f5es com um clique.",
      ],
      links: [{ label: "Agentes", href: docsPath("agents", "pt-br/") }],
      media: "agents",
      alt: "Abas de terminal na sidebar mostrando o status de cada agente.",
    },
    {
      index: "03",
      title: "Um editor no mesmo painel",
      body: [
        "Abra o arquivo ao lado do terminal que o produziu. Gram\u00e1ticas de sintaxe, minimapa, busca em todo o workspace, formata\u00e7\u00e3o ao salvar e uma grade que voc\u00ea divide em qualquer dire\u00e7\u00e3o.",
        "Os language servers v\u00eam da loja, n\u00e3o do bin\u00e1rio, e trazem hover, defini\u00e7\u00e3o, refer\u00eancias, renomear, autocompletar e diagn\u00f3sticos junto. Markdown, imagem, PDF, SVG e CSV abrem cada um no seu visualizador.",
      ],
      links: [
        { label: "O editor", href: docsPath("editor", "pt-br/") },
        { label: "Language servers", href: docsPath("language-servers", "pt-br/") },
      ],
      media: "editor",
      alt: "O editor do Phantom ao lado de um terminal, com minimapa e painel dividido.",
    },
    {
      index: "04",
      title: "Git, e uma worktree para cada branch",
      body: [
        "Status e staging na sidebar, conflitos resolvidos no pr\u00f3prio arquivo em vez de em outra ferramenta, diffs divididos, e um branch review de cada commit e arquivo contra a base.",
        "Crie ou adote uma worktree do git no mesmo lugar, uma se\u00e7\u00e3o por reposit\u00f3rio. Troque a worktree de um terminal e as abas abertas do editor acompanham; um arquivo sem correspondente do outro lado abre somente leitura e diz por qu\u00ea.",
      ],
      links: [
        { label: "Git", href: docsPath("git", "pt-br/") },
        { label: "Worktrees", href: docsPath("worktrees", "pt-br/") },
      ],
      media: "git",
      code: {
        label: "branch review",
        lang: "diff",
        body: `--- feat/status-dots against main        4 commits, 6 files

    7b4b688  Wire the status dots to the session state
    5f6655d  Group sessions by workspace
    9a1c204  Keep a waiting session at the top
    c31f8ad  Read the state from the hook, not the title

+++ src/lib/session.ts             18 added, 4 removed
+++ src/components/StatusDot.tsx    9 added, 1 removed
+++ src/lib/worktree.ts            21 added, 0 removed`,
      },
      alt: "O painel de git com altera\u00e7\u00f5es staged e unstaged ao lado de um diff dividido.",
    },
    {
      index: "05",
      title: "Agentes podem dirigir a janela",
      body: [
        "Phantom \u00e9 um servidor MCP. Vinte e cinco ferramentas entre terminais, grupos, editor, diagn\u00f3sticos, language servers e worktrees: abrir um arquivo numa linha, ler a sa\u00edda de um terminal, criar uma worktree, listar os diagn\u00f3sticos que um servidor reportou.",
        "Todo terminal exporta o socket, o handshake confere o pid do processo do outro lado, e cada capacidade \u00e9 concedida por voc\u00ea num aviso \u2014 no escopo de uma aba, de um grupo ou de tudo.",
      ],
      links: [{ label: "O servidor MCP", href: docsPath("mcp", "pt-br/") }],
      media: "mcp",
      code: {
        label: "tools/call",
        lang: "jsonc",
        body: `{
  "method": "tools/call",
  "params": {
    "name": "open_file",
    "arguments": {
      "path": "/Users/me/atlas-web/src/lib/session.ts",
      "line": 24
    }
  }
}

// -> Opened session.ts in this window's editor.`,
      },
      alt: "O painel de configura\u00e7\u00f5es do MCP listando clientes conectados e as capacidades concedidas.",
    },
    {
      index: "06",
      title: "Uma loja de extens\u00f5es, e uma cara sua",
      body: [
        "Linguagens, formatadores, temas, pacotes de \u00edcones e agentes se instalam a partir de um registro, e todo download \u00e9 conferido contra o sha256 do \u00edndice antes de ser descompactado.",
        "Desde a 0.19.0 uma extens\u00e3o tamb\u00e9m desenha: um painel na sidebar ou um editor associado a um nome de arquivo, escrito em TypeScript. Temas e pacotes de \u00edcones v\u00eam do mesmo lugar, e a interface do app segue o tema ativo.",
      ],
      links: [
        { label: "Extens\u00f5es", href: docsPath("extensions", "pt-br/") },
        { label: "Temas e \u00edcones", href: docsPath("themes-and-icons", "pt-br/") },
      ],
      media: "extensions",
      code: {
        label: "index.json",
        lang: "json",
        body: `{
  "id": "typescript",
  "publisher": "phantom",
  "version": "2.1.0",
  "minimumPhantomVersion": "0.17.0",
  "contributes": ["languages", "servers", "grammars"],
  "download": {
    "url": ".../phantom.typescript-2.1.0.zip",
    "sha256": "9f2b\u2026c41d",
    "bytes": 184320
  }
}`,
      },
      alt: "A loja de extens\u00f5es mostrando linguagens, temas e pacotes de \u00edcones instal\u00e1veis.",
    },
  ],
  numbers: [
    { value: "25", label: "ferramentas MCP" },
    { value: "6", label: "agentes de código" },
    { value: "13+", label: "versão do macOS" },
    { value: "MIT", label: "licença" },
  ],
  download: {
    title: "Baixe o Phantom",
    body: "Um .dmg universal e um só de Apple silicon, construídos e publicados a partir deste repositório a cada release. Requer macOS 13 Ventura ou superior.",
    button: "Baixar o .dmg",
    other: "Todos os releases",
    gatekeeperTitle: "Primeira abertura",
    gatekeeperBody:
      "O app é assinado ad-hoc e não é notarizado. Na primeira vez, clique com o botão direito e escolha Abrir — ou rode <code>xattr -cr Phantom.app</code> — em vez de dar dois cliques, senão o Gatekeeper recusa o app como sendo de um desenvolvedor não identificado.",
    updatesTitle: "Atualizações",
    updatesBody:
      "Toda versão seguinte chega no lugar, por Phantom &rsaquo; Check for Updates, e continua no build que você instalou — um app universal nunca vira o de Apple silicon, nem o contrário. Uma instalação nova verifica em segundo plano e instala ao sair; você pode desligar isso nas Configurações.",
  },
  footer: {
    legal:
      "Phantom é licenciado sob MIT, assim como o Ghostty, o terminal sobre o qual ele é construído. Phantom não é afiliado ao projeto Ghostty.",
    links: [
      { label: "Documentação", href: docsPath("install", "pt-br/") },
      { label: "Extensões", href: "pt-br/extensions/" },
      { label: "Registro", href: "https://github.com/ipetinate/phantom-extensions" },
      { label: "Repositório", href: "https://github.com/ipetinate/phantom" },
      { label: "Ghostty", href: "https://ghostty.org" },
    ],
  },
  emptyShot: "screenshot pendente",
  lightbox: { expand: "Ampliar este screenshot", close: "Fechar" },
  tour: {
    caption:
      "Uma passada pelo aplicativo inteiro, quatro minutos, sem som. Nada carrega at\u00e9 voc\u00ea apertar play.",
    play: "Assistir ao tour",
    pause: "Pausar",
    back: "Voltar dez segundos",
    forward: "Avan\u00e7ar dez segundos",
    fullscreen: "Tela cheia",
    pip: "Picture in picture",
    seek: "Avan\u00e7ar para",
    chapters: [
      { at: 0, label: "Boas-vindas" },
      { at: 52, label: "Apar\u00eancia" },
      { at: 62, label: "Sidebar e grupos" },
      { at: 82, label: "Arquivos" },
      { at: 90, label: "Loja de extens\u00f5es" },
      { at: 107, label: "O editor" },
      { at: 140, label: "Um language server" },
      { at: 190, label: "Grupos e abas" },
    ],
  },
  store: {
    title: "Extens\u00f5es",
    lede: "Linguagens, formatadores, temas, pacotes de \u00edcones e agentes, do mesmo registro que o Phantom l\u00ea. Instale qualquer um por Configura\u00e7\u00f5es \u203a Extensions, dentro do app.",
    search: "Buscar extens\u00f5es",
    kinds: {
      all: "Todas",
      languages: "Linguagens",
      formatters: "Formatadores",
      themes: "Temas",
      icons: "\u00cdcones",
      agents: "Agentes",
    },
    contributes: {
      languages: "Linguagens",
      servers: "Language servers",
      formatters: "Formatadores",
      grammars: "Gram\u00e1ticas",
      themes: "Temas",
      iconThemes: "Pacotes de \u00edcones",
      agents: "Agentes",
      views: "Views",
    },
    empty: "Nada corresponde a isso.",
    generated: "\u00cdndice gerado em",
    countLabel: "extens\u00f5es",
    back: "Todas as extens\u00f5es",
    install: "Como instalar",
    installBody:
      "Abra o Phantom, v\u00e1 em Configura\u00e7\u00f5es \u203a Extensions, procure pelo nome e clique em Install. O app confere o download contra o sha256 do \u00edndice antes de descompactar.",
    openRegistry: "Fonte",
    download: "Baixar o pacote",
    fields: {
      version: "Vers\u00e3o",
      publisher: "Publisher",
      license: "Licen\u00e7a",
      updated: "Atualizado",
      requires: "Requer o Phantom",
      size: "Pacote",
      releases: "Releases",
      contributes: "Contribui",
      tags: "Tags",
      homepage: "P\u00e1gina",
    },
    documentMissing: "Esta extens\u00e3o n\u00e3o traz p\u00e1gina de documento.",
  },
  downloads: {
    title: "Baixe o Phantom",
    lede: "Dois builds hoje, e o que o fork ainda persegue. Todo release sai deste reposit\u00f3rio, com o appcast pelo qual cada build se atualiza ao lado.",
    now: "Dispon\u00edvel",
    soon: "Em breve",
    counted: "downloads desde",
    get: "Baixar o .dmg",
    checksum: "macOS 13 Ventura ou superior",
    targets: {
      universal: {
        name: "macOS \u00b7 Universal",
        detail:
          "Um .dmg com as duas fatias: roda nativo em Apple silicon e em Intel, sem Rosetta no meio. \u00c9 o build de todo release e o que o Check for Updates acompanha.",
      },
      arm: {
        name: "macOS \u00b7 s\u00f3 Apple silicon",
        detail:
          "O mesmo app sem a metade Intel \u2014 cerca de metade do download, e nada mais de diferente. O universal acima j\u00e1 roda nativo em Apple silicon, ent\u00e3o este \u00e9 um arquivo menor, n\u00e3o um app mais r\u00e1pido.",
      },
      linux: {
        name: "Linux",
        detail:
          "O aplicativo GTK do pr\u00f3prio Ghostty roda em Linux hoje; a sidebar, o editor e as configura\u00e7\u00f5es do Phantom s\u00e3o AppKit e n\u00e3o rodam. Portar isso \u00e9 o trabalho que este alvo espera.",
      },
    },
  },
};

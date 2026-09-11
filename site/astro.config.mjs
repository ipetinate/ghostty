// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import sitemap from "@astrojs/sitemap";
import icon from "astro-icon";

export default defineConfig({
  site: "https://ipetinate.github.io",
  base: "/phantom",
  trailingSlash: "always",
  integrations: [
    starlight({
      title: "Phantom",
      description:
        "A Ghostty-powered terminal for macOS with a sidebar, an editor, git, worktrees, language servers, agents and an extension store.",
      logo: {
        src: "./src/assets/phantom-mark.svg",
        replacesTitle: false,
      },
      favicon: "/favicon.svg",
      customCss: ["./src/styles/docs.css"],
      expressiveCode: { themes: ["dracula"] },
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/ipetinate/phantom",
        },
      ],
      editLink: {
        baseUrl: "https://github.com/ipetinate/phantom/edit/main/site/",
      },
      defaultLocale: "root",
      locales: {
        root: { label: "English", lang: "en" },
        "pt-br": { label: "Português", lang: "pt-BR" },
      },
      sidebar: [
        {
          label: "Start",
          translations: { "pt-BR": "Começar" },
          items: [
            "docs/install",
            "docs/first-run",
            "docs/build-from-source",
          ],
        },
        {
          label: "The window",
          translations: { "pt-BR": "A janela" },
          items: [
            "docs/sidebar-and-groups",
            "docs/agents",
            "docs/editor",
            "docs/keybindings",
          ],
        },
        {
          label: "Code",
          translations: { "pt-BR": "Código" },
          items: [
            "docs/language-servers",
            "docs/git",
            "docs/worktrees",
          ],
        },
        {
          label: "Extend",
          translations: { "pt-BR": "Estender" },
          items: [
            "docs/extensions",
            "docs/extensions-authoring",
            "docs/mcp",
            "docs/themes-and-icons",
          ],
        },
        {
          label: "Reference",
          translations: { "pt-BR": "Referência" },
          items: ["docs/configuration", "docs/updates"],
        },
      ],
      lastUpdated: false,
      credits: false,
    }),
    sitemap(),
    icon({ include: { "fa6-brands": ["apple", "linux"] } }),
  ],
});

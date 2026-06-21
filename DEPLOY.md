# Deploy automático — PartyLens

Pipeline: você cria uma **tag git** (ex.: `v0.11.0`) → o GitHub Actions empacota o addon →
publica no **CurseForge** e cria um **Release no GitHub** com o `.zip`.

Ferramenta usada: [BigWigsMods/packager](https://github.com/BigWigsMods/packager), o
empacotador padrão da comunidade de addons de WoW.

---

## Configuração inicial (uma vez só)

### 1. Repositório no GitHub
- Criado em `https://github.com/danielcosta42/PartyLens` (público, MIT).

### 2. Projeto no CurseForge
1. Crie o projeto de addon (WoW) no painel de autor.
2. Copie o **Project ID** (fica na página do projeto, ex.: `123456`).
3. Cole esse número no `PartyLens.toc`, na linha:
   ```
   ## X-Curse-Project-ID: 123456
   ```
   É **assim** que o packager sabe para onde subir o arquivo.

### 3. Token da CurseForge → Secret no GitHub
1. Gere um token em **https://authors.curseforge.com** → *API Tokens* (ou
   `legacy.curseforge.com/account/api-tokens`).
2. No GitHub: **Settings → Secrets and variables → Actions → New repository secret**.
3. Nome: `CF_API_KEY` — Valor: cole o token.
   > O token é secreto: cole direto no GitHub, não o coloque em nenhum arquivo do repo.

Pronto. Não precisa configurar `GITHUB_TOKEN` — o Actions fornece automaticamente.

---

## Publicar uma nova versão

```bash
# 1. Faça suas mudanças e atualize o CHANGELOG.md
# 2. Commit
git add -A
git commit -m "Sua mudança"

# 3. Crie a tag (use o prefixo v + SemVer)
git tag v0.11.0

# 4. Envie commits e a tag
git push
git push --tags
```

A tag dispara o workflow `.github/workflows/release.yml`. Em poucos minutos:
- o `.zip` aparece no **CurseForge** (passa por aprovação na 1ª vez);
- um **Release** é criado no GitHub com o changelog entre as tags.

> A versão é injetada automaticamente: o `PartyLens.toc` usa `## Version: @project-version@`,
> que o packager substitui pela tag (`0.11.0`). Em instalações de desenvolvimento (clone
> direto) o WoW mostra o texto literal — isso é normal e só afeta quem roda do git, não o
> pacote publicado.

---

## Notas
- **Tag = versão.** O nome do release vem da tag, sem ela nada é publicado.
- **Categoria/versão de jogo:** marque **Burning Crusade Classic / TBC Anniversary (2.5.x)**
  no CurseForge — é o maior fator de descoberta na busca por TBC.
- **Primeira publicação** no CurseForge geralmente exige aprovação manual do projeto antes
  de ficar visível.

## Outras plataformas (quando quiser ampliar o alcance)
O mesmo workflow já cobre, é só descomentar e adicionar o secret:
- **WoWInterface** → secret `WOWI_API_TOKEN` + linha `## X-WoWI-ID:` no TOC.
- **Wago Addons** → secret `WAGO_API_TOKEN` + linha `## X-Wago-ID:` no TOC.

As linhas já estão preparadas (comentadas) em `release.yml`.

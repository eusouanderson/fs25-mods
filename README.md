
<p align="center">
  <img src="https://img.shields.io/badge/FS22→FS25-Mod%20Conversion-blue?style=for-the-badge" alt="FS22 to FS25 Mod Conversion">
</p>

<h1 align="center">🚜 B.O.B's FS25 Mods</h1>

<p align="center">
  <b>Converting Farming Simulator 22 mods to FS25</b><br>
  <i>Convertendo mods do Farming Simulator 22 para o FS25</i>
</p>

<p align="center">
  <a href="https://liberapay.com/eusouanderson/donate">
    <img src="https://img.shields.io/badge/Liberapay-F6C915?style=for-the-badge&logo=liberapay&logoColor=black" alt="Donate with Liberapay">
  </a>
</p>

---

## 🇧🇷 Português

**B.O.B** — Conversão e adaptação de mods de **Farming Simulator 22 → Farming Simulator 25**.

Aqui você encontra scripts e ferramentas que criei para resolver os problemas mais comuns na migração de mods entre versões do Giants Engine, incluindo:

- ✅ Restauração de caminhos `$data/` que o GE10 remove ao salvar
- ✅ Conversão automática de `collisionMask` (decimal FS22 → hexadecimal FS25)
- ✅ Ajustes de encoding (`iso-8859-1` → `utf-8`)
- ✅ E mais ferramentas à medida que novos problemas aparecerem

### Mods disponíveis

| Mod | Status | Descrição |
|-----|--------|-----------|
| [Kamaz 65116](mods/kamaz-65116/) | ✅ Convertido | Caminhão soviético 6×6 |

### Mods FS22 originais (base para conversão)

A pasta [`fs22/`](fs22/) contém os mods originais do FS22 baixados automaticamente via ferramenta própria.

| Mod | Arquivo |
|-----|---------|
| [Renault K480](fs22/renault-k480-v1-0/) | `FS22_RenaultK480_6x4.zip` |

### Ferramentas

| Ferramenta | Descrição |
|------------|-----------|
| [`tools/download_mod.py`](tools/download_mod.py) | Baixa mods do fs22.com automaticamente para a pasta `fs22/` |

```bash
# Exemplo de uso:
python tools/download_mod.py "https://fs22.com/farming-simulator-22-mods/trucks/renault-k480-v1-0/"
```

### Apoie o trabalho

Se meus mods e ferramentas te ajudaram, considere fazer uma doação. Isso me ajuda a continuar convertendo e criando conteúdo gratuitamente.

<div align="center">
  <a href="https://liberapay.com/eusouanderson/donate">
    <img src="https://liberapay.com/assets/widgets/donate.svg" alt="Donate using Liberapay" width="180">
  </a>
  <br>
  <sub><a href="https://liberapay.com/eusouanderson">liberapay.com/eusouanderson</a></sub>
</div>

---

## 🇺🇸 English

**B.O.B** — Converting and adapting **Farming Simulator 22 → Farming Simulator 25** mods.

Here you'll find scripts and tools I created to fix the most common issues when migrating mods between Giants Engine versions, including:

- ✅ Restoring `$data/` paths that GE10 strips on save
- ✅ Automatic `collisionMask` conversion (FS22 decimal → FS25 hexadecimal)
- ✅ Encoding fixes (`iso-8859-1` → `utf-8`)
- ✅ More tools as new issues come up

### Available Mods

| Mod | Status | Description |
|-----|--------|-------------|
| [Kamaz 65116](mods/kamaz-65116/) | ✅ Converted | Soviet 6×6 truck |

### Original FS22 Mods (conversion source)

The [`fs22/`](fs22/) folder holds original FS22 mods automatically downloaded via the built-in tool.

| Mod | File |
|-----|------|
| [Renault K480](fs22/renault-k480-v1-0/) | `FS22_RenaultK480_6x4.zip` |

### Tools

| Tool | Description |
|------|-------------|
| [`tools/download_mod.py`](tools/download_mod.py) | Download FS22 mods from fs22.com into `fs22/` |

```bash
# Usage example:
python tools/download_mod.py "https://fs22.com/farming-simulator-22-mods/trucks/renault-k480-v1-0/"
```

### Support the Work

If my mods and tools helped you, consider making a donation. It helps me keep converting and creating content for free.

<div align="center">
  <a href="https://liberapay.com/eusouanderson/donate">
    <img src="https://liberapay.com/assets/widgets/donate.svg" alt="Donate using Liberapay" width="180">
  </a>
  <br>
  <sub><a href="https://liberapay.com/eusouanderson">liberapay.com/eusouanderson</a></sub>
</div>

---

<p align="center">
  <a href="https://liberapay.com/eusouanderson/donate">
    <img src="https://img.shields.io/badge/Liberapay-Support%20Me-F6C915?style=flat-square&logo=liberapay&logoColor=black" alt="Liberapay">
  </a>
</p>

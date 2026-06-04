
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

### 📁 Estrutura / Structure

```
fs25-mods/
├── fs25/              ← Mods convertidos para FS25 (por categoria)
│   ├── trucks/        ←   Caminhões
│   ├── tractors/      ←   Tratores
│   ├── trailers/      ←   Reboques
│   ├── maps/          ←   Mapas
│   ├── cars/          ←   Carros
│   └── other/         ←   Outros
├── fs22/              ← Mods ORIGINAIS do FS22 (base para conversão)
│   ├── trucks/
│   ├── tractors/
│   ├── trailers/
│   ├── maps/
│   ├── cars/
│   └── other/
└── tools/             ← Ferramentas de automação
```

### 🚚 Mods Convertidos (FS25)

| Categoria | Mod | Download |
|-----------|-----|----------|
| 🚚 Caminhões | [Kamaz 65116](fs25/trucks/kamaz-65116/) | Ferramenta de fix |
| 🚚 Caminhões | [Kamaz 65116 VIP](fs25/trucks/kamaz-65116-vip/) | [⬇ Download](https://github.com/eusouanderson/fs25-mods/releases/tag/kamaz-65116-vip-v1.1.0) |

### 📦 Mods Originais (FS22)

Baixados automaticamente da [fs22.com](https://fs22.com) com a ferramenta abaixo.

| Categoria | Mod |
|-----------|-----|
| 🚚 Caminhões | [Renault K480](fs22/trucks/renault-k480-v1-0/) |

### 🛠️ Ferramentas / Tools

| Ferramenta | Descrição | Como usar |
|------------|-----------|-----------|
| [`download_mod.py`](tools/download_mod.py) | Baixa mods do fs22.com | `python tools/download_mod.py --category trucks` |
| [`release_mod.py`](tools/release_mod.py) | Zipa e publica como GitHub Release | `python tools/release_mod.py fs25/trucks/kamaz-65116` |

### ⬇ Baixar Todos os Caminhões FS22

```bash
# Preview (só mostra o que vai baixar)
python tools/download_mod.py --category trucks --dry-run

# Baixar os 10 primeiros
python tools/download_mod.py --category trucks --limit 10

# Baixar TODOS (60+ páginas!)
python tools/download_mod.py --category trucks

# Baixar outra categoria
python tools/download_mod.py --category tractors
python tools/download_mod.py --category maps
```

### 📤 Publicar um Mod Convertido

```bash
# Preview
python tools/release_mod.py fs25/trucks/kamaz-65116 --dry-run

# Publicar (zipa + cria release + atualiza README)
python tools/release_mod.py fs25/trucks/kamaz-65116 --version 1.0.0

# Mod vindo direto da sua pasta FS25 do Windows
python tools/release_mod.py "G:/Users/Administrador/Documents/My Games/FarmingSimulator2025/fs25/FS25Kamaz65116" --name kamaz-65116 --category trucks
```

### ❤️ Apoie o trabalho

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

### 🚚 Converted Mods (FS25)

| Category | Mod | Download |
|----------|-----|----------|
| 🚚 Trucks | [Kamaz 65116](fs25/trucks/kamaz-65116/) | Fix tool |
| 🚚 Trucks | [Kamaz 65116 VIP](fs25/trucks/kamaz-65116-vip/) | [⬇ Download](https://github.com/eusouanderson/fs25-mods/releases/tag/kamaz-65116-vip-v1.1.0) |

### 📦 Original Mods (FS22)

Automatically downloaded from [fs22.com](https://fs22.com).

| Category | Mod |
|----------|-----|
| 🚚 Trucks | [Renault K480](fs22/trucks/renault-k480-v1-0/) |

### 🛠️ Tools

| Tool | Description | Usage |
|------|-------------|-------|
| [`download_mod.py`](tools/download_mod.py) | Download mods from fs22.com | `python tools/download_mod.py --category trucks` |
| [`release_mod.py`](tools/release_mod.py) | Zip & publish as GitHub Release | `python tools/release_mod.py fs25/trucks/kamaz-65116` |

### ⬇ Download All FS22 Trucks

```bash
# Preview only
python tools/download_mod.py --category trucks --dry-run

# First 10
python tools/download_mod.py --category trucks --limit 10

# ALL trucks (60+ pages!)
python tools/download_mod.py --category trucks
```

### 📤 Publish a Converted Mod

```bash
# Preview
python tools/release_mod.py fs25/trucks/kamaz-65116 --dry-run

# Publish (zip + release + README update)
python tools/release_mod.py fs25/trucks/kamaz-65116 --version 1.0.0

# Mod from your local Windows FS25 folder
python tools/release_mod.py "G:/Users/Administrador/Documents/My Games/FarmingSimulator2025/fs25/FS25Kamaz65116" --name kamaz-65116 --category trucks
```

### ❤️ Support the Work

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

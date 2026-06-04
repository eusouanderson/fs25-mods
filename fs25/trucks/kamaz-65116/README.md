# FS22 → FS25 Kamaz 65116 Conversion Fix

| | |
|---|---|
| **Mod original** | Kamaz 65116 (FS22) |
| **Versão** | FS25 Converted |
| **Ferramenta** | `fs25_fix_i3d.py` |

## 🇧🇷 Sobre

Script Python que automatiza a correção de problemas gerados ao abrir e salvar um mod do FS22 no **Giants Editor 10 (GE10)** para conversão ao FS25.

### O que corrige

1. **Restaura caminhos `$data/`** — O GE10 remove o `$` de `$data/shared/...` ao salvar. Isso quebra todos os shaders e materiais. O script recoloca o `$`.
2. **Converte colisão** — FS22 usa `collisionMask="DECIMAL"` (ex: `10494210`). FS25 usa `collisionFilterGroup="0xHEX"` e `collisionFilterMask="0xHEX"`. O script converte automaticamente.
3. **Atualiza encoding** — Muda `iso-8859-1` para `utf-8` (padrão FS25).

### Ainda precisa fazer manualmente

O arquivo `.shapes` binário ainda contém dados de colisão do FS22. Depois de rodar o script:

1. Abra o I3D corrigido no **Giants Editor 10**
2. Selecione o shape raiz "kamaz"
3. Clique **Reimport from file** em Shapes → Attributes
4. **File → Save** para forçar regravação do `.shapes`

## 🇺🇸 About

Python script that automates fixing issues caused by opening and saving an FS22 mod in **Giants Editor 10 (GE10)** for FS25 conversion.

### What it fixes

1. **Restores `$data/` paths** — GE10 strips the `$` from `$data/shared/...` on save. This breaks all shaders and materials. The script re-adds the `$`.
2. **Converts collision** — FS22 uses `collisionMask="DECIMAL"` (e.g. `10494210`). FS25 uses `collisionFilterGroup="0xHEX"` and `collisionFilterMask="0xHEX"`. The script converts automatically.
3. **Updates encoding** — Changes `iso-8859-1` to `utf-8` (FS25 standard).

### Manual step still needed

The binary `.shapes` file still contains FS22 collision data. After running the script:

1. Open the fixed I3D in **Giants Editor 10**
2. Select the root "kamaz" shape
3. Click **Reimport from file** under Shapes → Attributes
4. **File → Save** to force a full `.shapes` rewrite

---

## 🚀 How to Use / Como Usar

```bash
# Preview changes (dry run - doesn't modify anything)
python fs25_fix_i3d.py kamaz65116.i3d --dry-run

# Apply fixes (creates .bak backup automatically)
python fs25_fix_i3d.py kamaz65116.i3d
```

## 📊 Collision Mapping / Mapeamento de Colisão

| Shape | FS22 (decimal) | FS25 (group) | FS25 (mask) |
|---|---|---|---|
| Main body (kamaz) | 10494210 | `0x10004` | `0xfe3ffb83` |
| AI collision trigger | 1056768 | `0x20000000` | `0x100000` |
| collPart (child) | 8194 | `0x10004` | `0xfe3ffb83` |
| Action trigger | 1048576 | `0x20000000` | `0x100000` |
| Axle (Axis/most) | 2105410 | `0x202042` | `0xfe3ffb83` |

## ✅ After Script + GE10 Reimport

- ✅ Render with all textures
- ✅ Working collisions (doesn't fall through ground)
- ✅ Shaders compile without errors

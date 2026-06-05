#!/usr/bin/env python3
"""
FS25 Icon Resizer — B.O.B's Mod Tool
=========================================
Converts any image (PNG, JPG, etc.) to the exact DDS format
FS25 needs for store icons, brand images, and store previews.

Usage:
    python tools/resize_icon.py foto.png -o stores/icon_tyagac.dds --type icon
    python tools/resize_icon.py foto.png -o stores/BRAND.dds --type brand
    python tools/resize_icon.py entrada.png -o stores/store_tyagac.dds --type store
    python tools/resize_icon.py foto.jpg --preview
"""

import argparse
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ICON_SIZES = {
    "icon": (512, 512),
    "brand": (512, 256),
    "store": (512, 512),
}

DESCRIPTIONS = {
    "icon": "Ícone principal do veículo na loja (icon_*.dds)",
    "brand": "Logo da marca na loja (BRAND*.dds)",
    "store": "Imagem de destaque na loja (store_*.dds)",
}


def _to_int(v):
    return int(v) if not isinstance(v, (int, np.integer)) else int(v)


def rgb_to_565(r, g, b):
    r, g, b = _to_int(r), _to_int(g), _to_int(b)
    r5 = (r * 31 + 127) // 255
    g6 = (g * 63 + 127) // 255
    b5 = (b * 31 + 127) // 255
    return (r5 << 11) | (g6 << 5) | b5


def color_dist_565(c1, c2):
    r1 = (c1 >> 11) & 0x1F
    g1 = (c1 >> 5) & 0x3F
    b1 = c1 & 0x1F
    r2 = (c2 >> 11) & 0x1F
    g2 = (c2 >> 5) & 0x3F
    b2 = c2 & 0x1F
    dr = (r1 - r2) * 255 // 31
    dg = (g1 - g2) * 255 // 63
    db = (b1 - b2) * 255 // 31
    return dr * dr + dg * dg + db * db


def lerp_color(c0, c1, t):
    r0 = (c0 >> 11) & 0x1F
    g0 = (c0 >> 5) & 0x3F
    b0 = c0 & 0x1F
    r1 = (c1 >> 11) & 0x1F
    g1 = (c1 >> 5) & 0x3F
    b1 = c1 & 0x1F
    rt = r0 + ((r1 - r0) * t // 3)
    gt = g0 + ((g1 - g0) * t // 3)
    bt = b0 + ((b1 - b0) * t // 3)
    return (rt << 11) | (gt << 5) | bt


def pack_block_dxt5(pixels):
    pixels = np.asarray(pixels, dtype=np.uint8)
    flat = pixels.reshape(-1, 4)

    a_ch = flat[:, 3].astype(np.int32)
    min_a = int(a_ch.min())
    max_a = int(a_ch.max())

    if max_a == min_a:
        a1, a2 = min_a, max_a
        a_vals = [min_a] * 8
        alpha_endpoints = struct.pack("<BB", a1, a2)
    elif min_a < max_a:
        a1, a2 = max_a, min_a
        alpha_endpoints = struct.pack("<BB", a1, a2)
        a_vals = [
            a1, a2,
            (6 * a1 + 1 * a2 + 3) // 7,
            (5 * a1 + 2 * a2 + 3) // 7,
            (4 * a1 + 3 * a2 + 3) // 7,
            (3 * a1 + 4 * a2 + 3) // 7,
            (2 * a1 + 5 * a2 + 3) // 7,
            (1 * a1 + 6 * a2 + 3) // 7,
        ]
    else:
        a1, a2 = max_a, min_a
        alpha_endpoints = struct.pack("<BB", a1, a2)
        a_vals = [
            a1, a2,
            (4 * a1 + 1 * a2 + 2) // 5,
            (3 * a1 + 2 * a2 + 2) // 5,
            (2 * a1 + 3 * a2 + 2) // 5,
            (1 * a1 + 4 * a2 + 2) // 5,
            0, 255,
        ]

    alpha_bits = 0
    for i in range(16):
        a = int(flat[i, 3])
        best_idx = min(range(8), key=lambda j: abs(a - a_vals[j]))
        alpha_bits = (alpha_bits << 3) | best_idx

    alpha_bytes = alpha_endpoints + struct.pack("<Q", alpha_bits)[:6]

    c_vals = [rgb_to_565(int(flat[i, 0]), int(flat[i, 1]), int(flat[i, 2])) for i in range(16)]
    c0 = min(c_vals)
    c1 = max(c_vals)

    if c0 == c1:
        c0, c1 = 0, 0xFFFF

    if c0 > c1:
        palette = [c1, c0, lerp_color(c1, c0, 2), lerp_color(c1, c0, 1)]
        is_3color = False
    else:
        palette = [c0, c1, lerp_color(c0, c1, 1), lerp_color(c0, c1, 2)]
        is_3color = True

    color_bits = 0
    for i in range(16):
        cv = c_vals[i]
        best_idx = min(range(4), key=lambda j: color_dist_565(cv, palette[j]))
        if is_3color and best_idx == 3:
            best_idx = 1
        color_bits = (color_bits << 2) | best_idx

    color_bytes = struct.pack("<HH", c0, c1) + struct.pack("<I", color_bits)
    return alpha_bytes + color_bytes


def compress_dxt5(img_array):
    h, w = img_array.shape[:2]
    if w % 4 != 0 or h % 4 != 0:
        new_w = (w + 3) & ~3
        new_h = (h + 3) & ~3
        pil = Image.fromarray(img_array)
        img_array = np.asarray(pil.resize((new_w, new_h), Image.LANCZOS))
        w, h = new_w, new_h
    data = b""
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            block = img_array[by:by + 4, bx:bx + 4]
            data += pack_block_dxt5(block)
    pitch = ((w + 3) // 4) * ((h + 3) // 4) * 16
    return data, w, h, pitch


def write_dds(filepath, img_array):
    if img_array.shape[2] == 3:
        alpha = np.full((img_array.shape[0], img_array.shape[1], 1), 255, dtype=np.uint8)
        img_array = np.concatenate([img_array, alpha], axis=2)

    data, w, h, pitch = compress_dxt5(img_array)

    header = struct.pack(
        "<"      # little-endian
        "4s"     # dwMagic: "DDS "
        "I"      # dwSize: 124
        "I"      # dwFlags
        "I"      # dwHeight
        "I"      # dwWidth
        "I"      # dwPitchOrLinearSize
        "I"      # dwDepth
        "I"      # dwMipMapCount
        "11I"    # dwReserved1[11]
        "I"      # pf.dwSize: 32
        "I"      # pf.dwFlags: DDPF_FOURCC
        "4s"     # pf.dwFourCC: "DXT5"
        "I"      # pf.dwRGBBitCount
        "I"      # pf.dwRBitMask
        "I"      # pf.dwGBitMask
        "I"      # pf.dwBBitMask
        "I"      # pf.dwABitMask
        "I"      # caps.dwCaps: DDSCAPS_TEXTURE
        "I"      # caps.dwCaps2
        "I"      # caps.dwCaps3
        "I"      # caps.dwCaps4
        "I",     # dwReserved2
        b"DDS ",
        124,
        0x00021007,
        h,
        w,
        pitch,
        0,
        0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        32,
        0x00000004,
        b"DXT5",
        0, 0, 0, 0, 0,
        0x00001000,
        0, 0, 0, 0,
    )
    assert len(header) == 128, f"DDS header should be 128 bytes, got {len(header)}"

    with open(filepath, "wb") as f:
        f.write(header)
        f.write(data)

    return w, h


def load_and_resize(input_path, target_size):
    img = Image.open(input_path).convert("RGBA")
    img = img.resize(target_size, Image.LANCZOS)
    return np.asarray(img, dtype=np.uint8)


def main():
    parser = argparse.ArgumentParser(
        description="Converte imagem para DDS no tamanho exato do FS25",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("input", help="Imagem de entrada (PNG, JPG, etc)")
    parser.add_argument("-o", "--output", help="Arquivo DDS de saída")
    parser.add_argument("--type", choices=list(ICON_SIZES.keys()), default="icon",
                        help="Tipo de imagem para o mod")
    parser.add_argument("--preview", action="store_true",
                        help="Mostra info sem converter")

    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"  ✖  Arquivo não encontrado: {input_path}")
        sys.exit(1)

    target_size = ICON_SIZES[args.type]
    desc = DESCRIPTIONS[args.type]

    img = Image.open(input_path)
    orig_size = img.size

    if args.preview:
        print(f"  📂  {input_path.name}")
        print(f"  📏  Original: {orig_size[0]}x{orig_size[1]}")
        print(f"  🎯  Destino:  {target_size[0]}x{target_size[1]} ({desc})")
        print(f"  💾  Formato:  DDS DXT5 (BC3)")
        print()
        print(f"  Ex: python tools/resize_icon.py \"{input_path.name}\" -o stores/icon_{args.type}.dds --type {args.type}")
        return

    if not args.output:
        print(f"  ✖  Informe -o para o arquivo de saída")
        print(f"  Ex: python tools/resize_icon.py \"{input_path}\" -o stores/icon_{args.type}.dds --type {args.type}")
        sys.exit(1)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"  📂  {input_path.name} ({orig_size[0]}x{orig_size[1]})")
    print(f"  🎯  Redimensionando para {target_size[0]}x{target_size[1]} ({desc})")

    img_array = load_and_resize(input_path, target_size)

    print(f"  📦  Comprimindo DXT5...")
    write_dds(str(output_path), img_array)

    size_kb = output_path.stat().st_size / 1024
    print(f"  ✅  Salvo: {output_path} ({size_kb:.0f} KB)")
    print(f"  ℹ   FS25 pronto: {target_size[0]}x{target_size[1]} DXT5")


if __name__ == "__main__":
    main()

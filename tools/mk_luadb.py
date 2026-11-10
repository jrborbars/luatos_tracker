#!/usr/bin/env python3
"""Monta script.bin (luadb v2) a partir de fontes Lua.

Formato extraído de luat/vfs/luat_fs_luadb.c: header TLV (type u8, len u8,
payload) seguido de uma entrada TLV por arquivo + dados crus. Os .lua são
gravados em texto puro, como o Luatools faz com as libs padrão.
"""

import os
import struct
import sys

MAGIC = b"\xA5\x5A\xA5\x5A"
HEAD_SIZE = 24  # tamanho fixo do header (soma de todos os TLVs de cabeçalho)


def _tlv(t, payload):
    return bytes([t, len(payload)]) + payload


def build_luadb(files, out_path):
    """files: lista de (nome_relativo, caminho_no_disco)."""

    # --- header ---
    head = bytearray()
    head += _tlv(1, MAGIC)                                    # magic
    head += _tlv(2, struct.pack("<H", 2))                     # versão v2
    head += _tlv(3, struct.pack("<I", HEAD_SIZE))             # headsize
    head += _tlv(4, struct.pack("<H", len(files)))            # filecount
    head += _tlv(0xFE, b"\x00\x00")                           # crc / fim do header
    assert len(head) == HEAD_SIZE, f"header tem {len(head)} bytes, esperado {HEAD_SIZE}"

    # --- corpo: uma entrada por arquivo ---
    body = bytearray()
    for nome, caminho in files:
        with open(caminho, "rb") as f:
            dados = f.read()
        if len(dados) > 64 * 1024:
            raise ValueError(f"{nome}: excede 64 KB")
        nome_b = nome.encode("utf-8")
        if len(nome_b) > 31:
            raise ValueError(f"{nome}: nome excede 31 bytes")
        body += _tlv(1, MAGIC)                    # magic do arquivo (ignorado)
        body += _tlv(2, nome_b)                    # nome
        body += _tlv(3, struct.pack("<I", len(dados)))  # tamanho
        body += _tlv(0xFE, b"\x00\x00")           # crc placeholder
        body += dados

    blob = bytes(head) + bytes(body)
    with open(out_path, "wb") as f:
        f.write(blob)
    print(f"luadb gravado: {out_path} ({len(blob)} bytes, {len(files)} arquivos)")


def main():
    if len(sys.argv) < 3:
        print("uso: python3 tools/mk_luadb.py <script.bin> <arquivo1.lua> [<arquivo2.lua> ...]")
        sys.exit(2)

    out_path = sys.argv[1]
    arquivos = sys.argv[2:]
    files = [(os.path.basename(c), c) for c in arquivos]

    build_luadb(files, out_path)


if __name__ == "__main__":
    main()

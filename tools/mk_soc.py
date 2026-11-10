#!/usr/bin/env python3
"""Substitui o script.bin dentro de um .soc da LuatOS.

Um .soc é um arquivo 7z contendo:
  - binpkg         (firmware EC618)
  - script.bin     (luadb com os scripts do usuário)
  - info.json      (metadados, inclui download.script_addr)

Este script lê o .soc, troca o script.bin pelo gerado por mk_luadb.py
e grava um novo .soc pronto para flash com o ectool.
"""

import json
import os
import sys
import tempfile

try:
    import py7zr
except ImportError as exc:
    print(f"falta py7zr: {exc}")
    sys.exit(1)


def replace_script_bin(soc_in, script_bin, soc_out):
    script_data = open(script_bin, "rb").read()

    with tempfile.TemporaryDirectory() as tmpdir:
        with py7zr.SevenZipFile(soc_in, "r") as z:
            names = z.getnames()
            print("conteúdo do .soc:")
            for n in names:
                print("  ", n)
            z.extractall(tmpdir)

        info_path = os.path.join(tmpdir, "info.json")
        info = json.loads(open(info_path, "rb").read() or b"{}")
        print("info.json:", json.dumps(info, indent=2, ensure_ascii=False))

        if "script.bin" not in names:
            print("AVISO: .soc não contém script.bin; será adicionado")

        with py7zr.SevenZipFile(soc_out, "w") as z:
            for n in names:
                z.write(os.path.join(tmpdir, n), n)
            z.writestr(script_data, "script.bin")
    print(f".soc gravado: {soc_out}")


def main():
    if len(sys.argv) != 4:
        print("uso: python3 tools/mk_soc.py <soc_original> <script.bin> <soc_saida>")
        sys.exit(2)

    replace_script_bin(sys.argv[1], sys.argv[2], sys.argv[3])


if __name__ == "__main__":
    main()

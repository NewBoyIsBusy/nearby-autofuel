"""Run with Python + lupa (Lua 5.1), using the local vanilla game components."""
from pathlib import Path
import os
import sys

SOURCE = Path(__file__).resolve().parents[1]
ROOT = SOURCE.parent
sys.path.insert(0, str(ROOT / ".tools" / "lua_test_runtime"))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().package.path = ";".join([
    str(SOURCE / "scripts/?.lua").replace("\\", "/"),
    str(Path(os.environ.get("DST_SCRIPTS_PATH", ROOT / "game_scripts_reference/scripts")) / "?.lua").replace("\\", "/"),
    lua.globals().package.path,
])
for file in SOURCE.rglob("*.lua"):
    lua.execute("assert(loadstring(...))", file.read_text(encoding="utf-8"))
lua.execute((Path(__file__).parent / "test_autofuel.lua").read_text(encoding="utf-8"))

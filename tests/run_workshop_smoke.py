"""Exercise both installed Workshop packages through DST's real UGC loader.

Uses a new offline world, never an existing player save. Pass --expect-failure
to reproduce the missing-module failure before applying the packaging fix.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parents[1]
GAME = Path("D:/Program Files (x86)/Steam/steamapps/common/Don't Starve Together")
WORKSHOP = GAME.parents[1] / "workshop"
MOD = (GAME / "mods/workshop_loading_validation").resolve()
assert MOD.parent == (GAME / "mods").resolve() and not MOD.exists()
STORAGE = Path(tempfile.mkdtemp(prefix="workshop_loading_", dir=SOURCE.parent))
CLUSTER = STORAGE / "DoNotStarveTogether/WorkshopLoadingTest"
MASTER = CLUSTER / "Master"
MASTER.mkdir(parents=True)
(CLUSTER / "cluster.ini").write_text("""[GAMEPLAY]
game_mode = survival
max_players = 1
pause_when_empty = false
[NETWORK]
cluster_name = Workshop Loading Validation
offline_cluster = true
lan_only_cluster = true
cluster_password = isolated-test
[MISC]
console_enabled = true
[SHARD]
shard_enabled = false
""", encoding="utf-8")
(MASTER / "server.ini").write_text("[NETWORK]\nserver_port = 11361\n[SHARD]\nis_master = true\n[ACCOUNT]\nencode_user_path = false\n", encoding="utf-8")
(MASTER / "modoverrides.lua").write_text('return { ["workshop-3822024875"] = {enabled=true}, ["workshop-3822016512"] = {enabled=true}, workshop_loading_validation = {enabled=true} }', encoding="utf-8")
preset = "DST_CAVE" if "--caves" in sys.argv else "SURVIVAL_TOGETHER"
(MASTER / "worldgenoverride.lua").write_text('return {override_enabled=true, preset="' + preset + '", overrides={world_size="small"}}', encoding="utf-8")
try:
    MOD.mkdir()
    (MOD / "scripts").mkdir()
    (MOD / "modinfo.lua").write_text('name="Workshop loading validation"\nversion="1"\napi_version=10\ndst_compatible=true\nserver_only_mod=true\nall_clients_require_mod=false\npriority=-1000\n', encoding="utf-8")
    backpack = (SOURCE.parent / "growing_backpack/tests/game_smoke.lua").read_text(encoding="utf-8")
    (MOD / "scripts/validation_backpack.lua").write_text(backpack.replace("c_shutdown(false)", "-- Continue to the autofuel suite."), encoding="utf-8")
    shutil.copy2(SOURCE / "tests/game_smoke.lua", MOD / "scripts/validation_autofuel.lua")
    (MOD / "modmain.lua").write_text('''AddSimPostInit(function()
    GLOBAL.TheWorld:DoTaskInTime(1, function()
        local ok, err = GLOBAL.pcall(function()
            GLOBAL.require("validation_backpack")
            GLOBAL.require("validation_autofuel")
        end)
        if not ok then
            print("WORKSHOP_LOADING_FAILURE "..GLOBAL.tostring(err))
            GLOBAL.c_shutdown(false)
        end
    end)
end)
''', encoding="utf-8")
    exe = GAME / "bin64/dontstarve_dedicated_server_nullrenderer_x64.exe"
    log = STORAGE / "engine_console.log"
    with log.open("wb") as out:
        process = subprocess.Popen([str(exe), "-console", "-offline", "-skip_update_server_mods",
            "-ugc_directory", str(WORKSHOP), "-persistent_storage_root", str(STORAGE),
            "-conf_dir", "DoNotStarveTogether", "-cluster", "WorkshopLoadingTest", "-shard", "Master"],
            cwd=exe.parent, stdout=out, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        print(f"Isolated Workshop test PID {process.pid}; log: {log}", flush=True)
        try:
            process.wait(timeout=240)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=15)
            raise RuntimeError(f"Engine timeout: {log}")
    output = log.read_text(encoding="utf-8", errors="replace")
    for line in output.splitlines():
        if any(s in line for s in ("GAME_", "WORKSHOP_LOADING_", "MOD ERROR", "module 'gb_layout' not found", "module 'nearby_autofuel' not found")):
            print(line)
    if "--expect-failure" in sys.argv:
        assert "module 'gb_layout' not found" in output, f"Expected original failure: {log}"
        print("REPRODUCED_WORKSHOP_MISSING_MODULE")
    else:
        assert "GROWINGPACK_GAME_SUCCESS" in output and "AUTOFUEL_GAME_SUCCESS" in output, f"Validation failed: {log}"
        assert "MOD ERROR" not in output and "WORKSHOP_LOADING_FAILURE" not in output
finally:
    if MOD.exists() and MOD.parent == (GAME / "mods").resolve() and MOD.name == "workshop_loading_validation":
        shutil.rmtree(MOD)

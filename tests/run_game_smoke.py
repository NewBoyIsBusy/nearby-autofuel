"""Isolated offline DST engine validation. Does not read or modify existing worlds."""
from pathlib import Path
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[1]
ROOT = SOURCE.parent
GAME = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("D:/Program Files (x86)/Steam/steamapps/common/Don't Starve Together")
MOD = GAME / "mods" / "nearby_autofuel_validation"
STORAGE = ROOT / "autofuel_test_storage"
CLUSTER = STORAGE / "DoNotStarveTogether" / "NearbyAutoFuelTest"
assert not MOD.exists(), f"Temporary test mod already exists: {MOD}"
assert MOD.resolve().parent == (GAME / "mods").resolve()
(CLUSTER / "Master").mkdir(parents=True, exist_ok=True)
(CLUSTER / "cluster.ini").write_text("""[GAMEPLAY]
game_mode = survival
max_players = 1
pvp = false
pause_when_empty = false
[NETWORK]
cluster_name = AutoFuel Isolated Validation
offline_cluster = true
lan_only_cluster = true
cluster_password = autofuel-test-only
[MISC]
console_enabled = true
[SHARD]
shard_enabled = false
""", encoding="utf-8")
(CLUSTER / "Master/server.ini").write_text("[NETWORK]\nserver_port = 11321\n[SHARD]\nis_master = true\n[ACCOUNT]\nencode_user_path = false\n", encoding="utf-8")
(CLUSTER / "Master/modoverrides.lua").write_text('return { nearby_autofuel_validation = { enabled = true } }\n', encoding="utf-8")
(CLUSTER / "Master/worldgenoverride.lua").write_text('return { override_enabled = true, preset = "SURVIVAL_TOGETHER", overrides = { world_size = "small" } }\n', encoding="utf-8")
try:
    MOD.mkdir()
    shutil.copy2(SOURCE / "modinfo.lua", MOD)
    shutil.copytree(SOURCE / "scripts", MOD / "scripts")
    shutil.copy2(SOURCE / "tests/game_smoke.lua", MOD / "scripts/nearby_autofuel_smoke.lua")
    main = (SOURCE / "modmain.lua").read_text(encoding="utf-8")
    main += '''
AddSimPostInit(function()
    GLOBAL.TheWorld:DoTaskInTime(1, function()
        local ok, err = GLOBAL.pcall(GLOBAL.require, "nearby_autofuel_smoke")
        if not ok then
            print("AUTOFUEL_GAME_FAILURE "..GLOBAL.tostring(err))
            GLOBAL.c_shutdown(false)
        end
    end)
end)
'''
    (MOD / "modmain.lua").write_text(main, encoding="utf-8")
    exe = GAME / "bin64/dontstarve_dedicated_server_nullrenderer_x64.exe"
    log = STORAGE / "engine_console.log"
    with log.open("wb") as out:
        process = subprocess.Popen([str(exe), "-console", "-offline", "-skip_update_server_mods",
            "-persistent_storage_root", str(STORAGE), "-conf_dir", "DoNotStarveTogether",
            "-cluster", "NearbyAutoFuelTest", "-shard", "Master"],
            cwd=exe.parent, stdout=out, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW)
        print(f"Started isolated offline DST engine, PID {process.pid}", flush=True)
        try:
            process.wait(timeout=240)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=15)
            raise RuntimeError(f"Engine test timeout; see {log}")
    output = log.read_text(encoding="utf-8", errors="replace")
    for line in output.splitlines():
        if "AUTOFUEL_GAME_" in line or "LUA ERROR" in line or "Error" in line:
            print(line)
    assert "AUTOFUEL_GAME_SUCCESS" in output, f"Engine validation failed; see {log}"
finally:
    # Only this newly-created, exact temporary mod folder is removed.
    if MOD.exists() and MOD.resolve().parent == (GAME / "mods").resolve() and MOD.name == "nearby_autofuel_validation":
        shutil.rmtree(MOD)

#!/usr/bin/env bash

set -Eeuo pipefail

# Public source: https://github.com/codebyant/tegra-installers
# This installer does not require sudo and only writes inside the current user's data directory.

tegra_api_url="${TEGRA_DOWNLOADS_API_URL:-https://api.tegramc.com/downloads/versions}"
tegra_icon_url="${TEGRA_ICON_URL:-https://tegramc.com/tegra-logo.png}"
tegra_artwork_base_url="${TEGRA_STEAM_ARTWORK_BASE_URL:-https://get.tegramc.com/steam-library}"
tegra_artwork_poll_attempts="${TEGRA_STEAM_ARTWORK_POLL_ATTEMPTS:-20}"
tegra_artwork_poll_interval="${TEGRA_STEAM_ARTWORK_POLL_INTERVAL:-1.5}"
tegra_allow_insecure_test_urls="${TEGRA_ALLOW_INSECURE_TEST_URLS:-0}"
tegra_skip_steam=0
tegra_force_steam_shortcut=0
tegra_channel='stable'

while [[ "$#" -gt 0 ]]; do
  tegra_arg="$1"
  case "$tegra_arg" in
    --no-steam)
      tegra_skip_steam=1
      ;;
    --force-steam-shortcut)
      tegra_force_steam_shortcut=1
      ;;
    --stable|--beta|--nightly|--experimental)
      tegra_channel="${tegra_arg#--}"
      ;;
    --channel)
      if [[ "$#" -lt 2 ]]; then
        printf '%s\n' 'Option --channel requires a value: stable, beta, nightly or experimental.' >&2
        exit 2
      fi
      shift
      tegra_channel="$1"
      ;;
    --channel=*)
      tegra_channel="${tegra_arg#--channel=}"
      ;;
    --help|-h)
      printf '%s\n' 'Usage: install-steamos.sh [--stable|--beta|--nightly|--experimental | --channel stable|beta|nightly|experimental] [--no-steam] [--force-steam-shortcut]'
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$tegra_arg" >&2
      exit 2
      ;;
  esac
  shift
done

case "$tegra_channel" in
  stable|beta|nightly|experimental)
    ;;
  *)
    printf 'Invalid channel: %s. Expected stable, beta, nightly or experimental.\n' "$tegra_channel" >&2
    exit 2
    ;;
esac

if [[ ! "$tegra_artwork_poll_attempts" =~ ^[1-9][0-9]*$ ]]; then
  tegra_artwork_poll_attempts=20
fi

if [[ ! "$tegra_artwork_poll_interval" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  tegra_artwork_poll_interval='1.5'
fi

if [[ "${LANG:-}" == pt_BR* ]]; then
  tegra_msg_start='Preparando a instalação do Tegra para o SteamOS.'
  tegra_msg_root='Execute este instalador sem sudo.'
  tegra_msg_arch='Este instalador requer um sistema Linux x86_64.'
  tegra_msg_missing='Comando necessário não encontrado:'
  tegra_msg_metadata="Consultando a versão mais recente do canal $tegra_channel."
  tegra_msg_bad_metadata='A API não retornou dados válidos para o Linux.'
  tegra_msg_untrusted_url='O endereço de download recebido não pertence ao CDN oficial do Tegra.'
  tegra_msg_downloading='Baixando o Tegra'
  tegra_msg_checksum='Verificando a integridade do download.'
  tegra_msg_checksum_failed='O checksum do arquivo não corresponde ao valor publicado. Nada foi instalado.'
  tegra_msg_installing='Instalando o AppImage e a entrada do menu.'
  tegra_msg_icon_warning='Não foi possível baixar o ícone. O Tegra foi instalado sem ele.'
  tegra_msg_steam='Adicionando o Tegra à biblioteca da Steam.'
  tegra_msg_steam_exists='O atalho da Steam já foi solicitado anteriormente. Pulando esta etapa.'
  tegra_msg_steam_found='O atalho do Tegra já existe na Steam. Reutilizando o atalho existente.'
  tegra_msg_steam_missing='O Tegra foi instalado, mas o comando steamos-add-to-steam não foi encontrado.'
  tegra_msg_steam_failed='O Tegra foi instalado, mas não foi possível adicionar o atalho à Steam.'
  tegra_msg_artwork='Preparando as capas e a arte da biblioteca da Steam.'
  tegra_msg_artwork_done='As capas e a arte da biblioteca foram instaladas.'
  tegra_msg_artwork_warning='O Tegra foi instalado, mas não foi possível concluir a arte da biblioteca. Execute o instalador novamente depois que a Steam salvar o atalho.'
  tegra_msg_done='Instalação concluída. Volte ao Modo Jogo para abrir o Tegra pela biblioteca no Steam Deck ou Steam Machine.'
  tegra_msg_update='Para atualizar manualmente, execute este mesmo comando novamente.'
else
  tegra_msg_start='Preparing Tegra installation for SteamOS.'
  tegra_msg_root='Run this installer without sudo.'
  tegra_msg_arch='This installer requires an x86_64 Linux system.'
  tegra_msg_missing='Required command not found:'
  tegra_msg_metadata="Checking the latest $tegra_channel release."
  tegra_msg_bad_metadata='The API did not return valid Linux release data.'
  tegra_msg_untrusted_url='The received download address does not belong to the official Tegra CDN.'
  tegra_msg_downloading='Downloading Tegra'
  tegra_msg_checksum='Verifying download integrity.'
  tegra_msg_checksum_failed='The file checksum does not match the published value. Nothing was installed.'
  tegra_msg_installing='Installing the AppImage and application-menu entry.'
  tegra_msg_icon_warning='The icon could not be downloaded. Tegra was installed without it.'
  tegra_msg_steam='Adding Tegra to the Steam library.'
  tegra_msg_steam_exists='The Steam shortcut was already requested. Skipping this step.'
  tegra_msg_steam_found='The Tegra shortcut already exists in Steam. Reusing the existing shortcut.'
  tegra_msg_steam_missing='Tegra was installed, but steamos-add-to-steam was not found.'
  tegra_msg_steam_failed='Tegra was installed, but its Steam shortcut could not be added.'
  tegra_msg_artwork='Preparing Steam library covers and artwork.'
  tegra_msg_artwork_done='The Steam library covers and artwork were installed.'
  tegra_msg_artwork_warning='Tegra was installed, but its library artwork could not be completed. Run the installer again after Steam saves the shortcut.'
  tegra_msg_done='Installation complete. Return to Gaming Mode to open Tegra from your library on Steam Deck or Steam Machine.'
  tegra_msg_update='To update manually, run this same command again.'
fi

tegra_log() {
  printf '[Tegra] %s\n' "$1"
}

tegra_fail() {
  printf '[Tegra] %s\n' "$1" >&2
  exit 1
}

tegra_log "$tegra_msg_start"

if [[ "$(id -u)" -eq 0 ]]; then
  tegra_fail "$tegra_msg_root"
fi

case "$(uname -m)" in
  x86_64|amd64)
    ;;
  *)
    tegra_fail "$tegra_msg_arch"
    ;;
esac

for tegra_command in curl python3 install mkdir mktemp mv; do
  if ! command -v "$tegra_command" >/dev/null 2>&1; then
    tegra_fail "$tegra_msg_missing $tegra_command"
  fi
done

if [[ "$tegra_allow_insecure_test_urls" != '1' ]]; then
  case "$tegra_api_url" in
    https://api.tegramc.com/*)
      ;;
    *)
      tegra_fail "$tegra_msg_untrusted_url"
      ;;
  esac

  case "$tegra_artwork_base_url" in
    https://get.tegramc.com/steam-library)
      ;;
    *)
      tegra_fail "$tegra_msg_untrusted_url"
      ;;
  esac
fi

tegra_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
tegra_install_dir="${TEGRA_INSTALL_DIR:-$tegra_data_home/tegra}"
tegra_applications_dir="${TEGRA_APPLICATIONS_DIR:-$tegra_data_home/applications}"
tegra_icons_dir="${TEGRA_ICONS_DIR:-$tegra_data_home/icons/hicolor/512x512/apps}"
tegra_appimage_path="$tegra_install_dir/Tegra.AppImage"
tegra_desktop_path="$tegra_applications_dir/com.seijin.tegramc.app.desktop"
tegra_icon_path="$tegra_icons_dir/com.seijin.tegramc.app.png"
tegra_shortcut_marker="$tegra_install_dir/.steam-shortcut-added"
tegra_temp_dir="$(mktemp -d -t tegra-steamos.XXXXXX)"
tegra_metadata_path="$tegra_temp_dir/versions.json"
tegra_download_path="$tegra_temp_dir/Tegra.AppImage"
tegra_icon_download_path="$tegra_temp_dir/tegra-logo.png"

tegra_find_steam_shortcuts() {
  python3 - "$tegra_appimage_path" <<'PY'
import os
import shlex
import struct
import sys
from pathlib import Path

TYPE_OBJECT = 0x00
TYPE_STRING = 0x01
TYPE_INT32 = 0x02
TYPE_FLOAT32 = 0x03
TYPE_POINTER = 0x04
TYPE_WSTRING = 0x05
TYPE_COLOR = 0x06
TYPE_UINT64 = 0x07
TYPE_END = 0x08
TYPE_INT64 = 0x0A


class InvalidVdf(Exception):
    pass


def read_cstring(data, offset):
    end = data.find(b"\0", offset)
    if end < 0:
        raise InvalidVdf
    return data[offset:end].decode("utf-8", "replace"), end + 1


def parse_object(data, offset):
    result = {}
    while offset < len(data):
        value_type = data[offset]
        offset += 1
        if value_type == TYPE_END:
            return result, offset

        key, offset = read_cstring(data, offset)
        if value_type == TYPE_OBJECT:
            value, offset = parse_object(data, offset)
        elif value_type == TYPE_STRING:
            value, offset = read_cstring(data, offset)
        elif value_type == TYPE_INT32:
            if offset + 4 > len(data):
                raise InvalidVdf
            value = struct.unpack_from("<i", data, offset)[0]
            offset += 4
        elif value_type in (TYPE_FLOAT32, TYPE_POINTER, TYPE_COLOR):
            if offset + 4 > len(data):
                raise InvalidVdf
            value = data[offset:offset + 4]
            offset += 4
        elif value_type in (TYPE_UINT64, TYPE_INT64):
            if offset + 8 > len(data):
                raise InvalidVdf
            value = data[offset:offset + 8]
            offset += 8
        elif value_type == TYPE_WSTRING:
            if offset + 2 > len(data):
                raise InvalidVdf
            length = struct.unpack_from("<H", data, offset)[0]
            offset += 2
            byte_length = length * 2
            if offset + byte_length > len(data):
                raise InvalidVdf
            value = data[offset:offset + byte_length]
            offset += byte_length
        else:
            raise InvalidVdf

        result[key] = value

    raise InvalidVdf


def read_shortcuts(path):
    data = path.read_bytes()
    root, offset = parse_object(data, 0)
    if offset != len(data):
        trailing = data[offset:]
        if any(byte != 0 for byte in trailing):
            raise InvalidVdf
    shortcuts = root.get("shortcuts", {})
    return shortcuts.values() if isinstance(shortcuts, dict) else ()


def executable_matches(raw_executable, expected_path):
    if not isinstance(raw_executable, str):
        return False
    try:
        arguments = shlex.split(raw_executable)
    except ValueError:
        arguments = []
    return bool(arguments and os.path.abspath(arguments[0]) == expected_path)


expected_executable = os.path.abspath(sys.argv[1])
home = Path.home()
data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share"))
candidate_roots = (
    data_home / "Steam",
    home / ".local" / "share" / "Steam",
    home / ".steam" / "steam",
    home / ".steam" / "root",
    home / ".var" / "app" / "com.valvesoftware.Steam" / "data" / "Steam",
)

seen_files = set()
matches = set()
for root in candidate_roots:
    try:
        shortcut_files = root.glob("userdata/*/config/shortcuts.vdf")
    except OSError:
        continue

    for shortcut_file in shortcut_files:
        try:
            identity = shortcut_file.resolve()
        except OSError:
            identity = shortcut_file.absolute()
        if identity in seen_files:
            continue
        seen_files.add(identity)

        try:
            shortcuts = read_shortcuts(shortcut_file)
        except (InvalidVdf, OSError):
            continue

        for shortcut in shortcuts:
            if not isinstance(shortcut, dict):
                continue
            fields = {str(key).lower(): value for key, value in shortcut.items()}
            appid = fields.get("appid")
            app_name = fields.get("appname")
            exact_executable = executable_matches(fields.get("exe"), expected_executable)
            name_fallback = isinstance(app_name, str) and app_name.casefold() == "tegra"
            if not isinstance(appid, int) or not (exact_executable or name_fallback):
                continue

            grid_directory = shortcut_file.parent / "grid"
            grid_value = str(grid_directory)
            if any(ord(character) < 32 for character in grid_value):
                continue
            matches.add((grid_value, appid & 0xFFFFFFFF))

for grid_directory, appid in sorted(matches):
    print(f"{grid_directory}\x1f{appid}")
PY
}

tegra_install_steam_artwork() {
  local tegra_records="$1"
  local -a tegra_artwork_files=(
    'tegra-grid-portrait.png'
    'tegra-grid-landscape.png'
    'tegra-hero.png'
    'tegra-logo.png'
    'tegra-icon.png'
  )
  local -a tegra_artwork_suffixes=('p.png' '.png' '_hero.png' '_logo.png' '_icon.png')
  local -a tegra_artwork_dimensions=('600x900' '920x430' '1920x620' '1280x720' '512x512')
  local -a tegra_artwork_downloads=()
  local -a tegra_artwork_available=()
  local tegra_index tegra_source tegra_grid_dir tegra_appid tegra_destination
  local tegra_any_downloaded=0
  local tegra_all_downloaded=1
  local tegra_any_installed=0

  tegra_log "$tegra_msg_artwork"
  for tegra_index in "${!tegra_artwork_files[@]}"; do
    tegra_source="$tegra_temp_dir/${tegra_artwork_files[$tegra_index]}"
    tegra_artwork_downloads[$tegra_index]="$tegra_source"
    if curl "${tegra_curl_args[@]}" --output "$tegra_source" \
      "$tegra_artwork_base_url/${tegra_artwork_files[$tegra_index]}" && \
      python3 - "$tegra_source" "${tegra_artwork_dimensions[$tegra_index]}" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_width, expected_height = (int(value) for value in sys.argv[2].split("x", 1))

try:
    header = path.read_bytes()[:24]
    valid = (
        header[:8] == b"\x89PNG\r\n\x1a\n"
        and header[12:16] == b"IHDR"
        and struct.unpack(">II", header[16:24]) == (expected_width, expected_height)
    )
except (OSError, ValueError, struct.error):
    valid = False

raise SystemExit(0 if valid else 1)
PY
    then
      tegra_artwork_available[$tegra_index]=1
      tegra_any_downloaded=1
    else
      tegra_artwork_available[$tegra_index]=0
      tegra_all_downloaded=0
    fi
  done

  [[ "$tegra_any_downloaded" -eq 1 ]] || return 1

  while IFS=$'\x1f' read -r tegra_grid_dir tegra_appid; do
    [[ -n "$tegra_grid_dir" && "$tegra_appid" =~ ^[0-9]+$ ]] || continue
    mkdir -p "$tegra_grid_dir" || return 1
    for tegra_index in "${!tegra_artwork_files[@]}"; do
      [[ "${tegra_artwork_available[$tegra_index]}" -eq 1 ]] || continue
      tegra_destination="$tegra_grid_dir/${tegra_appid}${tegra_artwork_suffixes[$tegra_index]}"
      install -m 0644 "${tegra_artwork_downloads[$tegra_index]}" "$tegra_destination.new" || return 1
      mv -f "$tegra_destination.new" "$tegra_destination" || return 1
      tegra_any_installed=1
    done
  done <<< "$tegra_records"

  [[ "$tegra_any_installed" -eq 1 && "$tegra_all_downloaded" -eq 1 ]]
}

tegra_cleanup() {
  rm -rf -- "$tegra_temp_dir"
}
trap tegra_cleanup EXIT

tegra_curl_args=(
  --fail
  --silent
  --show-error
  --location
  --retry 3
  --connect-timeout 20
  --user-agent 'Tegra-SteamOS-Installer/1'
)

if [[ "$tegra_allow_insecure_test_urls" != '1' ]]; then
  tegra_curl_args+=(--proto '=https' --tlsv1.2)
fi

tegra_log "$tegra_msg_metadata"
curl "${tegra_curl_args[@]}" --output "$tegra_metadata_path" "$tegra_api_url"

IFS=$'\x1f' read -r tegra_version tegra_file_name tegra_download_url tegra_expected_checksum < <(
  python3 - "$tegra_metadata_path" "$tegra_allow_insecure_test_urls" "$tegra_channel" <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

metadata_path = Path(sys.argv[1])
allow_insecure = sys.argv[2] == "1"
channel = sys.argv[3]

try:
    payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    release = payload if channel == "stable" else payload[channel]
    linux = release["linux"]
    version = str(linux["version"])
    url = str(linux["url"])
    parsed = urlparse(url)
    name = str(linux.get("name") or Path(parsed.path).name)
    checksum = str(linux["checksum"])
except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)

values = (version, name, url, checksum)
if any(not value or any(ord(character) < 32 for character in value) for value in values):
    raise SystemExit(1)

if not allow_insecure and (parsed.scheme != "https" or parsed.hostname != "updates.tegramc.com"):
    raise SystemExit(2)

print("\x1f".join(values))
PY
)

if [[ -z "${tegra_version:-}" || -z "${tegra_file_name:-}" || -z "${tegra_download_url:-}" || -z "${tegra_expected_checksum:-}" ]]; then
  tegra_fail "$tegra_msg_bad_metadata"
fi

if [[ "$tegra_allow_insecure_test_urls" != '1' ]]; then
  case "$tegra_download_url" in
    https://updates.tegramc.com/*)
      ;;
    *)
      tegra_fail "$tegra_msg_untrusted_url"
      ;;
  esac
fi

tegra_log "$tegra_msg_downloading $tegra_version ($tegra_file_name)."
curl "${tegra_curl_args[@]}" --output "$tegra_download_path" "$tegra_download_url"

tegra_log "$tegra_msg_checksum"
tegra_actual_checksum="$({
  python3 - "$tegra_download_path" <<'PY'
import base64
import hashlib
import sys
from pathlib import Path

digest = hashlib.sha512(Path(sys.argv[1]).read_bytes()).digest()
print(base64.b64encode(digest).decode("ascii"))
PY
} 2>/dev/null)"

if [[ -z "$tegra_expected_checksum" || "$tegra_actual_checksum" != "$tegra_expected_checksum" ]]; then
  tegra_fail "$tegra_msg_checksum_failed"
fi

tegra_log "$tegra_msg_installing"
mkdir -p "$tegra_install_dir" "$tegra_applications_dir" "$tegra_icons_dir"
install -m 0755 "$tegra_download_path" "$tegra_appimage_path.new"
mv -f "$tegra_appimage_path.new" "$tegra_appimage_path"
printf '%s\n' "$tegra_version" > "$tegra_install_dir/version"

if curl "${tegra_curl_args[@]}" --output "$tegra_icon_download_path" "$tegra_icon_url"; then
  install -m 0644 "$tegra_icon_download_path" "$tegra_icon_path"
else
  tegra_log "$tegra_msg_icon_warning"
  tegra_icon_path='com.seijin.tegramc.app'
fi

tegra_exec_path="${tegra_appimage_path//\\/\\\\}"
tegra_exec_path="${tegra_exec_path//\"/\\\"}"

{
  printf '%s\n' '[Desktop Entry]'
  printf '%s\n' 'Type=Application'
  printf '%s\n' 'Name=Tegra'
  printf '%s\n' 'Comment=Minecraft launcher and modpack manager'
  printf 'Exec="%s" %%U\n' "$tegra_exec_path"
  printf 'Icon=%s\n' "$tegra_icon_path"
  printf '%s\n' 'Terminal=false'
  printf '%s\n' 'Categories=Game;Utility;'
  printf '%s\n' 'MimeType=x-scheme-handler/tegra;'
  printf '%s\n' 'StartupNotify=true'
  printf '%s\n' 'StartupWMClass=Tegra'
  printf '%s\n' 'Keywords=Minecraft;Launcher;Modpacks;'
} > "$tegra_temp_dir/com.seijin.tegramc.app.desktop"

install -m 0644 "$tegra_temp_dir/com.seijin.tegramc.app.desktop" "$tegra_desktop_path"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$tegra_applications_dir" >/dev/null 2>&1 || true
fi

if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default "$(basename "$tegra_desktop_path")" x-scheme-handler/tegra >/dev/null 2>&1 || true
fi

if [[ "$tegra_skip_steam" -eq 0 ]]; then
  tegra_shortcut_requested=0
  tegra_shortcut_records="$(tegra_find_steam_shortcuts 2>/dev/null || true)"
  if [[ -f "$tegra_shortcut_marker" && "$tegra_force_steam_shortcut" -eq 0 ]]; then
    tegra_log "$tegra_msg_steam_exists"
  elif [[ -n "$tegra_shortcut_records" && "$tegra_force_steam_shortcut" -eq 0 ]]; then
    tegra_log "$tegra_msg_steam_found"
    printf '%s\n' "$tegra_version" > "$tegra_shortcut_marker"
  elif command -v steamos-add-to-steam >/dev/null 2>&1; then
    tegra_log "$tegra_msg_steam"
    if steamos-add-to-steam "$tegra_desktop_path"; then
      printf '%s\n' "$tegra_version" > "$tegra_shortcut_marker"
      tegra_shortcut_requested=1
    else
      tegra_fail "$tegra_msg_steam_failed"
    fi
  else
    tegra_fail "$tegra_msg_steam_missing"
  fi

  if [[ "$tegra_shortcut_requested" -eq 1 ]]; then
    tegra_shortcut_records=''
    for ((tegra_attempt = 1; tegra_attempt <= tegra_artwork_poll_attempts; tegra_attempt++)); do
      tegra_shortcut_records="$(tegra_find_steam_shortcuts 2>/dev/null || true)"
      if [[ -n "$tegra_shortcut_records" ]]; then
        break
      fi
      if [[ "$tegra_attempt" -lt "$tegra_artwork_poll_attempts" ]]; then
        sleep "$tegra_artwork_poll_interval"
      fi
    done
  fi

  if [[ -n "$tegra_shortcut_records" ]] && tegra_install_steam_artwork "$tegra_shortcut_records"; then
    tegra_log "$tegra_msg_artwork_done"
  else
    tegra_log "$tegra_msg_artwork_warning"
  fi
fi

tegra_log "$tegra_msg_done"
tegra_log "$tegra_msg_update"

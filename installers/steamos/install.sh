#!/usr/bin/env bash

set -Eeuo pipefail

# Public source: https://github.com/codebyant/tegra-installers
# This installer does not require sudo and only writes inside the current user's data directory.

tegra_api_url="${TEGRA_DOWNLOADS_API_URL:-https://api.tegramc.com/downloads/versions}"
tegra_icon_url="${TEGRA_ICON_URL:-https://tegramc.com/tegra-logo.png}"
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
  tegra_msg_steam_missing='O Tegra foi instalado, mas o comando steamos-add-to-steam não foi encontrado.'
  tegra_msg_steam_failed='O Tegra foi instalado, mas não foi possível adicionar o atalho à Steam.'
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
  tegra_msg_steam_missing='Tegra was installed, but steamos-add-to-steam was not found.'
  tegra_msg_steam_failed='Tegra was installed, but its Steam shortcut could not be added.'
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
  if [[ -f "$tegra_shortcut_marker" && "$tegra_force_steam_shortcut" -eq 0 ]]; then
    tegra_log "$tegra_msg_steam_exists"
  elif command -v steamos-add-to-steam >/dev/null 2>&1; then
    tegra_log "$tegra_msg_steam"
    if steamos-add-to-steam "$tegra_desktop_path"; then
      printf '%s\n' "$tegra_version" > "$tegra_shortcut_marker"
    else
      tegra_fail "$tegra_msg_steam_failed"
    fi
  else
    tegra_fail "$tegra_msg_steam_missing"
  fi
fi

tegra_log "$tegra_msg_done"
tegra_log "$tegra_msg_update"

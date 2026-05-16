#!/bin/bash
# Automacao MemPalace (Linux / macOS).
#
# ERRO: env: 'bash\r': No such file or directory  (ou exit 127 ao executar ./setup-mempalace.sh)
# Causa: ficheiro gravado com fins de linha Windows (CRLF). O kernel procura /bin/bash\r.
# Correcao (uma vez, na copia que tens no disco):
#   sed -i 's/\r$//' setup-mempalace.sh && chmod +x setup-mempalace.sh
# Alternativa sem tocar no ficheiro:  bash setup-mempalace.sh --menu
#
# Uso:
#   ./setup-mempalace.sh --menu
#   ./setup-mempalace.sh --action Full --project-path /caminho/do/projeto
# Apos git pull: ./setup-mempalace.sh --menu --force-install
# Cursor MCP: ./setup-mempalace.sh --action CursorMcp
#
# Sem argumentos: abre o mesmo assistente que --menu.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="${REPO_ROOT}/.venv"
ACTIVATE="${VENV_PATH}/bin/activate"

# Defaults (alinhados ao setup-mempalace.ps1)
ACTION="Full"
PROJECT_PATH=""
SEARCH_QUERY="mcp setup"
PALACE=""
SKIP_SEARCH=0
SKIP_INSTALL=0
FORCE_INSTALL=0
INTERACTIVE_INIT=0
MENU=0

write_step() {
  printf "\n\033[0;36m==> %s\033[0m\n" "$*"
}

is_yes() {
  case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    s|y|sim|yes) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_project_path() {
  local raw="${1:-}"
  if [[ -z "${raw// }" ]]; then
    pwd -P
  else
    cd "$raw" && pwd -P
  fi
}

get_expected_wing() {
  local dir="$1"
  local py=""
  command -v python3 >/dev/null 2>&1 && py="python3"
  [[ -z "$py" ]] && command -v python >/dev/null 2>&1 && py="python"
  if [[ -n "$py" ]]; then
    local out
    out="$($py - "$dir" <<'PY' 2>/dev/null || true
import pathlib, re, sys
d = pathlib.Path(sys.argv[1]).resolve()
for name in ("mempalace.yaml", "mempal.yaml"):
    p = d / name
    if not p.is_file():
        continue
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        t = line.lstrip()
        if t.startswith("#"):
            continue
        m = re.match(r'^\s*wing:\s*["\'](.+)["\']\s*$', line)
        if m:
            print(m.group(1).strip())
            raise SystemExit
        m = re.match(r"^\s*wing:\s*(.+)$", line)
        if m:
            v = m.group(1).split("#", 1)[0].strip().strip('"').strip("'")
            if v:
                print(v)
                raise SystemExit
print(d.name)
PY
)"
    out="$(echo "$out" | tr -d '\r' | tail -n1)"
    if [[ -n "${out// }" ]]; then
      echo "$out"
      return 0
    fi
  fi
  basename "$dir"
}

apply_palace_env() {
  local p="${1:-}"
  if [[ -z "${p// }" ]]; then
    return 0
  fi
  local full
  full="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
  export MEMPALACE_PALACE_PATH="$full"
  write_step "MEMPALACE_PALACE_PATH=$full"
}

ensure_venv() {
  write_step "Criar venv (se necessario)"
  if [[ ! -f "$ACTIVATE" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 -m venv "$VENV_PATH"
    elif command -v python >/dev/null 2>&1; then
      python -m venv "$VENV_PATH"
    else
      echo "Erro: precisa de python3 ou python no PATH." >&2
      exit 1
    fi
  fi
  write_step "Ativar venv"
  # shellcheck source=/dev/null
  source "$ACTIVATE"
}

ensure_mempalace_editable() {
  if [[ "$SKIP_INSTALL" == "1" ]]; then
    write_step "Saltar pip (--skip-install)"
    return 0
  fi
  if [[ "$FORCE_INSTALL" != "1" ]] && python -c "import mempalace" 2>/dev/null; then
    write_step "MemPalace ja no venv (sem pip). Use --force-install apos git pull."
    return 0
  fi
  write_step "Instalacao: pip + mempalace em modo editable (so quando falta ou com --force-install)"
  python -m pip install -q -U pip
  pip install -e "$REPO_ROOT"
}

python_exe_venv() {
  echo "${VENV_PATH}/bin/python"
}

read_project_folder() {
  local hint="${1:-}"
  echo ""
  echo "  --- Pasta do projeto ---"
  echo "  Codigo ou docs a indexar (nao precisa ser o repo MemPalace)."
  if [[ -n "$hint" ]]; then
    echo "  Sugestao: $hint"
  fi
  echo -n "  Pasta atual se carregar Enter: "
  pwd -P
  read -r -p "  Caminho (ou Enter): " in_path
  if [[ -z "${in_path// }" ]]; then
    pwd -P
  else
    resolve_project_path "$in_path"
  fi
}

show_banner() {
  echo ""
  echo "  ============================================="
  echo "    MemPalace - assistente"
  echo "  ============================================="
}

show_main_menu() {
  show_banner
  echo ""
  echo "  O que pretende fazer?"
  echo ""
  echo "  1  Primeira vez com este projeto"
  echo "     Instala o MemPalace, prepara pastas e guarda os ficheiros na memoria."
  echo ""
  echo "  2  Ja usei antes - quero atualizar"
  echo "     Volta a ler o projeto; ficheiros novos ou alterados entram na memoria."
  echo ""
  echo "  3  Ver o que ja esta na memoria"
  echo "     Mostra um resumo (por projeto / salas)."
  echo ""
  echo "  4  Gerar texto para colar na IA (ex.: Cursor)"
  echo "     Contexto curto (wake-up) para o chat."
  echo ""
  echo "  5  Procurar algo na memoria"
  echo "     Busca por palavra ou frase neste projeto."
  echo ""
  echo "  6  Mais opcoes..."
  echo ""
  echo "  7  Cursor: ligar MemPalace (MCP)"
  echo "     O Cursor nao descobre sozinho - mostra o JSON e o ficheiro a editar."
  echo ""
  echo "  0  Sair"
  echo ""
}

show_advanced_menu() {
  show_banner
  echo ""
  echo "  Mais opcoes"
  echo ""
  echo "  1  So reorganizar o projeto (init)"
  echo "     Atualiza salas e configuracao; nao reindexa todos os ficheiros."
  echo ""
  echo "  2  Usar outra pasta de memoria (palacio)"
  echo "     Para quem guarda a memoria noutro disco ou pasta."
  echo ""
  echo "  0  Voltar ao menu principal"
  echo ""
}

cursor_mcp_json_full_doc() {
  local pybin="${1:?}"
  VENV_PATH="$VENV_PATH" "$pybin" <<'PY'
import json, os
from pathlib import Path
venv = Path(os.environ["VENV_PATH"])
py = (venv / "bin" / "python").resolve()
args = ["-m", "mempalace.mcp_server"]
pal = os.environ.get("MEMPALACE_PALACE_PATH") or ""
if pal.strip():
    args = ["-m", "mempalace.mcp_server", "--palace", pal]
doc = {"mcpServers": {"mempalace": {"command": str(py), "args": args}}}
print(json.dumps(doc, indent=2))
PY
}

cursor_mcp_json_merge_inner() {
  local pybin="${1:?}"
  VENV_PATH="$VENV_PATH" "$pybin" <<'PY'
import json, os
from pathlib import Path
venv = Path(os.environ["VENV_PATH"])
py = (venv / "bin" / "python").resolve()
args = ["-m", "mempalace.mcp_server"]
pal = os.environ.get("MEMPALACE_PALACE_PATH") or ""
if pal.strip():
    args = ["-m", "mempalace.mcp_server", "--palace", pal]
inner = {"command": str(py), "args": args}
print(json.dumps(inner, separators=(",", ":")))
PY
}

show_cursor_mcp_instructions() {
  ensure_venv
  ensure_mempalace_editable
  local cursor_dir="${HOME}/.cursor"
  local cursor_mcp="${cursor_dir}/mcp.json"
  local pybin json_full merge_line
  pybin="$(python_exe_venv)"
  json_full="$(cursor_mcp_json_full_doc "$pybin")"
  merge_line='"mempalace": '"$(cursor_mcp_json_merge_inner "$pybin")"

  echo ""
  echo "  --- Cursor e o MemPalace ---"
  echo "  O chat do Cursor so ve ferramentas MCP se estiverem registadas (nao e automatico)."
  echo ""
  echo "  1) Definicoes do Cursor - Ferramentas e MCP (ou edite o JSON)."
  echo "  2) Ficheiro tipico (Linux/macOS): ${cursor_mcp}"
  echo "  3) Se ja tiver outros servidores, adicione so a chave \"mempalace\" dentro de \"mcpServers\"."
  echo ""
  echo "  --- Se o ficheiro for NOVO (copie o bloco inteiro) ---"
  echo "$json_full"
  echo ""
  echo "  --- Se ja existir mcp.json (so a entrada mempalace) ---"
  echo "  $merge_line"
  echo ""

  read -r -p "  Copiar o JSON completo para a area de transferencia? (S/N ou Y) " yn
  if is_yes "$yn"; then
    if command -v xclip >/dev/null 2>&1; then
      printf '%s' "$json_full" | xclip -selection clipboard 2>/dev/null || true
      echo "  Copiado (xclip). Cole no mcp.json ou na UI MCP."
    elif command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$json_full" | wl-copy 2>/dev/null || true
      echo "  Copiado (wl-copy). Cole no mcp.json ou na UI MCP."
    elif command -v pbcopy >/dev/null 2>&1; then
      printf '%s' "$json_full" | pbcopy 2>/dev/null || true
      echo "  Copiado (pbcopy). Cole no mcp.json ou na UI MCP."
    else
      echo "  Instale xclip (X11), wl-copy (Wayland) ou copie o bloco manualmente." >&2
    fi
  fi

  read -r -p "  Abrir a pasta .cursor no gestor de ficheiros? (S/N ou Y) " yn2
  if is_yes "$yn2"; then
    mkdir -p "$cursor_dir"
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$cursor_dir" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then
      open "$cursor_dir" >/dev/null 2>&1 || true
    fi
  fi

  echo ""
  echo "  Reinicie o Cursor depois de guardar o mcp.json."
  echo "  Referencia: mempalace mcp"
}

invoke_mempalace_setup() {
  local action="${1:?}"
  local project_path="${2:-}"
  local search_query="${3:-$SEARCH_QUERY}"
  local palace="${4:-$PALACE}"

  apply_palace_env "$palace"

  local proj
  proj="$(resolve_project_path "$project_path")"

  write_step "Operacao: $action"
  write_step "Instalacao MemPalace (repo): $REPO_ROOT"

  if [[ "$action" == "CursorMcp" ]]; then
    show_cursor_mcp_instructions
    write_step "Concluido"
    echo "Feito."
    return 0
  fi

  write_step "Projeto: $proj"
  if [[ ! -d "$proj" ]]; then
    echo "Erro: pasta do projeto nao existe: $proj" >&2
    exit 1
  fi

  local expected_wing
  expected_wing="$(get_expected_wing "$proj")"
  echo "  Nome do projeto na memoria (wing): $expected_wing"

  ensure_venv
  ensure_mempalace_editable

  case "$action" in
    Full)
      write_step "Preparar projeto (init)"
      if [[ "$INTERACTIVE_INIT" == "1" ]]; then
        mempalace init "$proj"
      else
        mempalace init --yes "$proj"
      fi
      write_step "Guardar ficheiros na memoria (pode demorar)"
      mempalace mine "$proj"
      echo "  Nota: se 'Files skipped' = total, o index ja existia (normal)."
      if [[ "$SKIP_SEARCH" != "1" ]]; then
        local test_q="$search_query"
        [[ "$search_query" == "mcp setup" ]] && test_q="$expected_wing"
        write_step "Teste de busca (consulta: $test_q)"
        mempalace search "$test_q" --wing "$expected_wing"
      fi
      ;;
    Update)
      write_step "Atualizar memoria (so ficheiros novos ou alterados)"
      mempalace mine "$proj"
      echo "  Se nada mudou, 0 processados e skipped - esperado."
      echo "  Totais: menu opcao 3."
      ;;
    InitOnly)
      write_step "Reorganizar projeto (init)"
      if [[ "$INTERACTIVE_INIT" == "1" ]]; then
        mempalace init "$proj"
      else
        mempalace init --yes "$proj"
      fi
      ;;
    Status)
      write_step "Resumo: wing esperado para este projeto: $expected_wing"
      write_step "Lista completa do palacio (todas as wings)"
      mempalace status
      ;;
    WakeUp)
      write_step "Texto para colar no chat (wake-up)"
      mempalace wake-up --wing "$expected_wing"
      echo "  L0 'No identity': opcional - crie ~/.mempalace/identity.txt (quem e o utilizador)."
      ;;
    Search)
      write_step "Busca: $search_query"
      mempalace search "$search_query" --wing "$expected_wing"
      ;;
    *)
      echo "Acao desconhecida: $action" >&2
      exit 1
      ;;
  esac

  write_step "Concluido"
  echo "Feito."
  if [[ "$action" == "Full" || "$action" == "Update" ]]; then
    echo "Dica: menu opcao 4 = wake-up para o Cursor."
  fi
}

menu_loop() {
  local repo_hint="$REPO_ROOT"
  while true; do
    show_main_menu
    read -r -p "  Escolha (0-7): " c
    c="$(echo "$c" | tr -d '[:space:]')"

    case "$c" in
      0)
        echo "Ate logo."
        return 0
        ;;
      7)
        show_cursor_mcp_instructions
        echo ""
        read -r -p "Enter para continuar " _
        continue
        ;;
      6)
        while true; do
          show_advanced_menu
          read -r -p "  Escolha (0-2): " a
          a="$(echo "$a" | tr -d '[:space:]')"
          case "$a" in
            0) break ;;
            1)
              pp="$(read_project_folder "$repo_hint")"
              invoke_mempalace_setup InitOnly "$pp" "$SEARCH_QUERY" ""
              echo ""
              read -r -p "Enter para continuar " _
              break
              ;;
            2)
              read -r -p "  Caminho completo da pasta do palacio: " pal_in
              if [[ -z "${pal_in// }" ]]; then
                echo "  Cancelado."
                sleep 1
                continue
              fi
              pal_in="$(echo "$pal_in" | sed "s/^[\"']//;s/[\"']$//")"
              echo ""
              echo "  Com essa pasta de memoria, o que fazer?"
              echo "  1  Ver resumo (status)  2  So mine  3  Full (init+mine)"
              read -r -p "  Escolha (1-3): " subp
              subp="$(echo "$subp" | tr -d '[:space:]')"
              pp="$(read_project_folder "$repo_hint")"
              export MEMPALACE_PALACE_PATH="$(resolve_project_path "$pal_in")"
              case "$subp" in
                1) invoke_mempalace_setup Status "$pp" "$SEARCH_QUERY" "$MEMPALACE_PALACE_PATH" ;;
                2) invoke_mempalace_setup Update "$pp" "$SEARCH_QUERY" "$MEMPALACE_PALACE_PATH" ;;
                3) invoke_mempalace_setup Full "$pp" "$SEARCH_QUERY" "$MEMPALACE_PALACE_PATH" ;;
                *)
                  echo "  Cancelado."
                  unset MEMPALACE_PALACE_PATH || true
                  sleep 1
                  continue
                  ;;
              esac
              unset MEMPALACE_PALACE_PATH || true
              echo "  (Palacio alternativo so nesta operacao.)"
              echo ""
              read -r -p "Enter para continuar " _
              break
              ;;
            *)
              echo "  Opcao invalida."
              sleep 1
              ;;
          esac
        done
        continue
        ;;
    esac

    case "$c" in
      1) sel_action=Full; sel_skip_search=0 ;;
      2) sel_action=Update; sel_skip_search=1 ;;
      3) sel_action=Status; sel_skip_search=1 ;;
      4) sel_action=WakeUp; sel_skip_search=1 ;;
      5) sel_action=Search; sel_skip_search=1 ;;
      *)
        echo "  Opcao invalida."
        sleep 1
        continue
        ;;
    esac

    pp="$(read_project_folder "$repo_hint")"
    sq="$SEARCH_QUERY"
    if [[ "$sel_action" == "Search" ]]; then
      read -r -p "  O que procura? (Enter = '$SEARCH_QUERY'): " qin
      if [[ -n "${qin// }" ]]; then
        sq="$qin"
      fi
    fi

    local old_skip="$SKIP_SEARCH"
    SKIP_SEARCH="$sel_skip_search"
    invoke_mempalace_setup "$sel_action" "$pp" "$sq" ""
    SKIP_SEARCH="$old_skip"

    echo ""
    read -r -p "Enter para voltar ao menu " _
  done
}

print_help() {
  cat <<EOF
MemPalace setup (Linux/macOS)

  ./setup-mempalace.sh                  # assistente interativo (= --menu)
  ./setup-mempalace.sh --menu
  ./setup-mempalace.sh --action Full --project-path /caminho/projeto
  ./setup-mempalace.sh --action CursorMcp
  ./setup-mempalace.sh --action Update --project-path /caminho --skip-search

Flags:
  --action Full|Update|Status|WakeUp|InitOnly|Search|CursorMcp
  --project-path DIR
  --search-query TEXTO   (default: mcp setup; em Full, se for o default, usa o wing no teste)
  --palace DIR           (export MEMPALACE_PALACE_PATH)
  --skip-search
  --skip-install
  --force-install
  --interactive-init     (init sem --yes)
  --menu
  -h, --help
EOF
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    MENU=1
    return 0
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --menu) MENU=1; shift ;;
      --action)
        ACTION="${2:?}"
        shift 2
        ;;
      --project-path)
        PROJECT_PATH="${2:?}"
        shift 2
        ;;
      --search-query)
        SEARCH_QUERY="${2:?}"
        shift 2
        ;;
      --palace)
        PALACE="${2:?}"
        shift 2
        ;;
      --skip-search) SKIP_SEARCH=1; shift ;;
      --skip-install) SKIP_INSTALL=1; shift ;;
      --force-install) FORCE_INSTALL=1; shift ;;
      --interactive-init) INTERACTIVE_INIT=1; shift ;;
      -h|--help) print_help; exit 0 ;;
      *)
        echo "Opcao desconhecida: $1" >&2
        print_help >&2
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  if [[ "$MENU" == "1" ]]; then
    menu_loop
    exit 0
  fi
  invoke_mempalace_setup "$ACTION" "$PROJECT_PATH" "$SEARCH_QUERY" "$PALACE"
}

main "$@"

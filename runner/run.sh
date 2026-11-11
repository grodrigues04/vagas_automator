#!/usr/bin/env bash
# Weekly job search routine. One attempt per ISO week: the week lock is created
# before anything else, so any error cancels the week and nothing retries it.
set -uo pipefail

# Never run Claude as root: see run-as-claude-user.sh
source /app/run-as-claude-user.sh

RUN_DATE=$(date +%F)
WEEK=$(date +%G-W%V)
LOCK_FILE="/data/state/$WEEK.lock"
OUTPUT_DIR="/data/out/$RUN_DATE"
LOG_FILE="/data/logs/$RUN_DATE.log"
MEMORY_FILE="/data/memoria/vagas-vistas.json"
MEMORY_BACKUP="/data/state/backup/vagas-vistas-$RUN_DATE.json"
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-5h}"
CLAUDE_MAX_TURNS="${CLAUDE_MAX_TURNS:-450}"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-5-5}"

log() {
  echo "[run $(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# MANUAL_RUN=1 runs the routine on demand: no week lock and no Thursday check,
# so the scheduled run of the week is not affected.
MANUAL_RUN="${MANUAL_RUN:-0}"

# Writes the reason to CANCELADO; send_results.py sends it as a message.
cancel_week() {
  mkdir -p "$OUTPUT_DIR"
  if [ "$MANUAL_RUN" = "1" ]; then
    printf 'Execução manual da rotina de vagas falhou (a rotina de quinta não foi afetada).\nMotivo: %s\n' "$1" > "$OUTPUT_DIR/CANCELADO"
  else
    printf 'Rotina de vagas da semana %s cancelada.\nMotivo: %s\n' "$WEEK" "$1" > "$OUTPUT_DIR/CANCELADO"
  fi
  log "CANCELADO: $1"
  exit 1
}

mkdir -p /data/state/backup /data/logs

if [ "$MANUAL_RUN" = "1" ]; then
  log "Starting MANUAL routine (no week lock, no Thursday check)"
else
  # 1. Week lock, before any check that could fail
  if [ -e "$LOCK_FILE" ]; then
    log "Week $WEEK already attempted, skipping"
    exit 0
  fi
  date '+%F %T' > "$LOCK_FILE" || { echo "cannot create $LOCK_FILE"; exit 1; }
  log "Starting routine for week $WEEK"

  # 2. Only Thursday, 21:00 to 21:09
  if [ "$(date +%u)" != "4" ] || [ "$(date +%H)" != "21" ] || [ "$((10#$(date +%M)))" -ge 10 ]; then
    cancel_week "a rotina tentou iniciar fora da janela de quinta-feira 21h ($(date '+%A %H:%M'))."
  fi
fi

# 3. Preflight
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || cancel_week "CLAUDE_CODE_OAUTH_TOKEN não está definido no .env."
[ -s /data/prompt.txt ] || cancel_week "arquivo data/prompt.txt não encontrado ou vazio."
[ -s /data/curriculo.pdf ] || cancel_week "arquivo data/curriculo.pdf não encontrado ou vazio."
[ -s "$MEMORY_FILE" ] || cancel_week "memória data/memoria/vagas-vistas.json não encontrada."
jq empty "$MEMORY_FILE" 2>/dev/null || cancel_week "memória data/memoria/vagas-vistas.json não é um JSON válido."
command -v claude >/dev/null || cancel_week "Claude Code não está instalado no container."
command -v weasyprint >/dev/null || cancel_week "weasyprint não está instalado no container."
mkdir -p "$OUTPUT_DIR" || cancel_week "não foi possível criar $OUTPUT_DIR."
cp "$MEMORY_FILE" "$MEMORY_BACKUP" || cancel_week "não foi possível fazer backup da memória."

# 4. Run Claude. The run date is fixed here so a run that crosses midnight
#    keeps writing to the same folder.
log "Running Claude (model $CLAUDE_MODEL, timeout $CLAUDE_TIMEOUT, max turns $CLAUDE_MAX_TURNS)"
{
  printf 'RUN DATE: %s. Use this date as D and as "today" everywhere in this prompt.\n\n' "$RUN_DATE"
  cat /data/prompt.txt
} | timeout "$CLAUDE_TIMEOUT" claude -p \
      --model "$CLAUDE_MODEL" \
      --max-turns "$CLAUDE_MAX_TURNS" \
      --allowedTools "Read" "Write" "Edit" "WebSearch" "WebFetch" \
                     "Bash(mkdir:*)" "Bash(weasyprint:*)" "Bash(pdfinfo:*)" \
      >> "$LOG_FILE" 2>&1
claude_exit_code=$?
log "Claude finished with exit code $claude_exit_code"

# 5. Memory must stay valid JSON; restore the backup otherwise
if ! jq empty "$MEMORY_FILE" 2>/dev/null; then
  cp "$MEMORY_BACKUP" "$MEMORY_FILE"
  log "Memory was invalid after the run, backup restored"
fi

# 6. Result
if [ -e "$OUTPUT_DIR/DONE" ] && [ -s "$OUTPUT_DIR/relatorio-vagas-$RUN_DATE.pdf" ]; then
  # PRONTO is the trigger of send_results.py: written only after Claude has exited
  touch "$OUTPUT_DIR/PRONTO"
  log "Routine finished, PDF ready for sending"
  exit 0
fi

if [ "$claude_exit_code" = "124" ]; then
  cancel_week "o Claude passou do tempo limite de $CLAUDE_TIMEOUT sem terminar o relatório."
fi
cancel_week "o Claude terminou (código $claude_exit_code) sem gerar o PDF final. Veja data/logs/$RUN_DATE.log."

#!/usr/bin/env bash
# Manual end-to-end test of the delivery chain (Claude auth, weasyprint, personalWhats).
# It is NOT the weekly routine: it uses a tiny prompt, does not touch the memory
# and does not create a week lock.
set -uo pipefail

# Never run Claude as root: see run-as-claude-user.sh
source /app/run-as-claude-user.sh

TEST_ID="teste-$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="/data/out/$TEST_ID"
mkdir -p "$OUTPUT_DIR"

claude -p --max-turns 10 --model "${CLAUDE_MODEL:-claude-opus-5-5}" \
  --allowedTools "Write" "Bash(weasyprint:*)" "Bash(pdfinfo:*)" <<EOF
This is a delivery test. Do exactly this and nothing else:
1. Write $OUTPUT_DIR/relatorio.html: a short HTML page in Brazilian Portuguese titled "Teste da rotina de vagas", with one sentence saying the test worked and the text 日本語テスト to check Japanese fonts. Use font-family "Noto Sans", "Noto Sans CJK JP", sans-serif.
2. Run: weasyprint $OUTPUT_DIR/relatorio.html $OUTPUT_DIR/relatorio-vagas-$TEST_ID.pdf
3. Run: pdfinfo $OUTPUT_DIR/relatorio-vagas-$TEST_ID.pdf
4. Write $OUTPUT_DIR/resumo.txt with the text: *Teste* da rotina de vagas: Claude, PDF e WhatsApp funcionando.
5. Write the empty file $OUTPUT_DIR/DONE.
EOF

if [ -e "$OUTPUT_DIR/DONE" ] && [ -s "$OUTPUT_DIR/relatorio-vagas-$TEST_ID.pdf" ]; then
  touch "$OUTPUT_DIR/PRONTO"
  echo "OK: $OUTPUT_DIR ready, send_results.py queues it in personalWhats within 30 seconds"
else
  echo "FAILED: $OUTPUT_DIR/DONE was not created"
  exit 1
fi

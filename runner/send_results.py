"""Sends every finished routine result in /data/out through interface-personal-whats.

Runs as root, called by the scheduler every 30 seconds, never by Claude. A result folder is sent
when it contains:
  PRONTO    -> relatorio-vagas-*.pdf as an attachment, resumo.txt as its caption.
               Written by run.sh only after the Claude process has exited, so the PDF is never
               picked up half-written.
  CANCELADO -> the cancellation reason as text (plus the partial PDF, when there is one)
Only the final report (PRONTO) goes to VAGAS_RECIPIENT; cancellations and failure notices go to
the personalWhats default chat (group "Claudio"), so the report recipient only gets the PDF.
After queueing, ENVIADO is written with the message id, so the folder is never sent twice.
Content the interface refuses (ex.: PDF over the size limit) can never be sent: the reason goes
to ENVIO_FALHOU and a short text message reports it.
"""

import logging
import os
import time
from pathlib import Path
from typing import Optional

from interface_personal_whats import (
    Attachment,
    InterfacePersonalWhats,
    PersonalWhatsError,
)
from pydantic import ValidationError

log = logging.getLogger("send_results")

OUTPUT_ROOT = Path("/data/out")
SOURCE = "vagas_automator"
MAX_RESULT_AGE_SECONDS = 7 * 24 * 60 * 60
MAX_CAPTION_LENGTH = 1000


def read_text(file_path: Path) -> str:
    return file_path.read_text(encoding="utf-8").strip() if file_path.exists() else ""


def find_report_pdf(result_dir: Path) -> Optional[Path]:
    return next(iter(sorted(result_dir.glob("relatorio-vagas-*.pdf"))), None)


def list_pending_results() -> list[Path]:
    if not OUTPUT_ROOT.exists():
        return []
    return sorted(
        result_dir
        for result_dir in OUTPUT_ROOT.iterdir()
        if result_dir.is_dir()
        and not (result_dir / "ENVIADO").exists()
        and not (result_dir / "ENVIO_FALHOU").exists()
        and ((result_dir / "PRONTO").exists() or (result_dir / "CANCELADO").exists())
        and time.time() - result_dir.stat().st_mtime < MAX_RESULT_AGE_SECONDS
    )


def write_marker(result_dir: Path, file_name: str, content: str) -> None:
    """Markers belong to the owner of /data, not to root."""
    marker = result_dir / file_name
    marker.write_text(content + "\n", encoding="utf-8")
    data_owner = OUTPUT_ROOT.stat()
    os.chown(marker, data_owner.st_uid, data_owner.st_gid)


def send_result(whats: InterfacePersonalWhats, result_dir: Path, recipient: Optional[str]) -> str:
    pdf_path = find_report_pdf(result_dir)

    if (result_dir / "PRONTO").exists():
        if pdf_path is None:
            raise FileNotFoundError("PRONTO existe mas o PDF não foi encontrado")
        caption = read_text(result_dir / "resumo.txt")[:MAX_CAPTION_LENGTH] or "Relatório de vagas"
        return whats.send_message(
            SOURCE,
            recipient=recipient,
            attachments=[Attachment.from_path(pdf_path, caption=caption)],
        )

    attachments = []  # CANCELADO: always to the default chat, never to the report recipient
    if pdf_path is not None:
        attachments.append(
            Attachment.from_path(pdf_path, caption="Relatório parcial gerado antes da falha.")
        )
    return whats.send_message(
        SOURCE,
        text=read_text(result_dir / "CANCELADO"),
        attachments=attachments,
    )


def send_pending_results(whats: InterfacePersonalWhats, recipient: Optional[str]) -> None:
    for result_dir in list_pending_results():
        try:
            message_id = send_result(whats, result_dir, recipient)
        except ValidationError as error:
            write_marker(result_dir, "ENVIO_FALHOU", str(error))
            log.error(f"Result {result_dir.name} refused by the interface: {error}")
            whats.send_message(
                SOURCE,
                text=(
                    f"Rotina de vagas: o resultado {result_dir.name} não pôde ser enviado "
                    "(conteúdo recusado pela interface). Veja ENVIO_FALHOU na pasta do resultado."
                ),
            )
            continue
        write_marker(result_dir, "ENVIADO", message_id)
        log.info(f"Result {result_dir.name} queued as message {message_id}")


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, format="[send_results %(asctime)s] %(levelname)s %(message)s"
    )
    if not list_pending_results():
        return
    whats = InterfacePersonalWhats(
        mongo_uri=os.environ["MONGO_URI"],
        encryption_password=os.environ["ENCRYPTION_PASSWORD"],
    )
    try:
        send_pending_results(whats, os.environ.get("VAGAS_RECIPIENT") or None)
    except (PersonalWhatsError, OSError) as error:
        log.error(f"Failed to send results, trying again in 30 seconds: {error}")
    finally:
        whats.close()


if __name__ == "__main__":
    main()

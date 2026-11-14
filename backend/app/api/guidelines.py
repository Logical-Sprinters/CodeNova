from fastapi import APIRouter, Depends, Query

from ..db import fetch_all
from ..deps import current_user

router = APIRouter(tags=["guidelines"])


@router.get("/rules", summary="Every rule version, with whether it is live today")
def rules(channel: str | None = Query(default=None), user: dict = Depends(current_user)):
    return fetch_all(
        """
        SELECT r.rule_id, r.version, r.type, r.rule_text, r.source_file, r.source_page,
               r.status, r.effective_from, r.expires_on, r.risk_tier, r.channels,
               r.price_sensitive, r.confirmed_by,
               (SELECT d.title FROM guideline_documents d
                 WHERE d.document_id = r.document_id) AS document_title,
               (SELECT d.version_label FROM guideline_documents d
                 WHERE d.document_id = r.document_id) AS document_version,
               EXISTS (SELECT 1 FROM v_live_rules l
                        WHERE l.rule_id = r.rule_id AND l.version = r.version) AS is_live_now
          FROM rules r
         WHERE (%(channel)s::text IS NULL OR %(channel)s::text = ANY (r.channels))
         ORDER BY r.rule_id, r.version
        """,
        {"channel": channel},
    )


@router.get("/documents", summary="The source documents rules come from")
def documents(user: dict = Depends(current_user)):
    return fetch_all(
        """
        SELECT d.document_id, d.title, d.version_label, d.doc_type, d.status,
               d.effective_from, d.expires_on, d.file_name, d.page_count, d.created_at,
               (SELECT count(*) FROM rules r WHERE r.document_id = d.document_id) AS rule_count
          FROM guideline_documents d
         ORDER BY d.status, d.title, d.version_label
        """
    )

"""
History router — scan session history and compliance trends.
GET /api/history            → paginated session list
GET /api/history/trends     → score over time (for charts)
GET /api/history/categories → per-category breakdown over time
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from core.database import get_db
from core.models import ScanSession, ScanResult, VERIFICATION_TRIGGERS, NOT_ASSESSED

router = APIRouter(prefix="/api/history", tags=["history"])


@router.get("")
def list_history(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    base = db.query(ScanSession).filter(
        ScanSession.triggered_by.notin_(VERIFICATION_TRIGGERS),
        ScanSession.finished_at.isnot(None),
    )
    total = base.count()
    sessions = (
        base
        .order_by(ScanSession.started_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "offset": offset,
        "sessions": [
            {
                "id": s.id,
                "started_at": s.started_at.isoformat() if s.started_at else None,
                "finished_at": s.finished_at.isoformat() if s.finished_at else None,
                "triggered_by": s.triggered_by,
                "total_rules": s.total_rules,
                "pass_count": s.pass_count,
                "fail_count": s.fail_count,
                "na_count": s.na_count,
                "error_count": s.error_count,
                "mdm_count": s.mdm_count,
                "exempt_count": s.exempt_count,
                "not_assessed_count": s.not_assessed_count or 0,
                "degraded_reason": s.degraded_reason,
                "assessed": (s.pass_count or 0) + (s.fail_count or 0) + (s.error_count or 0),
                "score_pct": s.score_pct,
            }
            for s in sessions
        ],
    }


@router.get("/trends")
def get_trends(
    days: int = Query(30, ge=1, le=365),
    db: Session = Depends(get_db),
):
    """Return compliance score over time for the trend chart."""
    since = datetime.utcnow() - timedelta(days=days)
    sessions = (
        db.query(ScanSession)
        .filter(
            ScanSession.finished_at.isnot(None),
            ScanSession.started_at >= since,
            ScanSession.score_pct.isnot(None),
            ScanSession.triggered_by.notin_(VERIFICATION_TRIGGERS),
        )
        .order_by(ScanSession.started_at.asc())
        .all()
    )
    return {
        "days": days,
        "data": [
            {
                "date": s.started_at.isoformat() if s.started_at else None,
                "score_pct": s.score_pct,
                "pass": s.pass_count,
                "fail": s.fail_count,
                # Coverage travels with the point so the chart can show that a
                # 100% scored over 12 rules is not the same as one over 268.
                "assessed": (s.pass_count or 0) + (s.fail_count or 0) + (s.error_count or 0),
                "not_assessed": s.not_assessed_count or 0,
                "total_rules": s.total_rules,
                "degraded_reason": s.degraded_reason,
                "session_id": s.id,
            }
            for s in sessions
        ],
    }


@router.get("/categories")
def get_category_trends(
    session_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
):
    """Return per-category compliance breakdown for a given session (or latest)."""
    if not session_id:
        latest = (
            db.query(ScanSession)
            .filter(
                ScanSession.finished_at.isnot(None),
                ScanSession.triggered_by.notin_(VERIFICATION_TRIGGERS),
            )
            .order_by(ScanSession.started_at.desc())
            .first()
        )
        if not latest:
            return {"categories": []}
        session_id = latest.id

    results = db.query(ScanResult).filter(ScanResult.session_id == session_id).all()
    by_cat: dict[str, dict] = {}
    for r in results:
        cat = r.category or "Other"
        if cat not in by_cat:
            by_cat[cat] = {"category": cat, "pass": 0, "fail": 0, "na": 0, "mdm": 0,
                           "exempt": 0, "error": 0, "not_assessed": 0}
        st = r.status
        if st == "PASS":
            by_cat[cat]["pass"] += 1
        elif st == "FAIL":
            by_cat[cat]["fail"] += 1
        elif st == "NOT_APPLICABLE":
            by_cat[cat]["na"] += 1
        elif st == "MDM_REQUIRED":
            by_cat[cat]["mdm"] += 1
        elif st == "EXEMPT":
            by_cat[cat]["exempt"] += 1
        elif st == NOT_ASSESSED:
            by_cat[cat]["not_assessed"] += 1
        else:
            by_cat[cat]["error"] += 1

    for cat_data in by_cat.values():
        cat_data["assessed"] = cat_data["pass"] + cat_data["fail"] + cat_data["error"]
        cat_data["total"] = sum(
            cat_data[k] for k in ("pass", "fail", "na", "mdm", "exempt", "error", "not_assessed")
        )
        # Same score rule as the session (see models.py): FAIL and ERROR count
        # against, NOT_ASSESSED is excluded, and a category with nothing but
        # NOT_ASSESSED has no percentage to express.
        denominator = cat_data["total"] - cat_data["not_assessed"]
        cat_data["score_pct"] = (
            round((denominator - cat_data["fail"] - cat_data["error"]) / denominator * 100, 1)
            if denominator else None
        )

    return {"session_id": session_id, "categories": sorted(by_cat.values(), key=lambda x: x["category"])}

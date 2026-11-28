"""Les jetons passés dans l'adresse (lecteur web) ne sont jamais écrits dans les journaux d'accès."""

import logging

from app.logging_config import HideTokens


def test_the_access_log_never_contains_a_token():
    record = logging.LogRecord(
        "uvicorn.access", logging.INFO, __file__, 1, '%s - "%s %s HTTP/%s" %d',
        ("1.2.3.4:5", "GET", "/stream/deezer/1?quality=best&token=abc.def.ghi", "1.1", 200), None,
    )
    assert HideTokens().filter(record)
    assert "abc.def.ghi" not in record.getMessage() and "token=***" in record.getMessage()
    assert "quality=best" in record.getMessage()

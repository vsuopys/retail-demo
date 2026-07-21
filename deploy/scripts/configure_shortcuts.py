"""Enable OneLake availability on the clickstream table and shortcut it into the lakehouse.

For the clickstream events to be readable through the ``retail_lakehouse``, two
things must happen after ``terraform apply`` -- neither of which Terraform or the
``microsoft/fabric`` provider can do:

1. **Enable OneLake availability** on the clickstream KQL table so it is exposed
   in Delta Lake format at the KQL database's OneLake path (``Tables/<table>``).
   This is the ``policy mirroring`` management command, which is *not* accepted in
   a KQL database item-definition schema (``ScriptContainsUnsupportedCommand``),
   so it is run against the live database via the Kusto SDK -- the same path
   ``apply_kql`` uses.
2. **Create a OneLake shortcut** in the lakehouse ``Tables/<schema>`` folder
   pointing at that OneLake path. Placing it under ``Tables/bronze`` on a
   schema-enabled lakehouse implicitly creates the ``bronze`` schema.

Downstream engines (Notebooks, Warehouse, Direct Lake) can then read the
clickstream events through ``bronze.<name>`` without querying the Eventhouse
directly. This runs as a post-apply deploy step (after ``configure_environment``)
and is a no-op when clickstream is disabled.

Steps (under the operator credential):

    # 1. mirroring policy via Kusto management endpoint
    .alter table <table> policy mirroring dataformat=parquet with (IsEnabled=true)

    # 2. OneLake shortcut via Fabric REST
    POST /v1/workspaces/{ws}/items/{lakehouseId}/shortcuts
         ?shortcutConflictPolicy=CreateOrOverwrite
         body = {
           "path": "Tables/<schema>",
           "name": "<shortcut>",
           "target": {"oneLake": {
             "workspaceId": "<ws>", "itemId": "<kqlDbId>",
             "path": "Tables/<table>"}}}
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any

from deploy.scripts import _output as console
from deploy.scripts._auth import AUTH_MODES, build_credential

if TYPE_CHECKING:
    from azure.core.credentials import TokenCredential

REPO_ROOT = Path(__file__).resolve().parents[2]
FABRIC_SCOPE = "https://api.fabric.microsoft.com/.default"
FABRIC_API = "https://api.fabric.microsoft.com/v1"


def _terraform_outputs(environment: str) -> dict[str, Any]:
    from deploy.scripts.deploy_config import load_terraform_outputs

    path = REPO_ROOT / "deploy" / ".generated" / environment / "terraform-output.json"
    if not path.exists():
        raise SystemExit(
            f"Terraform outputs not found: {path}\n"
            "Run a full deploy first (the Terraform steps write this file), or "
            "pass the ids/names explicitly."
        )
    return load_terraform_outputs(path)


def _headers(credential: TokenCredential) -> dict[str, str]:
    token = credential.get_token(FABRIC_SCOPE).token
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def enable_onelake_availability(
    *,
    workspace_id: str,
    kql_database_id: str,
    table_name: str,
    credential: TokenCredential,
) -> None:
    """Turn on OneLake availability (mirroring policy) for the clickstream table.

    Runs the ``policy mirroring`` management command against the live KQL database
    with the Kusto SDK (reusing ``apply_kql``'s resolver). This exposes the table
    in Delta Lake format at the database's OneLake path so it can be shortcut into
    the lakehouse.

    The operation is idempotent: an already-enabled mirroring policy has immutable
    ``Backfill``/``EffectiveDateTime`` properties, so re-issuing ``.alter table …
    policy mirroring`` on an enabled table fails. We therefore read the current
    policy first and skip the alter when mirroring is already enabled.
    """

    import json as _json

    from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

    from deploy.scripts.apply_kql import resolve_kql_database

    query_uri, database_name = resolve_kql_database(
        workspace_id, kql_database_id, credential
    )
    kcsb = KustoConnectionStringBuilder.with_azure_token_credential(
        query_uri, credential
    )
    with KustoClient(kcsb) as client:
        show = client.execute_mgmt(
            database_name, f".show table {table_name} policy mirroring"
        )
        results = show.primary_results
        for row in list(results[0]) if results else []:
            try:
                policy_raw = row["Policy"]
            except (KeyError, IndexError, TypeError):
                policy_raw = None
            if policy_raw:
                try:
                    if _json.loads(policy_raw).get("IsEnabled"):
                        console.info(
                            f"OneLake availability already enabled on "
                            f"'{database_name}.{table_name}'; skipping."
                        )
                        return
                except (ValueError, TypeError):
                    pass

        command = (
            f".alter table {table_name} policy mirroring "
            "dataformat=parquet with (IsEnabled=true)"
        )
        console.info(
            f"Enabling OneLake availability on '{database_name}.{table_name}' "
            f"@ {query_uri}"
        )
        client.execute_mgmt(database_name, command)


def create_shortcut(
    *,
    workspace_id: str,
    lakehouse_id: str,
    schema: str,
    shortcut_name: str,
    target_item_id: str,
    target_table: str,
    credential: TokenCredential,
    retries: int = 6,
    retry_interval: float = 20.0,
) -> None:
    """Create (or overwrite) the OneLake shortcut into the lakehouse schema.

    OneLake availability can lag a few moments behind the mirroring policy, so
    the target ``Tables/<table>`` path may not resolve on the first attempt. Retry
    on the "target not found" style failures before giving up.
    """

    import requests

    url = (
        f"{FABRIC_API}/workspaces/{workspace_id}/items/{lakehouse_id}/shortcuts"
        "?shortcutConflictPolicy=CreateOrOverwrite"
    )
    body = {
        "path": f"Tables/{schema}",
        "name": shortcut_name,
        "target": {
            "oneLake": {
                "workspaceId": workspace_id,
                "itemId": target_item_id,
                "path": f"Tables/{target_table}",
            }
        },
    }

    last_error: str = ""
    for attempt in range(1, retries + 1):
        resp = requests.post(url, headers=_headers(credential), json=body, timeout=60)
        if resp.status_code in (200, 201):
            console.info(
                f"Shortcut '{schema}/{shortcut_name}' -> KQL table "
                f"'{target_table}' created in lakehouse {lakehouse_id}."
            )
            return
        last_error = f"HTTP {resp.status_code}: {resp.text}"
        # The KQL table's OneLake (Delta) path may not be materialized yet right
        # after enabling the mirroring policy; retry those cases only.
        retryable = resp.status_code in (404, 409, 429) or _is_target_pending(resp)
        if not retryable or attempt == retries:
            break
        console.detail(
            f"Shortcut target not ready yet ({last_error}); "
            f"attempt {attempt}/{retries}, retrying in {retry_interval:.0f}s..."
        )
        time.sleep(retry_interval)

    raise RuntimeError(
        f"Failed to create clickstream shortcut '{schema}/{shortcut_name}'. "
        f"Last response: {last_error}"
    )


def _is_target_pending(resp: Any) -> bool:
    """True when the error indicates the shortcut target path isn't ready yet."""

    try:
        code = str(resp.json().get("errorCode", "")).lower()
    except ValueError:
        code = ""
    text = f"{code} {resp.text}".lower()
    return any(
        token in text
        for token in ("notfound", "not found", "does not exist", "unavailable")
    )


def configure(
    *,
    workspace_id: str,
    lakehouse_id: str,
    schema: str,
    shortcut_name: str,
    target_item_id: str,
    target_table: str,
    auth_mode: str = "azure_cli",
    credential: TokenCredential | None = None,
) -> int:
    """Enable OneLake availability then create the shortcut. Returns 0 on success."""

    credential = credential or build_credential(auth_mode)
    enable_onelake_availability(
        workspace_id=workspace_id,
        kql_database_id=target_item_id,
        table_name=target_table,
        credential=credential,
    )
    create_shortcut(
        workspace_id=workspace_id,
        lakehouse_id=lakehouse_id,
        schema=schema,
        shortcut_name=shortcut_name,
        target_item_id=target_item_id,
        target_table=target_table,
        credential=credential,
    )
    return 0


def main() -> int:
    """Create the retail_lakehouse bronze-schema shortcut to the clickstream table."""

    parser = argparse.ArgumentParser(
        description="Create the clickstream OneLake shortcut in the lakehouse."
    )
    parser.add_argument(
        "--environment",
        help="Read ids/names from deploy/.generated/<env>/terraform-output.json.",
    )
    parser.add_argument("--workspace-id", help="Fabric workspace id.")
    parser.add_argument("--lakehouse-id", help="Target lakehouse item id.")
    parser.add_argument("--schema", help="Lakehouse schema for the shortcut (e.g. bronze).")
    parser.add_argument("--shortcut-name", help="Shortcut name.")
    parser.add_argument("--kql-database-id", help="Source clickstream KQL database id.")
    parser.add_argument("--table-name", help="Source clickstream KQL table name.")
    parser.add_argument(
        "--auth-mode",
        choices=AUTH_MODES,
        default="azure_cli",
        help="Operator credential used for Fabric requests.",
    )
    args = parser.parse_args()

    workspace_id = args.workspace_id
    lakehouse_id = args.lakehouse_id
    schema = args.schema
    shortcut_name = args.shortcut_name
    kql_database_id = args.kql_database_id
    table_name = args.table_name
    if args.environment:
        outputs = _terraform_outputs(args.environment)
        workspace_id = workspace_id or outputs.get("workspace_id")
        lakehouse_id = lakehouse_id or outputs.get("lakehouse_id")
        schema = schema or outputs.get("clickstream_shortcut_schema")
        shortcut_name = shortcut_name or outputs.get("clickstream_shortcut_name")
        kql_database_id = kql_database_id or outputs.get("clickstream_kql_database_id")
        table_name = table_name or outputs.get("clickstream_table_name")

    # The clickstream path is opt-in. When disabled, the clickstream Terraform
    # outputs are null; skip cleanly so the step is a no-op in that case.
    if not kql_database_id or not shortcut_name or not schema or not table_name:
        console.info(
            "Clickstream not enabled (no KQL database / shortcut config); "
            "skipping OneLake shortcut creation."
        )
        return 0
    if not workspace_id or not lakehouse_id:
        raise SystemExit(
            "Creating the clickstream shortcut requires --workspace-id and "
            "--lakehouse-id, or --environment with generated Terraform outputs."
        )

    return configure(
        workspace_id=str(workspace_id),
        lakehouse_id=str(lakehouse_id),
        schema=str(schema),
        shortcut_name=str(shortcut_name),
        target_item_id=str(kql_database_id),
        target_table=str(table_name),
        auth_mode=args.auth_mode,
    )


if __name__ == "__main__":
    raise SystemExit(main())

# Cloud Database Design — Lagos Heritage Pensions Ltd

**Student:** Etim Christian Ime — 2026/A/MIT/0925 — MIT, Miva Open University — Sept 2026 cohort
**Database:** `pensions` (PostgreSQL 16)

This note describes how Lagos Heritage Pensions Ltd would run the `pensions` database on a managed PostgreSQL service in the cloud, with a Nigerian regulatory lens (NDPA 2023 for personal data and PenCom as the regulator of pension records). It does not invent cloud regions; it lists real ones offered by the major hyperscalers that have a presence in or near Nigeria.

## 1. Workload summary (what we are sizing for)

| Workload | Shape | Sizing driver |
|---|---|---|
| OLTP — contribution posting | ~1.5 k writes/min peak (employer batch uploads on the 25th of each month) | Sustained write throughput, low latency |
| OLTP — withdrawal claim submission | ~50/day, bursty on the first working day of the month | Low write volume but high consistency bar |
| OLAP — management dashboards (P2 queries) | ~10 concurrent analysts | Read-mostly; can be offloaded to a replica |
| Retention | PenCom requires pension records to be retained for the lifetime of the RSA + a post-retirement window; treat as 50-year retention | Cold storage / archived partitions |

## 2. Managed PostgreSQL service choice

Three managed PostgreSQL options that have a real region close to Nigeria:

* **AWS RDS for PostgreSQL** in `eu-west-1` (Dublin) or `af-south-1` (Cape Town).
* **Microsoft Azure Database for PostgreSQL — Flexible Server** in `West Europe` (Netherlands) or `South Africa North` (Johannesburg).
* **Google Cloud AlloyDB for PostgreSQL / Cloud SQL** in `europe-west1` (Belgium) or `africa-south1` (Johannesburg, in preview).

The closest physically available regions to Lagos are Cape Town (`af-south-1`), Johannesburg (`southafricanorth` / `africa-south1`) and the European regions. Latency from Lagos to Johannesburg is typically 40–80 ms round trip; Lagos to Dublin is around 120 ms.

**Residency caveat (NDPA 2023):** the Nigeria Data Protection Act 2023 requires that personal data of Nigerians is processed in Nigeria unless there is a lawful basis for transfer, such as the data subject's consent or an adequacy decision. The PFA should default to in-country processing where a managed PostgreSQL offering exists in an `ng`-located region, and only route to Johannesburg/Dublin if a documented lawful basis is recorded per data category. **The brief assumes nothing leaves Nigeria without flagging the residency question first.** If no in-country managed PostgreSQL region is available for the chosen hyperscaler, the alternative is a self-managed PostgreSQL cluster in a Tier-III Lagos data centre on top of a local cloud (e.g. Layer3, MDXi, Raxio) with the same high-availability pattern described below.

## 3. High-availability topology

```
                   ┌───────────────┐
                   │  Application  │  (PFA portal + employer batch uploader)
                   └───────┬───────┘
                           │ read/write
                  ┌────────▼────────┐        synchronous stream (no data loss)
                  │  Primary (AZ-1) │──────────────────────┐
                  │  pg16, r6g.2xl  │                      │
                  └────────┬────────┘                      │
                           │                       ┌───────▼────────┐
                  ┌────────▼────────┐              │ Standby (AZ-2) │
                  │  Read Replica   │              │  hot standby   │
                  │  (OLAP / dash)  │              │  promotable    │
                  └─────────────────┘              └────────────────┘
```

* **Multi-AZ primary + synchronous standby.** Both nodes live in different availability zones of the same region. The standby receives a synchronous replication stream so a primary failure does not lose committed transactions.
* **Read replica (asynchronous) in a third AZ** for OLAP / dashboard workload (the P2 reporting queries) so analyst traffic never competes with the contribution-posting write path on the primary.
* **Automated daily snapshots + continuous WAL archive** to object storage. Snapshot retention sized to PenCom's record-retention duty (decades, not days) using a tiered policy: 7 daily snapshots kept hot, monthly snapshots moved to cold archive.
* **Point-in-time recovery** to any second within the snapshot retention window (typically 35 days for the warm PITR window).

## 4. Sync vs async replication trade-off

| Mode | What it guarantees | What it costs | Where it fits in the PFA |
|---|---|---|---|
| **Synchronous** (wait for at least one standby to flush WAL before COMMIT returns) | Zero committed-transaction loss on a single-AZ failure | Higher write latency (a round trip to the standby per commit); throughput bounded by the slower of the two AZs | The primary contribution-posting path. A PFA cannot tolerate "the system says paid but the money was not actually debited from the RSA balance". |
| **Asynchronous** (primary commits locally, streams WAL to standby afterwards) | Lower commit latency, higher throughput | Small window (typically < 1 s) of committed transactions that can be lost if the primary fails before the WAL ships | The OLAP read replica and the cross-region DR replica. Analysts reading a dashboard do not need every last transaction; DR only needs to be within an RPO of a few seconds. |

**RPO / RTO targets:**

* RPO (data loss) — synchronous path: **0** for OLTP, ≤ 5 s for the cross-region DR replica.
* RTO (recovery time) — **≤ 60 s** for an AZ failover (managed service automatic failover), **≤ 4 h** for a full region restore from snapshot + WAL replay.

## 5. Backup strategy

| Tier | What | Frequency | Retention | Storage |
|---|---|---|---|---|
| Hot | Automated cluster snapshot | Daily | 14 days | Managed service snapshot bucket |
| Warm | WAL archive | Continuous | 35 days | Object storage in same region |
| Cold | Monthly snapshot + monthly `pg_dump` of static tables | Monthly | 10 years | Object storage in archive tier (e.g. S3 Glacier, Azure Archive, GCP Archive) |
| DR | Cross-region asynchronous replica | Continuous | n/a | Different region |

Backups are encrypted at rest with a customer-managed key. Restores are tested quarterly into a staging cluster and the result is checked against a known checksum of contribution totals per employer.

## 6. Partitioning strategy at scale

The P5 partitioning file partitions `contribution` by **month (RANGE)**. In production this gives us:

* **Pruning** — management reports for "this month" or "last 3 months" touch only the relevant partitions.
* **Tiered storage** — older partitions can be moved to cheaper tablespace backing storage without affecting the hot partitions.
* **Archival** — partitions older than the PenCom-defined retention window for online query can be detached and exported to a cold archive via `pg_dump` of the detached partition.

A monthly DEFAULT partition catches stray future-dated or out-of-range rows. A DO loop in `01_partitioning.sql` covers every month in the data plus one month ahead.

## 7. Nigerian regulatory and data-protection notes

* **PenCom (National Pension Commission)** regulates pension records in Nigeria under the Pension Reform Act. Pension data is treated as regulated financial data: PenCom audit trails (who changed a balance, when, why) must be retained and immutable. The schema's contribution ledger, withdrawal claim lifecycle and trigger-based balance maintenance give this audit trail at the row level.
* **NDPA 2023 (Nigeria Data Protection Act 2023)** governs the personal data of RSA holders (name, NIN, BVN, date of birth, salary). Practical implications for this design:
    * **Lawful basis for any cross-border processing** must be recorded before personal data leaves Nigeria; the design therefore prefers an in-country primary. If a managed PostgreSQL region inside Nigeria is not available for the chosen hyperscaler, the residency question must be raised with the DPO and a documented lawful basis (e.g. explicit consent or a recognised adequacy decision) recorded per data category.
    * **Data minimisation** — KYC documents and BVN are stored in MongoDB (`member_documents` collection) under access-controlled buckets; the relational schema stores only the references it needs.
    * **Encryption at rest** and **encryption in transit** (TLS) for both the PostgreSQL and MongoDB tiers, with customer-managed keys.
    * **Access control** — least-privilege roles: `app_write`, `app_read_only`, `analyst_read`, `pencom_audit_read`. No shared credentials; no shared `postgres` superuser for the application.
    * **Right to access / rectification** — handled via the existing `employee` and `rsa_account` tables; deletion is **not** appropriate for pension records because retention is legally mandated.

## 8. Failover runbook (high-level)

1. Managed service detects primary health failure.
2. Automatic promotion of the synchronous standby in the second AZ — typical 30–60 s.
3. Application connection pooler (e.g. PgBouncer) reconnects to the new primary via the managed service's cluster endpoint.
4. Asynchronous read replica re-establishes replication from the new primary.
5. Post-incident: verify `contribution` totals per employer against the most recent monthly snapshot; verify `rsa_account.balance` against the trigger-maintained ledger; raise a PenCom audit entry.

## AI-use note

Drafted by Z.ai GLM-5.2; tested and fixed by Claude; run by the student.

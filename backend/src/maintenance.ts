export async function cleanupExpiredRecords(db: D1Database, now: number): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM deleted_identity_tombstones WHERE expires_at <= ?").bind(now),
    db.prepare("DELETE FROM auth_rate_limits WHERE expires_at <= ?").bind(now),
    db.prepare("DELETE FROM planet_rate_limits WHERE expires_at <= ?").bind(now),
    db
      .prepare(
        `DELETE FROM planet_invites
         WHERE expires_at <= ? AND used_at IS NULL`,
      )
      .bind(now),
    db.prepare("DELETE FROM account_snapshot_mutations WHERE expires_at <= ?").bind(now),
  ]);
}

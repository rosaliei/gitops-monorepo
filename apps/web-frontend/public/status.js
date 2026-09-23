// Pure helpers shared by the browser page and the unit tests.

// Turn the /api/*/info responses into table rows. A failed call becomes a "down" row.
function toRows(results) {
  return results.map(({ name, info, error }) =>
    error || !info
      ? { name, version: '-', commit: '-', status: 'down' }
      : { name, version: info.version, commit: String(info.commit).slice(0, 7), status: 'up' },
  );
}

// Overall badge for the page header.
function overallStatus(rows) {
  if (rows.length === 0) return 'unknown';
  return rows.every((r) => r.status === 'up') ? 'healthy' : 'degraded';
}

if (typeof module !== 'undefined') module.exports = { toRows, overallStatus };

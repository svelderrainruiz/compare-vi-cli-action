export function normalizeSummary(summary) {
  const clone = JSON.parse(JSON.stringify(summary));
  clone.timestamp = 'normalized';
  if (Array.isArray(clone.steps)) {
    clone.steps = clone.steps
      .map((step) => ({
        ...step,
        durationMs: 0,
      }))
      .sort((a, b) => {
        if (a.name < b.name) { return -1; }
        if (a.name > b.name) { return 1; }
        return 0;
      });
  }
  return clone;
}

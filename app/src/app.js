const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || 'unknown';
const COLOR = process.env.COLOR || 'unknown';

// Simulate forced failure for rollback testing
let failMode = false;

app.get('/health', (req, res) => {
  if (failMode) {
    return res.status(503).json({ status: 'unhealthy', version: VERSION, color: COLOR });
  }
  res.json({ status: 'healthy', version: VERSION, color: COLOR });
});

app.get('/version', (req, res) => {
  res.json({ version: VERSION, color: COLOR, uptime: process.uptime() });
});

app.get('/api/hello', (req, res) => {
  if (req.query.fail === '1' || failMode) {
    return res.status(500).json({ error: 'Forced failure for testing', version: VERSION });
  }
  res.json({ message: 'Hello from Blue/Green v2!', version: VERSION, color: COLOR });
});

// Admin: toggle fail mode (used in rollback SLA tests)
app.post('/admin/fail', (req, res) => {
  failMode = req.query.enable !== 'false';
  res.json({ failMode, version: VERSION });
});

app.listen(PORT, () => {
  console.log(`[${COLOR}] v${VERSION} listening on :${PORT}`);
});

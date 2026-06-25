const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.send('<h1>Hello, GCP & DevOps Portfolio!</h1><p>Kubernetes Engine(GKE)에서 작동 중입니다.</p>');
});

app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
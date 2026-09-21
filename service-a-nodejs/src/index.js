// Initialize Elastic APM Node.js Agent (must be required before express/http)
const apm = require('elastic-apm-node').start({
  serviceName: process.env.ELASTIC_APM_SERVICE_NAME || process.env.SERVICE_NAME || 'service-a-nodejs',
  serverUrl: process.env.ELASTIC_APM_SERVER_URL || 'http://apm-server:8200',
  environment: process.env.ELASTIC_APM_ENVIRONMENT || process.env.APP_ENV || 'development',
  active: process.env.ELASTIC_APM_ACTIVE !== 'false',
  captureBody: 'all',
  errorOnAbortedRequests: true
});

const express = require('express');
const os = require('os');
const http = require('http');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'service-a-nodejs';
const APP_ENV = process.env.APP_ENV || 'development';
const API_KEY_SECRET = process.env.API_KEY || 'not-set';
const GOLANG_SERVICE_URL = process.env.GOLANG_SERVICE_URL || 'http://service-b-golang:8080/api/v1/golang/products';

app.use(express.json());

// Main Info Endpoint
app.get('/api/v1/nodejs/info', (req, res) => {
  res.json({
    service: SERVICE_NAME,
    language: 'Node.js',
    framework: 'Express',
    hostname: os.hostname(),
    environment: APP_ENV,
    secretLoaded: API_KEY_SECRET !== 'not-set',
    timestamp: new Date().toISOString()
  });
});

// Inter-Service Communication Endpoint (Node.js -> Golang)
app.get('/api/v1/nodejs/call-golang', (req, res) => {
  http.get(GOLANG_SERVICE_URL, (response) => {
    let data = '';
    response.on('data', (chunk) => { data += chunk; });
    response.on('end', () => {
      try {
        const parsed = JSON.parse(data);
        res.json({
          message: 'Node.js Service successfully called Golang Service via K8s Internal DNS!',
          calledUrl: GOLANG_SERVICE_URL,
          golangResponse: parsed
        });
      } catch (err) {
        res.json({
          message: 'Node.js Service received response from Golang Service',
          rawResponse: data
        });
      }
    });
  }).on('error', (err) => {
    res.status(502).json({
      error: 'Failed to call Golang service',
      details: err.message,
      targetUrl: GOLANG_SERVICE_URL
    });
  });
});

// Liveness Probe Endpoint
app.get('/api/v1/nodejs/healthz', (req, res) => {
  res.status(200).json({ status: 'HEALTHY', timestamp: new Date().toISOString() });
});

// Readiness Probe Endpoint
app.get('/api/v1/nodejs/readyz', (req, res) => {
  res.status(200).json({ status: 'READY' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[${SERVICE_NAME}] Listening on port ${PORT} in ${APP_ENV} mode`);
});

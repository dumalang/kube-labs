import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '10s', target: 20 },
    { duration: '20s', target: 50 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
  },
};

const BASE_URL = __ENV.TARGET_HOST || 'http://host.containers.internal';

export default function () {
  const res1 = http.get(`${BASE_URL}/api/v1/nodejs/info`);
  check(res1, { 'nodejs info status 200': (r) => r.status === 200 });

  const res2 = http.get(`${BASE_URL}/api/v1/golang/products`);
  check(res2, { 'golang products status 200': (r) => r.status === 200 });

  const res3 = http.get(`${BASE_URL}/api/v1/java/users`);
  check(res3, { 'java users status 200': (r) => r.status === 200 });

  const res4 = http.get(`${BASE_URL}/api/v1/nodejs/call-golang`);
  check(res4, { 'interservice node->go status 200': (r) => r.status === 200 });

  sleep(0.2);
}

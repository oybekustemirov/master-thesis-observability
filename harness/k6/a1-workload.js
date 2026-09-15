/*
 * A1 workload generator.
 *
 * One iteration = one complete A1 transaction lifecycle, which is 3 state transitions
 * (INITIATED -> VALIDATED -> PROCESSED) or 2 for the rejected minority. Rates below are
 * expressed in TRANSACTIONS per second, not requests per second; a 200 TPS run therefore
 * issues roughly 600 HTTP requests per second.
 *
 * The workload is identical in every observability mode. That is the whole point: the only
 * thing that varies between runs is the instrumentation being measured.
 */
import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import exec from 'k6/execution';

const BASE      = __ENV.BASE_URL   || 'http://localhost:8095';
const PROFILE   = __ENV.PROFILE    || 'P1';
const RUN_ID    = __ENV.RUN_ID     || 'adhoc';
const REJECT_PCT = Number(__ENV.REJECT_PCT || 4);

// Accounts are drawn from the synthetic reference population. Using a fixed synthetic range
// rather than querying the database keeps the generator stateless and reproducible.
const ACCOUNT_POOL = Number(__ENV.ACCOUNT_POOL || 30000);

export const transitions   = new Counter('a1_transitions_committed');
export const lifecycles    = new Counter('a1_lifecycles_completed');
export const lifecycleTime = new Trend('a1_lifecycle_duration', true);

/*
 * Workload profiles.
 *   P1 steady  — baseline overhead at a sustainable rate
 *   P2 peak    — ramp to saturation, finds the throughput ceiling per mode
 *   P3 burst   — 50 -> 800 -> 50, exercises backlog build-up and recovery (RTE)
 *   P5 idle    — 1 TPS for a long period; exposes the Debezium offset-stall failure
 * P4 (a single large batch transaction) is not an HTTP workload at all: it is generated
 * in-database by PKG_SYNTH_DATA, which is precisely what makes it invisible to the wrapper.
 */
const PROFILES = {
  P1: { executor: 'constant-arrival-rate', rate: Number(__ENV.TPS || 200), timeUnit: '1s',
        duration: __ENV.DURATION || '5m', preAllocatedVUs: 100, maxVUs: 600 },
  P2: { executor: 'ramping-arrival-rate', timeUnit: '1s', preAllocatedVUs: 200, maxVUs: 1500,
        startRate: 50,
        stages: [ { target: 200, duration: '2m' }, { target: 500, duration: '2m' },
                  { target: 900, duration: '2m' }, { target: 1400, duration: '2m' } ] },
  P3: { executor: 'ramping-arrival-rate', timeUnit: '1s', preAllocatedVUs: 200, maxVUs: 1200,
        startRate: 50,
        stages: [ { target: 50, duration: '3m' }, { target: 800, duration: '30s' },
                  { target: 800, duration: '2m' }, { target: 50, duration: '30s' },
                  { target: 50, duration: '4m' } ] },
  P5: { executor: 'constant-arrival-rate', rate: 1, timeUnit: '1s',
        duration: __ENV.DURATION || '4h', preAllocatedVUs: 5, maxVUs: 20 },
};

export const options = {
  scenarios: { a1: PROFILES[PROFILE] },
  // Thresholds are diagnostics, not pass/fail gates: a mode that saturates is a RESULT,
  // not a broken run, and aborting on it would discard the data point.
  thresholds: { http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: false }] },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

function account(n) {
  return '20208860' + String(n % 10000).padStart(4, '0') + String(n).padStart(8, '0');
}

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

export default function () {
  const seq = exec.scenario.iterationInTest;
  const ref = `${RUN_ID}-${seq}`;
  const debit  = account(seq % ACCOUNT_POOL);
  const credit = account((seq * 7919 + 13) % ACCOUNT_POOL);   // coprime stride: no self-pairs
  const start = Date.now();

  const created = http.post(`${BASE}/api/a1`, JSON.stringify({
    txnRef: ref, debitAccount: debit, creditAccount: credit,
    amount: (1000 + (seq % 500000)) + 0.5, currency: 'UZS',
    channel: ['MOBILE', 'WEB', 'ATM', 'BRANCH', 'API'][seq % 5],
  }), JSON_HEADERS);

  if (!check(created, { 'initiated': r => r.status === 201 })) return;
  transitions.add(1);

  const validated = http.post(`${BASE}/api/a1/${ref}/validate`, null, JSON_HEADERS);
  if (!check(validated, { 'validated': r => r.status === 200 })) return;
  transitions.add(1);

  const reject = (seq % 100) < REJECT_PCT;
  const final = reject
    ? http.post(`${BASE}/api/a1/${ref}/reject?reasonCode=AM04`, null, JSON_HEADERS)
    : http.post(`${BASE}/api/a1/${ref}/process`, null, JSON_HEADERS);

  if (!check(final, { 'terminal': r => r.status === 200 })) return;
  transitions.add(1);

  lifecycles.add(1);
  lifecycleTime.add(Date.now() - start);
}

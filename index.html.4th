<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Blowoff Top Detector — Full Auto (Countdown, Highlight, Auto-Pause)</title>
<style>
  :root{--bg:#07101a;--card:#0b1220;--muted:#9fb3cc;--accent:#2dd4bf;--danger:#ff7b7b}
  body{font-family:Inter,system-ui,Segoe UI,Roboto,Helvetica,Arial; background:var(--bg); color:#e6eef8; margin:16px}
  .card{background:var(--card); border:1px solid #172033; padding:14px; border-radius:10px; box-shadow:0 6px 20px rgba(0,0,0,.6)}
  h1{margin:0;font-size:18px}
  .controls{display:flex;flex-wrap:wrap;gap:10px;margin-top:12px;align-items:center}
  label{font-size:13px;color:var(--muted)}
  input,select{background:#071722;border:1px solid #243241;color:#e6eef8;padding:6px;border-radius:6px}
  button{background:#1f6feb;border:none;color:white;padding:8px 10px;border-radius:6px;cursor:pointer}
  button.alt{background:#2b3947}
  .status{margin-top:8px;color:var(--muted);font-size:13px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
  .progress{height:8px;background:#05101a;border-radius:4px;margin-top:8px;overflow:hidden;flex:1}
  .progress > i{display:block;height:100%;background:linear-gradient(90deg,var(--accent),#60a5fa);width:0%}
  .countdown{font-weight:700;color:#cfe8ff}
  table{width:100%;border-collapse:collapse;margin-top:12px;font-size:13px}
  th,td{padding:8px 10px;border-bottom:1px dashed #122331;text-align:left}
  th{color:var(--muted);font-size:12px}
  .green{color:#66f9a1}
  .red{color:var(--danger)}
  .small{font-size:12px;color:var(--muted)}
  .badge{display:inline-block;padding:4px 8px;border-radius:12px;background:#0f2430;color:#bfeee1;font-size:12px}
  pre{background:#041223;padding:8px;border-radius:6px;overflow:auto;color:#cfe8ff}
  footer{margin-top:12px;color:var(--muted);font-size:12px}
  a.button-like{display:inline-block;padding:6px 10px;background:#123b5a;border-radius:6px;color:#dff3ff;text-decoration:none;margin-top:8px}
  /* blink highlight for new blowoff entries */
  @keyframes blinkHighlight {
    0% { box-shadow: 0 0 0px rgba(255,80,80,0.0); }
    50% { box-shadow: 0 0 12px rgba(255,80,80,0.35); }
    100% { box-shadow: 0 0 0px rgba(255,80,80,0.0); }
  }
  .blink {
    animation: blinkHighlight 1.8s ease-in-out 3;
  }
  .mutedBadge { background: rgba(255,255,255,0.03); color:var(--muted); padding:4px 8px; border-radius:8px; font-size:12px; }
  .warning{color:#ffd966;font-weight:700}
</style>
</head>
<body>
<div class="card">
  <h1>Blowoff Top Detector — Full Auto</h1>
  <div class="small" style="margin-top:6px;color:var(--muted)">Auto scans top N futures by 24h change, evaluates blow-off top signals (RSI, wick, volume, funding, EMAs). Blacklist + safety enabled.</div>

  <div class="controls">
    <label>Prefilter (top by 24h) <input id="prefilter" type="number" value="30" min="5" max="100"/></label>
    <label>Delay (ms) <input id="delay" type="number" value="450" min="50" max="2000"/></label>
    <label>Auto update (sec) <input id="interval" type="number" value="60" min="10" max="3600"/></label>
    <label>Score threshold <input id="threshold" type="number" value="4" min="1" max="6"/></label>
    <button id="startBtn">Start</button>
    <button id="stopBtn" class="alt" disabled>Stop</button>
    <button id="oneShot" class="alt">Run Once</button>
  </div>

  <div class="status">
    <div id="message">Ready. Run from local server to avoid CORS (e.g. python -m http.server).</div>
    <div class="progress"><i id="bar"></i></div>
    <div class="countdown" id="countdown">Next scan in: -</div>
    <div id="safetyStatus" class="mutedBadge">Safety OK</div>
  </div>

  <div id="tableArea"></div>
  <div id="debug" style="margin-top:10px;color:var(--muted);font-size:12px"></div>
  <div id="downloadArea"></div>
</div>

<footer class="small">
  Notes: Auto-pause safety will pause scanning if request usage approaches threshold, then resume automatically after cooldown. Adjust delay/prefilter for speed vs safety.
</footer>

<script>
/* Full auto detector with countdown, highlight, and auto-pause safety */

const API_BASE = 'https://fapi.binance.com';

// ---------- USER BLACKLIST ----------
const blacklist = [
  "ALPACAUSDT","BNXUSDT","ALPHAUSDT","OCEANUSDT","DGBUSDT",
  "AGIXUSDT","LINAUSDT","LOKAUSDT","KEYUSDT","MDTUSDT",
  "LOOMUSDT","RENUSDT","OMNIUSDT","SLERFUSDT","STMXUSDT",
  "UXLINKUSDT","BSWUSDT","NEIROETHUSDT","VIDTUSDT","TROYUSDT",
  "BAKEUSDT","AMBUSDT","MEMEFIUSDT","NULSUSDT","HIFIUSDT",
  "LEVERUSDT","XEMUSDT","STRAXUSDT","COMBOUSDT"
];
// ------------------------------------

const el = {
  prefilter: document.getElementById('prefilter'),
  delay: document.getElementById('delay'),
  interval: document.getElementById('interval'),
  threshold: document.getElementById('threshold'),
  startBtn: document.getElementById('startBtn'),
  stopBtn: document.getElementById('stopBtn'),
  oneShot: document.getElementById('oneShot'),
  message: document.getElementById('message'),
  bar: document.getElementById('bar'),
  tableArea: document.getElementById('tableArea'),
  debug: document.getElementById('debug'),
  downloadArea: document.getElementById('downloadArea'),
  countdown: document.getElementById('countdown'),
  safetyStatus: document.getElementById('safetyStatus')
};

let running = false;
let queue = [];
let totalTasks = 0, doneTasks = 0;
let autoTimer = null;
let countdownTimer = null;

// Auto-pause safety tracker
let requestsThisWindow = 0;
let windowStart = Date.now();
const SAFETY_WINDOW_MS = 60_000; // 60s window
const SAFETY_MAX_REQUESTS = 900; // safe ceiling (conservative)
const SAFETY_PAUSE_SECONDS = 30; // pause length when triggered

// store previous blowoff symbols to highlight newly flagged ones
let prevBlowoffSet = new Set();

// small safe fetch wrapper
async function safeFetch(url){
  // If safety paused, throw early (shouldn't happen)
  if(!running) throw new Error('Not running');
  // increment usage
  requestsThisWindow++;
  return fetch(url).then(r=>{
    if(!r.ok) throw new Error('HTTP '+r.status+' '+r.statusText);
    return r.json();
  });
}

// utilities
function sma(values, n){
  if(!values || values.length < n) return null;
  let sum = 0;
  for(let i=values.length-n;i<values.length;i++) sum += values[i];
  return sum/n;
}
function ema(values, period){
  if(!values || values.length === 0) return null;
  const k = 2/(period+1);
  let emaVal = values[0];
  for(let i=1;i<values.length;i++){
    emaVal = values[i]*k + emaVal*(1-k);
  }
  return emaVal;
}
function rsiFromCloses(closes, period=14){
  if(!closes || closes.length <= period) return null;
  let gains=0, losses=0;
  for(let i=closes.length-period;i<closes.length;i++){
    const diff = closes[i] - closes[i-1];
    if(diff>0) gains += diff; else losses += Math.abs(diff);
  }
  const avgGain = gains/period;
  const avgLoss = losses/period;
  if(avgLoss===0) return 100;
  const rs = avgGain/avgLoss;
  return 100 - (100/(1+rs));
}
function pct(a,b){ if(b===0) return 0; return ((a-b)/b)*100; }

// progress and safety helpers
function resetRequestWindow(){
  requestsThisWindow = 0;
  windowStart = Date.now();
}
function checkSafetyAndMaybePause(){
  const now = Date.now();
  if(now - windowStart > SAFETY_WINDOW_MS){
    // window expired -> reset
    resetRequestWindow();
    el.safetyStatus.innerText = 'Safety OK';
    return false;
  }
  // If usage too high, auto-pause
  if(requestsThisWindow > SAFETY_MAX_REQUESTS){
    // pause scanning
    running = false;
    el.safetyStatus.innerText = `Auto-paused: high requests (${requestsThisWindow} in last minute)`;
    el.message.innerText = `Auto-paused for ${SAFETY_PAUSE_SECONDS}s to avoid rate limit.`;
    el.startBtn.disabled = false;
    el.stopBtn.disabled = true;
    // schedule resume
    setTimeout(()=>{
      el.safetyStatus.innerText = 'Resuming after pause';
      // increase delay slightly to be safer
      const currentDelay = Math.max(200, parseInt(el.delay.value,10) || 400);
      const newDelay = Math.min(2000, Math.round(currentDelay * 1.5));
      el.delay.value = newDelay;
      el.message.innerText = `Resumed. Delay increased to ${newDelay}ms for safety.`;
      // reset window tracking and restart
      resetRequestWindow();
      // restart auto-run if start was previously pressed
      if(!autoTimer){
        // user must press start again to resume repeated scans; to auto-resume, uncomment next line:
        // startAutoScan();
      }
    }, SAFETY_PAUSE_SECONDS*1000);
    return true;
  }
  // below threshold
  el.safetyStatus.innerText = `Requests/min: ${requestsThisWindow}`;
  return false;
}

// Queue processor (rate-limited)
async function processQueue(delay){
  while(queue.length && running){
    // safety quick check per loop
    if(checkSafetyAndMaybePause()) break;
    const job = queue.shift();
    try{ await job(); } catch(e){ console.warn('job error', e); el.debug.innerText += `\nJob error: ${e.message}`; }
    doneTasks++;
    updateProgress();
    await new Promise(r=>setTimeout(r, delay));
  }
  // finished or paused
  running=false;
  el.startBtn.disabled=false; el.stopBtn.disabled=true;
  if(doneTasks >= totalTasks) el.message.innerText = 'Scan complete.';
}

// Build candidate list (top N by 24h change) excluding blacklist
async function getTop24N(n){
  const tickers = await safeFetch(API_BASE + '/fapi/v1/ticker/24hr');
  const usdt = tickers.filter(t => t.symbol.endsWith('USDT') && !blacklist.includes(t.symbol));
  usdt.sort((a,b)=> parseFloat(b.priceChangePercent) - parseFloat(a.priceChangePercent));
  return usdt.slice(0,n).map(x=>({symbol:x.symbol,priceChangePercent:parseFloat(x.priceChangePercent),lastPrice:parseFloat(x.lastPrice)}));
}

// For a symbol compute signals (queued)
function queueSymbolAnalysis(symbol, results){
  queue.push(async ()=>{
    try{
      const [k1d, k4h, k15m, fundingArr] = await Promise.all([
        safeFetch(`${API_BASE}/fapi/v1/klines?symbol=${symbol}&interval=1d&limit=9`),
        safeFetch(`${API_BASE}/fapi/v1/klines?symbol=${symbol}&interval=4h&limit=20`),
        safeFetch(`${API_BASE}/fapi/v1/klines?symbol=${symbol}&interval=15m&limit=40`),
        safeFetch(`${API_BASE}/fapi/v1/fundingRate?symbol=${symbol}&limit=1`)
      ]);

      const closes1d = k1d.map(k=>parseFloat(k[4]));
      const closes4h = k4h.map(k=>parseFloat(k[4]));
      const vols4h = k4h.map(k=>parseFloat(k[5]));
      const last4h = k4h[k4h.length-1];
      const prev4h = k4h[k4h.length-2];
      const fundingRate = (fundingArr && fundingArr.length)? parseFloat(fundingArr[0].fundingRate) : 0;

      const rsi1d = rsiFromCloses(closes1d, 14);
      const rsi4h = rsiFromCloses(closes4h, 14);
      const volMA4h = sma(vols4h, Math.min(10, vols4h.length));
      const volSpike = volMA4h ? (parseFloat(last4h[5]) / volMA4h) : 1;

      // Wick/top ratio
      const open4 = parseFloat(last4h[1]), high4 = parseFloat(last4h[2]);
      const low4 = parseFloat(last4h[3]), close4 = parseFloat(last4h[4]);
      const body = Math.abs(close4 - open4) || 0.0000001;
      const wickTop = high4 - Math.max(open4, close4);
      const wickTopRatio = wickTop / body;

      // EMA distance
      const ema14 = ema(closes4h.slice(Math.max(0, closes4h.length-14)), 14);
      const ema70 = ema(closes4h.slice(Math.max(0, closes4h.length-70)), 70);
      const closeNow = closes4h[closes4h.length-1];
      const ema70DistPct = ema70 ? pct(closeNow, ema70) : 0;

      // lower high detection
      const prevHigh = parseFloat(prev4h[2]);
      const lastHigh = high4;
      const lowerHigh = lastHigh < prevHigh;

      // slope proxy: closeNow / close 3 bars ago
      const ratioSlope = closes4h.length>3 ? closeNow / closes4h[closes4h.length-4] : 1;

      // Score rules (tuned thresholds)
let score = 0;
const signals = {};
if (rsi1d !== null && rsi1d >= 88) { score++; signals.rsi1d = true; } // stricter 1D
else signals.rsi1d = false;

if (rsi4h !== null && rsi4h >= 80) { score++; signals.rsi4h = true; }
else signals.rsi4h = false;

if (volSpike >= 1.8) { score++; signals.volSpike = true; } // easier to trigger than 2.0
else signals.volSpike = false;

if (wickTopRatio >= 1.2) { score++; signals.wickTop = true; } // more sensitive wick detection
else signals.wickTop = false;

if (ema70DistPct >= 50) { score++; signals.emaDist = true; } // price 50% above EMA70 (tunable)
else signals.emaDist = false;

if (lowerHigh) { score++; signals.lowerHigh = true; }
else signals.lowerHigh = false;

// Extra: treat meaningful negative funding as confirmation
// fundingRate is decimal (e.g. -0.0005 = -0.05%)
if (typeof fundingRate === 'number' && fundingRate < -0.0005) {
  score++;
  signals.fundingConfirm = true;
} else {
  signals.fundingConfirm = false;
}

signals.funding = fundingRate;

      results.push({
        symbol,
        rsi1d, rsi4h,
        volSpike: Number(volSpike.toFixed(2)),
        wickTopRatio: Number(wickTopRatio.toFixed(2)),
        ema70DistPct: Number(ema70DistPct.toFixed(2)),
        lowerHigh,
        fundingRate,
        score,
        closeNow,
        ratioSlope: Number(ratioSlope.toFixed(2))
      });
    } catch(err){
      el.debug.innerText += `\nError for ${symbol}: ${err.message}`;
    }
  });
}

// ---- PLAY SOUND ----
function playAlertSound() {
  try {
    const audio = new Audio("https://actions.google.com/sounds/v1/alarms/beep_short.ogg");
    audio.volume = 0.7;
    audio.play().catch(()=>{});
  } catch(e){
    console.warn('sound err', e);
  }
}

// ---- NOTIFICATION ----
function sendNotification(title, body) {
  if (Notification.permission === "granted") {
    new Notification(title, { body });
  } else if (Notification.permission !== "denied") {
    Notification.requestPermission().then(permission => {
      if (permission === "granted") new Notification(title, { body });
    });
  }
}

// Render results with colors, badges, alerts, and highlight new blowoffs
function renderResults(results){
  results.sort((a,b)=> (b.score - a.score) || (b.ema70DistPct - a.ema70DistPct) || (b.volSpike - a.volSpike));
  const threshold = parseInt(el.threshold.value,10) || 3;

  // find blowoff symbols in this scan
  const currentBlowoff = new Set(results.filter(r=>r.score>=4).map(r=>r.symbol));
  let blowoffDetected = currentBlowoff.size > 0;

  // compute newly-flagged (present now, not present previously)
  const newlyFlagged = [...currentBlowoff].filter(s => !prevBlowoffSet.has(s));

  // store for next render
  prevBlowoffSet = currentBlowoff;

  const rows = results.map(r=>{
    let statusUI = "";
    let rowColor = "";
    let extraClass = "";

    if(r.score >= 4){
      statusUI = `<span style="background:#ff4d4d;padding:4px 8px;border-radius:6px;font-size:11px;font-weight:bold;">🔥 BLOWOFF TOP</span>`;
      rowColor = "background:rgba(255,50,50,0.18);";
      if(newlyFlagged.includes(r.symbol)) extraClass = "blink";
    }
    else if(r.score === 3){
      statusUI = `<span style="background:#e6b800;padding:4px 8px;border-radius:6px;font-size:11px;font-weight:bold;color:black;">⚠️ POTENTIAL</span>`;
      rowColor = "background:rgba(255,200,0,0.14);";
    }
    else {
      statusUI = `<span style="color:#7f8c9b;font-size:11px;">normal</span>`;
      rowColor = "background:rgba(255,255,255,0.02);";
    }

    return `
      <tr class="${extraClass}" style="${rowColor}">
        <td><strong>${r.symbol}</strong><br>${statusUI}</td>
        <td>${r.closeNow}</td>
        <td class="${r.rsi4h>=80?'green':''}">${r.rsi4h? r.rsi4h.toFixed(1):'n/a'}</td>
        <td class="small">vol:${r.volSpike} wick:${r.wickTopRatio} ema:${r.ema70DistPct}%</td>
        <td class="small">fund:${r.fundingRate}</td>
      </tr>`;
  }).join('');

  // Alerts
  if(blowoffDetected){
    playAlertSound();
    sendNotification("🔥 Blowoff Top Detected!", "One or more coins hit blowoff-top conditions. Check the scanner.");
  }

  el.tableArea.innerHTML = `
    <div class="card">
      <table>
        <thead>
          <tr>
            <th>Symbol<br>Status</th>
            <th>Last</th>
            <th>RSI 4H</th>
            <th class="small">Signals</th>
            <th class="small">Funding</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;

  // apply blink removal after a short delay so it only highlights briefly
  setTimeout(()=>{
    const nodes = document.querySelectorAll('tr.blink');
    nodes.forEach(n => n.classList.remove('blink'));
  }, 6000);

  // downloadable JSON of results
  try {
    const topJson = JSON.stringify(results, null, 2);
    const blob = new Blob([topJson], {type:'application/json'});
    const url = URL.createObjectURL(blob);
    el.downloadArea.innerHTML = `<a class="button-like" href="${url}" download="blowoff_results.json">Download results (JSON)</a>`;
  } catch(e){
    el.debug.innerText += `\nDownload prepare error: ${e.message}`;
  }
}

// Update progress
function updateProgress(){
  const pctDone = totalTasks ? Math.round((doneTasks/totalTasks)*100) : 0;
  el.bar.style.width = pctDone + '%';
  el.message.innerText = `Scanning ${doneTasks}/${totalTasks} (${pctDone}%) — delay ${el.delay.value}ms — threshold ${el.threshold.value}`;
  el.safetyStatus.innerText = `Requests/min: ${requestsThisWindow}`;
}

// Countdown logic
let nextScanAt = null;
function startCountdownInterval(intervalSec){
  if(countdownTimer) clearInterval(countdownTimer);
  nextScanAt = Date.now() + intervalSec*1000;
  el.countdown.innerText = `Next scan in: ${intervalSec}s`;
  countdownTimer = setInterval(()=>{
    const left = Math.max(0, Math.round((nextScanAt - Date.now())/1000));
    el.countdown.innerText = `Next scan in: ${left}s`;
    if(left <= 0) {
      el.countdown.innerText = 'Next scan: running...';
      clearInterval(countdownTimer);
      countdownTimer = null;
    }
  }, 500);
}

// Main run
async function runScan(once=false){
  try{
    el.debug.innerText = '';
    el.startBtn.disabled=true;
    el.stopBtn.disabled=false;
    running = true;
    resetRequestWindow(); // reset counters per-run
    const prefilter = Math.max(5, Math.min(100, parseInt(el.prefilter.value,10) || 30));
    const delayMs = Math.max(50, Math.min(2000, parseInt(el.delay.value,10) || 450));
    const intervalSec = Math.max(10, Math.min(3600, parseInt(el.interval.value,10) || 60));

    el.message.innerText = 'Fetching top symbols by 24h change (blacklist applied)...';
    const top = await getTop24N(prefilter);
    const symbols = top.map(t=>t.symbol);

    queue = [];
    totalTasks = symbols.length;
    doneTasks = 0;
    updateProgress();
    const results = [];

    for(const s of symbols) queueSymbolAnalysis(s, results);

    // safety quick-check before starting heavy processing: if requestsThisWindow already high, pause
    if(checkSafetyAndMaybePause()) return;

    // mark next scan time and start countdown
    if(!once) startCountdownInterval(intervalSec);

    processQueue(delayMs).then(()=>{
      renderResults(results);
      // schedule next run if not once and not auto-paused
      if(!once){
        // only schedule next run if running wasn't auto-paused by safety
        if(running === false && requestsThisWindow > SAFETY_MAX_REQUESTS){
          // auto-pause handled elsewhere; do not schedule immediate run
          el.debug.innerText += '\nAuto-paused due to safety.';
          return;
        }
        // schedule next run
        if(autoTimer) clearInterval(autoTimer);
        autoTimer = setInterval(()=>{ if(!running) runScan(false); }, intervalSec*1000);
      }
    });
  } catch(e){
    el.debug.innerText += '\nError run: ' + e.message;
  }
}

// UI events
el.startBtn.addEventListener('click', ()=>{
  if(running) return;
  // clear previous tracked set so new highlights detect fresh flags
  prevBlowoffSet = new Set();
  runScan(false);
});
el.stopBtn.addEventListener('click', ()=>{
  running=false;
  queue = [];
  el.startBtn.disabled=false;
  el.stopBtn.disabled=true;
  if(autoTimer) { clearInterval(autoTimer); autoTimer=null; }
  if(countdownTimer) { clearInterval(countdownTimer); countdownTimer=null; el.countdown.innerText = 'Next scan in: -'; }
  el.message.innerText = 'Stopped.';
});
el.oneShot.addEventListener('click', ()=>{ if(!running) runScan(true); });

// helper: fetch top N by 24h (with blacklist)
async function getTop24N(n){
  const tickers = await safeFetch(API_BASE + '/fapi/v1/ticker/24hr');
  const usdt = tickers.filter(t => t.symbol.endsWith('USDT') && !blacklist.includes(t.symbol));
  usdt.sort((a,b)=> parseFloat(b.priceChangePercent) - parseFloat(a.priceChangePercent));
  return usdt.slice(0,n).map(x=>({symbol:x.symbol,priceChangePercent:parseFloat(x.priceChangePercent),lastPrice:parseFloat(x.lastPrice)}));
}

// quick ping to detect CORS in console
(async function ping(){
  try { await fetch(API_BASE + '/fapi/v1/ping'); } catch(e){ console.warn('ping failed (CORS?)', e); }
})();

// request notification permission on load
if ("Notification" in window) {
  try { Notification.requestPermission(); } catch(e){ console.warn('notif req err', e); }
}

</script>
</body>
</html>

import Foundation
import Network

/// A minimal HTTP server on localhost:3737 serving the MacSynergy dashboard.
///
/// Routes:
///   GET /          → HTML dashboard page
///   GET /api/stats → JSON stats (polled every 3 s by the page)
///   GET /api/status → live status (engine, model, ollamaState)
class DashboardServer {
    nonisolated static let port: UInt16 = 3737
    private var listener: NWListener?

    // Injected from ViewModel — called on main actor, closures are safe to call from any thread
    var statsProvider: (() -> [String: Any])?
    var statusProvider: (() -> [String: Any])?

    // MARK: - Start / Stop

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.stateUpdateHandler = { state in
                if case .ready = state {
                    print("[Dashboard] Listening on http://localhost:\(DashboardServer.port)")
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                DispatchQueue.main.async { self?.handle(conn) }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            print("[Dashboard] Failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handler

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty,
                  let request = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let path = self.parsePath(from: request)
            self.respond(to: conn, path: path)
        }
    }

    private func parsePath(from request: String) -> String {
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.components(separatedBy: " ")
        return parts.count >= 2 ? parts[1] : "/"
    }

    private func respond(to conn: NWConnection, path: String) {
        let (body, contentType): (String, String)
        switch path {
        case "/api/stats":
            let stats = statsProvider?() ?? [:]
            body = jsonString(from: stats)
            contentType = "application/json"
        case "/api/status":
            let status = statusProvider?() ?? [:]
            body = jsonString(from: status)
            contentType = "application/json"
        default:
            body = htmlDashboard()
            contentType = "text/html; charset=utf-8"
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let responseData = Data(response.utf8)
        conn.send(content: responseData, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func jsonString(from dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) { return str }
        return "{}"
    }

    // MARK: - HTML

    private func htmlDashboard() -> String {
        """
        <!DOCTYPE html>
        <html lang="ko">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>MacSynergy Dashboard</title>
        <style>
          :root{--bg:#0f1117;--card:#1a1d27;--border:#2a2d3a;--accent:#7c3aed;--green:#22c55e;--yellow:#eab308;--red:#ef4444;--text:#e2e8f0;--muted:#64748b}
          *{box-sizing:border-box;margin:0;padding:0}
          body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh;padding:24px}
          h1{font-size:1.5rem;font-weight:700;display:flex;align-items:center;gap:10px;margin-bottom:8px}
          .subtitle{color:var(--muted);font-size:.85rem;margin-bottom:28px}
          .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:16px;margin-bottom:24px}
          .card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:20px}
          .card .label{font-size:.75rem;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px}
          .card .value{font-size:1.8rem;font-weight:700}
          .card .sub{font-size:.8rem;color:var(--muted);margin-top:4px}
          .badge{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;font-size:.78rem;font-weight:600}
          .badge.green{background:#16a34a22;color:var(--green)}
          .badge.yellow{background:#ca8a0422;color:var(--yellow)}
          .badge.red{background:#dc262622;color:var(--red)}
          .badge.purple{background:#7c3aed22;color:#a78bfa}
          .dot{width:7px;height:7px;border-radius:50%;display:inline-block}
          .dot.green{background:var(--green);box-shadow:0 0 6px var(--green)}
          .dot.yellow{background:var(--yellow)}
          .dot.red{background:var(--red)}
          .section-title{font-size:.9rem;font-weight:600;color:var(--muted);margin-bottom:12px;text-transform:uppercase;letter-spacing:.06em}
          table{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden;border:1px solid var(--border)}
          th{text-align:left;padding:10px 14px;font-size:.75rem;color:var(--muted);border-bottom:1px solid var(--border);text-transform:uppercase;letter-spacing:.05em}
          td{padding:10px 14px;font-size:.83rem;border-bottom:1px solid var(--border)22}
          tr:last-child td{border-bottom:none}
          .engine-local{color:#60a5fa}
          .engine-cloud{color:#a78bfa}
          #status-bar{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:14px 20px;margin-bottom:24px;display:flex;gap:24px;align-items:center;flex-wrap:wrap}
          .status-item{display:flex;flex-direction:column;gap:3px}
          .status-item .label{font-size:.7rem;color:var(--muted);text-transform:uppercase;letter-spacing:.05em}
          .status-item .val{font-size:.9rem;font-weight:600}
          .refresh-hint{margin-left:auto;font-size:.75rem;color:var(--muted)}
          .live{display:inline-flex;align-items:center;gap:5px;font-size:.72rem;color:var(--green)}
          .live-dot{width:6px;height:6px;border-radius:50%;background:var(--green);animation:pulse 1.5s infinite}
          @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
        </style>
        </head>
        <body>
        <h1>✦ MacSynergy <span style="color:var(--accent)">Dashboard</span>
          <span class="live"><span class="live-dot"></span>LIVE</span>
        </h1>
        <p class="subtitle">Real-time monitoring · Auto-refreshes every 3 seconds</p>

        <div id="status-bar">
          <div class="status-item"><span class="label">Engine Mode</span><span class="val" id="s-mode">—</span></div>
          <div class="status-item"><span class="label">Active Engine</span><span class="val" id="s-engine">—</span></div>
          <div class="status-item"><span class="label">Local Model</span><span class="val" id="s-local-model">—</span></div>
          <div class="status-item"><span class="label">Cloud Model</span><span class="val" id="s-cloud-model">—</span></div>
          <div class="status-item"><span class="label">Ollama</span><span class="val" id="s-ollama">—</span></div>
          <div class="status-item"><span class="label">API Key</span><span class="val" id="s-apikey">—</span></div>
          <div class="status-item"><span class="label">Generating</span><span class="val" id="s-gen">—</span></div>
          <span class="refresh-hint" id="last-updated">—</span>
        </div>

        <div class="grid">
          <div class="card"><div class="label">Requests Today</div><div class="value" id="stat-today">—</div><div class="sub">All engines</div></div>
          <div class="card"><div class="label">Local Requests</div><div class="value engine-local" id="stat-local">—</div><div class="sub">Ollama</div></div>
          <div class="card"><div class="label">Cloud Requests</div><div class="value engine-cloud" id="stat-cloud">—</div><div class="sub">Gemini</div></div>
          <div class="card"><div class="label">Avg Response</div><div class="value" id="stat-avg">—</div><div class="sub">seconds</div></div>
          <div class="card"><div class="label">Tokens Today</div><div class="value" id="stat-tokens">—</div><div class="sub">Approximate</div></div>
          <div class="card"><div class="label">Sessions</div><div class="value" id="stat-sessions">—</div><div class="sub">Since launch</div></div>
        </div>

        <p class="section-title">Recent Requests</p>
        <table>
          <thead><tr><th>Time</th><th>Engine</th><th>Action</th><th>Duration</th><th>Tokens</th></tr></thead>
          <tbody id="recent-tbody"><tr><td colspan="5" style="color:var(--muted);text-align:center;padding:20px">Loading…</td></tr></tbody>
        </table>

        <script>
        const $=id=>document.getElementById(id);
        function fmtTime(iso){const d=new Date(iso);return d.toLocaleTimeString('ko-KR',{hour:'2-digit',minute:'2-digit',second:'2-digit'});}
        function engineBadge(e){return e==='cloud'?'<span class="badge purple">☁ Cloud</span>':'<span class="badge" style="background:#1e3a5f33;color:#60a5fa">⬡ Local</span>';}
        async function fetchStats(){
          try{
            const [stats,status]=await Promise.all([fetch('/api/stats').then(r=>r.json()),fetch('/api/status').then(r=>r.json())]);
            $('s-mode').textContent=status.engineMode||'—';
            $('s-engine').textContent=status.activeEngine||'—';
            $('s-local-model').textContent=status.localModel||'—';
            $('s-cloud-model').textContent=status.cloudModel||'—';
            const os=status.ollamaState||'Unknown';
            const oc=os==='Loaded'?'green':os==='Unloaded'?'yellow':'muted';
            $('s-ollama').innerHTML=`<span class="badge ${oc}"><span class="dot ${oc}"></span>${os}</span>`;
            $('s-apikey').innerHTML=status.apiKeySet?'<span class="badge green"><span class="dot green"></span>Configured</span>':'<span class="badge red">Not Set</span>';
            $('s-gen').innerHTML=status.isGenerating?'<span class="badge green"><span class="dot green"></span>Active</span>':'<span style="color:var(--muted)">Idle</span>';
            $('stat-today').textContent=stats.todayRequests??'—';
            $('stat-local').textContent=stats.localRequests??'—';
            $('stat-cloud').textContent=stats.cloudRequests??'—';
            $('stat-avg').textContent=(stats.avgDurationSec??'—')+'s';
            const tok=stats.totalTokensToday;$('stat-tokens').textContent=tok!=null?tok.toLocaleString('ko-KR'):'—';
            $('stat-sessions').textContent=stats.sessionsCreated??'—';
            const rows=stats.recentRequests||[];
            $('recent-tbody').innerHTML=rows.length===0?'<tr><td colspan="5" style="color:var(--muted);text-align:center;padding:20px">No requests yet</td></tr>':rows.map(r=>`<tr><td>${fmtTime(r.time)}</td><td>${engineBadge(r.engine)}</td><td>${r.action}</td><td>${r.duration}s</td><td>${r.tokens}</td></tr>`).join('');
            $('last-updated').textContent='Updated '+new Date().toLocaleTimeString();
          }catch(e){$('last-updated').textContent='⚠ MacSynergy not running';}
        }
        fetchStats();setInterval(fetchStats,3000);
        </script>
        </body>
        </html>
        """
    }
}

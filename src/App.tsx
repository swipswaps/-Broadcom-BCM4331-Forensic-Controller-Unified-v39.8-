import { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Wifi, 
  WifiOff, 
  Activity, 
  ShieldCheck, 
  Zap, 
  History, 
  Terminal,
  AlertTriangle,
  RefreshCw,
  Sliders,
  Database,
  Search,
  Cpu,
  Lock,
  Unlock,
  ChevronRight
} from 'lucide-react';

interface Telemetry {
  signal: number;
  health: number;
  healthPing: number;
  healthDns: number;
  healthRoute: number;
  connectivity: boolean;
  bkwInterface: string;
  isFixing: boolean;
  rx: number;
  tx: number;
  pidKp: number;
  pidKi: number;
  pidKd: number;
  pidOut: number;
  pidIError: number;
  pidPrevError: number;
  gitUpdateAvailable: boolean;
  lastTick: string;
}

interface ForensicEvent {
  timestamp: string;
  type: string;
  label: string;
  message: string;
  details: string;
}

interface Forensics {
  events: ForensicEvent[];
  dbSnapshots: any[];
  logTail: string[];
}

export default function App() {
  const [telemetry, setTelemetry] = useState<Telemetry | null>(null);
  const [forensics, setForensics] = useState<Forensics | null>(null);
  const [activeTab, setActiveTab] = useState<'telemetry' | 'forensics' | 'evidence' | 'tuning'>('telemetry');
  const [pidParams, setPidParams] = useState({ kp: 100, ki: 10, kd: 5 });
  const logEndRef = useRef<HTMLDivElement>(null);

  const fetchData = useCallback(async () => {
    try {
      const [statusRes, forensicRes] = await Promise.all([
        fetch('/api/status'),
        fetch('/api/forensics')
      ]);
      if (statusRes.ok) {
        const data = await statusRes.json();
        setTelemetry(data);
        // Sync PID sliders with server state if not currently being edited
        // setPidParams({ kp: data.pidKp, ki: data.pidKi, kd: data.pidKd });
      }
      if (forensicRes.ok) setForensics(await forensicRes.json());
    } catch (error) {
      console.error('Fetch error:', error);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 2000);
    return () => clearInterval(interval);
  }, [fetchData]);

  useEffect(() => {
    if (activeTab === 'forensics') {
      logEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [forensics, activeTab]);

  const triggerFix = async () => {
    await fetch('/api/fix', { method: 'POST' });
    fetchData();
  };

  const updatePid = async () => {
    // In a real app, this would POST to /api/tuning
    console.log('Updating PID params:', pidParams);
  };

  if (!telemetry) return (
    <div className="min-h-screen bg-slate-950 flex items-center justify-center text-slate-400 font-mono">
      <div className="flex flex-col items-center gap-4">
        <RefreshCw className="animate-spin w-8 h-8 text-emerald-500" />
        <p className="tracking-widest animate-pulse">INITIALIZING FORENSIC PROBES...</p>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-slate-950 text-slate-200 font-mono selection:bg-emerald-500/30">
      {/* Top Status Bar */}
      <div className="bg-slate-900 border-b border-slate-800 px-4 py-2 flex justify-between items-center text-[10px] text-slate-500">
        <div className="flex gap-4">
          <span className="flex items-center gap-1">
            <Cpu size={10} /> CORE: {telemetry.bkwInterface}
          </span>
          <span className="flex items-center gap-1">
            <Database size={10} /> DB: config_db.jsonl
          </span>
        </div>
        <div className="flex gap-4">
          <span className={telemetry.gitUpdateAvailable ? 'text-amber-500' : 'text-slate-600'}>
            GIT: {telemetry.gitUpdateAvailable ? 'UPDATE PENDING' : 'SYNCED'}
          </span>
          <span>TICK: {new Date(telemetry.lastTick).toLocaleTimeString()}</span>
        </div>
      </div>

      <div className="p-4 md:p-8">
        {/* Header */}
        <header className="max-w-7xl mx-auto mb-8 flex flex-col md:flex-row justify-between items-start md:items-center gap-6 border-b border-slate-800 pb-8">
          <div>
            <h1 className="text-3xl font-black tracking-tighter flex items-center gap-3 text-white">
              <ShieldCheck className="text-emerald-400 w-8 h-8" />
              BCM4331 FORENSIC CONTROLLER
              <span className="text-xs bg-emerald-500/10 border border-emerald-500/20 px-2 py-1 rounded text-emerald-400 ml-2 font-mono">v39.8</span>
            </h1>
            <p className="text-sm text-slate-500 mt-2 max-w-xl">
              Hardened, forensic-grade, self-healing Wi-Fi recovery suite. 
              Monitoring 18 deterministic audit points in real-time.
            </p>
          </div>
          
          <div className="flex items-center gap-4">
            <div className={`flex items-center gap-3 px-4 py-2 rounded-lg border ${
              telemetry.connectivity ? 'bg-emerald-500/5 border-emerald-500/20 text-emerald-400' : 'bg-red-500/5 border-red-500/20 text-red-400'
            }`}>
              {telemetry.connectivity ? <Wifi size={20} /> : <WifiOff size={20} />}
              <div className="flex flex-col">
                <span className="text-[10px] uppercase font-bold opacity-60">Network State</span>
                <span className="text-sm font-black uppercase tracking-tight">{telemetry.connectivity ? 'System Online' : 'Network Dead'}</span>
              </div>
            </div>
            
            <button 
              onClick={triggerFix}
              disabled={telemetry.isFixing}
              className={`group flex items-center gap-3 px-6 py-3 rounded-lg font-black text-sm transition-all ${
                telemetry.isFixing 
                  ? 'bg-amber-500/20 text-amber-500 cursor-wait animate-pulse border border-amber-500/30' 
                  : 'bg-red-600 hover:bg-red-500 text-white shadow-xl shadow-red-900/20 hover:scale-[1.02] active:scale-95'
              }`}
            >
              <Zap size={18} fill="currentColor" className={telemetry.isFixing ? 'animate-bounce' : 'group-hover:rotate-12 transition-transform'} />
              {telemetry.isFixing ? 'RECOVERY ACTIVE' : 'NUCLEAR RECOVERY'}
            </button>
          </div>
        </header>

        <main className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Navigation */}
          <nav className="lg:col-span-2 flex lg:flex-col gap-2 overflow-x-auto pb-4 lg:pb-0">
            {[
              { id: 'telemetry', icon: Activity, label: 'Telemetry' },
              { id: 'forensics', icon: Terminal, label: 'Verbatim' },
              { id: 'evidence', icon: Search, label: 'Evidence' },
              { id: 'tuning', icon: Sliders, label: 'Tuning' }
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`flex items-center gap-3 px-4 py-4 rounded-xl text-sm font-bold transition-all whitespace-nowrap border ${
                  activeTab === tab.id 
                    ? 'bg-slate-800 text-white border-slate-700 shadow-lg' 
                    : 'text-slate-500 hover:bg-slate-900 hover:text-slate-300 border-transparent'
                }`}
              >
                <tab.icon size={20} className={activeTab === tab.id ? 'text-emerald-400' : ''} />
                {tab.label}
              </button>
            ))}
          </nav>

          {/* Content Area */}
          <div className="lg:col-span-10">
            <AnimatePresence mode="wait">
              {activeTab === 'telemetry' && (
                <motion.div 
                  key="telemetry"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="space-y-8"
                >
                  {/* Main Metrics Grid */}
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    {/* Health Card */}
                    <div className="md:col-span-2 bg-slate-900/40 border border-slate-800 p-8 rounded-2xl backdrop-blur-sm">
                      <div className="flex justify-between items-end mb-8">
                        <div>
                          <h3 className="text-xs font-black text-slate-500 uppercase tracking-[0.2em] mb-2">Integrity Score</h3>
                          <div className="flex items-baseline gap-2">
                            <span className="text-5xl font-black text-white">{telemetry.health}</span>
                            <span className="text-slate-600 font-bold">/ 100</span>
                          </div>
                        </div>
                        <div className="text-right">
                          <p className="text-[10px] text-slate-500 font-bold mb-1">SIGNAL STRENGTH</p>
                          <p className={`text-2xl font-black ${telemetry.signal > -60 ? 'text-emerald-400' : 'text-amber-400'}`}>
                            {telemetry.signal} <span className="text-xs opacity-50">dBm</span>
                          </p>
                        </div>
                      </div>

                      {/* Health Breakdown Bars */}
                      <div className="space-y-6">
                        {[
                          { label: 'ICMP PING', value: telemetry.healthPing, max: 40, color: 'bg-cyan-500' },
                          { label: 'DNS RESOLUTION', value: telemetry.healthDns, max: 30, color: 'bg-purple-500' },
                          { label: 'GATEWAY ROUTE', value: telemetry.healthRoute, max: 30, color: 'bg-amber-500' }
                        ].map((bar) => (
                          <div key={bar.label}>
                            <div className="flex justify-between text-[10px] font-bold mb-2">
                              <span className="text-slate-400">{bar.label}</span>
                              <span className="text-slate-500">{bar.value} / {bar.max}</span>
                            </div>
                            <div className="h-2 bg-slate-800 rounded-full overflow-hidden">
                              <motion.div 
                                className={`h-full ${bar.color}`}
                                initial={{ width: 0 }}
                                animate={{ width: `${(bar.value / bar.max) * 100}%` }}
                                transition={{ duration: 1, ease: "easeOut" }}
                              />
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>

                    {/* Throughput Card */}
                    <div className="bg-slate-900/40 border border-slate-800 p-8 rounded-2xl flex flex-col justify-between">
                      <h3 className="text-xs font-black text-slate-500 uppercase tracking-[0.2em] mb-8">Traffic Flow</h3>
                      <div className="space-y-8">
                        <div>
                          <p className="text-[10px] text-slate-500 font-bold mb-2 flex items-center gap-2">
                            <ChevronRight size={10} className="text-emerald-500" /> RX THROUGHPUT
                          </p>
                          <p className="text-3xl font-black text-white">{telemetry.rx.toFixed(2)} <span className="text-xs text-slate-600">KB/s</span></p>
                        </div>
                        <div>
                          <p className="text-[10px] text-slate-500 font-bold mb-2 flex items-center gap-2">
                            <ChevronRight size={10} className="text-purple-500" /> TX THROUGHPUT
                          </p>
                          <p className="text-3xl font-black text-white">{telemetry.tx.toFixed(2)} <span className="text-xs text-slate-600">KB/s</span></p>
                        </div>
                      </div>
                      <div className="mt-8 pt-6 border-t border-slate-800/50">
                        <div className="flex items-center gap-2 text-[10px] font-bold text-emerald-500/80">
                          <Activity size={12} />
                          <span>REAL-TIME TELEMETRY ACTIVE</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* PID Controller State */}
                  <div className="bg-slate-900/20 border border-slate-800/50 p-6 rounded-2xl">
                    <h3 className="text-xs font-black text-slate-600 uppercase tracking-[0.2em] mb-6">PID Controller Signals</h3>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                      {[
                        { label: 'Kp Signal', value: telemetry.pidKp, color: 'text-blue-400' },
                        { label: 'Ki Integral', value: telemetry.pidKi, color: 'text-purple-400' },
                        { label: 'Kd Derivative', value: telemetry.pidKd, color: 'text-orange-400' },
                        { label: 'Net Output', value: telemetry.pidOut, color: 'text-white' }
                      ].map((sig) => (
                        <div key={sig.label} className="bg-slate-950/50 border border-slate-800 p-4 rounded-xl">
                          <p className="text-[9px] text-slate-500 font-bold mb-1 uppercase">{sig.label}</p>
                          <p className={`text-xl font-black ${sig.color}`}>{sig.value}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                </motion.div>
              )}

              {activeTab === 'forensics' && (
                <motion.div 
                  key="forensics"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="bg-slate-950 border border-slate-800 rounded-2xl overflow-hidden shadow-2xl"
                >
                  <div className="bg-slate-900 px-6 py-4 border-b border-slate-800 flex justify-between items-center">
                    <div className="flex items-center gap-3">
                      <Terminal size={18} className="text-emerald-500" />
                      <span className="text-xs font-black text-white tracking-widest uppercase">Verbatim Handshake Log</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="w-2 h-2 bg-emerald-500 rounded-full animate-ping" />
                      <span className="text-[10px] font-bold text-emerald-500 uppercase">Live Stream</span>
                    </div>
                  </div>
                  <div className="p-6 h-[500px] overflow-y-auto font-mono text-[11px] leading-relaxed text-slate-400 custom-scrollbar">
                    {forensics?.logTail.map((line, i) => (
                      <div key={i} className="group hover:bg-slate-900/50 px-2 py-1 rounded transition-colors flex gap-4">
                        <span className="text-slate-700 select-none w-8 shrink-0">{i + 1}</span>
                        <span className="break-all">{line}</span>
                      </div>
                    ))}
                    <div ref={logEndRef} />
                  </div>
                </motion.div>
              )}

              {activeTab === 'evidence' && (
                <motion.div 
                  key="evidence"
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="space-y-6"
                >
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    {/* Forensic Events List */}
                    <div className="bg-slate-900/40 border border-slate-800 rounded-2xl overflow-hidden">
                      <div className="p-4 bg-slate-800/50 border-b border-slate-700 flex items-center gap-2">
                        <Search size={16} className="text-emerald-400" />
                        <h3 className="text-xs font-black uppercase tracking-widest">Audit Trail</h3>
                      </div>
                      <div className="divide-y divide-slate-800 max-h-[500px] overflow-y-auto">
                        {forensics?.events.map((event, i) => (
                          <div key={i} className="p-4 hover:bg-slate-800/30 transition-colors">
                            <div className="flex justify-between items-start mb-1">
                              <span className={`text-[9px] font-black px-1.5 py-0.5 rounded uppercase ${
                                event.type === 'RECOVERY' ? 'bg-red-500/20 text-red-400' :
                                event.type === 'HEALTH' ? 'bg-amber-500/20 text-amber-400' :
                                'bg-slate-700 text-slate-300'
                              }`}>
                                {event.label}
                              </span>
                              <span className="text-[9px] text-slate-600 font-bold">{event.timestamp}</span>
                            </div>
                            <p className="text-xs text-slate-300 font-bold">{event.message}</p>
                            {event.details && <p className="text-[10px] text-slate-500 mt-1 italic">{event.details}</p>}
                          </div>
                        ))}
                      </div>
                    </div>

                    {/* DB Snapshots */}
                    <div className="bg-slate-900/40 border border-slate-800 rounded-2xl overflow-hidden">
                      <div className="p-4 bg-slate-800/50 border-b border-slate-700 flex items-center gap-2">
                        <Database size={16} className="text-purple-400" />
                        <h3 className="text-xs font-black uppercase tracking-widest">State Snapshots</h3>
                      </div>
                      <div className="divide-y divide-slate-800 max-h-[500px] overflow-y-auto p-4 space-y-4">
                        {forensics?.dbSnapshots.map((snap, i) => (
                          <div key={i} className="bg-slate-950/50 border border-slate-800 p-4 rounded-xl">
                            <div className="flex justify-between items-center mb-2">
                              <span className="text-[10px] font-black text-slate-500 uppercase">{snap.type}</span>
                              <span className="text-[9px] text-slate-700">{snap.timestamp}</span>
                            </div>
                            <div className="grid grid-cols-2 gap-2">
                              {Object.entries(snap.data).map(([k, v]: [string, any]) => (
                                <div key={k} className="flex flex-col">
                                  <span className="text-[8px] text-slate-600 uppercase font-bold">{k}</span>
                                  <span className="text-[10px] text-emerald-400 truncate font-mono">{String(v)}</span>
                                </div>
                              ))}
                            </div>
                          </div>
                        )).reverse()}
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}

              {activeTab === 'tuning' && (
                <motion.div 
                  key="tuning"
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  className="max-w-2xl mx-auto bg-slate-900/40 border border-slate-800 p-8 rounded-3xl"
                >
                  <div className="flex items-center gap-4 mb-8">
                    <div className="p-3 bg-emerald-500/10 rounded-2xl text-emerald-500">
                      <Sliders size={24} />
                    </div>
                    <div>
                      <h3 className="text-xl font-black text-white">PID Controller Tuning</h3>
                      <p className="text-xs text-slate-500">Adjust recovery response sensitivity and damping.</p>
                    </div>
                  </div>

                  <div className="space-y-10">
                    {[
                      { id: 'kp', label: 'Proportional (Kp)', desc: 'Immediate response to health drop', value: pidParams.kp },
                      { id: 'ki', label: 'Integral (Ki)', desc: 'Accumulated error correction', value: pidParams.ki },
                      { id: 'kd', label: 'Derivative (Kd)', desc: 'Damping to prevent oscillation', value: pidParams.kd }
                    ].map((param) => (
                      <div key={param.id}>
                        <div className="flex justify-between items-end mb-4">
                          <div>
                            <p className="text-sm font-black text-slate-200">{param.label}</p>
                            <p className="text-[10px] text-slate-500 font-bold uppercase tracking-wider">{param.desc}</p>
                          </div>
                          <span className="text-xl font-black text-emerald-400">{param.value}</span>
                        </div>
                        <input 
                          type="range" 
                          min="0" 
                          max="500" 
                          value={param.value}
                          onChange={(e) => setPidParams({ ...pidParams, [param.id]: parseInt(e.target.value) })}
                          className="w-full h-1.5 bg-slate-800 rounded-lg appearance-none cursor-pointer accent-emerald-500"
                        />
                      </div>
                    ))}

                    <div className="pt-6 flex gap-4">
                      <button 
                        onClick={updatePid}
                        className="flex-1 bg-emerald-600 hover:bg-emerald-500 text-white font-black py-4 rounded-xl transition-all shadow-lg shadow-emerald-900/20 active:scale-[0.98]"
                      >
                        APPLY PARAMETERS
                      </button>
                      <button 
                        onClick={() => setPidParams({ kp: 100, ki: 10, kd: 5 })}
                        className="px-6 border border-slate-700 hover:bg-slate-800 text-slate-400 font-bold rounded-xl transition-all"
                      >
                        RESET
                      </button>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </main>

        {/* Footer */}
        <footer className="max-w-7xl mx-auto mt-12 pt-8 border-t border-slate-800 flex flex-col md:flex-row justify-between items-center gap-4 text-[10px] text-slate-600 font-bold tracking-[0.3em] uppercase">
          <div className="flex items-center gap-4">
            <span className="flex items-center gap-2"><Lock size={10} /> SECURE HANDSHAKE</span>
            <span className="flex items-center gap-2"><Unlock size={10} /> SUDOERS HARDENED</span>
          </div>
          <div>© 2026 SWIPSWAPS FORENSIC SYSTEMS</div>
        </footer>
      </div>
    </div>
  );
}

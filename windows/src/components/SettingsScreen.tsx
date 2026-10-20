import React, { useState } from 'react';
import {
  Sliders,
  Bot,
  Clock,
  Info,
  ExternalLink,
  ShieldCheck,
  Check,
} from 'lucide-react';
import { AppSettings } from '../types';

interface SettingsScreenProps {
  settings: AppSettings;
  onUpdateSettings: (newSettings: AppSettings) => void;
}

export const SettingsScreen: React.FC<SettingsScreenProps> = ({
  settings,
  onUpdateSettings,
}) => {
  const [activeTab, setActiveTab] = useState<'island' | 'ai' | 'work' | 'about'>('island');
  const [savedBadge, setSavedBadge] = useState(false);

  const update = (patch: Partial<AppSettings>) => {
    const updated = { ...settings, ...patch };
    onUpdateSettings(updated);
    setSavedBadge(true);
    setTimeout(() => setSavedBadge(false), 1500);
  };

  return (
    <div className="flex flex-col h-full p-5 space-y-4 overflow-y-auto">
      {/* Header and sub-tabs */}
      <div className="flex items-center justify-between pb-3 border-b border-white/10 shrink-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-white">Pengaturan NilaiKinerja</span>
          {savedBadge && (
            <span className="px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 text-[10px] font-medium flex items-center gap-1 border border-emerald-500/30">
              <Check className="w-3 h-3" /> Tersimpan
            </span>
          )}
        </div>

        {/* 4 Tabs - Solid pill 36pt height container */}
        <div className="flex bg-[#1E222A] rounded-lg p-1 text-xs gap-1">
          <button
            onClick={() => setActiveTab('island')}
            className={`px-3 py-1 rounded-md transition-colors flex items-center gap-1.5 ${
              activeTab === 'island' ? 'bg-white/10 text-white font-medium' : 'text-white/50 hover:text-white'
            }`}
          >
            <Sliders className="w-3.5 h-3.5" />
            Island
          </button>
          <button
            onClick={() => setActiveTab('ai')}
            className={`px-3 py-1 rounded-md transition-colors flex items-center gap-1.5 ${
              activeTab === 'ai' ? 'bg-white/10 text-white font-medium' : 'text-white/50 hover:text-white'
            }`}
          >
            <Bot className="w-3.5 h-3.5" />
            AI
          </button>
          <button
            onClick={() => setActiveTab('work')}
            className={`px-3 py-1 rounded-md transition-colors flex items-center gap-1.5 ${
              activeTab === 'work' ? 'bg-white/10 text-white font-medium' : 'text-white/50 hover:text-white'
            }`}
          >
            <Clock className="w-3.5 h-3.5" />
            Jadwal
          </button>
          <button
            onClick={() => setActiveTab('about')}
            className={`px-3 py-1 rounded-md transition-colors flex items-center gap-1.5 ${
              activeTab === 'about' ? 'bg-white/10 text-white font-medium' : 'text-white/50 hover:text-white'
            }`}
          >
            <Info className="w-3.5 h-3.5" />
            Tentang
          </button>
        </div>
      </div>

      {/* Tab 1: Island & Tampilan */}
      {activeTab === 'island' && (
        <div className="space-y-4">
          <div className="bg-white/5 border border-white/10 rounded-xl p-4 space-y-3">
            <h3 className="text-xs font-semibold text-white/90">Interaksi Dynamic Island Windows</h3>
            <p className="text-xs text-white/50">
              Konfigurasi kapsul mengambang di atas tengah layar monitor Windows Anda.
            </p>

            <div className="space-y-2 pt-2">
              <div className="flex items-center justify-between text-xs text-white">
                <span>Intensitas Border Glow (#60A5FA)</span>
                <span className="font-mono text-blue-400">
                  {Math.round(settings.idleGlowIntensity * 100)}%
                </span>
              </div>
              <input
                type="range"
                min="0.2"
                max="1.0"
                step="0.05"
                value={settings.idleGlowIntensity}
                onChange={(e) => update({ idleGlowIntensity: parseFloat(e.target.value) })}
                className="w-full h-1.5 bg-white/10 rounded-lg appearance-none cursor-pointer accent-blue-500"
              />
            </div>

            <div className="space-y-2 pt-2">
              <div className="flex items-center justify-between text-xs text-white">
                <span>Dwell Timer Hover Preview</span>
                <span className="font-mono text-blue-400">{settings.idleDwellDuration}s</span>
              </div>
              <input
                type="range"
                min="0.3"
                max="2.0"
                step="0.1"
                value={settings.idleDwellDuration}
                onChange={(e) => update({ idleDwellDuration: parseFloat(e.target.value) })}
                className="w-full h-1.5 bg-white/10 rounded-lg appearance-none cursor-pointer accent-blue-500"
              />
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Asisten AI */}
      {activeTab === 'ai' && (
        <div className="space-y-4">
          <div className="bg-white/5 border border-white/10 rounded-xl p-4 space-y-3">
            <h3 className="text-xs font-semibold text-white/90">Konfigurasi Endpoint AI</h3>
            <p className="text-xs text-white/50">
              Mendukung server lokal (Ollama, LM Studio) maupun remote OpenAI-compatible.
            </p>

            <div className="space-y-1.5 pt-1">
              <label className="text-xs font-medium text-white/80">Base URL API</label>
              <input
                type="text"
                value={settings.aiBaseURL}
                onChange={(e) => update({ aiBaseURL: e.target.value })}
                placeholder="http://localhost:11434/v1"
                className="w-full h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs font-mono text-white placeholder-white/30 focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-medium text-white/80">Model Default</label>
              <input
                type="text"
                value={settings.aiModel}
                onChange={(e) => update({ aiModel: e.target.value })}
                placeholder="llama3, gpt-4o-mini, dll."
                className="w-full h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs font-mono text-white placeholder-white/30 focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-medium text-white/80">API Key (Opsional)</label>
              <input
                type="password"
                value={settings.aiApiKey}
                onChange={(e) => update({ aiApiKey: e.target.value })}
                placeholder="Kosongkan jika menggunakan Ollama lokal"
                className="w-full h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs font-mono text-white placeholder-white/30 focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>
          </div>
        </div>
      )}

      {/* Tab 3: Jadwal Kerja */}
      {activeTab === 'work' && (
        <div className="space-y-4">
          <div className="bg-white/5 border border-white/10 rounded-xl p-4 space-y-3">
            <h3 className="text-xs font-semibold text-white/90">Jam Kerja & Pengingat</h3>
            <p className="text-xs text-white/50">
              Di luar jam kerja, Robot Head otomatis beralih ke ekspresi tidur (`sleeping`).
            </p>

            <div className="grid grid-cols-2 gap-3 pt-1">
              <div className="space-y-1.5">
                <label className="text-xs font-medium text-white/80">Mulai Kerja</label>
                <input
                  type="text"
                  value={`${String(settings.workStartHour).padStart(2, '0')}:${String(
                    settings.workStartMinute
                  ).padStart(2, '0')}`}
                  onChange={(e) => {
                    const [h, m] = e.target.value.split(':').map(Number);
                    if (!isNaN(h) && !isNaN(m)) {
                      update({ workStartHour: h, workStartMinute: m });
                    }
                  }}
                  className="w-full h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs font-mono text-white focus:outline-none focus:border-blue-500 transition-colors"
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs font-medium text-white/80">Selesai Kerja</label>
                <input
                  type="text"
                  value={`${String(settings.workEndHour).padStart(2, '0')}:${String(
                    settings.workEndMinute
                  ).padStart(2, '0')}`}
                  onChange={(e) => {
                    const [h, m] = e.target.value.split(':').map(Number);
                    if (!isNaN(h) && !isNaN(m)) {
                      update({ workEndHour: h, workEndMinute: m });
                    }
                  }}
                  className="w-full h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs font-mono text-white focus:outline-none focus:border-blue-500 transition-colors"
                />
              </div>
            </div>

            <div className="space-y-1.5 pt-2">
              <label className="text-xs font-medium text-white/80">Interval Pengingat (Menit)</label>
              <input
                type="number"
                value={settings.reminderIntervalMinutes}
                onChange={(e) => update({ reminderIntervalMinutes: parseInt(e.target.value, 10) || 60 })}
                className="w-full h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs font-mono text-white focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>
          </div>
        </div>
      )}

      {/* Tab 4: Tentang */}
      {activeTab === 'about' && (
        <div className="space-y-4">
          <div className="bg-white/5 border border-white/10 rounded-xl p-4 space-y-3 text-xs">
            <div className="flex items-center gap-3 pb-3 border-b border-white/10">
              <div className="w-10 h-10 rounded-xl bg-blue-600/30 border border-blue-500/40 flex items-center justify-center font-bold text-white text-base">
                NK
              </div>
              <div>
                <div className="text-sm font-bold text-white">NilaiKinerja Windows</div>
                <div className="text-[11px] text-white/50">Versi 1.0.0 (Tauri v2 + Rust)</div>
              </div>
            </div>

            <div className="space-y-2 text-white/80">
              <div className="flex items-center justify-between">
                <span className="text-white/50">Pengembang:</span>
                <span className="font-semibold text-white">nirwna</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-white/50">Lisensi:</span>
                <span className="text-blue-300">MIT License</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-white/50">Privasi:</span>
                <span className="text-emerald-400 flex items-center gap-1">
                  <ShieldCheck className="w-3.5 h-3.5" /> 100% Local-First
                </span>
              </div>
            </div>

            <div className="pt-3 border-t border-white/10">
              <a
                href="https://github.com/dendyadinirwana/nilaikinerja"
                target="_blank"
                rel="noreferrer"
                className="h-[36px] bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg flex items-center justify-center gap-2 text-xs font-medium text-white transition-colors"
              >
                <span>Lihat Repositori GitHub</span>
                <ExternalLink className="w-3.5 h-3.5 text-white/60" />
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
